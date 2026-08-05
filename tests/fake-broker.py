#!/usr/bin/env python3
"""A stand-in for the laptop's credential broker, for testing with-secret.

It answers /health and /request the way the real broker does, but decides
everything from command-line flags instead of a vault and a human. It exists so
the box half can be tested on a machine that deliberately has no vault on it.

  fake-broker.py --port 0 --token T --value SECRET [--status 403] [--error MSG]
                 [--delay SECONDS] [--record FILE]

Prints the port it bound to on stdout, one line, then serves until killed.
"""

import argparse
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

args = None


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"ok": True})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/request":
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode()
        try:
            request = json.loads(raw)
        except json.JSONDecodeError:
            self._send(400, {"error": "bad json"})
            return

        if args.record:
            with open(args.record, "a") as handle:
                handle.write(
                    json.dumps(
                        {
                            "auth": self.headers.get("Authorization", ""),
                            "request": request,
                        }
                    )
                    + "\n"
                )

        if self.headers.get("Authorization") != f"Bearer {args.token}":
            self._send(401, {"error": "bad bearer token"})
            return

        if args.delay:
            time.sleep(args.delay)

        if args.status != 200:
            self._send(args.status, {"error": args.error})
            return

        self._send(200, {"value": args.value, "ttl": 60})

    def log_message(self, *_):
        pass


def main():
    global args
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--token", default="test-token")
    parser.add_argument("--value", default="s3cret-value-abcdef")
    parser.add_argument("--status", type=int, default=200)
    parser.add_argument("--error", default="refused by policy")
    parser.add_argument("--delay", type=float, default=0.0)
    parser.add_argument("--record", default="")
    args = parser.parse_args()

    server = HTTPServer(("127.0.0.1", args.port), Handler)
    print(server.server_address[1], flush=True)
    try:
        server.serve_forever(poll_interval=0.05)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
