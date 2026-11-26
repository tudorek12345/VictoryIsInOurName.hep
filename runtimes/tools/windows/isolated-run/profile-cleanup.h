#pragma once

#include <algorithm>
#include <array>
#include <cstdint>

namespace profile_cleanup {
inline constexpr std::uint32_t sharing_violation = 0x80070020u;
inline constexpr std::uint64_t retry_budget_ms = 30000;
inline constexpr std::array<std::uint32_t, 12> delays_ms{
    125, 250, 500, 1000, 2000, 4000, 4000, 4000, 4000, 4000, 4000, 2125
};

struct Result {
    std::uint32_t status;
    unsigned attempts = 1;
    std::uint64_t waited_ms = 0;
    std::uint64_t elapsed_ms = 0;
    bool succeeded() const { return (status & 0x80000000u) == 0; }
};

// The injected clock/sleeper make deadline, status and exit-code behavior
// deterministic in tests. Only sharing violations are transient here.
// No new attempt starts after the 30-second retry deadline; a synchronous
// Windows API call already in progress cannot itself be interrupted.
template<class Delete, class Sleep, class Clock>
Result remove(Delete erase, Sleep wait, Clock now) {
    const auto began = now();
    Result result{static_cast<std::uint32_t>(erase())};
    for (const auto delay : delays_ms) {
        result.elapsed_ms = now() - began;
        if (result.status != sharing_violation || result.elapsed_ms >= retry_budget_ms) break;
        const auto pause = static_cast<std::uint32_t>(
            std::min<std::uint64_t>(delay, retry_budget_ms - result.elapsed_ms));
        wait(pause);
        result.waited_ms += pause;
        if (now() - began > retry_budget_ms) break;
        result.status = static_cast<std::uint32_t>(erase());
        ++result.attempts;
    }
    result.elapsed_ms = now() - began;
    return result;
}

inline std::uint32_t exit_code(std::uint32_t runtime, bool profile_removed, bool grants_restored) {
    return profile_removed && grants_restored ? runtime : 125;
}
}
