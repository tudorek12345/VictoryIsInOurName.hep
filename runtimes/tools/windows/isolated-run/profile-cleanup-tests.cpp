#include "profile-cleanup.h"
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace profile_cleanup;

void expect(bool condition, const char* what) {
    if (!condition) throw std::runtime_error(what);
}

struct Fixture {
    std::vector<std::uint32_t> results;
    std::vector<std::uint32_t> sleeps;
    unsigned calls = 0;
    std::uint64_t clock = 0;
    std::uint64_t api_ms = 0;
    std::uint64_t oversleep_ms = 0;
    Result run() {
        return remove([&] {
            clock += api_ms;
            return results[std::min<std::size_t>(calls++, results.size() - 1)];
        }, [&](std::uint32_t delay) { sleeps.push_back(delay); clock += delay + oversleep_ms; }, [&] { return clock; });
    }
};

int main() {
    try {
        unsigned tests = 0;
        for (const auto success : {0u, 1u}) {
            Fixture f{{success}};
            const auto r = f.run();
            expect(r.succeeded() && r.attempts == 1 && f.sleeps.empty(), "immediate success must not retry");
        }
        ++tests;
        {
            Fixture f{{sharing_violation, sharing_violation, 0}};
            const auto r = f.run();
            expect(r.succeeded() && r.attempts == 3 && r.elapsed_ms == 375 && r.waited_ms == 375, "sharing then success");
            expect(f.sleeps == std::vector<std::uint32_t>{125, 250}, "ordered backoff");
            ++tests;
        }
        {
            Fixture f{{sharing_violation}};
            const auto r = f.run();
            expect(!r.succeeded() && r.attempts == 13 && r.elapsed_ms == 30000 && r.waited_ms == 30000, "persistent sharing must be bounded");
            expect(*std::max_element(f.sleeps.begin(), f.sleeps.end()) == 4000, "no individual wait over four seconds");
            ++tests;
        }
        for (const auto permanent : {0x80070005u, 0x80070002u, 0x80004005u}) {
            Fixture f{{permanent}};
            const auto r = f.run();
            expect(r.status == permanent && r.attempts == 1 && f.sleeps.empty(), "genuine error must not retry or disappear");
        }
        ++tests;
        {
            Fixture f{{sharing_violation, 0x80070005u}};
            const auto r = f.run();
            expect(r.status == 0x80070005u && r.attempts == 2 && r.waited_ms == 125, "stop when sharing becomes a genuine failure");
            ++tests;
        }
        {
            Fixture f{{sharing_violation}};
            f.api_ms = 31000;
            const auto r = f.run();
            expect(r.attempts == 1 && f.sleeps.empty() && r.elapsed_ms == 31000, "slow synchronous API must not start more retries past deadline");
            ++tests;
        }
        {
            Fixture f{{sharing_violation}};
            f.oversleep_ms = 30000;
            const auto r = f.run();
            expect(r.attempts == 1 && r.waited_ms == 125 && r.elapsed_ms == 30125, "oversleep must not cause a post-deadline API call");
            ++tests;
        }
        {
            Fixture f{{sharing_violation}};
            f.api_ms = 29900;
            const auto r = f.run();
            expect(f.sleeps == std::vector<std::uint32_t>{100} && r.attempts == 2, "sleep must be clamped to remaining retry budget");
            ++tests;
        }
        {
            Fixture f{std::vector<std::uint32_t>(8, sharing_violation)};
            f.results.push_back(0);
            const auto r = f.run();
            expect(r.succeeded() && r.attempts == 9 && r.elapsed_ms > 4875 && r.elapsed_ms <= 30000, "cleanup must recover beyond the previous eight-attempt budget");
            ++tests;
        }
        for (const auto runtime : {0u, 7u, 124u, 125u, 126u, 0xc0000005u}) {
            expect(exit_code(runtime, true, true) == runtime, "successful cleanup must retain original runtime status");
            expect(exit_code(runtime, false, true) == 125 && exit_code(runtime, true, false) == 125,
                   "profile or ACL failure remains a cleanup failure");
        }
        ++tests;
        std::cout << tests << " profile-cleanup tests passed (mock clock; no actual waits or profiles).\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
