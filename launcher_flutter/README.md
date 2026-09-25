# Zero Hour Launcher

Modern Flutter launcher prototype for GeneralsXZH.

Profiles:
- Zero Hour 1.04
- Zero Hour Enhanced 1.0.0
- Contra X Beta 2

Windows binaries are built by GitHub Actions. Open the Actions tab, select Build Zero Hour Launcher (Windows), then download the ZeroHourLauncher-Windows artifact.

For local development with Flutter installed:
1. cd launcher_flutter
2. flutter create --platforms=windows .
3. flutter pub get
4. flutter run -d windows

The UI exposes the iOS method channel generalsx.launcher with the launchProfile method and one of these profile IDs: vanilla, enhanced, contra-x.
