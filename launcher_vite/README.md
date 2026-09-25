# Zero Hour Launcher (Vite)

A lightweight React + TypeScript launcher prototype for GeneralsXZH.

## Run on Windows 11

Node.js 20+ is enough. Flutter is not required.

```powershell
cd launcher_vite
npm install
npm run dev
```

Open:

```text
http://localhost:5173
```

The `predev` script downloads the selected real Zero Hour / Enhanced / Contra X artwork into `public/posters`, so the launcher uses local image files after the first run.

## Production build

```powershell
npm run build
npm run preview
```

The production output is written to `dist/`.

## Profiles

- Zero Hour 1.04
- Zero Hour Enhanced 1.0.0a + 28/03/2024 patch
- Contra X Beta 2 + Patch 1

## iPad bridge

The Play button already supports the future WKWebView bridge:

```text
window.webkit.messageHandlers.launchProfile.postMessage({ profile })
```

Supported IDs:

- `vanilla`
- `enhanced`
- `contra-x`

A Tauri Windows wrapper can be added after the launcher UI is approved.
