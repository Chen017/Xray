#!/usr/bin/env python3
"""Temporary bounded HTTPS byte source. Only same-host clients may fetch bytes.

Run via authenticated SSH stdin. The first JSON line contains an ephemeral
token and public certificate: keep it local. No files or proxying are served.
"""
import argparse
import base64
import http.server
import ipaddress
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import ssl
import subprocess
import tempfile
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', required=True)
    parser.add_argument('--seconds', type=int, default=300)
    args = parser.parse_args()
    address = str(ipaddress.ip_address(args.bind))
    if ':' in address or not 10 <= args.seconds <= 900:
        parser.error('Use the authorized server IPv4 and 10..900 seconds')
    token = secrets.token_urlsafe(24)
    block = os.urandom(256 * 1024)
    total = 0
    lock = threading.Lock()
    max_total = 4 * 1024**3

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def setup(self):
            # TLS handshakes belong in the request worker, not the accept loop.
            # Otherwise one WAN handshake serializes all other short requests.
            self.request.do_handshake()
            super().setup()

        def do_GET(self):
            nonlocal total
            self.connection.settimeout(15)
            if self.client_address[0] != address or self.headers.get('Authorization') != 'Bearer ' + token:
                self.send_error(403)
                self.close_connection = True
                return
            try:
                size = int(self.path.removeprefix('/bytes/'))
            except ValueError:
                self.send_error(404)
                return
            if not self.path.startswith('/bytes/') or not 1 <= size <= 256 * 1024**2:
                self.send_error(400)
                return
            with lock:
                if total + size > max_total:
                    self.send_error(429)
                    return
                total += size
            self.send_response(200)
            self.send_header('Content-Length', str(size))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Type', 'application/octet-stream')
            self.end_headers()
            try:
                while size:
                    chunk = block[:min(size, len(block))]
                    self.wfile.write(chunk)
                    size -= len(chunk)
            except (OSError, ssl.SSLError):
                self.close_connection = True

        def log_message(self, *_):
            pass

    def stop(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    with tempfile.TemporaryDirectory(prefix='xray-bench-origin-') as tmp:
        cert, key = Path(tmp) / 'cert.pem', Path(tmp) / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1',
                        '-subj', '/CN=xray-benchmark', '-addext', f'subjectAltName=IP:{address}'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.set_alpn_protocols(['http/1.1'])
        context.load_cert_chain(cert, key)
        class Server(http.server.ThreadingHTTPServer):
            request_queue_size = 128

            def get_request(self):
                connection, client = self.socket.accept()
                connection.settimeout(15)
                try:
                    return context.wrap_socket(connection, server_side=True, do_handshake_on_connect=False), client
                except Exception:
                    connection.close()
                    raise

        server = Server((address, 0), Handler)
        server.daemon_threads = True
        server.timeout = .5
        server.socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        print(json.dumps({'pid': os.getpid(), 'port': server.server_port, 'address': address,
                          'token': token, 'certificate': base64.b64encode(cert.read_bytes()).decode(),
                          'expires_in_seconds': args.seconds}), flush=True)
        deadline = time.monotonic() + args.seconds
        try:
            while time.monotonic() < deadline:
                server.handle_request()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()


if __name__ == '__main__':
    main()
