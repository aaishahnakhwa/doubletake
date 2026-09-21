#!/usr/bin/env python3
"""Checks Phase 2 role-preserving reconnect and lobby host transfer."""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

from test_phase2 import ROOT, find_godot


def start_process(arguments: list[str]) -> subprocess.Popen:
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    return subprocess.Popen(arguments, cwd=ROOT, creationflags=flags)


def wait_for_text(path: Path, text: str, timeout: float = 10) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.exists() and text in path.read_text(encoding="utf-8", errors="replace"):
            return True
        time.sleep(0.1)
    return False


def stop(process: subprocess.Popen) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()


def server_command(godot: str, port: int, code: str, log: Path, minimum: int) -> list[str]:
    return [
        godot,
        "--headless",
        "--path",
        str(ROOT),
        "--log-file",
        str(log),
        "--",
        "--server",
        f"--port={port}",
        f"--code={code}",
        f"--minimum-players={minimum}",
    ]


def client_command(godot: str, port: int, token: str, name: str, log: Path, *flags: str) -> list[str]:
    return [
        godot,
        "--headless",
        "--path",
        str(ROOT),
        "--log-file",
        str(log),
        "--",
        "--address=127.0.0.1",
        f"--port={port}",
        f"--token={token}",
        f"--name={name}",
        *flags,
    ]


def test_role_reconnect(godot: str) -> bool:
    port = 7220
    server_log = ROOT / "builds" / "phase2_reconnect_server.log"
    first_log = ROOT / "builds" / "phase2_reconnect_first.log"
    second_log = ROOT / "builds" / "phase2_reconnect_second.log"
    server = start_process(server_command(godot, port, "RECON1", server_log, 1))
    try:
        if not wait_for_text(server_log, "PHASE2_SERVER_READY"):
            return False
        first = start_process(
            client_command(
                godot,
                port,
                "dev:reconnect-player:host",
                "Reconnect",
                first_log,
                "--auto-ready",
                "--auto-start",
                "--test-exit-on-match",
            )
        )
        first.wait(timeout=12)
        if not wait_for_text(first_log, "role=Killer", 1):
            return False
        time.sleep(0.5)
        second = start_process(
            client_command(
                godot,
                port,
                "dev:reconnect-player:host",
                "Reconnect",
                second_log,
                "--test-exit-on-match",
            )
        )
        second.wait(timeout=12)
        return wait_for_text(second_log, "role=Killer", 1)
    finally:
        stop(server)


def test_host_transfer(godot: str) -> bool:
    port = 7221
    server_log = ROOT / "builds" / "phase2_transfer_server.log"
    host_log = ROOT / "builds" / "phase2_transfer_host.log"
    guest_log = ROOT / "builds" / "phase2_transfer_guest.log"
    server = start_process(server_command(godot, port, "HOST01", server_log, 4))
    host: subprocess.Popen | None = None
    guest: subprocess.Popen | None = None
    try:
        if not wait_for_text(server_log, "PHASE2_SERVER_READY"):
            return False
        host = start_process(
            client_command(
                godot,
                port,
                "dev:original-host:host",
                "OriginalHost",
                host_log,
                "--test-exit-after-lobby-delay",
            )
        )
        if not wait_for_text(host_log, "PHASE2_JOINED"):
            return False
        guest = start_process(
            client_command(
                godot,
                port,
                "dev:new-host:guest",
                "NewHost",
                guest_log,
                "--test-host-transfer",
            )
        )
        return wait_for_text(guest_log, "PHASE2_HOST_TRANSFERRED", 12)
    finally:
        if host is not None:
            stop(host)
        if guest is not None:
            stop(guest)
        stop(server)


def test_authoritative_movement(godot: str) -> bool:
    port = 7222
    server_log = ROOT / "builds" / "phase2_movement_server.log"
    client_log = ROOT / "builds" / "phase2_movement_client.log"
    server = start_process(server_command(godot, port, "MOVE01", server_log, 1))
    client: subprocess.Popen | None = None
    try:
        if not wait_for_text(server_log, "PHASE2_SERVER_READY"):
            return False
        client = start_process(
            client_command(
                godot,
                port,
                "dev:mover:host",
                "Mover",
                client_log,
                "--auto-ready",
                "--auto-start",
                "--test-movement",
            )
        )
        return wait_for_text(client_log, "PHASE2_MOVEMENT_SYNCED", 12)
    finally:
        if client is not None:
            stop(client)
        stop(server)


def main() -> int:
    godot = find_godot()
    reconnect = test_role_reconnect(godot)
    transfer = test_host_transfer(godot)
    movement = test_authoritative_movement(godot)
    print(
        "PHASE2_RESILIENCE "
        f"reconnect={reconnect} host_transfer={transfer} movement={movement}"
    )
    return 0 if reconnect and transfer and movement else 1


if __name__ == "__main__":
    sys.exit(main())
