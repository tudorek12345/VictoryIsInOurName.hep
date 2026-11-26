"""Authored compute-only cache probe; no game input or GPU execution."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
lines = [
    'cbuffer Params : register(b0) { uint inputIndex; uint outputIndex; uint seed; };',
    '[numthreads(32,1,1)] void main(uint3 tid : SV_DispatchThreadID) {',
    'ByteAddressBuffer src = ResourceDescriptorHeap[inputIndex];',
    'RWByteAddressBuffer dst = ResourceDescriptorHeap[outputIndex];',
    'uint x = seed ^ tid.x;'
]
for n in range(2048):
    c = (n * 1664525 + 1013904223) & 0xffffffff
    lines.append(f'if ((src.Load((x & 1023u) * 4u) ^ {c}u) & 1u) x = ((x << 5u) | (x >> 27u)) + {c}u; else x = (x * 33u) ^ {c}u;')
lines.extend(['dst.Store(tid.x * 4u, x);', '}'])
with (root/'cache-stress.hlsl').open('w',encoding='utf-8',newline='\n') as f:
    f.write('\n'.join(lines)+'\n')
dxc = r'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe'
subprocess.run([dxc,'-T','cs_6_6','-E','main','-O3','-Ges','-WX',str(root/'cache-stress.hlsl'),
                '-Fo',str(root/'cache-stress.dxil')],check=True,timeout=120)
print({'authoredBranches':2048,'dxilBytes':(root/'cache-stress.dxil').stat().st_size})
