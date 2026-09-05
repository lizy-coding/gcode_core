"""Compile the probe with the selected Flutter SDK's official impellerc."""
import json
import pathlib
import subprocess
import shutil

root = pathlib.Path(__file__).resolve().parents[1]
sdk = pathlib.Path(shutil.which('flutter')).resolve().parents[1]
compilers = sorted((sdk / 'bin/cache/artifacts/engine').glob('darwin-*/impellerc'))
if not compilers:
    raise SystemExit('Run flutter precache --macos first')
spec = {name: {'type': kind, 'file': str(root / 'shaders' / file)}
        for name, kind, file in [('ProbeVertex', 'vertex', 'probe.vert'),
                                 ('ProbeFragment', 'fragment', 'probe.frag')]}
subprocess.run([str(compilers[0]), '--runtime-stage-metal',
                '--runtime-stage-vulkan', '--runtime-stage-gles',
                '--shader-bundle=' + json.dumps(spec),
                '--sl=' + str(root / 'shaders/probe.shaderbundle')], check=True)
