#!/usr/bin/env python3
"""Compile production Foundation transport/proxy on macOS and exercise a local fixture NAS."""
import http.server
import pathlib
import subprocess
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
class NAS(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass
    def do_GET(self):
        if self.headers.get('Authorization') != 'fixture-token' or self.headers.get('Cookie') != 'mode=relay':
            self.send_response(401); self.end_headers(); return
        if self.path == '/redirect':
            self.send_response(302); self.send_header('Location', 'http://outside.invalid/secret'); self.end_headers(); return
        if self.path == '/wait-slow-start':
            assert self.server.slow_started.wait(3)
            body = b'ok'
        elif self.path == '/slow-segment.ts':
            body = b'abcdef'
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.flush()
            self.server.slow_started.set()
            time.sleep(0.4)
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        elif self.path == '/huge-poster.webp':
            body = b'x'*(4*1024*1024+1)
        elif self.path == '/big':
            body = b'x'*1024
        elif self.path == '/master.m3u8':
            body = b'#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:2,\nsegment.ts\n#EXT-X-ENDLIST\n'
        elif self.path == '/segment.ts':
            body = b'abcdef'
        else:
            body = b'ok'
        if self.headers.get('Range') == 'bytes=2-4':
            self.send_response(206); self.send_header('Content-Range', 'bytes 2-4/6'); body = body[2:5]
        else:
            self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Content-Type', 'application/vnd.apple.mpegurl' if '.m3u8' in self.path else 'application/octet-stream')
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

with http.server.ThreadingHTTPServer(('127.0.0.1', 0), NAS) as server, tempfile.TemporaryDirectory(prefix='fntv-network-test-') as tmp:
    server.slow_started = threading.Event()
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    binary = pathlib.Path(tmp)/'network_selftest'
    subprocess.run(['xcrun', 'clang', '-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-I', str(ROOT/'Sources/Networking'), str(ROOT/'Tests/network_selftest.m'), str(ROOT/'Sources/Networking/FNTVHTTP.m'), str(ROOT/'Sources/Networking/FNTVSignature.m'), str(ROOT/'Sources/Networking/FNTVHLSProxy.m'), '-framework', 'Foundation', '-framework', 'Security', '-o', str(binary)], check=True)
    subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}', str(pathlib.Path(tmp)/'proxy-metrics.json')], check=True, timeout=30)
    login_binary = pathlib.Path(tmp)/'login_selftest'
    subprocess.run(['xcrun', 'clang', '-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-I', str(ROOT/'Sources/Networking'), str(ROOT/'Tests/login_selftest.m'), str(ROOT/'Sources/Networking/FNTVLogin.m'), str(ROOT/'Sources/Networking/FNTVHTTP.m'), str(ROOT/'Sources/Networking/FNTVSignature.m'), '-framework', 'Foundation', '-framework', 'Security', '-o', str(login_binary)], check=True)
    subprocess.run([str(login_binary)], check=True, timeout=10)
    signature_binary = pathlib.Path(tmp)/'signature_selftest'
    subprocess.run(['xcrun', 'clang', '-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-I', str(ROOT/'Sources/Networking'), str(ROOT/'Tests/signature_selftest.m'), str(ROOT/'Sources/Networking/FNTVSignature.m'), '-framework', 'Foundation', '-framework', 'Security', '-o', str(signature_binary)], check=True)
    subprocess.run([str(signature_binary), str(ROOT/'Tests/signature-fixtures.json')], check=True, timeout=10)
    registry_binary = pathlib.Path(tmp)/'proxy_registry_selftest'
    subprocess.run(['xcrun', 'clang', '-O2', '-fblocks', '-fno-objc-arc', '-Wno-deprecated-declarations', '-I', str(ROOT/'Sources/Networking'), str(ROOT/'Tests/proxy_registry_selftest.m'), str(ROOT/'Sources/Networking/FNTVHLSProxy.m'), str(ROOT/'Sources/Networking/FNTVHTTP.m'), str(ROOT/'Sources/Networking/FNTVSignature.m'), '-framework', 'Foundation', '-framework', 'Security', '-o', str(registry_binary)], check=True)
    subprocess.run([str(registry_binary)], check=True, timeout=15)
    server.shutdown()
