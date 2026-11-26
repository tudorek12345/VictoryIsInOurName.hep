"""Compile only authored synthetic HLSL with DXC; never create a D3D device."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parent
dxc = Path(r'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe')
variants = {
    'baseline': [],
    'no-wave': ['NO_WAVE=1'],
    'no-dimensions': ['NO_DIMENSIONS=1'],
    'load-only': ['NO_WAVE=1', 'NO_DIMENSIONS=1'],
    'threads32': ['THREADS=32'],
    'wave64': ['WAVE64=1'],
    'wave32': ['WAVE32=1'],
    'lane-at-zero': ['LANE_AT_ZERO=1'],
    'lane-at-first-active': ['LANE_AT_FIRST_ACTIVE=1'],
    'lane-at-first-active-no-dimensions': ['LANE_AT_FIRST_ACTIVE=1', 'NO_DIMENSIONS=1'],
    'nonuniform-index': ['NONUNIFORM_INDEX=1'],
    'nonuniform-source': ['NONUNIFORM_SOURCE=1'],
    'nonuniform-source-no-dimensions': ['NONUNIFORM_SOURCE=1', 'NO_DIMENSIONS=1'],
    'explicit-registers': ['EXPLICIT_REGISTERS=1'],
    'explicit-registers-no-wave': ['EXPLICIT_REGISTERS=1', 'NO_WAVE=1'],
    'dimensions-only': ['NO_LOAD=1', 'NO_WAVE=1'],
    'typed-srv-dimensions-only': ['TYPED_SOURCE=1', 'NO_LOAD=1', 'NO_WAVE=1'],
    'raw-uav-dimensions-only': ['UAV_SOURCE=1', 'NO_LOAD=1', 'NO_WAVE=1'],
    'typed-srv-dimensions-load': ['TYPED_SOURCE=1', 'NO_WAVE=1'],
    'raw-uav-dimensions-load': ['UAV_SOURCE=1', 'NO_WAVE=1'],
    'raw-srv-finite-array': ['EXPLICIT_ARRAY=1', 'FINITE_ARRAY=1', 'NO_WAVE=1'],
    'raw-srv-unbounded-array': ['EXPLICIT_ARRAY=1', 'NO_WAVE=1'],
    'raw-uav-finite-array': ['EXPLICIT_ARRAY=1', 'FINITE_ARRAY=1', 'UAV_SOURCE=1', 'NO_WAVE=1'],
    'raw-uav-unbounded-array': ['EXPLICIT_ARRAY=1', 'UAV_SOURCE=1', 'NO_WAVE=1'],
    'split-dimension-nonuniform': ['DIMENSION_NONUNIFORM=1', 'NO_WAVE=1'],
    'split-load-nonuniform': ['DIMENSION_UNIFORM=1', 'NONUNIFORM_SOURCE=1', 'NO_WAVE=1'],
    'split-dimension-wave-index': ['DIMENSION_WAVE_INDEX=1', 'NO_WAVE=1'],
    'split-load-wave-index': ['LOAD_WAVE_INDEX=1', 'NO_WAVE=1'],
    'mixed-srv-table-query-heap-load': ['MIXED_QUERY_TABLE=1', 'NO_WAVE=1'],
    'mixed-srv-heap-query-table-load': ['MIXED_LOAD_TABLE=1', 'NO_WAVE=1'],
    'mixed-uav-table-query-heap-load': ['MIXED_QUERY_TABLE=1', 'UAV_SOURCE=1', 'NO_WAVE=1'],
    'mixed-uav-heap-query-table-load': ['MIXED_LOAD_TABLE=1', 'UAV_SOURCE=1', 'NO_WAVE=1'],
    'query-lane-identity': ['QUERY_LANE_IDENTITY=1', 'NO_WAVE=1'],
    'varying-index-baseline': ['VARYING_INDEX=1', 'NONUNIFORM_SOURCE=1', 'THREADS=32', 'NO_WAVE=1'],
    'query-lane-identity-varying': ['QUERY_LANE_IDENTITY=1', 'VARYING_INDEX=1', 'NONUNIFORM_SOURCE=1', 'THREADS=32', 'NO_WAVE=1'],
    'query-lane-identity-dimensions-only': ['QUERY_LANE_IDENTITY=1', 'NO_LOAD=1', 'NO_WAVE=1'],
}
out = root / 'variants'
out.mkdir(exist_ok=True)
manifest = []
for name, defines in variants.items():
    artifact = out / f'{name}.dxil'
    command = [str(dxc), '-T', 'cs_6_6', '-E', 'main', '-O3', '-Ges', '-WX',
               str(root / 'probe.hlsl'), '-Fo', str(artifact)]
    for define in defines:
        command += ['-D', define]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise SystemExit(f'{name}: DXC failed: {result.stderr}')
    data = artifact.read_bytes()
    root_args = (['--array16'] if 'FINITE_ARRAY=1' in defines else ['--array']) if 'EXPLICIT_ARRAY=1' in defines else \
                (['--explicit'] if 'EXPLICIT_REGISTERS=1' in defines else [])
    if 'MIXED_QUERY_TABLE=1' in defines or 'MIXED_LOAD_TABLE=1' in defines:
        root_args = ['--mixed-array']
    manifest.append(dict(name=name, defines=defines, path=str(artifact), bytes=len(data),
                         sha256=hashlib.sha256(data).hexdigest(),
                         probeArguments=[str(artifact)] + root_args))
(root / 'variants.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps([dict(name=x['name'], bytes=x['bytes'], sha256=x['sha256']) for x in manifest], indent=2))
