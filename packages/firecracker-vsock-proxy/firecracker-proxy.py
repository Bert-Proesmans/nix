#!/usr/bin/env python3

import socket
import sys
import selectors
import os
import fcntl
import argparse
import re

# Parse command-line arguments
parser = argparse.ArgumentParser(
    description="Bidirectional proxy using a Unix socket (firecracker style)."
)
parser.add_argument(
    "socket_path",
    help="Path to the Unix socket to proxy.",
)
parser.add_argument(
    "service_port",
    help="Port to connect to, where the service is listening.",
)
args = parser.parse_args()

# Define the socket path and port
SOCKET_PATH = args.socket_path
PORT = args.service_port

# Maximum amount of data that can be written atomically without being
# fractured by interleaving writes
PIPE_BUF = os.sysconf("SC_PAGE_SIZE")

# Set stdin to non-blocking mode
fd_stdin = sys.stdin.fileno()
flags = fcntl.fcntl(fd_stdin, fcntl.F_GETFL)  # Get current flags
fcntl.fcntl(fd_stdin, fcntl.F_SETFL, flags | os.O_NONBLOCK)  # Set non-blocking

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    sock.setblocking(False)
    sock.connect(SOCKET_PATH)
except BlockingIOError:
    pass  # Ignore the error, as the connection will be established later

# Setup evented I/O and proxy
selector = selectors.DefaultSelector()
selector.register(sock, selectors.EVENT_READ)

# Firecracker multiplexing handshake
completed_handshake = False
buffer_handshake = bytearray()
pattern_response = re.compile(rb"^OK \d+\n")
sock.sendall(f"CONNECT {PORT}\n".encode())
while not completed_handshake:
    for key, _ in selector.select():
        if key.fileobj == sock:
            try:
                data = sock.recv(PIPE_BUF)
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
                if not data:
                    # EOF AF_UNIX
                    sock.close()
                    sys.exit(1)

                buffer_handshake.extend(data)
                match_response = pattern_response.match(buffer_handshake)
                if match_response:
                    # Valid handshake reply
                    completed_handshake = True
                    # Cut the buffer right after the newline character
                    stow = buffer_handshake[match_response.end() :]
                    # NOTE; We're reading in non-blocking, so pushing data out
                    # into stdout must be followed by a flush
                    sys.stdout.buffer.write(stow)
                    sys.stdout.flush()
                    break
            except BlockingIOError:
                # Assumes attempt at retrieving empty data buffer
                continue

# Handshake is done, proxy as normal
selector.register(fd_stdin, selectors.EVENT_READ)
while True:
    for key, _ in selector.select():
        if key.fileobj == sock:
            try:
                data = sock.recv(PIPE_BUF)
                if not data:
                    # EOF AF_UNIX
                    sock.close()
                    sys.exit(0)

                # NOTE; We're reading in non-blocking, so pushing data out
                # into stdout must be followed by a flush
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
            except BlockingIOError:
                # Assumes attempt at retrieving empty data buffer
                continue

        elif key.fileobj == fd_stdin:
            try:
                # Read non-blocking data from stdin
                input_data = os.read(fd_stdin, PIPE_BUF)
                if not input_data:
                    # EOF stdin
                    sock.close()  # Close AF_UNIX connection
                    sys.exit(0)

                # Send input data to the socket
                sock.sendall(input_data)
            except BlockingIOError:
                # Assumes attempt at retrieving empty data buffer
                continue
