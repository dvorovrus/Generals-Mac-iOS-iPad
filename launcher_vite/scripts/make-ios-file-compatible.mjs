import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const indexPath = resolve(process.cwd(), 'dist/index.html')
let html = await readFile(indexPath, 'utf8')

// WKWebView + loadFileURL can leave external ES modules blocked under file://.
// Vite emits a self-contained bundle with no ESM imports, so run it as a
// classic deferred script in the packaged iOS launcher.
html = html.replace(
  /<script\s+type="module"\s+crossorigin\s+src="([^"]+)"\s*><\/script>/,
  '<script defer src="$1"></script>',
)

// Keep a native-bridge fallback visible until React mounts. If the bundle is
// blocked for any reason, the user can still select a profile instead of
// getting a permanent black screen.
const fallback = `
    <div id="root">
      <div id="launcher-fallback" style="
        min-height:100vh;display:flex;flex-direction:column;align-items:center;
        justify-content:center;gap:18px;background:#090b0c;color:#f2f0e9;
        font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
        <div style="font-size:12px;letter-spacing:.24em;opacity:.55">ZERO HOUR LAUNCHER</div>
        <div style="font-size:28px;font-weight:800">Select profile</div>
        <div style="display:flex;gap:12px;flex-wrap:wrap;justify-content:center">
          <button onclick="window.__gxLaunch('vanilla')" style="padding:16px 22px">Zero Hour 1.04</button>
          <button onclick="window.__gxLaunch('enhanced')" style="padding:16px 22px">Enhanced</button>
          <button onclick="window.__gxLaunch('contra-x')" style="padding:16px 22px">Contra X</button>
        </div>
      </div>
    </div>
    <script>
      window.__gxLaunch = function(profile) {
        var handler = window.webkit &&
          window.webkit.messageHandlers &&
          window.webkit.messageHandlers.launchProfile;
        if (handler) {
          handler.postMessage({ profile: profile });
        }
      };
      window.addEventListener('error', function(event) {
        var handler = window.webkit &&
          window.webkit.messageHandlers &&
          window.webkit.messageHandlers.launcherLog;
        if (handler) {
          handler.postMessage({
            level: 'error',
            message: String(event.message || 'window error')
          });
        }
      });
      window.addEventListener('unhandledrejection', function(event) {
        var handler = window.webkit &&
          window.webkit.messageHandlers &&
          window.webkit.messageHandlers.launcherLog;
        if (handler) {
          handler.postMessage({
            level: 'error',
            message: 'unhandled rejection: ' + String(event.reason || '')
          });
        }
      });
    </script>`

html = html.replace('<div id="root"></div>', fallback)

await writeFile(indexPath, html, 'utf8')

if (html.includes('type="module"')) {
  throw new Error('iOS compatibility rewrite failed: type="module" remains in dist/index.html')
}
if (!html.includes('launcher-fallback')) {
  throw new Error('iOS compatibility rewrite failed: fallback UI missing')
}

console.log('iOS WKWebView compatibility rewrite complete')
