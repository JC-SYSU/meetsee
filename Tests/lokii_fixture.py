"""Isolated Unix-socket fixtures; never starts or changes the installed Lokii."""
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import threading
import time

with tempfile.TemporaryDirectory(prefix='meetsee-lokii-test-', dir='/tmp') as tmp:
    tmp = Path(tmp).resolve()
    root = tmp / 'files'
    root.mkdir()
    for name in ['旅行.txt', 'README', '.hidden/旅行.txt', '父目录/笔记.txt', 'Fake.app/Contents/旅行.txt', 'Font Book.app/Contents/Info.plist']:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
    with (root / 'Font Book.app/Contents/Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleName': 'Font Book', 'CFBundleDisplayName': '字体册', 'CFBundlePackageType': 'APPL'}, f)
    outside = tmp / 'outside'
    outside.mkdir()
    (outside / '旅行.txt').touch()
    os.symlink(outside, root / 'link')
    paths = [root] + list(root.rglob('*')) + [root / '旅行.txt', root / 'link/旅行.txt']
    records = [{'path': str(p), 'isDir': p.is_dir(), 'modified': 0} for p in paths]
    records.append({'path': str(outside / '旅行.txt'), 'isDir': False, 'modified': 0})
    servers = []
    def handle(conn, kind):
        try:
            with conn:
                req = conn.makefile('rb').readline()
                if not req: return
                request = json.loads(req)
                if kind == 'stall': time.sleep(0.3); return
                if kind == 'eof': return
                if kind == 'malformed': conn.sendall(b'not-json\n'); return
                if kind == 'error': conn.sendall(b'{"results":[],"error":"mock-error"}\n'); return
                if kind == 'oversize': conn.sendall(b'x' * (4 * 1024 * 1024 + 1)); return
                if kind == 'bulk':
                    assert request['limit'] == 5000, request
                    result = [{'path': '/bulk/item' + str(i), 'isDir': False, 'modified': 0} for i in range(min(request['limit'], 750))]
                elif kind == 'normal':
                    assert request == {'q': '中文 " \\ \n type:app', 'mode': 'substring', 'limit': 17}
                    result = [{'path': '/中文路径', 'isDir': True, 'modified': 5}]
                else:
                    assert request['limit'] == 5000, request
                    result = [r for r in records if r['path'].endswith('Font Book.app')] if request['mode'] == 'regex' else records
                data = (json.dumps({'results': result, 'error': None}, ensure_ascii=False) + '\n').encode()
                if kind == 'normal':
                    for b in data:
                        conn.sendall(bytes([b]))
                        time.sleep(0.0001)
                else: conn.sendall(data)
        except (BrokenPipeError, ConnectionResetError): pass
    def serve(server, kind):
        while True:
            try: conn, _ = server.accept()
            except OSError: return
            threading.Thread(target=handle, args=(conn, kind), daemon=True).start()
    for kind in ['normal', 'stall', 'eof', 'malformed', 'error', 'oversize', 'engine', 'bulk']:
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(tmp / kind))
        server.listen()
        servers.append(server)
        threading.Thread(target=serve, args=(server, kind), daemon=True).start()
    result = subprocess.run([sys.argv[1], str(root), str(tmp)])
    for server in servers: server.close()
    sys.exit(result.returncode)
