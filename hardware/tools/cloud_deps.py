#!/usr/bin/env python3
"""Build the pinned OpenH264 decoder for the selected Arduino ESP32-S3 SDK."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

COMMIT = '652bdb7719f30b52b08e506645a7322ff1b2cc6f'  # Cisco OpenH264 v2.6.0
SHA256 = '7a060916a9fcb63ba51d83a4f2388660c0b58797be547c4fa5c52e8d65660a85'
ROOT = Path(__file__).resolve().parents[1]
DEPS = ROOT / 'build/deps'
TARGET = DEPS / 'libopenh264dec.a'
FQBN = 'esp32:esp32:esp32s3:USBMode=default,CDCOnBoot=cdc,FlashSize=8M,PSRAM=opi,PartitionScheme=default_8MB'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f'OpenH264 port patch no longer matches {path.name}')
    path.write_text(text.replace(old, new))


def extract(archive, destination):
    # Extract only regular codec sources; reject links and path traversal.
    with tarfile.open(archive) as tf:
        for member in tf.getmembers():
            parts = PurePosixPath(member.name).parts
            if not parts or parts[0] != f'openh264-{COMMIT}' or '..' in parts:
                raise RuntimeError('Unexpected OpenH264 archive path')
            rel = PurePosixPath(*parts[1:])
            if not str(rel).startswith(('codec/common/', 'codec/decoder/', 'codec/api/')) or member.isdir():
                continue
            if not member.isfile():
                raise RuntimeError('Unexpected link in codec sources')
            target = destination / str(rel)
            target.parent.mkdir(parents=True, exist_ok=True)
            with tf.extractfile(member) as stream:
                target.write_bytes(stream.read())


def patch_reference_numbers(source):
    # MMCO 3/6 carries long_term_frame_idx, not long_term_pic_num. For the
    # progressive frames supported by this decoder, LongTermPicNum equals
    # LongTermFrameIdx (H.264 8.2.4.1). Leaving it zero makes ReorderRefList2
    # silently select an older reference when AirPlay uses LTR indices 1/2.
    core = source / 'codec/decoder/core/src/decoder_core.cpp'
    old = 'kpRefMarking->sMmcoRef[iIdx].iLongTermFrameIdx = uiCode;'
    replace_once(core, old, old + '\n          kpRefMarking->sMmcoRef[iIdx].uiLongTermPicNum = uiCode;')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fqbn', default=FQBN)
    args = parser.parse_args()
    raw = subprocess.check_output(['arduino-cli', 'compile', '-b', args.fqbn,
                                   '--show-properties=expanded', str(ROOT / 'hid_bridge')], text=True)
    props = dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)
    sdk, tool = Path(props['compiler.sdk.path']), Path(props['compiler.path'])
    compiler = tool / (props['compiler.prefix'] + 'g++')
    archiver = tool / (props['compiler.prefix'] + 'ar')
    config = sdk / props['build.memory_type'] / 'include/sdkconfig.h'
    identity = '\n'.join((digest(Path(__file__)), SHA256, str(sdk), str(compiler),
                          digest(config), digest(sdk / 'flags/includes'),
                          subprocess.check_output([str(compiler), '--version'], text=True)))
    fingerprint = hashlib.sha256(identity.encode()).hexdigest()
    manifest = DEPS / 'openh264-build.json'
    if TARGET.exists() and manifest.exists():
        saved = json.loads(manifest.read_text())
        if saved.get('fingerprint') == fingerprint and saved.get('sha256') == digest(TARGET):
            print('Verified OpenH264 decoder:', COMMIT)
            return
    DEPS.mkdir(parents=True, exist_ok=True)
    archive = DEPS / f'openh264-{COMMIT}.tar.gz'
    if not archive.exists() or digest(archive) != SHA256:
        tmp = archive.with_suffix('.download')
        subprocess.run(['curl', '-fL', '--retry', '2', '--max-time', '120', '-o', str(tmp),
                        f'https://codeload.github.com/cisco/openh264/tar.gz/{COMMIT}'], check=True)
        if digest(tmp) != SHA256:
            tmp.unlink()
            raise RuntimeError('OpenH264 source checksum mismatch')
        tmp.replace(archive)
    work = DEPS / ('openh264-build-' + fingerprint[:12])
    source, objects = work / 'source', work / 'objects'
    objects.mkdir(parents=True, exist_ok=True)
    extract(archive, source)
    patch_reference_numbers(source)
    for name in ('codec_api.h', 'codec_app_def.h', 'codec_def.h'):
        if (source / 'codec/api/wels' / name).read_bytes() != (ROOT / 'hid_bridge/src/cloud/openh264' / name).read_bytes():
            raise RuntimeError(f'Vendored OpenH264 API header mismatch: {name}')
    # ESP-IDF supports POSIX synchronization but not desktop CPU enumeration
    # or scheduling APIs. The decoder retains its default single-thread mode.
    threads = source / 'codec/common/src/WelsThreadLib.cpp'
    replace_once(threads, '#elif !defined(__Fuchsia__)', '#elif !defined(__Fuchsia__) && !defined(ESP_PLATFORM)')
    replace_once(threads, '#ifdef ANDROID_NDK\n  pInfo->ProcessorCount',
                 '#if defined(ESP_PLATFORM)\n  pInfo->ProcessorCount = 1;\n'
                 '  return WELS_THREAD_ERROR_OK;\n#elif defined(ANDROID_NDK)\n  pInfo->ProcessorCount')
    for call in ('pthread_attr_setscope (&at, PTHREAD_SCOPE_SYSTEM)', 'pthread_attr_setschedpolicy (&at, SCHED_FIFO)'):
        replace_once(threads, 'err = ' + call + ';', '#ifndef ESP_PLATFORM\n  err = ' + call + ';\n#endif')
    # Xtensa's int32_t is long: align definitions with their declarations.
    core = source / 'codec/decoder/core/src/decoder_core.cpp'
    for fn, arg in (('ExpandBsBuffer', 'kiSrcLen'), ('ExpandBsLenBuffer', 'kiCurrLen')):
        replace_once(core, f'{fn} (PWelsDecoderContext pCtx, const int {arg})',
                     f'{fn} (PWelsDecoderContext pCtx, const int32_t {arg})')
    # vision.cpp rejects AUs larger than 256 KiB. OpenH264 otherwise reserves
    # 3 MiB of compressed-stream storage even for our small AirPlay display.
    constants = source / 'codec/decoder/core/inc/wels_const.h'
    replace_once(constants, '#define MIN_ACCESS_UNIT_CAPACITY        1048576',
                 '#define MIN_ACCESS_UNIT_CAPACITY        262144')
    # Keep decoder allocations out of the small internal heap needed by Wi-Fi/TLS.
    memory = source / 'codec/common/src/memory_align.cpp'
    memory.write_text('#include <esp_heap_caps.h>\n#include <stdio.h>\n'
                      'extern "C" void cloud_decoder_allocation_failed(unsigned size);\n' + memory.read_text())
    replace_once(memory, 'uint8_t* pBuf = (uint8_t*) malloc (kiActualRequestedSize);',
                 'uint8_t* pBuf = (uint8_t*) heap_caps_malloc (kiActualRequestedSize, MALLOC_CAP_SPIRAM);\n'
                 '  if (!pBuf) cloud_decoder_allocation_failed((unsigned)kiActualRequestedSize);\n'
                 '  if (!pBuf) printf("cloud: decoder allocation failed %u bytes (%s), PSRAM free %u largest %u\\n", '
                 '(unsigned)kiActualRequestedSize, kpTag ? kpTag : "?", '
                 '(unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM), '
                 '(unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM));')
    (source / 'codec/common/inc/version_gen.h').write_text('#pragma once\n#define VERSION_NUMBER "OpenH264 2.6.0 ESP32-S3"\n')
    # OpenH264's upstream GNU build requires -fno-strict-aliasing. Its C
    # pixel/reference-buffer paths deliberately access memory through different
    # integer types; enabling strict aliasing can silently corrupt P-frames.
    flags = ['-O2', '-fno-strict-aliasing', '-mlongcalls', '-mdisable-hardware-atomics', '-fno-rtti', '-fno-exceptions',
             '-ffunction-sections', '-fdata-sections', '-std=gnu++11', '-DESP_PLATFORM', '-DNDEBUG',
             '-DGENERATED_VERSION_HEADER', '-D_GNU_SOURCE', '-iprefix', str(sdk / 'include') + '/',
             '@' + str(sdk / 'flags/includes'), '-I' + str(config.parent)]
    for inc in ('codec/api/wels', 'codec/common/inc', 'codec/decoder/core/inc', 'codec/decoder/plus/inc'):
        flags.append('-I' + str(source / inc))
    sources = []
    for part in ('codec/common/src', 'codec/decoder/core/src', 'codec/decoder/plus/src'):
        sources.extend(sorted((source / part).glob('*.cpp')))
    if len({p.stem for p in sources}) != len(sources):
        raise RuntimeError('Duplicate codec object name')
    def compile_file(path):
        obj = objects / (path.stem + '.o')
        result = subprocess.run([str(compiler), *flags, '-c', str(path), '-o', str(obj)], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        return str(obj)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        compiled = list(pool.map(compile_file, sources))
    temporary = work / 'libopenh264dec.a'
    temporary.unlink(missing_ok=True)
    subprocess.run([str(archiver), 'rcs', str(temporary), *compiled], check=True)
    temporary.replace(TARGET)
    manifest.write_text(json.dumps({'commit': COMMIT, 'fingerprint': fingerprint, 'sha256': digest(TARGET)}, indent=2))
    print('Built OpenH264 decoder:', COMMIT)


if __name__ == '__main__':
    main()
