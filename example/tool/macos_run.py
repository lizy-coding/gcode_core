#!/usr/bin/env python3
"""Scoped Xcode compiler-probe workaround; no SDK or global settings changed."""
import argparse
import os
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--mode', choices=['debug', 'profile', 'release'], default='debug')
parser.add_argument('--target', default='lib/main.dart')
parser.add_argument('--build-only', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
subprocess.run(['python3',str(root/'tool/build_gpu_shaders.py')],check=True)
os.environ['GCODE_REAL_CLANG'] = subprocess.check_output(['xcrun','--find','clang'], text=True).strip()
subprocess.run(['flutter','build','macos',f'--{args.mode}','--config-only','-t',args.target],cwd=root,check=True)
subprocess.run(['xcodebuild','-workspace','macos/Runner.xcworkspace','-scheme','Runner',
                '-configuration',args.mode.capitalize(),'-derivedDataPath','build/macos',
                '-destination','platform=macOS,arch=arm64',
                'CC='+str(root/'tool/macos/compiler_probe.py'),'COMPILER_INDEX_STORE_ENABLE=NO'],cwd=root,check=True)
products=root/'build/macos/Build/Products'/args.mode.capitalize()
apps=list(products.glob('*.app'))
if len(apps)!=1:
    raise SystemExit(f'Expected one application in {products}, got {apps}')
print(f'Built {apps[0]}',flush=True)
if not args.build_only:
    info=plistlib.loads((apps[0]/'Contents/Info.plist').read_bytes())
    subprocess.run([str(apps[0]/'Contents/MacOS'/info['CFBundleExecutable'])],check=True)
