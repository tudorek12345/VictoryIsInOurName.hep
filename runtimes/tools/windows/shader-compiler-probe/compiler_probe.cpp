#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <vector>
#include <chrono>
#include <fstream>

using Microsoft::WRL::ComPtr;

static void address(const char* label, DWORD64 pc) noexcept {
    HMODULE module = nullptr;
    wchar_t name[MAX_PATH]{};
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(pc), &module)) {
        GetModuleFileNameW(module, name, MAX_PATH);
    }
    const wchar_t* slash = std::wcsrchr(name, L'\\');
    std::fprintf(stderr, "%s=%ls+0x%llx address=0x%llx\n", label,
                 slash ? slash + 1 : name,
                 static_cast<unsigned long long>(pc - reinterpret_cast<DWORD64>(module)),
                 static_cast<unsigned long long>(pc));
}

// Unwind only the captured faulting thread; no symbol download or process dump.
static void stack(CONTEXT context) noexcept {
    for (unsigned frame = 0; frame < 24 && context.Rip; ++frame) {
        address("stack", context.Rip);
        const DWORD64 old = context.Rip;
        DWORD64 image = 0;
        PRUNTIME_FUNCTION function = RtlLookupFunctionEntry(context.Rip, &image, nullptr);
        if (function) {
            PVOID handler = nullptr;
            DWORD64 establisher = 0;
            __try {
                RtlVirtualUnwind(UNW_FLAG_NHANDLER, image, context.Rip, function,
                                 &context, &handler, &establisher, nullptr);
            } __except (EXCEPTION_EXECUTE_HANDLER) { break; }
        } else {
            DWORD64 next = 0;
            SIZE_T read = 0;
            if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(context.Rsp),
                                   &next, sizeof(next), &read) || read != sizeof(next)) break;
            context.Rip = next;
            context.Rsp += sizeof(next);
        }
        if (context.Rip == old) break;
    }
}

static LONG WINAPI crash(EXCEPTION_POINTERS* info) noexcept {
    const auto* record = info->ExceptionRecord;
    const auto* context = info->ContextRecord;
    std::fprintf(stderr, "exception=0x%08lx parameters=%lu\n",
                 record->ExceptionCode, record->NumberParameters);
    address("fault", reinterpret_cast<DWORD64>(record->ExceptionAddress));
    if (record->NumberParameters >= 2) {
        std::fprintf(stderr, "access=%llu target=0x%llx\n",
                     static_cast<unsigned long long>(record->ExceptionInformation[0]),
                     static_cast<unsigned long long>(record->ExceptionInformation[1]));
    }
    std::fprintf(stderr, "rcx=0x%llx rdx=0x%llx r8=0x%llx r9=0x%llx rsp=0x%llx\n",
                 context->Rcx, context->Rdx, context->R8, context->R9, context->Rsp);
    stack(*context);
    std::fflush(stderr);
    return EXCEPTION_EXECUTE_HANDLER;
}

static int failed(const char* step, HRESULT hr) {
    std::fprintf(stderr, "step=%s result=0x%08lx\n", step, static_cast<unsigned long>(hr));
    return 1;
}

static std::vector<unsigned char> read_shader(const wchar_t* path) {
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return {};
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 32 || size.QuadPart > 16 * 1024 * 1024) {
        CloseHandle(file);
        return {};
    }
    std::vector<unsigned char> bytes(static_cast<size_t>(size.QuadPart));
    DWORD got = 0;
    const bool ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &got, nullptr)
                    && got == bytes.size();
    CloseHandle(file);
    if (!ok || std::memcmp(bytes.data(), "DXBC", 4)) return {};
    return bytes;
}

int wmain(int argc, wchar_t** argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    SetUnhandledExceptionFilter(crash);
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::setvbuf(stderr, nullptr, _IONBF, 0);
    const wchar_t* cache_path = nullptr;
    if (argc >= 4 && !std::wcscmp(argv[argc - 2], L"--cache")) {
        cache_path = argv[argc - 1];
        argc -= 2;
    }
    const bool mixed = argc == 3 && !std::wcscmp(argv[2], L"--mixed-array");
    const bool array16 = argc == 3 && !std::wcscmp(argv[2], L"--array16");
    const bool unbounded = (argc == 3 && !std::wcscmp(argv[2], L"--array")) || mixed;
    if (argc < 2 || argc > 3 || (argc == 3 && std::wcscmp(argv[2], L"--explicit") && !array16 && !unbounded)) {
        std::fprintf(stderr, "usage: compiler_probe.exe SHADER.dxil [--explicit|--array16|--array|--mixed-array] [--cache PATH]\n");
        return 2;
    }
    const bool explicit_registers = argc == 3;
    auto bytes = read_shader(argv[1]);
    if (bytes.empty()) return failed("read_shader", HRESULT_FROM_WIN32(ERROR_INVALID_DATA));
    std::printf("shader_bytes=%zu root_mode=%s pid=%lu\n", bytes.size(),
                mixed ? "mixed-table-and-heaps" : unbounded ? "unbounded-table" : array16 ? "finite-table" :
                explicit_registers ? "explicit-registers" : "direct-heaps", GetCurrentProcessId());

    ComPtr<IDXGIFactory4> factory;
    HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return failed("CreateDXGIFactory1", hr);
    ComPtr<IDXGIAdapter1> adapter;
    DXGI_ADAPTER_DESC1 description{};
    for (UINT n = 0; ; ++n) {
        ComPtr<IDXGIAdapter1> candidate;
        hr = factory->EnumAdapters1(n, &candidate);
        if (hr == DXGI_ERROR_NOT_FOUND) break;
        if (FAILED(hr)) return failed("EnumAdapters1", hr);
        hr = candidate->GetDesc1(&description);
        if (FAILED(hr)) return failed("GetDesc1", hr);
        if (description.VendorId == 0x1002 && description.DeviceId == 0x7590 &&
            !(description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
            adapter = candidate;
            break;
        }
    }
    if (!adapter) return failed("required Radeon RX 9060 XT (1002:7590) absent", DXGI_ERROR_NOT_FOUND);
    std::printf("adapter=%ls vendor=0x%x device=0x%x vram_bytes=%zu\n", description.Description,
                description.VendorId, description.DeviceId, description.DedicatedVideoMemory);
    LARGE_INTEGER driver{};
    hr = adapter->CheckInterfaceSupport(__uuidof(IDXGIDevice), &driver);
    if (SUCCEEDED(hr)) std::printf("driver_version=0x%llx\n", static_cast<unsigned long long>(driver.QuadPart));
    ComPtr<ID3D12Device> device;
    hr = D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device));
    if (FAILED(hr)) return failed("D3D12CreateDevice", hr);
    D3D12_FEATURE_DATA_SHADER_CACHE cache_support{};
    hr = device->CheckFeatureSupport(D3D12_FEATURE_SHADER_CACHE, &cache_support, sizeof(cache_support));
    if (SUCCEEDED(hr)) std::printf("shader_cache_support=0x%x\n", cache_support.SupportFlags);
    D3D12_FEATURE_DATA_D3D12_OPTIONS1 waves{};
    hr = device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS1, &waves, sizeof(waves));
    if (SUCCEEDED(hr)) std::printf("wave_operations=%d lanes=%u..%u\n", waves.WaveOps,
                                 waves.WaveLaneCountMin, waves.WaveLaneCountMax);

    D3D12_ROOT_PARAMETER parameters[3]{};
    parameters[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;
    parameters[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
    parameters[0].Constants = {0, 0, explicit_registers ? 62u : 64u};
    D3D12_DESCRIPTOR_RANGE ranges[2]{};
    if (explicit_registers) {
        // For the UAV array, u0 is the destination and source entries begin at u1.
        const UINT srvs = unbounded ? UINT_MAX : array16 ? 16u : 1u;
        const UINT uavs = unbounded ? UINT_MAX : array16 ? 17u : 1u;
        ranges[0] = {D3D12_DESCRIPTOR_RANGE_TYPE_SRV, srvs, 0, 0, D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND};
        ranges[1] = {D3D12_DESCRIPTOR_RANGE_TYPE_UAV, uavs, 0, 0, D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND};
        for (unsigned i = 0; i < 2; ++i) {
            parameters[i + 1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
            parameters[i + 1].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
            parameters[i + 1].DescriptorTable = {1, &ranges[i]};
        }
    }
    D3D12_ROOT_SIGNATURE_DESC signature{};
    signature.NumParameters = explicit_registers ? 3u : 1u;
    signature.pParameters = parameters;
    signature.Flags = (explicit_registers && !mixed) ? D3D12_ROOT_SIGNATURE_FLAG_NONE :
        static_cast<D3D12_ROOT_SIGNATURE_FLAGS>(D3D12_ROOT_SIGNATURE_FLAG_CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED |
                                              D3D12_ROOT_SIGNATURE_FLAG_SAMPLER_HEAP_DIRECTLY_INDEXED);
    ComPtr<ID3DBlob> serialized, errors;
    hr = D3D12SerializeRootSignature(&signature, D3D_ROOT_SIGNATURE_VERSION_1,
                                   &serialized, &errors);
    if (FAILED(hr)) {
        if (errors) std::fprintf(stderr, "root_error=%.*s\n", static_cast<int>(errors->GetBufferSize()),
                                 static_cast<const char*>(errors->GetBufferPointer()));
        return failed("D3D12SerializeRootSignature", hr);
    }
    ComPtr<ID3D12RootSignature> root;
    hr = device->CreateRootSignature(0, serialized->GetBufferPointer(), serialized->GetBufferSize(),
                                    IID_PPV_ARGS(&root));
    if (FAILED(hr)) return failed("CreateRootSignature", hr);
    D3D12_COMPUTE_PIPELINE_STATE_DESC desc{};
    desc.pRootSignature = root.Get();
    desc.CS = {bytes.data(), bytes.size()};
    std::vector<unsigned char> cached;
    if (cache_path) {
        std::ifstream file(cache_path, std::ios::binary | std::ios::ate);
        if (file) {
            const auto size = file.tellg();
            if (size <= 0 || size > 64 * 1024 * 1024) return failed("cache_size", E_INVALIDARG);
            cached.resize(static_cast<size_t>(size));
            file.seekg(0);
            if (!file.read(reinterpret_cast<char*>(cached.data()), static_cast<std::streamsize>(cached.size()))) return failed("cache_read", E_FAIL);
            desc.CachedPSO = {cached.data(), cached.size()};
        }
        std::printf("cached_input_bytes=%zu\n", cached.size());
    }
    ComPtr<ID3D12PipelineState> pipeline;
    std::printf("step=CreateComputePipelineState begin\n");
    const auto start = std::chrono::steady_clock::now();
    hr = device->CreateComputePipelineState(&desc, IID_PPV_ARGS(&pipeline));
    const double elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now()-start).count();
    std::printf("step=CreateComputePipelineState result=0x%08lx elapsed_ms=%.3f\n",
                static_cast<unsigned long>(hr), elapsed);
    if (SUCCEEDED(hr) && cache_path) {
        ComPtr<ID3DBlob> blob;
        hr = pipeline->GetCachedBlob(&blob);
        if (FAILED(hr)) return failed("GetCachedBlob", hr);
        std::printf("cached_output_bytes=%zu\n", blob->GetBufferSize());
        std::ofstream file(cache_path, std::ios::binary | std::ios::trunc);
        if (!file.write(static_cast<const char*>(blob->GetBufferPointer()), static_cast<std::streamsize>(blob->GetBufferSize()))) return failed("cache_write", E_FAIL);
    }
    // No command queue, allocator, command list, resources, dispatch or fence.
    return FAILED(hr) ? 1 : 0;
}
