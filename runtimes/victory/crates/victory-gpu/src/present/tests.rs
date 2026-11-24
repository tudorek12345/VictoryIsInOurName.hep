use super::*;
use crate::host::{Host, host, transition};

const FORMAT: DXGI_FORMAT = DXGI_FORMAT_R8G8B8A8_UNORM;
const TARGET: D3D12_RESOURCE_STATES = D3D12_RESOURCE_STATE_RENDER_TARGET;

fn target(host: &Host, width: u32, height: u32) -> ID3D12Resource {
    let mut target = None;
    // SAFETY: ordinary RGBA8 target with an owned out pointer.
    unsafe {
        host.device
            .CreateCommittedResource(
                &D3D12_HEAP_PROPERTIES {
                    Type: D3D12_HEAP_TYPE_DEFAULT,
                    ..Default::default()
                },
                D3D12_HEAP_FLAG_NONE,
                &D3D12_RESOURCE_DESC {
                    Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
                    Width: width.into(),
                    Height: height,
                    DepthOrArraySize: 1,
                    MipLevels: 1,
                    Format: FORMAT,
                    SampleDesc: DXGI_SAMPLE_DESC {
                        Count: 1,
                        Quality: 0,
                    },
                    Flags: D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
                    ..Default::default()
                },
                TARGET,
                None,
                &mut target,
            )
            .unwrap();
    }
    target.unwrap()
}

fn pixels(host: &Host, out: &ID3D12Resource) -> Vec<u8> {
    let list = host.new_list().unwrap();
    let copy = D3D12_RESOURCE_STATE_COPY_SOURCE;
    // SAFETY: live target and open list; restore the target for the next run.
    let (buffer, placed) = unsafe {
        list.list.ResourceBarrier(&[transition(out, TARGET, copy)]);
        let read = crate::capture::read_back(&host.device, &list.list, out).unwrap();
        list.list.ResourceBarrier(&[transition(out, copy, TARGET)]);
        read
    };
    list.close();
    host.execute(&[&list]);
    let mut data = std::ptr::null_mut();
    let f = placed.Footprint;
    let mut pixels = Vec::with_capacity((f.Width * f.Height * 4) as usize);
    // SAFETY: execute waited; read only the copied bytes, excluding row padding.
    unsafe {
        buffer.Map(0, None, Some(&mut data)).unwrap();
        for y in 0..f.Height {
            let row = data
                .cast::<u8>()
                .add(placed.Offset as usize + (y * f.RowPitch) as usize);
            pixels.extend_from_slice(std::slice::from_raw_parts(row, f.Width as usize * 4));
        }
        buffer.Unmap(0, None);
    }
    pixels
}

#[test]
fn scales_and_blends_two_planes() {
    let Some(host) = host() else { return };
    let compositor = Compositor::new(&host.device, FORMAT).unwrap();
    let base = target(host, 8, 8);
    let overlay = target(host, 16, 16);
    let out = target(host, 4, 4);
    let list = host.new_list().unwrap();
    // SAFETY: both targets are live, in RENDER_TARGET, on an open list.
    unsafe {
        list.list
            .ClearRenderTargetView(host.rtv(&base, None), &[0.0, 0.0, 1.0, 1.0], None);
        list.list
            .ClearRenderTargetView(host.rtv(&overlay, None), &[0.5, 0.0, 0.0, 0.5], None);
    }
    compositor.record(
        &host.device,
        &list.list,
        &out,
        &[(&base, TARGET.0 as u32), (&overlay, TARGET.0 as u32)],
        4,
        4,
    );
    list.close();
    host.execute(&[&list]);
    assert!(
        pixels(host, &out)
            .chunks_exact(4)
            .all(|p| p == [128, 0, 127, 255])
    );
}

// Write a repeating, high-frequency RGBA8 pattern. Neighbours differ in both
// axes, including alpha 0, 255 and intermediate values. No title resources.
fn patterned(host: &Host, width: u32, height: u32, seed: u8) -> ID3D12Resource {
    let tex = target(host, width, height);
    let pitch = (width * 4).next_multiple_of(256);
    let (upload, data) = host
        .upload_buffer(u64::from(pitch) * u64::from(height))
        .unwrap();
    let list = host.new_list().unwrap();
    // SAFETY: upload spans all pitched rows; borrowed COM pointers in the two
    // copy locations remain live until execute has waited for the copy.
    unsafe {
        for y in 0..height {
            for x in 0..width {
                let h = (x * 73 + y * 151 + u32::from(seed)) as u8;
                let alpha = h.rotate_left(3);
                let pixel = [
                    h.min(alpha),
                    (!h).min(alpha),
                    h.rotate_left(5).min(alpha),
                    alpha,
                ];
                data.add((y * pitch + x * 4) as usize)
                    .cast::<[u8; 4]>()
                    .write(pixel);
            }
        }
        upload.Unmap(0, None);
        let src = D3D12_TEXTURE_COPY_LOCATION {
            pResource: std::mem::transmute_copy(&upload),
            Type: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
            Anonymous: D3D12_TEXTURE_COPY_LOCATION_0 {
                PlacedFootprint: D3D12_PLACED_SUBRESOURCE_FOOTPRINT {
                    Offset: 0,
                    Footprint: D3D12_SUBRESOURCE_FOOTPRINT {
                        Format: FORMAT,
                        Width: width,
                        Height: height,
                        Depth: 1,
                        RowPitch: pitch,
                    },
                },
            },
        };
        let dst = D3D12_TEXTURE_COPY_LOCATION {
            pResource: std::mem::transmute_copy(&tex),
            Type: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
            Anonymous: D3D12_TEXTURE_COPY_LOCATION_0 {
                SubresourceIndex: 0,
            },
        };
        let copy = D3D12_RESOURCE_STATE_COPY_DEST;
        list.list.ResourceBarrier(&[transition(&tex, TARGET, copy)]);
        list.list.CopyTextureRegion(&dst, 0, 0, 0, &src, None);
        list.list.ResourceBarrier(&[transition(&tex, copy, TARGET)]);
    }
    list.close();
    host.execute(&[&list]);
    tex
}

fn compare(host: &Host, width: u32, height: u32, overlay_size: (u32, u32), benchmark: bool) {
    let mut linear = Compositor::new(&host.device, FORMAT).unwrap();
    linear.overlay_3x = None;
    let candidate = Compositor::new(&host.device, FORMAT).unwrap();
    let base = patterned(host, 3 * width / 2, 3 * height / 2, 11);
    let overlay = patterned(host, overlay_size.0, overlay_size.1, 239);
    // SAFETY: the fixture owns this live overlay.
    let desc = unsafe { overlay.GetDesc() };
    let selected = candidate.plane_pso(1, &desc, width, height);
    let fast = candidate.overlay_3x.as_ref().expect("3x overlay PSO");
    assert_eq!(selected == fast, overlay_size == (3 * width, 3 * height));
    assert_eq!(
        candidate.plane_pso(0, &desc, width, height),
        &candidate.opaque
    );
    let srgb = D3D12_RESOURCE_DESC {
        Format: DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
        ..desc
    };
    assert_eq!(
        candidate.plane_pso(1, &srgb, width, height),
        &candidate.overlay
    );
    let reference_out = target(host, width, height);
    let out = target(host, width, height);
    let planes = [(&base, TARGET.0 as u32), (&overlay, TARGET.0 as u32)];
    let list = host.new_list().unwrap();
    list.close();
    let render = |compositor: &Compositor, target: &ID3D12Resource| {
        list.reset();
        compositor.record(&host.device, &list.list, target, &planes, width, height);
        list.close();
        host.execute(&[&list]);
    };
    render(&linear, &reference_out);
    let expected = pixels(host, &reference_out);
    assert!(expected.chunks_exact(4).any(|p| p != &expected[..4]));
    render(&candidate, &out);
    let actual = pixels(host, &out);
    if let Some(i) = actual.iter().zip(&expected).position(|(a, e)| a != e) {
        panic!(
            "at ({}, {}), channel {}: got {}, expected {}",
            (i / 4) % width as usize,
            (i / 4) / width as usize,
            i % 4,
            actual[i],
            expected[i]
        );
    }
    if benchmark {
        // Timed region is recording + submission/fence only. Alternate order
        // after warm-up; do not turn host load into a flaky pass/fail test.
        let mut samples = [Vec::new(), Vec::new()];
        for pair in 0..109 {
            for i in [pair % 2, 1 - pair % 2] {
                let start = std::time::Instant::now();
                render([&linear, &candidate][i], &out);
                if pair >= 8 {
                    samples[i].push(start.elapsed());
                }
            }
        }
        for (name, mut times) in ["linear", "3x load"].into_iter().zip(samples) {
            times.sort();
            eprintln!(
                "{name} compositor median ({}/path) {:?}",
                times.len(),
                times[times.len() / 2]
            );
        }
    }
}

#[test]
fn overlay_matches_linear_including_fractional_scales() {
    let Some(host) = host() else { return };
    for overlay in [(93, 51), (92, 51), (93, 52), (62, 34)] {
        compare(host, 31, 17, overlay, false);
    }
}

#[test]
#[ignore = "full-size compositor A/B; run explicitly on the selected D3D12 adapter"]
fn measure_720p_compositor() {
    compare(
        host().expect("D3D12 adapter required"),
        1280,
        720,
        (3840, 2160),
        true,
    );
}
