#!/usr/bin/env python3
"""Local mock of the Supabase HTTP surface used by api_denial.sh.

Purpose: execute api_denial.sh's failure paths deterministically WITHOUT a
real project (see run_selftest.sh). This mock is a test double for the
script's own logic only — it proves the script fails closed; it does NOT
prove anything about a deployed Supabase project.

Usage: MOCK_SCENARIO=<scenario> python3 mock_api.py <port>
Scenarios:
  ok              everything healthy; cleanup returns 204
  bad_json        auth endpoint returns unparseable body      -> expect exit 2
  bad_uuid        auth returns a non-UUID user id             -> expect exit 2
  fixture_missing owner read of fixture returns 404           -> expect exit 2
  owner_forbidden fixture EXISTS but owner read returns 403   -> expect exit 2
  list_500        anonymous storage list returns 500          -> expect FAIL
  leak            anonymous storage list discloses fixture    -> expect HARD FAIL
  cleanup_500     session delete returns 500                  -> expect WARN, exit 0
"""
import http.server
import json
import os
import sys
from urllib.parse import urlparse, parse_qs

SCEN = os.environ.get("MOCK_SCENARIO", "ok")
UUID_A = "11111111-1111-4111-8111-111111111111"
UUID_C = "33333333-3333-4333-8333-333333333333"
SESS = "22222222-2222-4222-8222-222222222222"
FIXTURE_PATH = "conv1/user-a/fixture.png"
STATE = {"deleted": False}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep selftest output clean
        pass

    def _send(self, code, body="", ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle(self):
        parsed = urlparse(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        auth = (self.headers.get("Authorization") or "").replace("Bearer ", "")
        anon = auth == "anon-key-mock"

        # PostgREST rejects non-exposed schema profiles before anything else.
        if (self.headers.get("Accept-Profile") == "private"
                or self.headers.get("Content-Profile") == "private"):
            return self._send(406, '{"message":"The schema must be one of the following: public"}')

        if path == "/auth/v1/token":
            if SCEN == "bad_json":
                return self._send(200, "garbage{{not-json")
            email = json.loads(body).get("email", "")
            uid = UUID_A if email.startswith("a@") else UUID_C
            if SCEN == "bad_uuid":
                uid = "not-a-uuid"
            token = "tok-a" if email.startswith("a@") else "tok-c"
            return self._send(200, json.dumps({"access_token": token, "user": {"id": uid}}))

        if path in ("/rest/v1/rpc/is_blocked_between", "/rest/v1/rpc/is_conversation_member"):
            return self._send(404, '{"message":"Could not find the function in the schema cache"}')

        if path.startswith("/rest/v1/rpc/"):
            if anon:
                return self._send(401, '{"message":"permission denied"}')
            return self._send(200, "[]")

        if path in ("/rest/v1/messages", "/rest/v1/profiles"):
            return self._send(200, "[]")  # RLS-filtered empty sets

        if path == "/rest/v1/device_sessions":
            if self.command == "POST":
                return self._send(201, json.dumps([{"id": SESS}]))
            if self.command == "DELETE":
                if SCEN == "cleanup_500":
                    return self._send(500, '{"error":"internal"}')
                STATE["deleted"] = True
                return self._send(204, "")
            # GET
            if auth == "tok-c":
                return self._send(200, "[]")
            user_filter = (query.get("user_id") or [""])[0]
            id_filter = (query.get("id") or [""])[0]
            if user_filter.startswith("neq."):
                return self._send(200, "[]")
            if id_filter == f"eq.{SESS}":
                return self._send(200, "[]" if STATE["deleted"] else json.dumps([{"id": SESS}]))
            if "device_name" in query:
                return self._send(200, json.dumps([{"id": SESS}]))
            return self._send(200, "[]")

        if path == f"/storage/v1/object/personal-media/{FIXTURE_PATH}":
            if auth == "tok-a":
                if SCEN == "fixture_missing":
                    return self._send(404, '{"error":"Object not found"}')
                if SCEN == "owner_forbidden":
                    # Object exists (list shows it) but the owner read is
                    # denied — distinct failure from a missing fixture.
                    return self._send(403, '{"error":"Unauthorized"}')
                return self._send(200, "PNGDATA", "application/octet-stream")
            if anon:
                return self._send(400, '{"error":"headers must have required property authorization"}')
            return self._send(403, '{"error":"Unauthorized"}')

        if path == "/storage/v1/object/list/personal-media":
            if auth == "tok-a":
                return self._send(200, json.dumps([{"name": "fixture.png"}]))
            if anon and SCEN == "list_500":
                return self._send(500, '{"error":"internal server error"}')
            if anon and SCEN == "leak":
                return self._send(200, json.dumps([{"name": "fixture.png"}]))
            return self._send(200, "[]")

        return self._send(404, '{"message":"not found"}')

    do_GET = _handle
    do_POST = _handle
    do_DELETE = _handle


if __name__ == "__main__":
    port = int(sys.argv[1])
    with http.server.HTTPServer(("127.0.0.1", port), Handler) as server:
        server.serve_forever()
