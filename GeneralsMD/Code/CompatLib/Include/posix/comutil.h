#pragma once

// Unix-only COM utility shim. This filename must not shadow the MSVC SDK.
#ifdef _WIN32
#error "The Unix comutil.h shim must not be on the Windows include path"
#else
#include "comutil_compat.h"
#endif
