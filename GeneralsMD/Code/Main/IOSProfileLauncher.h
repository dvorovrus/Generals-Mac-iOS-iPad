#pragma once

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

// GeneralsX @feature dvorovrus 25/09/2026 Show the embedded Vite launcher before game initialization.
// Returns one of: "vanilla", "enhanced", "contra-x".
const char *GeneralsXRunIOSProfileLauncher();

#endif
