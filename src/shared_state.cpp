#include "shared_state.h"
#include <cstring>

namespace vrkbd {

void InitializeDefaults(SharedState& s) {
    std::memset(&s, 0, sizeof(s));
    s.magic = kMagic;
    s.version = kVersion;
    s.sequence = 0;
    s.controllerAlive = 1;
    s.head = {0.0, 1.65, 0.0, 0.0, 0.0, 0.0};
    s.left.pose = {-0.25, 1.30, -0.35, 0.0, 0.0, 0.0};
    s.right.pose = {0.25, 1.30, -0.35, 0.0, 0.0, 0.0};
}

Mapping OpenOrCreateMapping(bool initialize) {
    Mapping m;
    m.handle = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                  static_cast<DWORD>(sizeof(SharedState)), kMappingName);
    if (!m.handle) return m;
    const bool alreadyExisted = GetLastError() == ERROR_ALREADY_EXISTS;
    m.state = static_cast<SharedState*>(MapViewOfFile(m.handle, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(SharedState)));
    if (!m.state) {
        CloseHandle(m.handle);
        m.handle = nullptr;
        return m;
    }
    if (initialize || !alreadyExisted || m.state->magic != kMagic || m.state->version != kVersion)
        InitializeDefaults(*m.state);
    return m;
}

void CloseMapping(Mapping& m) {
    if (m.state) UnmapViewOfFile(m.state);
    if (m.handle) CloseHandle(m.handle);
    m.state = nullptr;
    m.handle = nullptr;
}

} // namespace vrkbd
