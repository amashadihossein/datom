"""Tiny local stand-in for S3: logs which access key signed each request.

Only fake keys are used. Logs one line per request: METHOD PATH KEYID TOKEN.
"""
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def _record(self):
        auth = self.headers.get("Authorization", "")
        m = re.search(r"Credential=([^/]+)/", auth)
        key = m.group(1) if m else "UNSIGNED"
        token = self.headers.get("x-amz-security-token", "-")
        with open(LOG, "a") as f:
            f.write(f"{self.command} {self.path} {key} {token}\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_HEAD = _record
    do_GET = _record

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
