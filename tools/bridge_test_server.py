#!/usr/bin/env python3
"""Local test site for the KtxAndroidApp bridge (Debug builds), without the TMS server.

Serves pages that call the bridge and report every result back here, plus an OsmAnd /gps receiver.

    python3 tools/bridge_test_server.py
    # point the Debug app at it (admin override of the site address):
    xcrun simctl spawn booted defaults write com.ktxtransport.driver start_url http://127.0.0.1:8099/driver/
    xcrun simctl launch --terminate-running-process booted com.ktxtransport.driver
    # afterwards:
    xcrun simctl spawn booted defaults delete com.ktxtransport.driver start_url

Pages:
    /driver/          automatic checks (allowed page), then goes to /other/ and back to /driver/?stop=1
    /driver/?manual=1 buttons only (start / stop / status / requestPermissions)
    /other/           outside the allowed path: every call must be refused
Results print as "REPORT <page> <check> = <value>". Python 3.9 standard library only.
"""
import json
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8099

DRIVER_PAGE = r"""<!doctype html><html><head><meta name=viewport content="width=device-width">
<title>Bridge test</title><style>body{font:15px -apple-system,sans-serif;padding:12px}button{font-size:16px;margin:4px}
pre{white-space:pre-wrap;font-size:12px;background:#eee;padding:6px}</style></head><body>
<h3>KtxAndroidApp test (%PAGE%)</h3>
<button onclick="r('start', KtxAndroidApp.startTracking('6045551234', GPS, '{&quot;interval&quot;:10,&quot;heartbeat&quot;:60}'))">start</button>
<button onclick="KtxAndroidApp.stopTracking(); r('stop', 'called')">stop</button>
<button onclick="r('status', KtxAndroidApp.status())">status</button>
<button onclick="KtxAndroidApp.requestPermissions(); r('requestPermissions', 'called')">permissions</button>
<button onclick="alert('alert works')">alert</button>
<button onclick="r('confirm', confirm('confirm works?'))">confirm</button>
<button onclick="r('prompt', prompt('normal prompt', 'abc'))">prompt</button>
<pre id=out></pre>
<iframe id=frame src="/driver/frame.html" style="width:100%;height:40px"></iframe>
<script>
var PAGE = '%PAGE%', GPS = location.origin + '/gps';
function r(name, value) {
  var text = typeof value === 'string' ? value : JSON.stringify(value);
  document.getElementById('out').textContent += name + ' = ' + text + ' (' + typeof value + ')\n';
  fetch('/report', {method: 'POST', body: JSON.stringify({page: PAGE, name: name, value: value, type: typeof value})});
}
function onStatus(where) { return function (e) { r('event ktxappstatus on ' + where, e.detail); }; }
window.addEventListener('ktxappstatus', onStatus('window'));
document.addEventListener('ktxappstatus', onStatus('document'));
var q = new URLSearchParams(location.search);
if (q.get('manual')) { /* buttons only */ }
else if (PAGE === 'driver' && q.get('stop')) {
  KtxAndroidApp.stopTracking();
  setTimeout(function () { r('status after stop', JSON.parse(KtxAndroidApp.status())); }, 500);
} else if (PAGE === 'driver') {
  r('typeof bridge', typeof window.KtxAndroidApp);
  r('version', KtxAndroidApp.version());
  r('status', JSON.parse(KtxAndroidApp.status()));
  r('bad phone -> false', KtxAndroidApp.startTracking('12345', GPS));
  r('foreign url -> false', KtxAndroidApp.startTracking('6045551234', 'https://example.com/gps'));
  r('http non-local url -> false', KtxAndroidApp.startTracking('6045551234', 'http://www.withktx.com/gps'));
  r('bad options -> false', KtxAndroidApp.startTracking('6045551234', GPS, '{bad'));
  r('object options -> false', KtxAndroidApp.startTracking('6045551234', GPS, {interval: 10}));
  r('stopTracking returns', KtxAndroidApp.stopTracking());
  r('start 11 digits + options -> true',
    KtxAndroidApp.startTracking('1 (604) 555-1234', GPS, '{"interval":5,"heartbeat":30}'));
  setTimeout(function () { r('status after restarts (10/300)', JSON.parse(KtxAndroidApp.status())); }, 1500);
  r('restart with "undefined" options -> true', KtxAndroidApp.startTracking('6045551234', GPS, 'undefined'));
  r('restart options -> true', KtxAndroidApp.startTracking('6045551234', GPS, '{"interval":10}'));
  setTimeout(function () { location.href = '/other/'; }, 15000);
} else {
  r('typeof bridge', typeof window.KtxAndroidApp);
  r('status -> {}', KtxAndroidApp.status());
  r('version -> ""', KtxAndroidApp.version());
  r('start -> false', KtxAndroidApp.startTracking('6045551234', GPS));
  setTimeout(function () { location.href = '/driver/?stop=1'; }, 3000);
}
</script></body></html>"""

FRAME_PAGE = """<!doctype html><body><script>
fetch('/report', {method: 'POST', body: JSON.stringify({page: 'iframe', name: 'typeof bridge in iframe',
  value: typeof window.KtxAndroidApp, type: 'string'})});
</script>iframe</body>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/driver/frame.html":
            self.reply(200, FRAME_PAGE)
        elif path.startswith("/driver"):
            self.reply(200, DRIVER_PAGE.replace("%PAGE%", "driver"))
        elif path.startswith("/other"):
            self.reply(200, DRIVER_PAGE.replace("%PAGE%", "other"))
        else:
            self.reply(404, "not found")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode("utf-8", "replace")
        if self.path == "/report":
            data = json.loads(body)
            value = json.dumps(data["value"]) if "value" in data else "undefined"
            print(f"REPORT {data['page']:<6} {data['name']} = {value} ({data['type']})", flush=True)
        elif self.path.startswith("/gps"):
            fields = dict(urllib.parse.parse_qsl(body))
            print(f"GPS id={fields.get('id')} lat={fields.get('lat')} lon={fields.get('lon')} "
                  f"timestamp={fields.get('timestamp')}", flush=True)
        self.reply(200, "")

    def reply(self, code, text):
        data = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    print(f"Bridge test site on http://127.0.0.1:{PORT}/driver/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
