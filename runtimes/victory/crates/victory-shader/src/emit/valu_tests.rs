//! End-to-end tests of synthetic GFX10 VALU shaders lowered to DXIL, validated
//! by `dxil.dll` when present, and executed on the host GPU and WARP.
//!
//! Covers RDNA2 hardware semantics that differ from naive DXIL lowering:
//! `v_med3_f32`/`v_med3_f16` with NaN operands, `v_fract_f32`/`v_fract_f16`
//! near `1.0`, and turn-range reduction for `v_sin_*`/`v_cos_*`.

use super::host::{Dispatch, Host, Root, Stride, View};
use super::{HostShader, IntegerView, IntegerViewKind, lower, validator};
use crate::native::{
    ComputeIo, HwStage, NativeProgram, ResourceType, RootParam, RootType, StageIo, UsedResource,
};
use crate::{io, ir, resource, structure};

const S_ENDPGM: u32 = 0xBF81_0000;

/// SOP1 `s_mov_b32 sdst, src0`.
const fn s_mov_b32(sdst: u8, src0: u8) -> u32 {
    0xBE80_0000 | (sdst as u32) << 16 | 0x03 << 8 | src0 as u32
}

/// SOP2 `op sdst, src0, src1`.
const fn sop2(op: u8, sdst: u8, src0: u8, src1: u8) -> u32 {
    0x8000_0000
        | (op as u32 & 0x7F) << 23
        | (sdst as u32 & 0x7F) << 16
        | (src1 as u32) << 8
        | src0 as u32
}

/// SMEM `s_load_dwordx4 s[dst:dst+3], s[base:base+1], offset`.
const fn s_load_dwordx4(dst: u8, base: u8, offset: u32) -> [u32; 2] {
    [
        0x3D << 26 | 0x02 << 18 | (dst as u32) << 6 | (base as u32 >> 1),
        125 << 25 | offset,
    ]
}

/// VOP1 `op vdst, src0` (`src0`: 0..105 = SGPR, 256..511 = VGPR).
const fn vop1(op: u16, vdst: u8, src0: u16) -> u32 {
    0x7E00_0000 | (vdst as u32) << 17 | (op as u32) << 9 | (src0 as u32 & 0x1FF)
}

/// VOP3 `op vdst, src0, src1, src2` (no modifiers).
const fn vop3(op: u16, vdst: u8, src0: u16, src1: u16, src2: u16) -> [u32; 2] {
    [
        0x35 << 26 | (op as u32 & 0x3FF) << 16 | vdst as u32,
        (src0 as u32 & 0x1FF) | (src1 as u32 & 0x1FF) << 9 | (src2 as u32 & 0x1FF) << 18,
    ]
}

/// MUBUF `buffer_store_dword vdata, off, s[srsrc:srsrc+3], 0 offset:byte_off`.
const fn buffer_store_dword(vdata: u8, srsrc: u8, byte_off: u16) -> [u32; 2] {
    [
        0x38 << 26 | 0x1C << 18 | (byte_off as u32 & 0xFFF),
        0x80 << 24 | ((srsrc as u32 >> 2) & 0x1F) << 16 | (vdata as u32) << 8,
    ]
}

const fn sgpr(n: u8) -> u16 {
    n as u16
}

const fn vgpr(n: u8) -> u16 {
    256 + n as u16
}

/// Builds and lowers a 1-thread synthetic RDNA2 compute shader that receives
/// 4 dwords of root constants in `s0..s3`, runs `body` (leaving its result in
/// `v0`), and stores `v0` to dword 0 of the raw UAV at heap index 0.
fn build_valu_cs(body: &[u32]) -> HostShader {
    build_cs_with_inputs(body, &[])
}

fn build_cs_with_inputs(body: &[u32], inputs: &[UsedResource]) -> HostShader {
    build_cs_for_views(body, inputs, &[])
}

fn build_cs_for_views(
    body: &[u32],
    inputs: &[UsedResource],
    integer_views: &[IntegerView],
) -> HostShader {
    build_cs(body, inputs, integer_views, false)
}

fn build_cs(
    body: &[u32],
    inputs: &[UsedResource],
    integer_views: &[IntegerView],
    resource_heap: bool,
) -> HostShader {
    try_build_cs(body, inputs, integer_views, resource_heap).expect("lower")
}

fn try_build_cs(
    body: &[u32],
    inputs: &[UsedResource],
    integer_views: &[IntegerView],
    resource_heap: bool,
) -> Result<HostShader, crate::ShaderError> {
    let mut words = Vec::new();
    // s[4:5] = descriptor table address (heap index 0 -> byte offset 0).
    words.push(s_mov_b32(5, 0x80)); // inline constant 0
    words.extend_from_slice(&s_load_dwordx4(8, 4, 0));
    // Copy root constants s0..s3 into v1..v4 so VALU instructions operate on
    // VGPRs just as they do in real shaders.
    for i in 0..4u8 {
        words.push(vop1(0x001, i + 1, sgpr(i))); // v_mov_b32
    }
    words.extend_from_slice(body);
    words.extend_from_slice(&buffer_store_dword(0, 8, 0));
    words.push(S_ENDPGM);

    let code: Vec<u8> = words.iter().flat_map(|w| w.to_le_bytes()).collect();
    let mut native = NativeProgram {
        stage: HwStage::Cs,
        wave64: false,
        vgprs: 8,
        layout: vec![
            RootParam {
                root: RootType::Constants,
                table_offset_dwords: 0,
                sgprs: 4,
                base_register: 0,
                user_data: 0,
                slot: 0,
            },
            RootParam {
                root: RootType::Table,
                table_offset_dwords: 0,
                sgprs: 1,
                base_register: 0,
                user_data: 4,
                slot: 1,
            },
        ],
        used: [UsedResource {
            kind: ResourceType::Uav,
            root: RootType::Table,
            table_offset_dwords: 0,
            lower_bound: 0,
            stride: 0,
            dwords: 4,
            user_data: 4,
            slot: 1,
        }]
        .into_iter()
        .chain(inputs.iter().copied())
        .collect(),
        io: StageIo::Cs(ComputeIo {
            rsrc2: (if resource_heap { 7 } else { 5 }) << 1,
            threads: [1, 1, 1],
        }),
        code,
    };
    if resource_heap {
        native.layout.push(RootParam {
            root: RootType::ResourceHeap,
            table_offset_dwords: 0,
            sgprs: 1,
            base_register: 0,
            user_data: 6,
            slot: 0,
        });
    }

    let p = ir::build(&native.code, native.wave64, native.vgprs).expect("ir::build");
    let res = resource::track(&p, &native.layout, native.stage).expect("resource::track");
    let io = io::raise(&p, &native).expect("io::raise");
    let st = structure::structure(&p).expect("structure");
    let lowered = lower::lower_for_views(
        &lower::Parts {
            native: &native,
            p: &p,
            st: &st,
            io: &io,
            res: &res,
            inputs: Vec::new(),
            outputs: Vec::new(),
            prims: Vec::new(),
            mesh_stride: 0,
        },
        integer_views,
    )?;

    let shader = HostShader {
        stage: HwStage::Cs,
        dxil: lowered.dxil,
        user_data: lowered.user_data,
        samplers: lowered.samplers,
        static_samplers: Vec::new(),
        root_cbvs: lowered.root_cbvs,
        root_srvs: lowered.root_srvs,
    };

    if let Ok(mut v) = validator::Validator::load(validator::Validator::default_path().as_deref()) {
        let mut copy = shader.dxil.clone();
        let ours = copy[4..20].to_vec();
        v.validate(&mut copy).expect("DXIL validation failed");
        assert_eq!(copy[4..20], ours[..], "container hash mismatch");
    }

    Ok(shader)
}

#[test]
fn scalar_load_crosses_a_structured_buffer_element_boundary() {
    let _native_test_guard = super::native_test_guard();
    let mut body = s_load_dwordx4(12, 4, 32).to_vec();
    // s_buffer_load_dwordx2 s[16:17], s[12:15], 8
    body.extend([0x3D << 26 | 0x09 << 18 | 16 << 6 | 6, 125 << 25 | 8]);
    body.extend([vop1(1, 0, sgpr(16)), vop1(1, 1, sgpr(17))]);
    body.extend(buffer_store_dword(1, 8, 4));
    let shader = build_cs_with_inputs(
        &body,
        &[UsedResource {
            kind: ResourceType::Srv,
            root: RootType::Table,
            table_offset_dwords: 8,
            lower_bound: 0,
            stride: 12,
            dwords: 4,
            user_data: 4,
            slot: 1,
        }],
    );
    let Ok(host) = Host::new(true) else {
        eprintln!("no SM 6.6 WARP device; skipped");
        return;
    };
    let (root, pipeline) = host.compute_pipeline(&shader).unwrap();
    let result = host
        .dispatch(
            &root,
            &pipeline,
            &Dispatch {
                roots: vec![(0, Root::Constants(vec![0; shader.user_data_dwords() as usize]))],
                views: &[
                    View::RawUav(2),
                    View::Buffer {
                        data: &[0x11, 0x22, 0x33, 0x44, 0x55, 0x66],
                        stride: Stride::Structured(12),
                    },
                ],
                samplers: &[],
                groups: [1, 1, 1],
            },
        )
        .unwrap();
    assert_eq!(result[0], [0x33, 0x44]);
}

#[test]
fn scalar_and_vector_reads_share_the_bindless_raw_srv_type() {
    let _native_test_guard = super::native_test_guard();
    let mut body = vec![s_mov_b32(7, 128)];
    body.extend(s_load_dwordx4(12, 6, 32));
    // s_buffer_load_dword s16, s[12:15], 4
    body.extend([0x3D << 26 | 8 << 18 | 16 << 6 | 6, 125 << 25 | 4]);
    body.push(vop1(1, 0, sgpr(16)));
    // buffer_load_dword v2, off, s[12:15], 0
    body.extend([0x38 << 26 | 0x0C << 18, 0x80 << 24 | 3 << 16 | 2 << 8]);
    body.extend(buffer_store_dword(2, 8, 4));
    // A different descriptor on the same heap still uses the CBV path.
    body.extend(s_load_dwordx4(20, 6, 64));
    body.extend([0x3D << 26 | 8 << 18 | 24 << 6 | 10, 125 << 25 | 8]);
    body.push(vop1(1, 3, sgpr(24)));
    body.extend(buffer_store_dword(3, 8, 8));
    let shader = build_cs(&body, &[], &[], true);
    for warp in [true, false] {
        let Ok(host) = Host::new(warp) else {
            eprintln!("no SM 6.6 device (requested WARP: {warp}); skipped");
            continue;
        };
        let (root, pipeline) = host.compute_pipeline(&shader).unwrap();
        let result = host.dispatch(&root, &pipeline, &Dispatch {
            roots: vec![(0, Root::Constants(vec![0; shader.user_data_dwords() as usize]))],
            views: &[
                View::RawUav(3),
                View::Buffer { data: &[0x1122_3344, 0xAABB_CCDD], stride: Stride::Raw },
                View::Cbv(&[0, 0, 0x5566_7788, 0]),
            ],
            samplers: &[],
            groups: [1, 1, 1],
        }).unwrap();
        assert_eq!(result[0], [0xAABB_CCDD, 0x1122_3344, 0x5566_7788], "requested WARP: {warp}");
    }
}

#[test]
fn integer_image_store_preserves_the_dword() {
    let _native_test_guard = super::native_test_guard();
    let body = [
        // s_load_dwordx8 s[16:23], s[4:5], 32
        0x3D << 26 | 3 << 18 | 16 << 6 | 2,
        125 << 25 | 32,
        vop1(1, 0, sgpr(0)),
        vop1(1, 4, 128), // v4 and v5: texel coordinates (0, 0)
        vop1(1, 5, 128),
        // image_store v[0:3], v[4:5], s[16:23] dmask:0xf dim:2d unorm
        0x3C << 26 | 8 << 18 | 1 << 12 | 0xF << 8 | 1 << 3,
        4 << 16 | 4,
    ];
    let shader = build_cs_for_views(
        &body,
        &[UsedResource {
            kind: ResourceType::Uav,
            root: RootType::Table,
            table_offset_dwords: 8,
            lower_bound: 1,
            stride: 4,
            dwords: 8,
            user_data: 4,
            slot: 1,
        }],
        &[IntegerView {
            kind: IntegerViewKind::ImageUav,
            slot: 1,
            table_offset_dwords: 8,
            signed: false,
        }],
    );
    let Ok(host) = Host::new(true) else {
        eprintln!("no SM 6.6 WARP device; skipped");
        return;
    };
    let (root, pipeline) = host.compute_pipeline(&shader).unwrap();
    let value = 0xF123_4567;
    let mut user_data = vec![0; shader.user_data_dwords() as usize];
    user_data[0] = value;
    let result = host
        .dispatch(
            &root,
            &pipeline,
            &Dispatch {
                roots: vec![(0, Root::Constants(user_data))],
                views: &[View::RawUav(1), View::UintTextureUav(1, 1)],
                samplers: &[],
                groups: [1, 1, 1],
            },
        )
        .unwrap();
    assert_eq!(result[0][0], value);
    assert_eq!(result[1][0], value);
}

#[test]
fn uint16_buffer_load_preserves_unsigned_indices() {
    use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_R16_UINT;

    let _native_test_guard = super::native_test_guard();
    let mut body = s_load_dwordx4(16, 4, 32).to_vec();
    // buffer_load_format_x v0, v1, s[16:19], 0 idxen
    body.extend([0xE000_2000, 0x8004_0001]);
    // Store the descriptor's element count alongside the loaded element.
    body.push(vop1(1, 2, sgpr(18)));
    body.extend(buffer_store_dword(2, 8, 4));
    let shader = build_cs_for_views(
        &body,
        &[UsedResource {
            kind: ResourceType::Srv,
            root: RootType::Table,
            table_offset_dwords: 8,
            lower_bound: 1,
            stride: 2,
            dwords: 4,
            user_data: 4,
            slot: 1,
        }],
        &[IntegerView {
            kind: IntegerViewKind::BufferSrv,
            slot: 1,
            table_offset_dwords: 8,
            signed: false,
        }],
    );
    let Ok(host) = Host::new(true) else {
        eprintln!("no SM 6.6 WARP device; skipped");
        return;
    };
    let (root, pipeline) = host.compute_pipeline(&shader).unwrap();
    let packed = [0xFFFF_002A];
    let views = [
        View::RawUav(2),
        View::Buffer {
            data: &packed,
            stride: Stride::Format(DXGI_FORMAT_R16_UINT, 2),
        },
    ];
    for (index, expected) in [(0, 42), (1, u16::MAX as u32)] {
        let mut user_data = vec![0; shader.user_data_dwords() as usize];
        user_data[0] = index;
        let result = host.dispatch(
            &root,
            &pipeline,
            &Dispatch {
                roots: vec![(0, Root::Constants(user_data))],
                views: &views,
                samplers: &[],
                groups: [1, 1, 1],
            },
        ).unwrap();
        assert_eq!(&result[0][..2], &[expected, 2]);
    }
}

fn table_buffer_uav(offset: u32) -> UsedResource {
    UsedResource {
        kind: ResourceType::Uav, root: RootType::Table, table_offset_dwords: offset,
        lower_bound: 1, stride: 0, dwords: 4, user_data: 4, slot: 1,
    }
}

fn uint16_uav(channels: u8) -> IntegerView {
    IntegerView { kind: IntegerViewKind::BufferUav { channels }, slot: 1, table_offset_dwords: 8, signed: false }
}

/// Ordinary MUBUF format load/store with an element index, zero byte offset,
/// descriptor s[16:19] and the first data VGPR at `data`.
fn buffer_format(op: u32, data: u8, index: u8) -> [u32; 2] {
    [0x38 << 26 | op << 18 | 1 << 13, 0x80 << 24 | 4 << 16 | u32::from(data) << 8 | u32::from(index)]
}

#[test]
fn fixed_uint16_buffer_uav_readback() {
    let _guard = super::native_test_guard();
    let host = Host::new(true).expect("SM 6.6 WARP");
    // The indexed load reads element 1. A full-width store writes element 2
    // with a new X and the other loaded channels. Read the dimensions too.
    for channels in [1u8, 4] {
        let mut body = s_load_dwordx4(16, 4, 32).to_vec();
        for v in 5..=7 { body.push(vop1(1, v, 128)); }
        body.extend(buffer_format(u32::from(channels - 1), 4, 1));
        body.push(vop1(1, 0, vgpr(4)));
        for k in 1..channels { body.extend(buffer_store_dword(4 + k, 8, 4 * u16::from(k))); }
        body.push(vop1(1, 4, sgpr(1)));
        body.push(vop1(1, 1, 130)); // inline constant 2
        body.extend(buffer_format(7, 4, 1)); // buffer_store_format_xyzw
        body.push(vop1(1, 2, sgpr(18))); // NUM_RECORDS
        body.extend(buffer_store_dword(2, 8, 4 * u16::from(channels)));
        let used = [table_buffer_uav(8)];
        let shader = build_cs_for_views(&body, &used, &[uint16_uav(channels)]);
        let base = build_cs_for_views(&body, &used, &[]);
        assert_ne!(shader.dxil, base.dxil);
        assert_eq!(shader.user_data, base.user_data);
        assert_eq!(shader.root_cbvs, base.root_cbvs);
        assert_eq!(shader.root_srvs, base.root_srvs);
        assert_eq!(shader.samplers, base.samplers);
        assert_eq!(shader.static_samplers, base.static_samplers);
        let (root, pipeline) = host.compute_pipeline(&shader).unwrap();
        let packed: &[u32] = if channels == 1 { &[0xfedc_4321, 0xabcd_0123] }
            else { &[1, 2, 0x8001_fedc, 0xffff_3456, 3, 4] };
        for x in [0xbabe, 0x1_0003] {
            let mut constants = vec![0; shader.user_data_dwords() as usize];
            constants[0] = 1;
            constants[1] = x;
            let result = host.dispatch(&root, &pipeline, &Dispatch {
                roots: vec![(0, Root::Constants(constants))],
                views: &[View::RawUav(u32::from(channels) + 1), View::Uint16Uav { channels, data: packed }],
                samplers: &[], groups: [1, 1, 1],
            }).unwrap();
            let x = x.min(0xffff);
            if channels == 1 {
                assert_eq!(result[0], [0xfedc, 4]);
                assert_eq!(result[1], [packed[0], 0xabcd_0000 | x]);
            } else {
                assert_eq!(result[0], [0xfedc, 0x8001, 0x3456, 0xffff, 3]);
                assert_eq!(result[1], [1, 2, packed[2], packed[3], 0x8001_0000 | x, packed[3]]);
            }
        }
    }
}

/// Runs `shader` on every available SM 6.6 host (hardware GPU and WARP) for
/// each 4-dword input set and invokes `check(backend, case_index, inputs, result_dword)`.
fn run_cases(
    shader: &HostShader,
    cases: &[[u32; 4]],
    mut check: impl FnMut(&str, usize, [u32; 4], u32),
) {
    let mut ran = 0;
    for (label, warp) in [("hardware", false), ("warp", true)] {
        let Ok(host) = Host::new(warp) else {
            eprintln!("no SM 6.6 {label} device; skipped");
            continue;
        };
        let (root, pso) = host
            .compute_pipeline(shader)
            .unwrap_or_else(|e| panic!("{label}: compute_pipeline failed: {e}"));
        for (i, &inputs) in cases.iter().enumerate() {
            let mut ud = vec![0u32; shader.user_data_dwords().max(1) as usize];
            for u in &shader.user_data {
                ud[u.index as usize] = match (u.root, u.slot) {
                    (RootType::Constants, 0) => inputs[u.dword as usize],
                    (RootType::Table, 1) => 0,
                    other => panic!("unexpected user data {other:?}"),
                };
            }
            let out = host
                .dispatch(
                    &root,
                    &pso,
                    &Dispatch {
                        roots: vec![(0, Root::Constants(ud))],
                        views: &[View::RawUav(1)],
                        samplers: &[],
                        groups: [1, 1, 1],
                    },
                )
                .unwrap_or_else(|e| panic!("{label}: dispatch failed: {e}"));
            check(label, i, inputs, out[0][0]);
        }
        ran += 1;
    }
    assert!(ran > 0, "neither hardware nor WARP SM 6.6 device available");
}

fn is_f16_nan(bits: u16) -> bool {
    (bits & 0x7FFF) > 0x7C00
}

fn f16_to_f32(bits: u16) -> f32 {
    let sign = u32::from(bits >> 15) << 31;
    let exp = (bits >> 10) & 0x1F;
    let mant = bits & 0x3FF;
    let f32_bits = match exp {
        0 => {
            if mant == 0 {
                sign
            } else {
                let mut m = u32::from(mant);
                let mut e = 127 - 14;
                while (m & 0x400) == 0 {
                    m <<= 1;
                    e -= 1;
                }
                sign | (e << 23) | ((m & 0x3FF) << 13)
            }
        }
        0x1F => sign | (0xFF << 23) | (u32::from(mant) << 13),
        _ => sign | ((u32::from(exp) + 112) << 23) | (u32::from(mant) << 13),
    };
    f32::from_bits(f32_bits)
}

#[test]
fn v_med3_f32_matches_rdna2_with_nan() {
    let _native_test_guard = super::native_test_guard();
    // v_med3_f32 v0, v1, v2, v3 (VOP3 opcode 0x157)
    let shader = build_valu_cs(&vop3(0x157, 0, vgpr(1), vgpr(2), vgpr(3)));
    let nan = f32::NAN.to_bits();
    let f = f32::to_bits;

    let cases: &[([u32; 4], Option<f32>)] = &[
        // Normal medians (all orderings).
        ([f(1.0), f(2.0), f(3.0), 0], Some(2.0)),
        ([f(3.0), f(1.0), f(2.0), 0], Some(2.0)),
        ([f(-5.0), f(0.0), f(5.0), 0], Some(0.0)),
        ([f(1.0), f(1.0), f(2.0), 0], Some(1.0)),
        // One NaN: RDNA2 returns min3 of the non-NaN operands.
        ([f(1.0), f(2.0), nan, 0], Some(1.0)),
        ([nan, f(1.0), f(0.0), 0], Some(0.0)),
        ([nan, f(0.0), f(1.0), 0], Some(0.0)),
        ([f(2.0), nan, f(1.0), 0], Some(1.0)),
        ([f(-3.0), nan, f(4.0), 0], Some(-3.0)),
        // Two NaNs: returns the sole non-NaN operand.
        ([nan, f(5.0), nan, 0], Some(5.0)),
        ([nan, nan, f(-2.0), 0], Some(-2.0)),
        ([f(7.0), nan, nan, 0], Some(7.0)),
        // Three NaNs: returns NaN.
        ([nan, nan, nan, 0], None),
    ];

    let inputs: Vec<[u32; 4]> = cases.iter().map(|c| c.0).collect();
    run_cases(&shader, &inputs, |backend, i, inp, got| {
        let expect = cases[i].1;
        let got_f = f32::from_bits(got);
        match expect {
            Some(want) => assert_eq!(
                got_f,
                want,
                "{backend}: v_med3_f32({:?}, {:?}, {:?}) = {got_f} ({got:#010x}), want {want}",
                f32::from_bits(inp[0]),
                f32::from_bits(inp[1]),
                f32::from_bits(inp[2]),
            ),
            None => assert!(
                got_f.is_nan(),
                "{backend}: v_med3_f32(NaN, NaN, NaN) = {got_f} ({got:#010x}), want NaN",
            ),
        }
    });
}

#[test]
fn v_med3_f16_matches_rdna2_with_nan() {
    let _native_test_guard = super::native_test_guard();
    // v_med3_f16 v0, v1, v2, v3 (VOP3 opcode 0x357)
    let shader = build_valu_cs(&vop3(0x357, 0, vgpr(1), vgpr(2), vgpr(3)));
    let h0 = 0x0000u32; // 0.0
    let h1 = 0x3C00u32; // 1.0
    let h2 = 0x4000u32; // 2.0
    let h3 = 0x4200u32; // 3.0
    let h5 = 0x4500u32; // 5.0
    let hn2 = 0xC000u32; // -2.0
    let nan = 0x7E00u32;

    let cases: &[([u32; 4], Option<u16>)] = &[
        ([h1, h2, h3, 0], Some(h2 as u16)),
        ([hn2, h0, h3, 0], Some(h0 as u16)),
        ([h1, h2, nan, 0], Some(h1 as u16)),
        ([nan, h1, h0, 0], Some(h0 as u16)),
        ([nan, h0, h1, 0], Some(h0 as u16)),
        ([h2, nan, h1, 0], Some(h1 as u16)),
        ([nan, h5, nan, 0], Some(h5 as u16)),
        ([nan, nan, nan, 0], None),
    ];

    let inputs: Vec<[u32; 4]> = cases.iter().map(|c| c.0).collect();
    run_cases(&shader, &inputs, |backend, i, inp, got| {
        let expect = cases[i].1;
        let got_h = got as u16;
        match expect {
            Some(want) => assert_eq!(
                got_h, want,
                "{backend}: v_med3_f16({:#06x}, {:#06x}, {:#06x}) = {got_h:#06x}, want {want:#06x}",
                inp[0], inp[1], inp[2],
            ),
            None => assert!(
                is_f16_nan(got_h),
                "{backend}: v_med3_f16(NaN, NaN, NaN) = {got_h:#06x}, want NaN",
            ),
        }
    });
}

#[test]
fn v_fract_f32_never_returns_one() {
    let _native_test_guard = super::native_test_guard();
    // v_fract_f32 v0, v1 (VOP1 opcode 0x020)
    let shader = build_valu_cs(&[vop1(0x020, 0, vgpr(1))]);
    let f = f32::to_bits;
    let below_one = 0x3F7F_FFFFu32;

    let cases: &[(u32, Option<u32>)] = &[
        // Tiny negatives: must clamp strictly below 1.0 (not 0x3f800000).
        (f(-1e-10), Some(below_one)),
        (f(-1e-8), Some(below_one)),
        (f(-2.0f32.powi(-25)), Some(below_one)),
        (f(-2.0f32.powi(-24)), Some(below_one)),
        // Normal values.
        (f(0.0), Some(f(0.0))),
        (f(-0.0), Some(f(0.0))),
        (f(0.25), Some(f(0.25))),
        (f(3.75), Some(f(0.75))),
        (f(-0.25), Some(f(0.75))),
        (f(-3.25), Some(f(0.75))),
        (f(1.0), Some(f(0.0))),
        (f(-1.0), Some(f(0.0))),
        // Non-finite inputs yield NaN.
        (f(f32::NAN), None),
        (f(f32::INFINITY), None),
        (f(f32::NEG_INFINITY), None),
    ];

    let inputs: Vec<[u32; 4]> = cases.iter().map(|&(x, _)| [x, 0, 0, 0]).collect();
    run_cases(&shader, &inputs, |backend, i, inp, got| {
        let expect = cases[i].1;
        match expect {
            Some(want) => assert_eq!(
                got,
                want,
                "{backend}: v_fract_f32({:?} / {:#010x}) = {got:#010x} ({:?}), want {want:#010x}",
                f32::from_bits(inp[0]),
                inp[0],
                f32::from_bits(got),
            ),
            None => assert!(
                f32::from_bits(got).is_nan(),
                "{backend}: v_fract_f32({:?}) = {got:#010x}, want NaN",
                f32::from_bits(inp[0]),
            ),
        }
    });
}

#[test]
fn v_fract_f16_never_returns_one() {
    let _native_test_guard = super::native_test_guard();
    // v_fract_f16 v0, v1 (VOP1 opcode 0x05f)
    let shader = build_valu_cs(&[vop1(0x05f, 0, vgpr(1))]);
    let below_one = 0x3BFFu16; // 1.0 - 2^-11

    assert_eq!(f16_to_f32(0x9400), -2.0f32.powi(-10));
    assert_eq!(f16_to_f32(0x9000), -2.0f32.powi(-11));
    assert_eq!(f16_to_f32(0x8C00), -2.0f32.powi(-12));

    let cases: &[(u16, Option<u16>)] = &[
        // Negatives in (-2^-11, 0): must clamp to 0x3BFF, never 0x3C00 (1.0).
        (0x8C00, Some(below_one)), // -2^-12
        (0x8400, Some(below_one)), // -2^-14
        (0x8001, Some(below_one)), // -2^-24 (smallest negative f16 subnormal)
        (0x9000, Some(below_one)), // -2^-11 (exact 1 - 2^-11 = 0x3BFF)
        (0x9400, Some(0x3BFE)),    // -2^-10 (exact 1 - 2^-10 = 0x3BFE)
        // Normal values.
        (0x0000, Some(0x0000)), // 0.0 -> 0.0
        (0x3400, Some(0x3400)), // 0.25 -> 0.25
        (0xB400, Some(0x3A00)), // -0.25 -> 0.75
        (0x4300, Some(0x3800)), // 3.5 -> 0.5
        (0x3C00, Some(0x0000)), // 1.0 -> 0.0
        // Non-finite inputs yield NaN.
        (0x7E00, None), // NaN
        (0x7C00, None), // +inf
        (0xFC00, None), // -inf
    ];

    let inputs: Vec<[u32; 4]> = cases
        .iter()
        .map(|&(x, _)| [u32::from(x), 0, 0, 0])
        .collect();
    run_cases(&shader, &inputs, |backend, i, inp, got| {
        let expect = cases[i].1;
        let got_h = got as u16;
        match expect {
            Some(want) => assert_eq!(
                got_h, want,
                "{backend}: v_fract_f16({:#06x}) = {got_h:#06x}, want {want:#06x}",
                inp[0],
            ),
            None => assert!(
                is_f16_nan(got_h),
                "{backend}: v_fract_f16({:#06x}) = {got_h:#06x}, want NaN",
                inp[0],
            ),
        }
    });
}

#[test]
fn v_sin_and_v_cos_f32_reduce_large_turns() {
    let _native_test_guard = super::native_test_guard();
    let sin_shader = build_valu_cs(&[vop1(0x035, 0, vgpr(1))]);
    let cos_shader = build_valu_cs(&[vop1(0x036, 0, vgpr(1))]);
    let f = f32::to_bits;
    let half_sqrt2 = std::f32::consts::FRAC_1_SQRT_2;

    let sin_cases: &[(f32, Option<f32>)] = &[
        (0.0, Some(0.0)),
        (0.25, Some(1.0)),
        (255.0, Some(0.0)),
        (255.25, Some(1.0)),
        (255.5, Some(0.0)),
        (-255.25, Some(-1.0)),
        (10_000.125, Some(half_sqrt2)),
        (f32::NAN, None),
        (f32::INFINITY, None),
        (f32::NEG_INFINITY, None),
    ];
    let sin_inputs: Vec<[u32; 4]> = sin_cases.iter().map(|&(x, _)| [f(x), 0, 0, 0]).collect();
    run_cases(&sin_shader, &sin_inputs, |backend, i, inp, got| {
        let expect = sin_cases[i].1;
        let got_f = f32::from_bits(got);
        match expect {
            Some(want) => assert!(
                (got_f - want).abs() < 1e-5,
                "{backend}: v_sin_f32({}) = {got_f}, want {want} (err = {})",
                f32::from_bits(inp[0]),
                (got_f - want).abs(),
            ),
            None => assert!(
                got_f.is_nan(),
                "{backend}: v_sin_f32({}) = {got_f}, want NaN",
                f32::from_bits(inp[0]),
            ),
        }
    });

    let cos_cases: &[(f32, Option<f32>)] = &[
        (0.0, Some(1.0)),
        (0.25, Some(0.0)),
        (255.0, Some(1.0)),
        (255.25, Some(0.0)),
        (255.5, Some(-1.0)),
        (-255.5, Some(-1.0)),
        (10_000.125, Some(half_sqrt2)),
        (f32::NAN, None),
        (f32::INFINITY, None),
        (f32::NEG_INFINITY, None),
    ];
    let cos_inputs: Vec<[u32; 4]> = cos_cases.iter().map(|&(x, _)| [f(x), 0, 0, 0]).collect();
    run_cases(&cos_shader, &cos_inputs, |backend, i, inp, got| {
        let expect = cos_cases[i].1;
        let got_f = f32::from_bits(got);
        match expect {
            Some(want) => assert!(
                (got_f - want).abs() < 1e-5,
                "{backend}: v_cos_f32({}) = {got_f}, want {want} (err = {})",
                f32::from_bits(inp[0]),
                (got_f - want).abs(),
            ),
            None => assert!(
                got_f.is_nan(),
                "{backend}: v_cos_f32({}) = {got_f}, want NaN",
                f32::from_bits(inp[0]),
            ),
        }
    });

    // Main's `trig_turns` preserves sin(-0.0) = -0.0 and produces exact +0.0 at
    // half-turns (sin) and quarter-turns (cos).
    let exact_sin: &[(u32, u32)] = &[
        (0x8000_0000, 0x8000_0000), // sin(-0.0) = -0.0
        (f(255.0), 0),              // sin(255.0) = +0.0
        (f(255.5), 0),              // sin(255.5) = +0.0
    ];
    let exact_sin_in: Vec<[u32; 4]> = exact_sin.iter().map(|&(x, _)| [x, 0, 0, 0]).collect();
    run_cases(&sin_shader, &exact_sin_in, |backend, i, inp, got| {
        let want = exact_sin[i].1;
        assert_eq!(
            got, want,
            "{backend}: v_sin_f32({:#010x}) = {got:#010x}, want {want:#010x}",
            inp[0],
        );
    });
    let exact_cos: &[(u32, u32)] = &[
        (f(0.25), 0),   // cos(0.25) = +0.0
        (f(255.25), 0), // cos(255.25) = +0.0
    ];
    let exact_cos_in: Vec<[u32; 4]> = exact_cos.iter().map(|&(x, _)| [x, 0, 0, 0]).collect();
    run_cases(&cos_shader, &exact_cos_in, |backend, i, inp, got| {
        let want = exact_cos[i].1;
        assert_eq!(
            got, want,
            "{backend}: v_cos_f32({:#010x}) = {got:#010x}, want {want:#010x}",
            inp[0],
        );
    });
}

#[test]
fn v_sin_and_v_cos_f16_reduce_large_turns() {
    let _native_test_guard = super::native_test_guard();
    let sin_shader = build_valu_cs(&[vop1(0x060, 0, vgpr(1))]);
    let cos_shader = build_valu_cs(&[vop1(0x061, 0, vgpr(1))]);

    // Sanity-check the f16 bit encodings of large turns.
    assert_eq!(f16_to_f32(0x5BF8), 255.0);
    assert_eq!(f16_to_f32(0x5BFA), 255.25);
    assert_eq!(f16_to_f32(0x5BFC), 255.5);
    assert_eq!(f16_to_f32(0x7BFF), 65504.0);

    let sin_cases: &[(u16, Option<f32>)] = &[
        (0x5BF8, Some(0.0)),  // 255.0
        (0x5BFA, Some(1.0)),  // 255.25
        (0x5BFC, Some(0.0)),  // 255.5
        (0xDBFA, Some(-1.0)), // -255.25
        (0x7BFF, Some(0.0)),  // 65504.0 (largest finite f16, exact integer)
        (0x7E00, None),       // NaN
        (0x7C00, None),       // +inf
        (0xFC00, None),       // -inf
    ];
    let sin_inputs: Vec<[u32; 4]> = sin_cases
        .iter()
        .map(|&(x, _)| [u32::from(x), 0, 0, 0])
        .collect();
    run_cases(&sin_shader, &sin_inputs, |backend, i, inp, got| {
        let expect = sin_cases[i].1;
        let got_h = got as u16;
        match expect {
            Some(want) => {
                let got_f = f16_to_f32(got_h);
                assert!(
                    (got_f - want).abs() < 1e-3,
                    "{backend}: v_sin_f16({:#06x} = {}) = {got_f} ({got_h:#06x}), want {want}",
                    inp[0],
                    f16_to_f32(inp[0] as u16),
                );
            }
            None => assert!(
                is_f16_nan(got_h),
                "{backend}: v_sin_f16({:#06x}) = {got_h:#06x}, want NaN",
                inp[0],
            ),
        }
    });

    let cos_cases: &[(u16, Option<f32>)] = &[
        (0x5BF8, Some(1.0)),  // 255.0
        (0x5BFA, Some(0.0)),  // 255.25
        (0x5BFC, Some(-1.0)), // 255.5
        (0x7BFF, Some(1.0)),  // 65504.0 (largest finite f16, exact integer)
        (0x7E00, None),       // NaN
        (0x7C00, None),       // +inf
        (0xFC00, None),       // -inf
    ];
    let cos_inputs: Vec<[u32; 4]> = cos_cases
        .iter()
        .map(|&(x, _)| [u32::from(x), 0, 0, 0])
        .collect();
    run_cases(&cos_shader, &cos_inputs, |backend, i, inp, got| {
        let expect = cos_cases[i].1;
        let got_h = got as u16;
        match expect {
            Some(want) => {
                let got_f = f16_to_f32(got_h);
                assert!(
                    (got_f - want).abs() < 1e-3,
                    "{backend}: v_cos_f16({:#06x} = {}) = {got_f} ({got_h:#06x}), want {want}",
                    inp[0],
                    f16_to_f32(inp[0] as u16),
                );
            }
            None => assert!(
                is_f16_nan(got_h),
                "{backend}: v_cos_f16({:#06x}) = {got_h:#06x}, want NaN",
                inp[0],
            ),
        }
    });
}

#[test]
fn bfe_signed_and_unsigned_match_rdna2() {
    let _native_test_guard = super::native_test_guard();
    // v_bfe_i32 v0, v1, v2, v3 (VOP3 opcode 0x149)
    let v_signed = build_valu_cs(&vop3(0x149, 0, vgpr(1), vgpr(2), vgpr(3)));
    // v_bfe_u32 v0, v1, v2, v3 (VOP3 opcode 0x148)
    let v_unsigned = build_valu_cs(&vop3(0x148, 0, vgpr(1), vgpr(2), vgpr(3)));
    // s_bfe_i32 s6, s0, s1 (SOP2 opcode 0x28: s1 = off[4:0] | width[22:16]); v_mov_b32 v0, s6
    let s_signed = build_valu_cs(&[sop2(0x28, 6, 0, 1), vop1(0x001, 0, sgpr(6))]);

    let signed_cases: &[([u32; 4], u32)] = &[
        // Field crosses bit 31: extends from bit 31.
        ([0xd2f9_0159, 28, 16, 0], 0xffff_fffd),
        ([0x8000_0000, 31, 4, 0], 0xffff_ffff),
        ([0x7000_0000, 28, 8, 0], 0x0000_0007),
        // Normal fields inside 32 bits.
        ([0x0000_0080, 4, 4, 0], 0xffff_fff8),
        ([0x0000_0070, 4, 4, 0], 0x0000_0007),
        // Edge widths: 0 yields 0; v_bfe masks width to 5 bits (32 -> 0),
        // while 31 extracts all remaining bits from offset 4.
        ([0xffff_ffff, 4, 0, 0], 0),
        ([0x8000_0000, 4, 31, 0], 0xf800_0000),
    ];
    let v_in: Vec<[u32; 4]> = signed_cases.iter().map(|c| c.0).collect();
    run_cases(&v_signed, &v_in, |backend, i, inp, got| {
        let want = signed_cases[i].1;
        assert_eq!(
            got, want,
            "{backend}: v_bfe_i32({:#010x}, {}, {}) = {got:#010x}, want {want:#010x}",
            inp[0], inp[1], inp[2],
        );
    });
    // v_bfe_i32 width is 5-bit (src2[4:0]), so width=32 wraps to 0.
    run_cases(
        &v_signed,
        &[[0x8000_0000, 4, 32, 0]],
        |backend, _, _, got| {
            assert_eq!(got, 0, "{backend}: v_bfe_i32 width 32 should mask to 0");
        },
    );

    // s_bfe_i32 width is 7-bit (src1[22:16]), so width=32 keeps all 32 bits.
    let mut s_cases = signed_cases.to_vec();
    s_cases.push(([0x8000_0000, 4, 32, 0], 0xf800_0000));
    let s_in: Vec<[u32; 4]> = s_cases
        .iter()
        .map(|&(inp, _)| [inp[0], (inp[1] & 31) | ((inp[2] & 0x7F) << 16), 0, 0])
        .collect();
    run_cases(&s_signed, &s_in, |backend, i, inp, got| {
        let want = s_cases[i].1;
        assert_eq!(
            got, want,
            "{backend}: s_bfe_i32({:#010x}, {:#010x}) = {got:#010x}, want {want:#010x}",
            inp[0], inp[1],
        );
    });

    let unsigned_cases: &[([u32; 4], u32)] = &[
        ([0xd2f9_0159, 28, 16, 0], 0x0000_000d),
        ([0x8000_0000, 31, 4, 0], 0x0000_0001),
        ([0xffff_ffff, 4, 0, 0], 0),
        ([0x8000_0000, 4, 31, 0], 0x0800_0000),
    ];
    let u_in: Vec<[u32; 4]> = unsigned_cases.iter().map(|c| c.0).collect();
    run_cases(&v_unsigned, &u_in, |backend, i, inp, got| {
        let want = unsigned_cases[i].1;
        assert_eq!(
            got, want,
            "{backend}: v_bfe_u32({:#010x}, {}, {}) = {got:#010x}, want {want:#010x}",
            inp[0], inp[1], inp[2],
        );
    });
}
