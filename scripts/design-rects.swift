// UI-005j tool 1: design rectangles. Loads a mockup HTML file from docs/UI/mockups at 1440 x 900 CSS pixels, injects Inter
// (Vendor/Inter/InterVariable.ttf) so the render uses the font of the design pictures, waits for layout, and writes JSON:
// every visible element under .win with a stable path, getBoundingClientRect, computed font size/weight/line height/colour,
// background, border width, radius, and its own text. Run by hand (check.sh does not call it).
// Usage: scripts/design-rects <mockup.html> <out.json> [--light] [--query edit=1] [--png out.png]
//        [--root <css selector, default .win>] [--width W --height H view size, default 1440 x 900] [--css <style text injected into the page>]
// UI-005h: --root, --width, --height and --css let a mockup without a .win (07 output looks) be dumped at the size its panels are designed for.
import AppKit
import WebKit

var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { FileHandle.standardError.write(Data("usage: design-rects <mockup.html> <out.json> [--light] [--query k=v] [--png out.png]\n".utf8)); exit(2) }
let htmlPath = URL(fileURLWithPath: args[0]).standardizedFileURL.path
let outPath = args[1]
var light = false, query = "", pngPath: String? = nil, rootSelector = ".win", extraCSS = "", viewW = 1440.0, viewH = 900.0
var i = 2
while i < args.count {
    switch args[i] {
    case "--light": light = true
    case "--query": i += 1; query = args[i]
    case "--png": i += 1; pngPath = args[i]
    case "--root": i += 1; rootSelector = args[i]
    case "--css": i += 1; extraCSS = args[i]
    case "--width": i += 1; viewW = Double(args[i]) ?? 1440
    case "--height": i += 1; viewH = Double(args[i]) ?? 900
    default: break
    }
    i += 1
}
// The repository root: the nearest ancestor that holds Vendor/Inter. (UI-005h: the earlier fixed three-levels-up guess named docs/, where no
// font is, so the page quietly used its fallback font; the tool now says so when Inter did not load.)
var rootURL = URL(fileURLWithPath: htmlPath).deletingLastPathComponent()
while rootURL.path != "/" && !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Vendor/Inter/InterVariable.ttf").path) {
    rootURL = rootURL.deletingLastPathComponent()
}
let root = rootURL.path
let fontURL = "file://\(root)/Vendor/Inter/InterVariable.ttf"

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let cfg = WKWebViewConfiguration()
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: viewW, height: viewH), configuration: cfg)
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: viewW, height: viewH), styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = web
win.setFrameOrigin(NSPoint(x: -5000, y: -5000))  // off-screen
win.orderBack(nil)

let extract = """
(() => {
  const out = [];
  const w = document.querySelector('\(rootSelector)');
  const cs = (e) => getComputedStyle(e);
  function path(e) {
    const parts = [];
    for (let n = e; n && n !== document.body; n = n.parentElement) {
      const p = n.parentElement; let idx = 0;
      if (p) { for (const s of p.children) { if (s === n) break; if (s.tagName === n.tagName) idx++; } }
      const cls = (n.getAttribute && n.getAttribute('class') || '').trim().split(/\\s+/).filter(Boolean).join('.');
      parts.unshift(n.tagName.toLowerCase() + (cls ? '.' + cls : '') + '[' + idx + ']');
    }
    return parts.join('>');
  }
  function ownText(e) { let t = ''; for (const c of e.childNodes) if (c.nodeType === 3) t += c.textContent; return t.replace(/\\s+/g, ' ').trim(); }
  const all = [w, ...w.querySelectorAll('*')];
  for (const e of all) {
    if (e.closest('svg') && e.tagName.toLowerCase() !== 'svg') continue;
    const r = e.getBoundingClientRect(); const s = cs(e);
    if (r.width === 0 || r.height === 0 || s.display === 'none' || s.visibility === 'hidden') continue;
    out.push({ path: path(e), text: ownText(e), x: r.x, y: r.y, w: r.width, h: r.height,
      fontSize: parseFloat(s.fontSize), fontWeight: parseFloat(s.fontWeight) || 400, lineHeight: s.lineHeight, color: s.color,
      background: s.backgroundColor, borderWidth: parseFloat(s.borderTopWidth) || 0,
      radius: parseFloat(s.borderTopLeftRadius) || 0 });
  }
  return JSON.stringify(out);
})()
"""

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let setup = """
        (async () => {
          const st = document.createElement('style');
          st.textContent = '@font-face{font-family:"Inter";src:url("\(fontURL)");font-weight:100 900;font-style:normal}' + `\(extraCSS.replacingOccurrences(of: "`", with: ""))`;
          document.head.appendChild(st);
          if (\(light)) document.body.classList.add('light');
          try { await document.fonts.load('13px Inter'); await document.fonts.load('600 13px Inter'); } catch (e) {}
          await document.fonts.ready;
          await new Promise(r => setTimeout(r, 400));
          return document.fonts.check('13px Inter') && ![...document.fonts].some(f => f.status === 'error');
        })()
        """
        webView.callAsyncJavaScript(setup, in: nil, in: .page) { r in
            if case .success(let ok) = r, (ok as? Bool) == false { FileHandle.standardError.write(Data("warning: Inter did not load\n".utf8)) }
            webView.evaluateJavaScript(extract) { res, err in
                guard let s = res as? String else { FileHandle.standardError.write(Data("extract failed: \(String(describing: err))\n".utf8)); exit(1) }
                try? s.write(toFile: outPath, atomically: true, encoding: .utf8)
                if let png = pngPath {
                    let c = WKSnapshotConfiguration(); c.rect = CGRect(x: 0, y: 0, width: viewW, height: viewH)
                    webView.takeSnapshot(with: c) { img, _ in
                        if let img, let t = img.tiffRepresentation, let b = NSBitmapImageRep(data: t), let d = b.representation(using: .png, properties: [:]) { try? d.write(to: URL(fileURLWithPath: png)) }
                        exit(0)
                    }
                } else { exit(0) }
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { FileHandle.standardError.write(Data("load failed: \(error)\n".utf8)); exit(1) }
}
let nav = Nav()
web.navigationDelegate = nav
let url = URL(string: "file://\(htmlPath)" + (query.isEmpty ? "" : "?\(query)"))!
web.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: root))
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { FileHandle.standardError.write(Data("timeout\n".utf8)); exit(1) }
app.run()
