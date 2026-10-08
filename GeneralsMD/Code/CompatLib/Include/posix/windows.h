#pragma once

// Unix-only shim for source files that include <windows.h> with DXVK.
// Kept in a separate include directory to avoid shadowing the real Windows SDK.
#ifdef _WIN32
#error "The Unix windows.h shim must not be on the Windows include path"
#else
#include "windows_compat.h"
#endif
