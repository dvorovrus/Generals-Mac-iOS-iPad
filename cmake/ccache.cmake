# GeneralsX @build BenderAI 29/05/2025
# ccache compiler cache support
#
# Significantly speeds up recompilation by caching object files.
# Auto-detects ccache installation; no-op if not found.
#
# Reference pattern from old-multiplatform-attempt branch:
#   CMAKE_C_COMPILER_LAUNCHER   = ccache
#   CMAKE_CXX_COMPILER_LAUNCHER = ccache

option(SAGE_USE_CCACHE "Use ccache compiler cache if available" ON)

if(SAGE_USE_CCACHE)
    find_program(CCACHE_PROGRAM ccache)
    if(CCACHE_PROGRAM)
        set(CMAKE_C_COMPILER_LAUNCHER   "${CCACHE_PROGRAM}" CACHE STRING "C compiler launcher")
        set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}" CACHE STRING "C++ compiler launcher")
        message(STATUS "ccache enabled: ${CCACHE_PROGRAM}")
        
        # Configure-time environment changes do not survive a separate cmake --build.
        # Put the PCH settings in the generated launcher instead of the global config.
        if(APPLE)
            foreach(lang C CXX)
                if(CMAKE_${lang}_COMPILER_LAUNCHER STREQUAL "${CCACHE_PROGRAM}")
                    set(CMAKE_${lang}_COMPILER_LAUNCHER
                        "${CMAKE_COMMAND};-E;env;CCACHE_SLOPPINESS=pch_defines,time_macros,locale;${CCACHE_PROGRAM}")
                endif()
            endforeach()
            # Do not embed checkout timestamps in Clang PCH files restored on a new runner.
            add_compile_options(
                "$<$<COMPILE_LANG_AND_ID:C,Clang,AppleClang>:SHELL:-Xclang -fno-pch-timestamp>"
                "$<$<COMPILE_LANG_AND_ID:CXX,Clang,AppleClang>:SHELL:-Xclang -fno-pch-timestamp>"
            )
            message(STATUS "ccache: Apple PCH support enabled")
        endif()
    else()
        message(STATUS "ccache not found, building without compiler cache")
    endif()
else()
    message(STATUS "ccache disabled (SAGE_USE_CCACHE=OFF)")
endif()
