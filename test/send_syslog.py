#!/usr/bin/env python3
"""
Send RFC 3164 syslog test messages via UDP or TCP. No external dependencies.

Usage:
  python3 send_syslog.py --host 127.0.0.1 --port 5514 --count 5
  python3 send_syslog.py --host 127.0.0.1 --port 5514 --proto tcp --hostname my-firewall
"""

import argparse
import datetime
import socket
import time

FACILITY = {
    "kern": 0, "user": 1, "mail": 2, "daemon": 3,
    "auth": 4, "syslog": 5, "lpr": 6, "news": 7,
    "local0": 16, "local1": 17, "local2": 18, "local3": 19,
    "local4": 20, "local5": 21, "local6": 22, "local7": 23,
}

SEVERITY = {
    "emerg": 0, "alert": 1, "crit": 2, "err": 3,
    "warning": 4, "notice": 5, "info": 6, "debug": 7,
}


def build_message(facility: str, severity: str, hostname: str, tag: str, body: str) -> bytes:
    pri = (FACILITY[facility] * 8) + SEVERITY[severity]
    timestamp = datetime.datetime.now().strftime("%b %d %H:%M:%S")
    line = f"<{pri}>{timestamp} {hostname} {tag}: {body}"
    return line.encode("utf-8")


def send_udp(host: str, port: int, data: bytes) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(data, (host, port))


def send_tcp(host: str, port: int, data: bytes) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((host, port))
        s.sendall(data + b"\n")


def main() -> None:
    p = argparse.ArgumentParser(description="Send test syslog messages")
    p.add_argument("--host", default="127.0.0.1", help="Target host (default: 127.0.0.1)")
    p.add_argument("--port", type=int, default=5514, help="Target port (default: 5514)")
    p.add_argument("--proto", choices=["udp", "tcp"], default="udp", help="Protocol (default: udp)")
    p.add_argument("--facility", choices=list(FACILITY), default="local0")
    p.add_argument("--severity", choices=list(SEVERITY), default="info")
    p.add_argument("--hostname", default="test-device", help="Syslog HOSTNAME field")
    p.add_argument("--tag", default="test", help="Syslog TAG field")
    p.add_argument("--count", type=int, default=1, help="Number of messages to send")
    p.add_argument("--interval", type=float, default=0.1, help="Seconds between messages")
    p.add_argument("--message", default="Test syslog message from send_syslog.py")
    args = p.parse_args()

    sender = send_udp if args.proto == "udp" else send_tcp

    for i in range(args.count):
        body = args.message if args.count == 1 else f"{args.message} [{i + 1}/{args.count}]"
        data = build_message(args.facility, args.severity, args.hostname, args.tag, body)
        sender(args.host, args.port, data)
        print(f"[{args.proto.upper()}] -> {args.host}:{args.port}  {data.decode()}")
        if i < args.count - 1:
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
