#!/usr/bin/env python3
"""Minimal stand-in for BlueBubbles Server, used by tests/smoke.sh.

Implements just the REST endpoints Hermes's BlueBubbles adapter calls (ping,
server info, webhook registry, chat query, send text, read receipts) and
appends every request to a JSONL log so the test can assert on what Hermes
sent.

Usage: fake_bluebubbles.py PORT PASSWORD LOGFILE
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT, PASSWORD, LOG = int(sys.argv[1]), sys.argv[2], sys.argv[3]
webhooks: list = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep test output quiet
        pass

    def _reply(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle(self, method: str) -> None:
        url = urlparse(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            body = raw.decode(errors="replace")
        with open(LOG, "a") as fh:
            fh.write(json.dumps({"method": method, "path": url.path, "body": body}) + "\n")

        if parse_qs(url.query).get("password", [None])[0] != PASSWORD:
            return self._reply(401, {"status": 401, "message": "unauthorized"})

        path = url.path
        if method == "GET" and path == "/api/v1/ping":
            return self._reply(200, {"status": 200, "message": "pong"})
        if method == "GET" and path == "/api/v1/server/info":
            return self._reply(200, {"status": 200, "data": {"private_api": False, "helper_connected": False}})
        if method == "GET" and path == "/api/v1/webhook":
            return self._reply(200, {"status": 200, "data": webhooks})
        if method == "POST" and path == "/api/v1/webhook":
            hook = {"id": len(webhooks) + 1, "url": body["url"], "events": body.get("events", [])}
            webhooks.append(hook)
            return self._reply(200, {"status": 200, "data": hook})
        if method == "DELETE" and path.startswith("/api/v1/webhook/"):
            webhooks[:] = [w for w in webhooks if str(w["id"]) != path.rsplit("/", 1)[-1]]
            return self._reply(200, {"status": 200})
        if method == "POST" and path == "/api/v1/chat/query":
            # One known DM, so sends addressed by phone number resolve to a chat GUID.
            chats = [{"guid": "iMessage;-;+64210000000", "chatIdentifier": "+64210000000"}]
            return self._reply(200, {"status": 200, "data": chats})
        if method == "POST" and path == "/api/v1/message/text":
            return self._reply(200, {"status": 200, "data": {"guid": "fake-sent-guid"}})
        return self._reply(200, {"status": 200, "data": {}})

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def do_DELETE(self):
        self._handle("DELETE")


# Bind all interfaces like the real BlueBubbles Server does.
ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
