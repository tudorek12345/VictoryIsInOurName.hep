//! SDR scene and UI composition for PresentX.
use windows::Win32::Foundation::RECT;
use windows::Win32::Graphics::Direct3D::Fxc::D3DCompile;
use windows::Win32::Graphics::Direct3D::{D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST, ID3DBlob};
use windows::Win32::Graphics::Direct3D12::*;
use windows::Win32::Graphics::Dxgi::Common::*;
use windows::core::{PCSTR, s};

pub(crate) const MAX_PLANES: u32 = 8;

/// Built-in fullscreen-triangle compositor for multi-plane `PresentX` calls
/// (e.g. Series S presenting a 1080p scene plane with a 4K UI overlay plane).
pub(super) struct Compositor {
    pub(super) format: DXGI_FORMAT,
    root: ID3D12RootSignature,
    opaque: ID3D12PipelineState,
    overlay: ID3D12PipelineState,
    overlay_3x: Option<ID3D12PipelineState>,
    rtv_heap: ID3D12DescriptorHeap,
    srv_heap: ID3D12DescriptorHeap,
    srv_stride: u32,
}

impl Compositor {
    pub(super) fn new(device: &ID3D12Device, format: DXGI_FORMAT) -> windows::core::Result<Self> {
        const SOURCE: &str = r#"
            #define RS "DescriptorTable(SRV(t0), visibility=SHADER_VISIBILITY_PIXEL), \
                        StaticSampler(s0, filter=FILTER_MIN_MAG_MIP_LINEAR, \
                            addressU=TEXTURE_ADDRESS_CLAMP, addressV=TEXTURE_ADDRESS_CLAMP, \
                            visibility=SHADER_VISIBILITY_PIXEL)"
            Texture2D tex : register(t0);
            SamplerState smp : register(s0);
            [RootSignature(RS)]
            void vs(uint id : SV_VertexID, out float4 pos : SV_Position, out float2 uv : TEXCOORD) {
                uv = float2((id << 1) & 2, id & 2);
                pos = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
            }
            [RootSignature(RS)]
            float4 ps(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
                return tex.SampleLevel(smp, uv, 0);
            }
            [RootSignature(RS)]
            float4 ps_3x(float4 pos : SV_Position) : SV_Target {
                return tex.Load(int3(3 * int2(pos.xy) + 1, 0));
            }
        "#;
        let compile = |entry: PCSTR, target: PCSTR| -> windows::core::Result<ID3DBlob> {
            let mut code: Option<ID3DBlob> = None;
            let mut errors: Option<ID3DBlob> = None;
            // SAFETY: static source and entry/target strings; out pointers ours.
            let res = unsafe {
                D3DCompile(
                    SOURCE.as_ptr().cast(),
                    SOURCE.len(),
                    s!("present_composite"),
                    None,
                    None,
                    entry,
                    target,
                    0,
                    0,
                    &mut code,
                    Some(&mut errors),
                )
            };
            if let Err(e) = res {
                if let Some(errors) = errors {
                    // SAFETY: the blob's own bytes.
                    let text = unsafe {
                        std::slice::from_raw_parts(
                            errors.GetBufferPointer().cast::<u8>(),
                            errors.GetBufferSize(),
                        )
                    };
                    tracing::warn!("present compositor: {}", String::from_utf8_lossy(text));
                }
                return Err(e);
            }
            code.ok_or_else(windows::core::Error::empty)
        };
        let vs = compile(s!("vs"), s!("vs_5_1"))?;
        let ps = compile(s!("ps"), s!("ps_5_1"))?;
        // SAFETY: compiled shader blobs live through PSO creation.
        unsafe {
            let vs_bytes =
                std::slice::from_raw_parts(vs.GetBufferPointer().cast::<u8>(), vs.GetBufferSize());
            let root: ID3D12RootSignature = device.CreateRootSignature(0, vs_bytes)?;
            let make_pso = |ps: &ID3DBlob, blend: bool| {
                let mut rt_blend = D3D12_RENDER_TARGET_BLEND_DESC {
                    RenderTargetWriteMask: D3D12_COLOR_WRITE_ENABLE_ALL.0 as u8,
                    ..Default::default()
                };
                if blend {
                    rt_blend.BlendEnable = true.into();
                    rt_blend.SrcBlend = D3D12_BLEND_ONE;
                    rt_blend.DestBlend = D3D12_BLEND_INV_SRC_ALPHA;
                    rt_blend.BlendOp = D3D12_BLEND_OP_ADD;
                    rt_blend.SrcBlendAlpha = D3D12_BLEND_ONE;
                    rt_blend.DestBlendAlpha = D3D12_BLEND_INV_SRC_ALPHA;
                    rt_blend.BlendOpAlpha = D3D12_BLEND_OP_ADD;
                }
                let mut blend_desc = D3D12_BLEND_DESC::default();
                blend_desc.RenderTarget[0] = rt_blend;
                let mut rtv_formats = [DXGI_FORMAT_UNKNOWN; 8];
                rtv_formats[0] = format;
                let desc = D3D12_GRAPHICS_PIPELINE_STATE_DESC {
                    pRootSignature: std::mem::ManuallyDrop::new(Some(root.clone())),
                    VS: D3D12_SHADER_BYTECODE {
                        pShaderBytecode: vs_bytes.as_ptr().cast(),
                        BytecodeLength: vs_bytes.len(),
                    },
                    PS: D3D12_SHADER_BYTECODE {
                        pShaderBytecode: ps.GetBufferPointer(),
                        BytecodeLength: ps.GetBufferSize(),
                    },
                    BlendState: blend_desc,
                    SampleMask: u32::MAX,
                    RasterizerState: D3D12_RASTERIZER_DESC {
                        FillMode: D3D12_FILL_MODE_SOLID,
                        CullMode: D3D12_CULL_MODE_NONE,
                        DepthClipEnable: false.into(),
                        ..Default::default()
                    },
                    PrimitiveTopologyType: D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
                    NumRenderTargets: 1,
                    RTVFormats: rtv_formats,
                    SampleDesc: DXGI_SAMPLE_DESC {
                        Count: 1,
                        Quality: 0,
                    },
                    ..Default::default()
                };
                let pso = device.CreateGraphicsPipelineState(&desc);
                let _ = std::mem::ManuallyDrop::into_inner(desc.pRootSignature);
                pso
            };
            let opaque = make_pso(&ps, false)?;
            let overlay = make_pso(&ps, true)?;
            // Optional specialization: the linear overlay PSO is always usable.
            let overlay_3x = if format == DXGI_FORMAT_R8G8B8A8_UNORM {
                compile(s!("ps_3x"), s!("ps_5_1"))
                    .and_then(|ps| make_pso(&ps, true))
                    .ok()
            } else {
                None
            };
            let rtv_heap: ID3D12DescriptorHeap =
                device.CreateDescriptorHeap(&D3D12_DESCRIPTOR_HEAP_DESC {
                    Type: D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
                    NumDescriptors: 1,
                    Flags: D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
                    NodeMask: 0,
                })?;
            let srv_heap: ID3D12DescriptorHeap =
                device.CreateDescriptorHeap(&D3D12_DESCRIPTOR_HEAP_DESC {
                    Type: D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
                    NumDescriptors: MAX_PLANES,
                    Flags: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
                    NodeMask: 0,
                })?;
            let srv_stride =
                device.GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
            Ok(Compositor {
                format,
                root,
                opaque,
                overlay,
                overlay_3x,
                rtv_heap,
                srv_heap,
                srv_stride,
            })
        }
    }

    fn plane_pso(
        &self,
        index: usize,
        desc: &D3D12_RESOURCE_DESC,
        width: u32,
        height: u32,
    ) -> &ID3D12PipelineState {
        if index == 0 {
            return &self.opaque;
        }
        // Full viewport, mip 0: on BOTH axes the destination pixel center i + 0.5
        // maps to source texel center 3*i + 1.5. Other bilinear taps have zero
        // weight, regardless of the contents or alpha of either plane.
        if desc.Format == DXGI_FORMAT_R8G8B8A8_UNORM
            && desc.Width == 3 * u64::from(width)
            && u64::from(desc.Height) == 3 * u64::from(height)
            && let Some(pso) = &self.overlay_3x
        {
            return pso;
        }
        &self.overlay
    }

    /// Draws the scene and its premultiplied overlays. The caller has
    /// transitioned the target to RENDER_TARGET and will transition it to
    /// the state needed for readback or presentation.
    pub(super) fn record(
        &self,
        device: &ID3D12Device,
        list: &ID3D12GraphicsCommandList,
        back: &ID3D12Resource,
        planes: &[(&ID3D12Resource, u32)],
        width: u32,
        height: u32,
    ) {
        let readable = D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
        // SAFETY: the list is open and reads live compatible 2D textures.
        // The presenter waits for this list before rewriting its descriptors.
        unsafe {
            let rtv = self.rtv_heap.GetCPUDescriptorHandleForHeapStart();
            device.CreateRenderTargetView(back, None, rtv);
            let cpu = self.srv_heap.GetCPUDescriptorHandleForHeapStart();
            let gpu = self.srv_heap.GetGPUDescriptorHandleForHeapStart();
            let mut before = Vec::with_capacity(planes.len());
            let mut after = Vec::with_capacity(planes.len());
            for &(texture, state) in planes {
                let state = D3D12_RESOURCE_STATES(state as i32);
                if state != readable {
                    before.push(super::host::transition(texture, state, readable));
                    after.push(super::host::transition(texture, readable, state));
                }
            }
            if !before.is_empty() {
                list.ResourceBarrier(&before);
            }
            list.SetDescriptorHeaps(&[Some(self.srv_heap.clone())]);
            list.SetGraphicsRootSignature(&self.root);
            list.RSSetViewports(&[D3D12_VIEWPORT {
                Width: width as f32,
                Height: height as f32,
                MaxDepth: 1.0,
                ..Default::default()
            }]);
            list.RSSetScissorRects(&[RECT {
                left: 0,
                top: 0,
                right: width as i32,
                bottom: height as i32,
            }]);
            list.OMSetRenderTargets(1, Some(&rtv), false, None);
            list.IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            for (index, &(texture, _)) in planes.iter().enumerate() {
                let desc = texture.GetDesc();
                let srv = D3D12_SHADER_RESOURCE_VIEW_DESC {
                    Format: sample_format(desc.Format).unwrap_or(desc.Format),
                    ViewDimension: D3D12_SRV_DIMENSION_TEXTURE2D,
                    Shader4ComponentMapping: D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING,
                    Anonymous: D3D12_SHADER_RESOURCE_VIEW_DESC_0 {
                        Texture2D: D3D12_TEX2D_SRV {
                            MipLevels: 1,
                            ..Default::default()
                        },
                    },
                };
                device.CreateShaderResourceView(
                    texture,
                    Some(&srv),
                    D3D12_CPU_DESCRIPTOR_HANDLE {
                        ptr: cpu.ptr + index * self.srv_stride as usize,
                    },
                );
                list.SetPipelineState(self.plane_pso(index, &desc, width, height));
                list.SetGraphicsRootDescriptorTable(
                    0,
                    D3D12_GPU_DESCRIPTOR_HANDLE {
                        ptr: gpu.ptr + index as u64 * u64::from(self.srv_stride),
                    },
                );
                list.DrawInstanced(3, 1, 0, 0);
            }
            if !after.is_empty() {
                list.ResourceBarrier(&after);
            }
        }
    }
}

fn sample_format(format: DXGI_FORMAT) -> Option<DXGI_FORMAT> {
    Some(match format {
        DXGI_FORMAT_R8G8B8A8_TYPELESS => DXGI_FORMAT_R8G8B8A8_UNORM,
        DXGI_FORMAT_B8G8R8A8_TYPELESS => DXGI_FORMAT_B8G8R8A8_UNORM,
        DXGI_FORMAT_R10G10B10A2_TYPELESS => DXGI_FORMAT_R10G10B10A2_UNORM,
        DXGI_FORMAT_R16G16B16A16_TYPELESS => DXGI_FORMAT_R16G16B16A16_FLOAT,
        DXGI_FORMAT_R8G8B8A8_UNORM
        | DXGI_FORMAT_R8G8B8A8_UNORM_SRGB
        | DXGI_FORMAT_B8G8R8A8_UNORM
        | DXGI_FORMAT_B8G8R8A8_UNORM_SRGB
        | DXGI_FORMAT_R10G10B10A2_UNORM
        | DXGI_FORMAT_R16G16B16A16_FLOAT => format,
        _ => return None,
    })
}

pub(crate) fn sampleable(desc: &D3D12_RESOURCE_DESC) -> bool {
    desc.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D
        && desc.SampleDesc.Count == 1
        && desc.DepthOrArraySize == 1
        && desc.Flags.0 & D3D12_RESOURCE_FLAG_DENY_SHADER_RESOURCE.0 == 0
        && sample_format(desc.Format).is_some()
}

pub(super) fn output_size(width: u32, height: u32) -> (u32, u32) {
    static LIMIT: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    if !*LIMIT.get_or_init(|| std::env::var_os("VICTORY_PRESENT_720P").is_some_and(|v| v == "1")) {
        return (width, height);
    }
    let scale = (1280.0 / f64::from(width))
        .min(720.0 / f64::from(height))
        .min(1.0);
    (
        (f64::from(width) * scale).round().max(1.0) as u32,
        (f64::from(height) * scale).round().max(1.0) as u32,
    )
}

#[cfg(all(test, feature = "diagnostics"))]
mod tests;
