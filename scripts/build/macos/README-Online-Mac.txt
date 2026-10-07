GeneralsZH Online Dev — Apple Silicon (arm64), macOS 15 or later

1. Extract GeneralsZH-Online-macos-arm64.tar.
2. Run "Install Online Data.command" and select your Original or Online IPA.
3. Open GeneralsZH-Online-Dev.app and select Online in the game menu.

Game assets are not included. The installer copies your IPA's retail GameData,
then synchronizes the exact official Generals Online QFE6 community data pack
needed for Windows INI parity. Mod profiles are not imported.

Runtime log: ~/Library/Logs/GeneralsXZH/online-dev.log
GameData: ~/GeneralsX/Online/GeneralsZH
The game uses its standard macOS user-data directory for settings and replays.
Build commit: GeneralsZH-Online-Dev.app/Contents/Resources/build-info.txt

The app is ad-hoc signed, not notarized. If macOS blocks it, use the system's
Privacy & Security "Open Anyway" action for this app.

Environment overrides (when launching Contents/MacOS/run.sh from Terminal):
  GX_GAME_ROOT=/path/to/retail/GameData
  GX_MAC_FULLSCREEN=1

macOS tests exercise shared GO logic; UIKit and iOS lifecycle issues still
require testing on iPad. Both Apple Online presets use the 30 Hz client.
