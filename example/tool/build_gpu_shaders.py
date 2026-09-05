"""Compile the GPU scene with the selected Flutter SDK's official impellerc."""
import json
import pathlib
import subprocess
import shutil

root = pathlib.Path(__file__).resolve().parents[1]
sdk = pathlib.Path(shutil.which('flutter')).resolve().parents[1]
compilers = sorted((sdk / 'bin/cache/artifacts/engine').glob('darwin-*/impellerc'))
if not compilers:
    raise SystemExit('Run flutter precache --macos first')
package_root = root.parent
spec = {name: {'type': kind, 'file': str(package_root / 'shaders' / file)}
        for name, kind, file in [('ToolpathVertex', 'vertex', 'toolpath.vert'),
                                 ('ToolpathFragment', 'fragment', 'toolpath.frag'),
                                 ('GuidesVertex', 'vertex', 'guides.vert'),
                                 ('GuidesFragment', 'fragment', 'guides.frag')]}
subprocess.run([str(compilers[0]), '--runtime-stage-metal',
                '--runtime-stage-vulkan', '--runtime-stage-gles',
                '--shader-bundle=' + json.dumps(spec),
                '--sl=' + str(package_root / 'shaders/toolpath.shaderbundle')], check=True)
