#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <array>
#include <cstring>
#include <iostream>
#include <vector>

bool same_file(const wchar_t* path) {
    const HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    std::array<char, 16> bytes{};
    DWORD n = 0;
    const BOOL read = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &n, nullptr);
    CloseHandle(file);
    return read && n == 5 && std::memcmp(bytes.data(), "probe", n) == 0;
}

bool write_file(const wchar_t* path, bool allow) {
    const HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        const DWORD error = GetLastError();
        std::cerr << "CreateFileW returned " << error << "\n";
        return !allow && error == ERROR_ACCESS_DENIED;
    }
    DWORD written = 0;
    const BOOL write = WriteFile(file, "probe", 5, &written, nullptr);
    CloseHandle(file);
    return allow && write && written == 5;
}

bool read_denied(const wchar_t* path) {
    const HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_ACCESS_DENIED;
    CloseHandle(file);
    return false;
}

bool socket_denied(const wchar_t* address, u_short port) {
    WSADATA ws{};
    if (WSAStartup(MAKEWORD(2, 2), &ws) != 0) return false;
    const SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) {
        WSACleanup();
        return false;
    }
    sockaddr_in target{};
    target.sin_family = AF_INET;
    target.sin_port = htons(port);
    u_long nonblocking = 1;
    const bool ready = InetPtonW(AF_INET, address, &target.sin_addr) == 1 &&
                       ioctlsocket(s, FIONBIO, &nonblocking) == 0;
    int error = ready && connect(s, reinterpret_cast<sockaddr*>(&target), sizeof(target)) == SOCKET_ERROR
        ? WSAGetLastError() : 0;
    if (error == WSAEWOULDBLOCK) {
        fd_set writable, failed;
        FD_ZERO(&writable);
        FD_ZERO(&failed);
        FD_SET(s, &writable);
        FD_SET(s, &failed);
        timeval limit{2, 0};
        const int selected = select(0, nullptr, &writable, &failed, &limit);
        int length = sizeof(error);
        if (!selected) error = WSAETIMEDOUT;
        else if (selected == SOCKET_ERROR || getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error), &length)) {
            error = WSAGetLastError();
        }
    }
    closesocket(s);
    WSACleanup();
    std::cerr << "connect returned " << error << "\n";
    return error == WSAEACCES || error == WSAETIMEDOUT;
}

bool commit_denied() {
    auto excess = VirtualAlloc(nullptr, SIZE_T{96} * 1024 * 1024, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (excess) {
        VirtualFree(excess, 0, MEM_RELEASE);
        return false;
    }
    const DWORD error = GetLastError();
    std::cerr << "96 MiB commit returned " << error << "\n";
    return error == ERROR_COMMITMENT_LIMIT || error == ERROR_NOT_ENOUGH_MEMORY || error == ERROR_COMMITMENT_MINIMUM;
}

int wmain(int argc, wchar_t** argv) {
    if (argc == 2 && std::wcscmp(argv[1], L"grow") == 0) {
        // Small controlled allocations cross the warning threshold before
        // the hard cap, without requiring system-wide memory pressure.
        std::vector<void*> allocations;
        for (unsigned i = 0; i != 40; ++i) {
            auto* p = VirtualAlloc(nullptr, 1024 * 1024, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
            if (!p) { std::cerr << "probe allocation failed\n"; return 20; }
            allocations.push_back(p);
            Sleep(100);
        }
        std::cout << "Waiting after controlled allocations" << std::endl;
        Sleep(15000);
        for (auto* p : allocations) VirtualFree(p, 0, MEM_RELEASE);
        return 21;
    }
    if (argc == 2 && std::wcscmp(argv[1], L"wait") == 0) {
        std::cout << "Waiting in test process" << std::endl;
        Sleep(15000);
        return 10;
    }
    if (argc != 7) return 9;
    if (!same_file(argv[1])) { std::cerr << "Read-only input read failed\n"; return 11; }
    if (!write_file(argv[2], false)) { std::cerr << "Read-only input allowed creation\n"; return 12; }
    if (!write_file(argv[3], true)) { std::cerr << "Output write failed\n"; return 13; }
    if (!read_denied(argv[4])) { std::cerr << "Unspecified input was readable\n"; return 14; }
    if (!socket_denied(argv[5], static_cast<u_short>(std::wcstoul(argv[6], nullptr, 10)))) {
        std::cerr << "Outward socket was not blocked\n";
        return 15;
    }
    if (!commit_denied()) { std::cerr << "Commit limit was not enforced\n"; return 16; }
    std::cout << "Read-only input, writable output, denied unspecified input, denied socket and bounded commit all passed\n";
}
