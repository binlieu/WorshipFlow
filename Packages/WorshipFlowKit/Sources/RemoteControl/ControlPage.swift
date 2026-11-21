// CUE-004 (AUTO-13): the one page a phone loads from the server. A remote, not the app's interface.
// One document, no external assets. Every piece of text from the show is put on the page with textContent, never as markup,
// and the Content-Security-Policy pins the inline script and style by hash so nothing else can run.
import Foundation
import CryptoKit

enum ControlPage {
    static let style = #"""

    :root{color-scheme:dark light;--bg:#101214;--fg:#f2f4f5;--dim:#9aa3a8;--card:#1b1f22;--line:#343b40;--accent:#4aa3ff;--warn:#ff6b5e}
    @media (prefers-color-scheme:light){:root{--bg:#f5f6f7;--fg:#14181a;--dim:#566066;--card:#fff;--line:#cdd3d7;--accent:#0b63c5;--warn:#c0281c}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--fg);font:18px/1.35 -apple-system,system-ui,sans-serif;padding:16px;max-width:640px;margin-inline:auto}
    h1{font-size:20px;margin:0 0 12px}
    h2{font-size:14px;margin:18px 0 6px;color:var(--dim);text-transform:uppercase;letter-spacing:.05em}
    [hidden]{display:none!important}
    .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:12px;white-space:pre-wrap;overflow-wrap:anywhere}
    .live{font-size:26px;min-height:3em}
    .dim{color:var(--dim)}
    .row{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:12px}
    button,input{font:inherit;border-radius:12px;border:1px solid var(--line);background:var(--card);color:var(--fg)}
    button{min-height:64px;font-weight:600;padding:8px}
    button[type=submit]{width:100%}
    button.primary{background:var(--accent);border-color:var(--accent);color:#fff}
    button[aria-pressed=true]{background:var(--warn);border-color:var(--warn);color:#fff}
    button:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
    input{width:100%;min-height:52px;padding:8px 12px;margin:4px 0 12px}
    label{display:block;color:var(--dim)}
    ul{list-style:none;margin:0;padding:0}
    li{padding:10px 12px;border-bottom:1px solid var(--line);overflow-wrap:anywhere}
    li[aria-current=true]{font-weight:700;border-left:4px solid var(--accent)}
    #status{font-size:14px;color:var(--dim);margin-top:16px}
    #message{color:var(--warn);min-height:1.4em}
    """#

    static let script = #"""

    (function () {
      'use strict';
      var KEY = 'wf-remote-token';
      var token = null;
      var controller = null;
      var retry = 1000;
      var current = null;
      try { token = window.localStorage.getItem(KEY); } catch (e) { token = null; }

      function byId(id) { return document.getElementById(id); }
      function put(el, value) { el.textContent = (value === null || value === undefined) ? '' : String(value); }
      function clear(el) { while (el.firstChild) { el.removeChild(el.firstChild); } }
      function status(text) { put(byId('status'), text); }
      function notice(text) { put(byId('message'), text); }
      function showPaired(paired) { byId('pair').hidden = paired; byId('remote').hidden = !paired; }

      function forget() {
        token = null;
        try { window.localStorage.removeItem(KEY); } catch (e) { }
        if (controller) { controller.abort(); }
        showPaired(false);
        status('Not paired');
      }

      function modeLabel(mode) {
        if (mode === 'live') { return 'Live'; }
        if (mode === 'cleared') { return 'Cleared'; }
        if (mode === 'blackedOut') { return 'Blackout'; }
        return 'Stopped';
      }

      function api(path, method, payload) {
        var headers = { 'Authorization': 'Bearer ' + token };
        var options = { method: method, headers: headers, cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer' };
        if (payload !== undefined) { headers['Content-Type'] = 'application/json'; options.body = JSON.stringify(payload); }
        return fetch(path, options).then(function (r) {
          if (r.status === 401) { forget(); throw new Error('unauthorized'); }
          return r;
        });
      }

      function send(payload) {
        notice('');
        api('/api/v1/transport', 'POST', payload).then(function (r) {
          return r.json().then(function (body) {
            if (r.ok && body.state) { render(body.state); } else { notice(body.error || 'Not done'); }
          });
        }).catch(function () { if (token) { notice('Could not reach the Mac'); } });
      }

      function runMacro(id) {
        notice('');
        api('/api/v1/macros/' + encodeURIComponent(id) + '/run', 'POST').then(function (r) {
          if (!r.ok) { return r.json().then(function (b) { notice(b.error || 'Not done'); }); }
        }).catch(function () { if (token) { notice('Could not reach the Mac'); } });
      }

      function render(s) {
        current = s;
        put(byId('mode'), modeLabel(s.mode) + (s.position ? ' · ' + s.position : ''));
        put(byId('title'), s.presentationTitle || '');
        put(byId('live1'), s.live ? s.live.primary : '');
        put(byId('live2'), s.live && s.live.secondary ? s.live.secondary : '');
        put(byId('next1'), s.next ? s.next.primary : '');
        put(byId('next2'), s.next && s.next.secondary ? s.next.secondary : '');
        byId('blackout').setAttribute('aria-pressed', s.mode === 'blackedOut' ? 'true' : 'false');
        var list = byId('playlist');
        clear(list);
        (s.playlist || []).forEach(function (item) {
          var li = document.createElement('li');
          put(li, item.title);
          if (item.isLive) { li.setAttribute('aria-current', 'true'); }
          list.appendChild(li);
        });
        var timers = byId('timers');
        clear(timers);
        (s.timers || []).forEach(function (t) {
          var li = document.createElement('li');
          put(li, t.name + ': ' + t.value);
          timers.appendChild(li);
        });
        var macros = byId('macros');
        clear(macros);
        (s.macros || []).forEach(function (m) {
          var b = document.createElement('button');
          b.type = 'button';
          put(b, m.name);
          b.addEventListener('click', function () { runMacro(m.id); });
          macros.appendChild(b);
        });
        byId('playlist-head').hidden = !(s.playlist && s.playlist.length);
        byId('timers-head').hidden = !(s.timers && s.timers.length);
        byId('macros-head').hidden = !(s.macros && s.macros.length);
      }

      function handleBlock(block) {
        var kind = 'message';
        var data = [];
        block.split('\n').forEach(function (line) {
          if (line.indexOf('event:') === 0) { kind = line.slice(6).trim(); }
          else if (line.indexOf('data:') === 0) { data.push(line.slice(5).replace(/^ /, '')); }
        });
        if (kind === 'state' && data.length) {
          try { render(JSON.parse(data.join('\n'))); } catch (e) { }
        }
      }

      function connect() {
        if (!token) { return; }
        var ctl = new AbortController();
        controller = ctl;
        var lastByte = Date.now();
        var watchdog = setInterval(function () {
          if (Date.now() - lastByte > 45000) { ctl.abort(); }
        }, 5000);
        status('Connecting');
        fetch('/api/v1/events', { headers: { 'Authorization': 'Bearer ' + token }, signal: ctl.signal, cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer' })
          .then(function (r) {
            if (r.status === 401) { forget(); return; }
            if (!r.ok || !r.body) { throw new Error('bad response'); }
            status('Connected');
            retry = 1000;
            var reader = r.body.getReader();
            var decoder = new TextDecoder();
            var buffer = '';
            function pump() {
              return reader.read().then(function (chunk) {
                if (chunk.done) { throw new Error('closed'); }
                lastByte = Date.now();
                buffer += decoder.decode(chunk.value, { stream: true });
                var at;
                while ((at = buffer.indexOf('\n\n')) >= 0) {
                  handleBlock(buffer.slice(0, at));
                  buffer = buffer.slice(at + 2);
                }
                if (buffer.length > 1000000) { throw new Error('too much'); }
                return pump();
              });
            }
            return pump();
          })
          .catch(function () {
            clearInterval(watchdog);
            if (ctl.signal.aborted && !token) { return; }
            if (!token) { return; }
            status('Disconnected. Trying again');
            setTimeout(connect, retry);
            retry = Math.min(retry * 2, 10000);
          });
      }

      function start() {
        showPaired(true);
        connect();
        api('/api/v1/state', 'GET').then(function (r) { return r.json(); }).then(render).catch(function () { });
      }

      byId('pair-form').addEventListener('submit', function (event) {
        event.preventDefault();
        notice('');
        var code = byId('code').value.replace(/\s+/g, '');
        var label = byId('label').value.trim() || 'Phone';
        fetch('/api/v1/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: code, label: label }), cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer' })
          .then(function (r) {
            return r.json().catch(function () { return {}; }).then(function (body) {
              if (r.ok && body.token) {
                token = body.token;
                try { window.localStorage.setItem(KEY, token); } catch (e) { }
                byId('code').value = '';
                start();
              } else if (r.status === 429) {
                notice('Too many tries. Wait a minute, then try again.');
              } else if (r.status === 403) {
                notice('That code is not right, or it has expired. Read the new one from the Mac.');
              } else {
                notice(body.error || 'Could not pair');
              }
            });
          })
          .catch(function () { notice('Could not reach the Mac'); });
      });

      byId('previous').addEventListener('click', function () { send({ command: 'previous' }); });
      byId('next').addEventListener('click', function () { send({ command: 'next' }); });
      byId('clear').addEventListener('click', function () { send({ command: 'clear' }); });
      byId('blackout').addEventListener('click', function () {
        var on = current && current.mode === 'blackedOut';
        send({ command: 'blackout', mode: on ? 'off' : 'on' });
      });
      byId('forget').addEventListener('click', forget);

      if (token) { start(); } else { showPaired(false); status('Not paired'); }
    })();
    """#

    static let body = #"""

    <h1>WorshipFlow remote</h1>
    <section id="pair" aria-labelledby="pair-title">
      <h2 id="pair-title">Pair this phone</h2>
      <form id="pair-form" autocomplete="off">
        <label for="code">Pairing code shown on the Mac</label>
        <input id="code" name="code" inputmode="numeric" pattern="[0-9 ]*" maxlength="8" required autocomplete="one-time-code">
        <label for="label">Name for this phone</label>
        <input id="label" name="label" maxlength="64" value="Phone">
        <button class="primary" type="submit">Pair</button>
      </form>
    </section>
    <section id="remote" hidden>
      <div id="mode" class="dim" aria-live="polite"></div>
      <div id="title" class="dim"></div>
      <h2>Live</h2>
      <div class="card live" aria-live="polite"><div id="live1"></div><div id="live2" class="dim"></div></div>
      <h2>Next</h2>
      <div class="card dim"><div id="next1"></div><div id="next2"></div></div>
      <div class="row">
        <button id="previous" type="button" aria-label="Previous slide">Previous</button>
        <button id="next" type="button" class="primary" aria-label="Next slide">Next</button>
        <button id="clear" type="button" aria-label="Clear the screens">Clear</button>
        <button id="blackout" type="button" aria-pressed="false" aria-label="Blackout">Blackout</button>
      </div>
      <h2 id="macros-head" hidden>Macros</h2>
      <div id="macros" class="row"></div>
      <h2 id="playlist-head" hidden>Playlist</h2>
      <ul id="playlist"></ul>
      <h2 id="timers-head" hidden>Timers</h2>
      <ul id="timers"></ul>
      <p><button id="forget" type="button">Forget this phone</button></p>
    </section>
    <div id="message" role="alert"></div>
    <div id="status" role="status" aria-live="polite"></div>
    """#

    static var html: String {
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
        + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        + "<title>WorshipFlow remote</title><style>" + style + "</style></head><body>" + body
        + "<script>" + script + "</script></body></html>"
    }

    private static func hash(_ s: String) -> String { "'sha256-" + Data(SHA256.hash(data: Data(s.utf8))).base64EncodedString() + "'" }

    static var contentSecurityPolicy: String {
        "default-src 'none'; script-src \(hash(script)); style-src \(hash(style)); connect-src 'self'; "
        + "base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    }
}
