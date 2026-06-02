#!/usr/bin/env python3
"""Deterministic mock upstream for Rails golden capture.

Serves the exact canned payloads the Phoenix parity test (api_parity_test.exs)
feeds via Bypass, so Rails goldens are captured against identical upstream
inputs. Every Atlas upstream (Photon, Placeholder, libpostal, Valhalla, OTP,
Overpass) points its base URL at this one server during capture.

Run: python3 scripts/mock_upstream.py 5599
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PHOTON_FEATURES = {
    "features": [
        {"geometry": {"coordinates": [13.4, 52.5]}, "properties": {"name": "Berlin"}}
    ]
}

# path -> (status, body) ; matched on exact path (query string ignored)
ROUTES = {
    "GET": {
        "/api": PHOTON_FEATURES,                       # Photon search
        "/reverse": PHOTON_FEATURES,                   # Photon reverse
        "/parser": [],                                 # libpostal parse
        "/parser/search": [],                          # Placeholder search
        "/parser/findbyid": [],                        # Placeholder findbyid
        "/otp/routers/default/plan": {"plan": {"itineraries": []}},
        "/api/interpreter": {"elements": []},          # Overpass (GET form)
    },
    "POST": {
        "/route": {"trip": {"summary": {"length": 1.0}}},  # Valhalla
        "/api/interpreter": {"elements": []},              # Overpass (POST form)
    },
}


class Handler(BaseHTTPRequestHandler):
    def _serve(self, method):
        path = urlparse(self.path).path
        table = ROUTES.get(method, {})
        if path in table:
            self._json(200, table[path])
        else:
            sys.stderr.write(f"[mock] UNHANDLED {method} {path}\n")
            sys.stderr.flush()
            self._json(404, {"error": "unhandled mock path", "path": path})

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._serve("GET")

    def do_POST(self):
        # drain request body so the client write completes
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length:
            self.rfile.read(length)
        self._serve("POST")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5599
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
