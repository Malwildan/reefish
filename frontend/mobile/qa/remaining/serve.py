"""Loopback-only server for the synthetic remaining-screen QA build and captures."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = Path(__file__).resolve().parent

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / 'build' / 'remaining-qa'), **kwargs)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_POST(self):
        request = urlparse(self.path)
        name = parse_qs(request.query).get('name', [''])[0]
        size = int(self.headers.get('Content-Length', '0'))
        if request.path != '/qa-capture' or not re.fullmatch(r'remaining-[a-z-]+-(430x932|360x640)\.png', name) or not 0 < size <= 5_000_000:
            self.send_error(400)
            return
        data = self.rfile.read(size)
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            self.send_error(400)
            return
        (OUTPUT / name).write_bytes(data)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'saved': name}).encode())

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 4197), Handler).serve_forever()
