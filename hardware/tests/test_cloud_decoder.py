#!/usr/bin/env python3
"""Compare a local I/P AirPlay capture against FFmpeg; never commit private captures.

Usage: python3 hardware/tests/test_cloud_decoder.py --stream capture.h264 --packets packets.json
Packets JSON: [{"size": 29, "at_ms": 100, "config": true}, ...]
Requires clang++, ar, ffmpeg and the pinned archive cached by cloud_deps.py.
"""
import argparse
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('cloud_deps',ROOT/'tools/cloud_deps.py')
deps=importlib.util.module_from_spec(spec)
spec.loader.exec_module(deps)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stream',type=Path,required=True)
    parser.add_argument('--packets',type=Path,required=True)
    parser.add_argument('--unpatched',action='store_true',help='Demonstrate the original reference-frame failure')
    args=parser.parse_args()
    archive=deps.DEPS/f'openh264-{deps.COMMIT}.tar.gz'
    assert deps.digest(archive)==deps.SHA256,'Pinned archive checksum mismatch'
    packets=json.loads(args.packets.read_text())
    assert sum(p['size'] for p in packets)==args.stream.stat().st_size
    with tempfile.TemporaryDirectory(prefix='cloud-decoder-test-') as directory:
        work=Path(directory);source=work/'source';deps.extract(archive,source)
        if not args.unpatched:deps.patch_reference_numbers(source)
        (source/'codec/common/inc/version_gen.h').write_text('#define VERSION_NUMBER "regression-test"\n')
        flags=['-O2','-fno-strict-aliasing','-std=c++11','-DGENERATED_VERSION_HEADER','-DNDEBUG','-pthread']
        for inc in ('api/wels','common/inc','decoder/core/inc','decoder/plus/inc'):
            flags.append('-I'+str(source/'codec'/inc))
        sources=[p for part in ('common/src','decoder/core/src','decoder/plus/src') for p in (source/'codec'/part).glob('*.cpp')]
        def compile_one(path):
            obj=work/(path.stem+'.o')
            subprocess.run(['clang++',*flags,'-c',str(path),'-o',str(obj)],check=True,capture_output=True)
            return str(obj)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:objects=list(pool.map(compile_one,sources))
        lib=work/'decoder.a';subprocess.run(['ar','rcs',str(lib),*objects],check=True)
        probe=work/'probe'
        subprocess.run(['clang++','-O2','-std=c++11','-pthread','-I'+str(ROOT/'hid_bridge/src/cloud'),
                        str(ROOT/'tests/cloud_decoder_probe.cpp'),str(lib),'-o',str(probe)],check=True)
        sizes=work/'sizes.txt';sizes.write_text(''.join(f"{p['size']} {p['at_ms']} {int(p['config'])}\n" for p in packets))
        actual,metadata,expected=work/'actual.raw',work/'frames.txt',work/'expected.raw'
        subprocess.run([str(probe),str(args.stream),str(sizes),str(actual),str(metadata)],check=True)
        frames=[tuple(map(int,line.split())) for line in metadata.read_text().splitlines()]
        assert [f[2] for f in frames]==[p['at_ms'] for p in packets if not p['config']], 'Picture was delayed, lost, or mislabeled'
        subprocess.run(['ffmpeg','-y','-v','error','-i',str(args.stream),'-vf','extractplanes=y','-pix_fmt','gray',
                        '-fps_mode','passthrough','-f','rawvideo',str(expected)],check=True)
        a,b=actual.read_bytes(),expected.read_bytes()
        assert len(a)==len(b)==sum(w*h for w,h,_ in frames),'Decoded size differs'
        assert a==b,f'{sum(x!=y for x,y in zip(a,b))} luma pixels differ from FFmpeg'
        print(f'PASS: {len(frames)} frames match FFmpeg pixel-for-pixel; every timestamp matches its input, without one-frame delay.')

if __name__=='__main__':main()
