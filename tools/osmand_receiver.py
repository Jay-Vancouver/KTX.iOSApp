#!/usr/bin/env python3
"""Local OsmAnd receiver for testing the app's location upload without the TMS server.

Prints every POST and appends it to tools/received.csv (git-ignored).

    python3 tools/osmand_receiver.py                  # http://127.0.0.1:8099/gps, answers 200
    python3 tools/osmand_receiver.py --status 503     # every POST fails -> app queues and retries
    python3 tools/osmand_receiver.py --delay 70       # hang 70 s -> app's 60 s watchdog cancels
    python3 tools/osmand_receiver.py --host 0.0.0.0   # reachable from a phone on the same Wi-Fi

Simulator: start tracking with -debugURL http://127.0.0.1:8099/gps (see DebugCommands in AppDelegate.swift).
Python 3.9 standard library only.
"""
import argparse
import csv
import datetime
import os
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIELDS = ["id", "lat", "lon", "timestamp", "speed", "bearing", "altitude", "accuracy", "batt"]
CSV_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "received.csv")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8099)
    parser.add_argument("--status", type=int, default=200, help="HTTP status to answer (default 200)")
    parser.add_argument("--delay", type=float, default=0, help="seconds to wait before answering")
    args = parser.parse_args()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length).decode("utf-8", "replace")
            fields = dict(urllib.parse.parse_qsl(body, keep_blank_values=True))
            now = datetime.datetime.now().strftime("%H:%M:%S")
            ts = fields.get("timestamp", "")
            fix_time = datetime.datetime.fromtimestamp(int(ts)).strftime("%H:%M:%S") if ts.isdigit() else "?"
            print(f"{now} {self.path} fix={fix_time} " + " ".join(f"{k}={fields.get(k, '')}" for k in FIELDS)
                  + f"  UA={self.headers.get('User-Agent', '')}  -> {args.status}", flush=True)
            unexpected = sorted(set(fields) - set(FIELDS))
            if unexpected:
                print(f"   unexpected fields: {unexpected}", flush=True)
            new_file = not os.path.exists(CSV_PATH)
            with open(CSV_PATH, "a", newline="") as f:
                writer = csv.writer(f)
                if new_file:
                    writer.writerow(["received"] + FIELDS)
                writer.writerow([datetime.datetime.now().isoformat(timespec="seconds")]
                                + [fields.get(k, "") for k in FIELDS])
            if args.delay:
                time.sleep(args.delay)
            self.send_response(args.status)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"OsmAnd receiver on http://{args.host}:{args.port}/gps (status {args.status}, delay {args.delay}s)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
