#!/usr/bin/env python3
"""Print message metadata from a forwarded Lumen v1 video stream."""

import argparse
import socket
import struct
import sys

MAGIC = b"LU"
VERSION = 1
MAX_PAYLOAD = 8_388_608
MAX_CONFIG = 65_536
HEADER = struct.Struct(">2sBIBQ")
CONFIG_FIXED = struct.Struct(">BHHHHB")


class ProtocolError(Exception):
    pass


def read_exact(sock, size, *, allow_clean_eof=False):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            if allow_clean_eof and not data:
                return None
            raise ProtocolError("connection closed in the middle of a message")
        data.extend(chunk)
    return bytes(data)


def inspect(sock):
    configured = False
    saw_keyframe = False
    last_timestamp = 0

    while True:
        raw_header = read_exact(sock, HEADER.size, allow_clean_eof=True)
        if raw_header is None:
            return
        magic, version, length, message_type, timestamp = HEADER.unpack(raw_header)
        if magic != MAGIC or version != VERSION:
            raise ProtocolError("bad magic or unsupported protocol version")
        if message_type not in (1, 2, 3):
            raise ProtocolError(f"unknown message type {message_type}")
        if length == 0 or length > MAX_PAYLOAD:
            raise ProtocolError(f"invalid payload length {length}")
        if message_type == 1 and length > MAX_CONFIG:
            raise ProtocolError(f"config payload exceeds {MAX_CONFIG} bytes")

        payload = read_exact(sock, length)
        if message_type == 1:
            if configured or timestamp != 0 or len(payload) < 14:
                raise ProtocolError("invalid or repeated config message")
            codec, width, height, fps, rotation, mirror = CONFIG_FIXED.unpack_from(payload)
            sps_length = struct.unpack_from(">H", payload, CONFIG_FIXED.size)[0]
            pps_length_offset = CONFIG_FIXED.size + 2 + sps_length
            if pps_length_offset + 2 > len(payload):
                raise ProtocolError("truncated SPS in config")
            pps_length = struct.unpack_from(">H", payload, pps_length_offset)[0]
            if pps_length_offset + 2 + pps_length != len(payload):
                raise ProtocolError("invalid PPS length in config")
            if codec != 1 or not width or not height or not fps:
                raise ProtocolError("unsupported codec or invalid video dimensions/rate")
            if rotation not in (0, 90, 180, 270) or mirror not in (0, 1):
                raise ProtocolError("invalid rotation or mirror flag")
            if not sps_length or not pps_length:
                raise ProtocolError("config is missing SPS or PPS")
            configured = True
            print(f"config {width}x{height} {fps}fps rotation={rotation} mirror={bool(mirror)} sps={sps_length}B pps={pps_length}B", flush=True)
            continue

        if not configured:
            raise ProtocolError("video received before config")
        if message_type == 2:
            if not payload.startswith(b"\x00\x00\x00\x01"):
                raise ProtocolError("keyframe is not Annex-B")
            saw_keyframe = True
        elif not saw_keyframe:
            raise ProtocolError("delta frame received before keyframe")
        if timestamp < last_timestamp:
            raise ProtocolError("capture timestamps moved backwards")
        last_timestamp = timestamp
        name = "keyframe" if message_type == 2 else "delta"
        print(f"{name} {length}B capture={timestamp}us", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", help="forwarded TCP host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=5000, help="forwarded TCP port (default: 5000)")
    args = parser.parse_args()

    try:
        with socket.create_connection((args.host, args.port)) as sock:
            inspect(sock)
    except (OSError, ProtocolError) as error:
        print(f"stream error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
