// Authored capability probe: creates and maps 4 MiB buffers; executes no GPU commands.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstring>
#include <initializer_list>
using Microsoft::WRL::ComPtr;
int main() {
    ComPtr<IDXGIFactory4> factory;
    if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return 1;
    ComPtr<ID3D12Device> device;
    for (UINT i = 0;; ++i) {
        ComPtr<IDXGIAdapter1> adapter;
        if (FAILED(factory->EnumAdapters1(i, &adapter))) break;
        DXGI_ADAPTER_DESC1 desc{};
        if (FAILED(adapter->GetDesc1(&desc))) continue;
        if (desc.VendorId != 0x1002 || (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) continue;
        if (SUCCEEDED(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device)))) {
            std::printf("adapter=%ls\n", desc.Description);
            break;
        }
    }
    if (!device) return 2;
    D3D12_FEATURE_DATA_D3D12_OPTIONS16 options{};
    HRESULT hr = device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS16, &options, sizeof(options));
    std::printf("options16=0x%08lx supported=%d\n", static_cast<unsigned long>(hr), options.GPUUploadHeapSupported);
    if (FAILED(hr) || !options.GPUUploadHeapSupported) return 3;
    for (const bool writable : {false, true}) {
        D3D12_HEAP_PROPERTIES heap{};
        heap.Type = D3D12_HEAP_TYPE_GPU_UPLOAD;
        D3D12_RESOURCE_DESC desc{};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        desc.Width = 4 * 1024 * 1024;
        desc.Height = desc.DepthOrArraySize = desc.MipLevels = 1;
        desc.SampleDesc.Count = 1;
        desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        desc.Flags = writable ? D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS : D3D12_RESOURCE_FLAG_NONE;
        ComPtr<ID3D12Resource> resource;
        hr = device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &desc,
            D3D12_RESOURCE_STATE_COMMON, nullptr, IID_PPV_ARGS(&resource));
        std::printf("uav=%d create=0x%08lx\n", writable, static_cast<unsigned long>(hr));
        if (FAILED(hr)) return 4;
        void* mapped = nullptr;
        D3D12_RANGE noRead{0, 0};
        hr = resource->Map(0, &noRead, &mapped);
        std::printf("uav=%d map=0x%08lx\n", writable, static_cast<unsigned long>(hr));
        if (FAILED(hr)) return 5;
        memset(mapped, 0x5A, 4096);
        D3D12_RANGE written{0, 4096};
        resource->Unmap(0, &written);
    }
    return 0;
}
