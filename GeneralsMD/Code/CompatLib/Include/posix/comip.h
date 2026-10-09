#pragma once

// Unix-only COM interface pointer shim. The MSVC SDK provides comip.h.
#ifdef _WIN32
#error "The Unix comip.h shim must not be on the Windows include path"
#else
#include "comip_compat.h"
#endif
