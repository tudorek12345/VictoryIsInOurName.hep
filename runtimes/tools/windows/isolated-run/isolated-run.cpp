#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <userenv.h>
#include <objbase.h>

#include <algorithm>
#include <filesystem>
#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace fs = std::filesystem;

struct Failure {
    std::wstring operation;
    DWORD code = 0;
};

void check(BOOL ok, const std::wstring& operation) {
    if (!ok) throw Failure{operation, GetLastError()};
}

void status(DWORD code, const std::wstring& operation) {
    if (code) throw Failure{operation, code};
}

struct Handle {
    HANDLE value;
    explicit Handle(HANDLE handle) : value(handle) {}
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};

struct LocalMemory {
    HLOCAL value = nullptr;
    ~LocalMemory() { if (value) LocalFree(value); }
};

bool same(const fs::path& left, const fs::path& right) {
    return CompareStringOrdinal(left.c_str(), -1, right.c_str(), -1, TRUE) == CSTR_EQUAL;
}

bool within(const fs::path& path, const fs::path& root) {
    auto current = path.begin();
    for (const auto& folder : root) {
        if (current == path.end() || !same(*current++, folder)) return false;
    }
    return true;
}

fs::path absolute(const wchar_t* value) {
    auto path = fs::absolute(value).lexically_normal();
    if (path.root_name().native().size() != 2 || path.root_name().native()[1] != L':' ||
        path.native().find(L':', 2) != std::wstring::npos) {
        throw Failure{L"Expected a normal local path: " + path.native()};
    }
    return path;
}

void ordinary(const fs::path& path, bool single_link) {
    const DWORD attrs = GetFileAttributesW(path.c_str());
    check(attrs != INVALID_FILE_ATTRIBUTES, L"Inspect " + path.native());
    if (attrs & FILE_ATTRIBUTE_REPARSE_POINT) throw Failure{L"Reparse point: " + path.native()};
    if (single_link && !(attrs & FILE_ATTRIBUTE_DIRECTORY) && fs::hard_link_count(path) != 1) {
        throw Failure{L"File shares a hard link: " + path.native()};
    }
}

void inside_stage(const fs::path& path, const fs::path& stage) {
    if (!within(path, stage) || same(path, stage)) throw Failure{L"Outside stage: " + path.native()};
    for (auto current = path; current != current.root_path(); current = current.parent_path()) {
        ordinary(current, same(current, path));
    }
}

struct Options {
    fs::path program;
    fs::path log;
    fs::path output;
    fs::path external_input;
    std::vector<fs::path> inputs;
    std::vector<std::wstring> arguments;
    std::map<std::wstring, std::wstring> environment;
    DWORD timeout_ms = 0;
    SIZE_T commit_bytes = 0;
    ULONGLONG reserve_physical_bytes = 0;
    ULONGLONG reserve_commit_bytes = 0;
    bool reuse_output = false;
};

unsigned number(const std::wstring& value, unsigned min, unsigned max) {
    if (value.empty() || value.size() > 7 || value.find_first_not_of(L"0123456789") != value.npos) {
        throw Failure{L"Expected an integer: " + value};
    }
    const auto parsed = std::stoul(value);
    if (parsed < min || parsed > max) throw Failure{L"Value out of range: " + value};
    return parsed;
}

Options parse(int argc, wchar_t** argv) {
    Options options;
    for (int i = 1; i < argc; ++i) {
        const std::wstring key = argv[i];
        if (key == L"--") {
            for (++i; i < argc; ++i) options.arguments.emplace_back(argv[i]);
            break;
        }
        if (key == L"--reuse-output") {
            options.reuse_output = true;
            continue;
        }
        if (++i == argc) throw Failure{L"Missing value for " + key};
        if (key == L"--program") options.program = absolute(argv[i]);
        else if (key == L"--log") options.log = absolute(argv[i]);
        else if (key == L"--modify") options.output = absolute(argv[i]);
        else if (key == L"--rx") options.inputs.push_back(absolute(argv[i]));
        else if (key == L"--external-rx" && options.external_input.empty()) options.external_input = absolute(argv[i]);
        else if (key == L"--seconds") options.timeout_ms = 1000 * number(argv[i], 1, 3600);
        else if (key == L"--commit-mib") options.commit_bytes = SIZE_T{1024 * 1024} * number(argv[i], 64, 131072);
        else if (key == L"--reserve-physical-mib") options.reserve_physical_bytes = 1048576ULL * number(argv[i], 512, 131072);
        else if (key == L"--reserve-commit-mib") options.reserve_commit_bytes = 1048576ULL * number(argv[i], 512, 131072);
        else if (key == L"--env") {
            const std::wstring entry = argv[i];
            const auto split = entry.find(L'=');
            const auto name = entry.substr(0, split);
            const bool victory_variable = name.starts_with(L"VICTORY_") &&
                name.find_first_not_of(L"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") == name.npos;
            const bool xcl_variable = name == L"XCL_DATA_ROOT" || name == L"XCL_DXC_DIR" ||
                name == L"XCL_ADAPTER" || name == L"XCL_NETWORK" || name == L"XCL_FRAME_DUMP" ||
                name == L"XCL_DRED" || name == L"XCL_ACTIVITY";
            if (split == entry.npos || (!victory_variable && !xcl_variable)) {
                throw Failure{L"--env requires a supported Victory or XCL variable"};
            }
            options.environment[name] = entry.substr(split + 1);
        } else throw Failure{L"Unknown option " + key};
    }
    if (options.program.empty() || options.log.empty() || options.output.empty() ||
        options.inputs.empty() || !options.timeout_ms || !options.commit_bytes) {
        throw Failure{L"Required: --program EXE --rx DIR [--rx DIR] --modify EMPTY_DIR --log NEW_FILE "
                      L"--seconds N --commit-mib N [--reserve-physical-mib N] [--reserve-commit-mib N] [--reuse-output] "
                      L"[--external-rx PACKAGE_DIR] [--env NAME=VALUE] [-- ARGS]"};
    }
    return options;
}

void validate(const Options& options, const fs::path& stage) {
    inside_stage(options.program, stage);
    inside_stage(options.output, stage);
    inside_stage(options.log.parent_path(), stage);
    if (!fs::is_regular_file(options.program) || !same(options.program.extension(), L".exe") ||
        !fs::is_directory(options.output) ||
        (!options.reuse_output && !fs::is_empty(options.output)) || fs::exists(options.log)) {
        throw Failure{L"Use an existing EXE, an empty modify directory and a new log file"};
    }
    if (options.reuse_output) {
        for (const auto& entry : fs::recursive_directory_iterator(options.output))
            ordinary(entry.path(), true);
    }
    if (within(options.log, options.output)) throw Failure{L"Log must be outside the modify directory"};
    bool has_program = false;
    for (size_t i = 0; i < options.inputs.size(); ++i) {
        const auto& input = options.inputs[i];
        inside_stage(input, stage);
        if (!fs::is_directory(input) || within(input, options.output) || within(options.output, input) ||
            within(options.log, input)) throw Failure{L"Overlapping grant or log: " + input.native()};
        for (size_t j = 0; j < i; ++j) {
            if (within(input, options.inputs[j]) || within(options.inputs[j], input)) {
                throw Failure{L"Overlapping RX grants: " + input.native()};
            }
        }
        has_program |= within(options.program, input);
        for (const auto& entry : fs::recursive_directory_iterator(input)) ordinary(entry.path(), true);
    }
    if (!has_program) throw Failure{L"The program must be inside an RX directory"};
}

struct Profile {
    std::wstring name;
    PSID sid = nullptr;

    Profile() {
        GUID guid{};
        status(CoCreateGuid(&guid), L"Create unique profile name");
        wchar_t id[40]{};
        StringFromGUID2(guid, id, ARRAYSIZE(id));
        name = L"VictoryLocal-" + std::wstring(id + 1, 36);
        status(CreateAppContainerProfile(name.c_str(), name.c_str(), L"Local isolated run", nullptr, 0, &sid),
               L"CreateAppContainerProfile");
    }
    bool remove() {
        if (name.empty()) return true;
        std::wstring profile;
        profile.swap(name);
        auto result = DeleteAppContainerProfile(profile.c_str());
        // Profile files can stay in use briefly after the job has exited.
        constexpr DWORD delays_ms[]{125, 250, 500, 1000, 1000, 1000, 1000};
        for (const auto delay : delays_ms) {
            if (result != HRESULT_FROM_WIN32(ERROR_SHARING_VIOLATION)) break;
            Sleep(delay);
            result = DeleteAppContainerProfile(profile.c_str());
        }
        if (FAILED(result)) {
            std::wcerr << L"DeleteAppContainerProfile failed for " << profile << L" (0x" << std::hex << result << L")\n";
            return false;
        }
        return true;
    }
    ~Profile() {
        remove();
        if (sid) FreeSid(sid);
    }
};

struct Grant {
    fs::path path;
    LocalMemory original;
    PACL old_dacl = nullptr;
    PACL old_label = nullptr;
    bool changed_dacl = false;
    bool changed_label = false;

    explicit Grant(fs::path dir) : path(std::move(dir)) {}

    static constexpr DWORD denied_package_access = FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA |
        FILE_WRITE_ATTRIBUTES | FILE_DELETE_CHILD | DELETE | WRITE_DAC | WRITE_OWNER;

    void add(PSID sid, bool writable, bool external = false) {
        const DWORD flags = DACL_SECURITY_INFORMATION | (writable ? LABEL_SECURITY_INFORMATION : 0);
        status(GetNamedSecurityInfoW(path.c_str(), SE_FILE_OBJECT, flags, nullptr, nullptr,
                                    &old_dacl, &old_label, &original.value), L"Read access rules for " + path.native());
        EXPLICIT_ACCESSW entries[2]{};
        auto& access = entries[0];
        access.grfAccessPermissions = FILE_GENERIC_READ | FILE_GENERIC_EXECUTE;
        if (writable) access.grfAccessPermissions |= FILE_GENERIC_WRITE | DELETE;
        access.grfAccessMode = GRANT_ACCESS;
        access.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
        BuildTrusteeWithSidW(&access.Trustee, sid);
        std::vector<std::byte> user;
        if (external) {
            auto& deny = entries[1];
            deny.grfAccessPermissions = denied_package_access;
            deny.grfAccessMode = DENY_ACCESS;
            deny.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
            BuildTrusteeWithSidW(&deny.Trustee, sid);
        }
        if (writable) {
            // The directory owner can grant itself WRITE_OWNER for the label
            // operation even where the inherited DACL only grants Modify.
            HANDLE token = nullptr;
            check(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token), L"Open launcher token");
            Handle close_token(token);
            DWORD size = 0;
            GetTokenInformation(token, TokenUser, nullptr, 0, &size);
            user.resize(size);
            check(GetTokenInformation(token, TokenUser, user.data(), size, &size), L"Read launcher SID");
            auto& label_writer = entries[1];
            label_writer.grfAccessPermissions = WRITE_OWNER;
            label_writer.grfAccessMode = GRANT_ACCESS;
            BuildTrusteeWithSidW(&label_writer.Trustee, reinterpret_cast<TOKEN_USER*>(user.data())->User.Sid);
        }
        LocalMemory new_dacl;
        PACL acl = nullptr;
        status(SetEntriesInAclW(writable || external ? 2 : 1, entries, old_dacl, &acl), L"Build access rules");
        new_dacl.value = acl;
        status(SetNamedSecurityInfoW(const_cast<wchar_t*>(path.c_str()), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
                                    nullptr, nullptr, acl, nullptr), L"Grant access to " + path.native());
        changed_dacl = true;
        if (!writable) return;

        LocalMemory label;
        check(ConvertStringSecurityDescriptorToSecurityDescriptorW(
            L"S:(ML;OICI;NW;;;LW)", SDDL_REVISION_1, &label.value, nullptr), L"Build low-integrity label");
        BOOL present = FALSE, defaulted = FALSE;
        PACL sacl = nullptr;
        check(GetSecurityDescriptorSacl(label.value, &present, &sacl, &defaulted), L"Read low-integrity label");
        status(SetNamedSecurityInfoW(const_cast<wchar_t*>(path.c_str()), SE_FILE_OBJECT, LABEL_SECURITY_INFORMATION,
                                    nullptr, nullptr, nullptr, sacl), L"Set output integrity label");
        changed_label = true;
    }

    bool restore() {
        auto restore_rule = [&](bool& changed, DWORD flag, PACL dacl, PACL label) {
            if (!changed) return true;
            const DWORD error = SetNamedSecurityInfoW(const_cast<wchar_t*>(path.c_str()), SE_FILE_OBJECT,
                                                       flag, nullptr, nullptr, dacl, label);
            if (!error) changed = false;
            else std::wcerr << L"Restore access rules failed for " << path.native() << L" (" << error << L")\n";
            return !error;
        };
        const bool label = restore_rule(changed_label, LABEL_SECURITY_INFORMATION, nullptr, old_label);
        const bool dacl = restore_rule(changed_dacl, DACL_SECURITY_INFORMATION, old_dacl, nullptr);
        return label && dacl;
    }
    ~Grant() { restore(); }
};

struct PackageRules {
    std::vector<std::vector<std::byte>> entries;
    bool protected_acl = false;
    bool denies_write = false;
    bool allows_read = false;
};

PackageRules package_rules(const fs::path& path, PSID sid) {
    LocalMemory descriptor;
    PACL acl = nullptr;
    status(GetNamedSecurityInfoW(path.c_str(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, nullptr,
                                nullptr, &acl, nullptr, &descriptor.value), L"Read package ACL for " + path.native());
    if (!acl) throw Failure{L"No package DACL on " + path.native()};
    SECURITY_DESCRIPTOR_CONTROL control = 0;
    DWORD revision = 0;
    check(GetSecurityDescriptorControl(descriptor.value, &control, &revision), L"Read package ACL flags");
    PackageRules rules;
    rules.protected_acl = (control & SE_DACL_PROTECTED) != 0;
    for (DWORD i = 0; i < acl->AceCount; ++i) {
        void* entry = nullptr;
        check(GetAce(acl, i, &entry), L"Read package access entry");
        const auto& header = *static_cast<const ACE_HEADER*>(entry);
        const auto* start = static_cast<const std::byte*>(entry);
        rules.entries.emplace_back(start, start + header.AceSize);
        if (!sid || (header.AceFlags & INHERIT_ONLY_ACE)) continue;
        if (header.AceType == ACCESS_DENIED_ACE_TYPE) {
            auto& deny = *static_cast<ACCESS_DENIED_ACE*>(entry);
            rules.denies_write |= EqualSid(&deny.SidStart, sid) &&
                (deny.Mask & Grant::denied_package_access) == Grant::denied_package_access;
        } else if (header.AceType == ACCESS_ALLOWED_ACE_TYPE) {
            auto& allow = *static_cast<ACCESS_ALLOWED_ACE*>(entry);
            rules.allows_read |= EqualSid(&allow.SidStart, sid) &&
                (allow.Mask & (FILE_GENERIC_READ | FILE_GENERIC_EXECUTE)) == (FILE_GENERIC_READ | FILE_GENERIC_EXECUTE) &&
                !(allow.Mask & Grant::denied_package_access);
        }
    }
    return rules;
}

struct ExternalPackage {
    Grant grant;
    std::vector<std::pair<fs::path, PackageRules>> baseline;
    bool active = false;

    ExternalPackage(const fs::path& package, const fs::path& stage) : grant(package) {
#ifdef VICTORY_TEST_EXTERNAL_PACKAGE
        const auto allowed = stage.parent_path() / L"external-test-package";
#else
        (void)stage;
        const fs::path allowed = LR"(D:\BuildGTA$\buildgta)";
#endif
        if (!same(package, allowed)) throw Failure{L"The only permitted external package is " + allowed.native()};
        for (auto current = package; current != current.root_path(); current = current.parent_path()) {
            ordinary(current, false);
        }
        if (!fs::is_directory(package)) throw Failure{L"External package is not a directory"};
        auto inspect = [&](const fs::path& path) {
            ordinary(path, true);
            auto rules = package_rules(path, nullptr);
            if (rules.protected_acl) throw Failure{L"External package ACL blocks inheritance: " + path.native()};
            baseline.emplace_back(path, std::move(rules));
        };
        inspect(package);
        for (const auto& entry : fs::recursive_directory_iterator(package)) inspect(entry.path());
    }

    void open(PSID sid) {
        active = true;
        grant.add(sid, false, true);
        for (const auto& [path, baseline_rules] : baseline) {
            const auto rules = package_rules(path, sid);
            if (!rules.denies_write || !rules.allows_read) throw Failure{L"Cannot verify external RX grant for " + path.native()};
        }
    }

    bool restore() noexcept {
        if (!active) return true;
        try {
            if (!grant.restore()) return false;
            for (const auto& [path, before] : baseline) {
                const auto after = package_rules(path, nullptr);
                if (after.entries != before.entries || after.protected_acl != before.protected_acl) {
                    std::wcerr << L"External package ACEs changed on " << path.native() << L"\n";
                    return false;
                }
            }
            active = false;
            std::wcout << L"Verified restored package access rules on " << baseline.size() << L" paths.\n";
            return true;
        } catch (const Failure& failure) {
            std::wcerr << failure.operation << L" (0x" << std::hex << failure.code << L")\n";
        } catch (const std::exception& failure) {
            std::cerr << failure.what() << '\n';
        }
        return false;
    }
    ~ExternalPackage() { restore(); }
};

struct Attributes {
    std::vector<std::byte> memory;
    LPPROC_THREAD_ATTRIBUTE_LIST list = nullptr;
    Attributes() {
        SIZE_T size = 0;
        InitializeProcThreadAttributeList(nullptr, 3, 0, &size);
        memory.resize(size);
        list = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(memory.data());
        check(InitializeProcThreadAttributeList(list, 3, 0, &size), L"Initialize process attributes");
    }
    ~Attributes() { DeleteProcThreadAttributeList(list); }

    void set(DWORD_PTR attribute, void* value, SIZE_T size) {
        check(UpdateProcThreadAttribute(list, 0, attribute, value, size, nullptr, nullptr), L"Set process attribute");
    }
};

std::wstring quote(const std::wstring& argument) {
    std::wstring out = L"\"";
    size_t slashes = 0;
    for (const auto ch : argument) {
        if (ch == L'\\') ++slashes;
        else {
            out.append(ch == L'\"' ? 2 * slashes + 1 : slashes, L'\\');
            slashes = 0;
            out.push_back(ch);
        }
    }
    out.append(2 * slashes, L'\\');
    return out + L'\"';
}

std::wstring environment(const Options& options) {
    auto vars = options.environment;
    wchar_t windows[MAX_PATH]{};
    check(GetWindowsDirectoryW(windows, ARRAYSIZE(windows)) != 0, L"Locate Windows");
    vars[L"SYSTEMROOT"] = vars[L"WINDIR"] = windows;
    vars[L"PATH"] = std::wstring(windows) + L"\\System32;" + windows;
    vars[L"TEMP"] = vars[L"TMP"] = vars[L"LOCALAPPDATA"] = options.output.native();
    std::wstring block;
    for (const auto& [key, value] : vars) {
        block += key + L"=" + value;
        block.push_back(L'\0');
    }
    return block;
}

void verify_token(HANDLE process, PSID expected, HANDLE job) {
    HANDLE token = nullptr;
    check(OpenProcessToken(process, TOKEN_QUERY, &token), L"Open child token");
    Handle close_token(token);
    DWORD is_container = 0, size = 0;
    check(GetTokenInformation(token, TokenIsAppContainer, &is_container, sizeof(is_container), &size), L"Query AppContainer token");
    if (!is_container) throw Failure{L"The suspended child did not receive an AppContainer token"};
    GetTokenInformation(token, TokenAppContainerSid, nullptr, 0, &size);
    std::vector<std::byte> info(size);
    check(GetTokenInformation(token, TokenAppContainerSid, info.data(), size, &size), L"Read child AppContainer SID");
    if (!EqualSid(expected, reinterpret_cast<TOKEN_APPCONTAINER_INFORMATION*>(info.data())->TokenAppContainer)) {
        throw Failure{L"The suspended child's AppContainer SID mismatched"};
    }
    GetTokenInformation(token, TokenCapabilities, nullptr, 0, &size);
    info.resize(size);
    check(GetTokenInformation(token, TokenCapabilities, info.data(), size, &size), L"Read child capabilities");
    if (reinterpret_cast<TOKEN_GROUPS*>(info.data())->GroupCount) throw Failure{L"The suspended child has capabilities"};
    BOOL assigned = FALSE;
    check(IsProcessInJob(process, job, &assigned), L"Verify child job assignment");
    if (!assigned) throw Failure{L"The suspended child is outside the bounded job"};
}

DWORD run(const Options& options, const Profile& container) {
    Handle job(CreateJobObjectW(nullptr, nullptr));
    check(job.value != nullptr, L"Create process job");
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE |
        JOB_OBJECT_LIMIT_PROCESS_MEMORY | JOB_OBJECT_LIMIT_JOB_MEMORY | JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
    limits.ProcessMemoryLimit = limits.JobMemoryLimit = options.commit_bytes;
    check(SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits)), L"Set job commit limits");

    SECURITY_ATTRIBUTES inheritable{sizeof(inheritable), nullptr, TRUE};
    Handle log(CreateFileW(options.log.c_str(), FILE_APPEND_DATA | SYNCHRONIZE, FILE_SHARE_READ,
                           &inheritable, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
    check(log.value != INVALID_HANDLE_VALUE, L"Create log " + options.log.native());
    Handle input(CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                             &inheritable, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
    check(input.value != INVALID_HANDLE_VALUE, L"Open inert stdin");

    SECURITY_CAPABILITIES security{container.sid, nullptr, 0, 0};
    HANDLE inherited[]{log.value, input.value};
    Attributes attributes;
    attributes.set(PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES, &security, sizeof(security));
    attributes.set(PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited, sizeof(inherited));
    attributes.set(PROC_THREAD_ATTRIBUTE_JOB_LIST, &job.value, sizeof(job.value));

    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdOutput = startup.StartupInfo.hStdError = log.value;
    startup.StartupInfo.hStdInput = input.value;
    startup.lpAttributeList = attributes.list;
    PROCESS_INFORMATION child{};
    auto command = quote(options.program.native());
    for (const auto& arg : options.arguments) command += L" " + quote(arg);
    auto env = environment(options);
    check(CreateProcessW(options.program.c_str(), command.data(), nullptr, nullptr, TRUE,
                         EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                         env.data(), options.program.parent_path().c_str(), &startup.StartupInfo, &child), L"Create suspended AppContainer child");
    Handle process(child.hProcess), thread(child.hThread);
    verify_token(process.value, container.sid, job.value);
    std::wcout << L"Verified zero-capability AppContainer and bounded job. Child PID " << child.dwProcessId << std::endl;
    check(ResumeThread(thread.value) != DWORD(-1), L"Resume verified child");

    const ULONGLONG deadline = GetTickCount64() + options.timeout_ms;
    const bool guard_memory = options.reserve_physical_bytes || options.reserve_commit_bytes;
    DWORD result = 124;
    while (true) {
        if (guard_memory) {
            MEMORYSTATUSEX memory{sizeof(MEMORYSTATUSEX)};
            check(GlobalMemoryStatusEx(&memory), L"Query available physical memory");
            if (memory.ullAvailPhys < options.reserve_physical_bytes) {
                std::wcout << L"Host memory guard reached. Available physical bytes: " << memory.ullAvailPhys
                           << L"; reserve bytes: " << options.reserve_physical_bytes << L". Terminating job.\n";
                result = 126;
                break;
            }
            if (memory.ullAvailPageFile < options.reserve_commit_bytes) {
                std::wcout << L"Host commit guard reached. Available commit bytes: " << memory.ullAvailPageFile
                           << L"; reserve bytes: " << options.reserve_commit_bytes << L". Terminating job.\n";
                result = 126;
                break;
            }
        }
        const auto now = GetTickCount64();
        const auto remaining = static_cast<DWORD>(now < deadline ? deadline - now : 0);
        const auto slice = guard_memory ? std::min(remaining, DWORD{500}) : remaining;
        const auto wait = WaitForSingleObject(process.value, slice);
        if (wait == WAIT_OBJECT_0) {
            check(GetExitCodeProcess(process.value, &result), L"Read child exit code");
            break;
        }
        check(wait == WAIT_TIMEOUT, L"Wait for child process");
        if (GetTickCount64() >= deadline) {
            std::wcout << L"Timeout reached. Terminating job.\n";
            break;
        }
    }
    check(TerminateJobObject(job.value, result), L"Terminate remaining job processes");
    for (int attempt = 0; attempt != 200; ++attempt) {
        JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
        check(QueryInformationJobObject(job.value, JobObjectBasicAccountingInformation, &accounting,
                                        sizeof(accounting), nullptr), L"Confirm job exited");
        if (!accounting.ActiveProcesses) {
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION measured{};
            if (QueryInformationJobObject(job.value, JobObjectExtendedLimitInformation,
                                          &measured, sizeof(measured), nullptr)) {
                std::wcout << L"Peak job commit bytes: " << measured.PeakJobMemoryUsed
                           << L"; limit bytes: " << options.commit_bytes << L"\n";
            }
            return result;
        }
        Sleep(25);
    }
    throw Failure{L"Job termination did not finish within five seconds"};
}

int wmain(int argc, wchar_t** argv) {
    try {
        wchar_t module[32768]{};
        const DWORD length = GetModuleFileNameW(nullptr, module, ARRAYSIZE(module));
        check(length && length < ARRAYSIZE(module), L"Locate helper directory");
        const auto stage = absolute(module).parent_path() / L"stage";
        auto options = parse(argc, argv);
        validate(options, stage);
        std::unique_ptr<ExternalPackage> external;
        if (!options.external_input.empty()) external = std::make_unique<ExternalPackage>(options.external_input, stage);
        Profile container;
        std::vector<std::unique_ptr<Grant>> grants;
        auto grant = [&](const fs::path& dir, bool writable) {
            grants.push_back(std::make_unique<Grant>(dir));
            grants.back()->add(container.sid, writable);
        };
        for (const auto& input : options.inputs) grant(input, false);
        grant(options.output, true);
        if (external) external->open(container.sid);
        const DWORD result = run(options, container);
        bool restored = true;
        if (external) restored &= external->restore();
        for (auto& access : grants) restored &= access->restore();
        if (!container.remove() || !restored) return 125;
        std::wcout << L"Job ended and stage grants were restored. Child result " << result << L"\n";
        return static_cast<int>(result);
    } catch (const Failure& failure) {
        std::wcerr << failure.operation << L" (0x" << std::hex << failure.code << L")\n";
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
    }
    return 125;
}
