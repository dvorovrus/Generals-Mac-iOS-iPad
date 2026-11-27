# Experimental Reforged iPadOS build

The opt-in device target builds the Reforged engine as a standalone app with a separate bundle identifier and container. The stable Generals Hub 1.4.15 app continues to launch its existing engine and profiles. The experiment has no entry in the Hub catalog.

## Source and rendering

The build pins [Reforged main at 2b331b2](https://github.com/olcayseygan/CnCGeneralsZH-Reforged/commit/2b331b2057577e158de724cb3d2b3fe574752bd2). The source identifies itself as v4.3.2. The published [v4.3.2 tag](https://github.com/olcayseygan/CnCGeneralsZH-Reforged/releases/tag/v4.3.2) is a different commit, `ab986646b3ab5a60e8379f775f945d5dc5eb4273`.

The Apple path uses the Reforged SDL3 GPU backend with Metal. Shader generators compile through glslang and SDL_shadercross with SPIRV-Cross to produce the Metal shader source at runtime. The Windows DX11 shader cache is specific to that backend. The build also uses Reforged's FreeType, miniaudio, and static FFmpeg Bink decoder path. It stages the upstream source overlay and skips downloadable art archives.

Reforged is GPL-3.0-or-later with EA's Section 7 terms. The bundle includes upstream notices, the port patch, and licenses selected from the libraries on the link line. Keep the matching source, port build scripts, and dependency sources available for any future distribution. [Upstream license](https://github.com/olcayseygan/CnCGeneralsZH-Reforged/blob/2b331b2057577e158de724cb3d2b3fe574752bd2/LICENSE.md) · [Upstream notices](https://github.com/olcayseygan/CnCGeneralsZH-Reforged/blob/2b331b2057577e158de724cb3d2b3fe574752bd2/NOTICE.md)

## Build an unsigned bundle

On macOS with Xcode and the iPhoneOS SDK, CMake, Ninja, Python 3, and upstream's vendor tools available:

```sh
bash scripts/build/ios/build-reforged-ipados.sh
```

The script creates a fresh run folder under `build/reforged-ipados/`. It fetches the pinned source, applies the port patch, builds a host-native fingerprint generator and the ARM64 device runtime, and checks the executable's architecture, Mach-O platform, and dynamic dependencies before publishing the local app bundle. The output is an unsigned `Reforged-iPad.app`.

At runtime the app expects an authorized retail install copied to its own Files app folder under `GameData`. The upstream validator looks for `INIZH.big` and the base game's `Textures.big` in one of its supported layouts, such as `GameData/ZH_Generals/Textures.big`. The runtime uses that install as a read-only root and keeps its registry, options, and saves under its own Application Support directory. Input starts with SDL's touch-to-mouse mapping and the upstream mouse and keyboard path.

## Validation still required

The first Mac run must compile and link the patched source and vendored dependencies against iPhoneOS. The unsigned build is only the compile and packaging milestone. Device testing still needs to establish Metal shader compilation and presentation, Core Audio and Bink playback, a stock skirmish with its AI and input working, and foreground/background behavior. Hub gestures such as two-finger camera movement still need to be adapted to Reforged's SDL input path and tested.

Hub dispatch depends on a validated in-process entry point. iPadOS uses one application lifecycle. A future combined app needs one SDL UIKit bootstrap and a single build-compatible SDL implementation, engine symbol and allocator isolation, explicit ownership of windows and save paths, and a return-to-Hub lifecycle verified on device. A runtime framework would need to ship inside the app and be signed with it. The standalone build gives those changes a device baseline and uses a separate app container.
