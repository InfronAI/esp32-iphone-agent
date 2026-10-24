#!/usr/bin/env python3
"""Compile the firmware harness against pinned cJSON with address/UB sanitizers."""
from pathlib import Path
import hashlib
import subprocess
import urllib.request

root=Path(__file__).resolve().parents[2]
build=root/'build/harness';build.mkdir(parents=True,exist_ok=True)
hashes={'cJSON.c':'298581a04a36c0165da4b0aade235c23088cb2faa58651d720ea2f3706ed0b0d',
        'cJSON.h':'25b0145150d500498e4d209cec69c18c42cf818bffcc54690be3b895a2a16dee'}
for name,sha in hashes.items():
    p=build/name
    if not p.exists():
        with urllib.request.urlopen('https://raw.githubusercontent.com/DaveGamble/cJSON/v1.7.19/'+name,timeout=30) as r:p.write_bytes(r.read())
    assert hashlib.sha256(p.read_bytes()).hexdigest()==sha,'cJSON checksum mismatch'
flags=['-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-I'+str(build)]
src=root/'hardware/hid_bridge/src/cloud'
for path,name in [(build/'cJSON.c','json.o'),(src/'action.c','action.o')]:
    vendor_flags=['-Wno-deprecated-declarations'] if name=='json.o' else []
    subprocess.run(['clang','-std=c11',*flags,*vendor_flags,'-c',str(path),'-o',str(build/name)],check=True)
subprocess.run(['clang++','-std=c++11',*flags,str(root/'hardware/tests/test_cloud_harness.cpp'),str(src/'harness.cpp'),
                str(build/'json.o'),str(build/'action.o'),'-o',str(build/'test_harness')],check=True)
subprocess.run([str(build/'test_harness')],check=True)
