#!/usr/bin/env python3
# Принимает POST /log?step=<name> от плагина и пишет тело в logs/<step>.txt (+ logs/last.txt).
# POST /file?name=<x.png> — сохраняет тело как есть в logs/<x.png> (экспорт фреймов для проверки).
# Запуск: python3 -I logserver.py
import pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

LOGS = pathlib.Path(__file__).resolve().parent / 'logs'
LOGS.mkdir(exist_ok=True)

class H(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def do_POST(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == '/file':
            name = ''.join(c for c in q.get('name', ['out.png'])[0] if c.isalnum() or c in '-_.') or 'out.png'
            data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            (LOGS / name).write_bytes(data)
            print(f'[file] {name} {len(data)} bytes', flush=True)
            self.send_response(200); self._cors(); self.end_headers(); self.wfile.write(b'ok'); return
        step = q.get('step', ['unknown'])[0]
        step = ''.join(c for c in step if c.isalnum() or c in '-_') or 'unknown'
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode('utf-8', 'replace')
        (LOGS / f'{step}.txt').write_text(body)
        (LOGS / 'last.txt').write_text(body)
        print(f'[{step}] {len(body)} chars', flush=True)
        self.send_response(200); self._cors(); self.end_headers(); self.wfile.write(b'ok')

    def log_message(self, *a):
        pass

HTTPServer(('127.0.0.1', 8377), H).serve_forever()
