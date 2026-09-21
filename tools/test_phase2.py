#!/usr/bin/env python3
"""Self-contained 4–10 client lobby and private-role regression check."""

from __future__ import annotations

import glob
import os
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def find_godot() -> str:
    configured = os.getenv("GODOT_BIN")
    if configured:
        return configured
    local = os.getenv("LOCALAPPDATA", "")
    matches = sorted(
        glob.glob(
            os.path.join(
                local,
                "Microsoft",
                "WinGet",
                "Packages",
                "GodotEngine.GodotEngine_*",
                "Godot_v*-stable_win64_console.exe",
            )
        ),
        reverse=True,
    )
    if not matches:
        raise RuntimeError("Godot executable not found; set GODOT_BIN")
    return matches[0]


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


def main() -> int:
    godot = find_godot()
    client_count = int(os.getenv("PHASE2_CLIENTS", "4"))
    preferred_camper = os.getenv("PHASE2_PREFER_CAMPER", "").strip()
    if not 4 <= client_count <= 10:
        raise ValueError("PHASE2_CLIENTS must be between 4 and 10")
    port = 7210
    room_code = "TEST01"
    server_log = ROOT / "builds" / "phase2_server_test.log"
    server = start_process(
        [
            godot,
            "--headless",
            "--path",
            str(ROOT),
            "--log-file",
            str(server_log),
            "--",
            "--server",
            f"--port={port}",
            f"--code={room_code}",
            "--minimum-players=4",
        ]
        + ([f"--prefer-camper={preferred_camper}"] if preferred_camper else [])
    )
    processes: list[subprocess.Popen] = []
    logs: list[Path] = []
    try:
        if not wait_for_text(server_log, "PHASE2_SERVER_READY"):
            raise RuntimeError("Local test server did not start")

        all_identities = [
            ("Riya", "riya", 1, False),
            ("Kabir", "kabir", 2, False),
            ("Zoya", "zoya", 3, False),
            ("Host", "host-player", 0, True),
            ("Aman", "aman", 4, False),
            ("Meera", "meera", 5, False),
            ("Ishaan", "ishaan", 0, False),
            ("Naina", "naina", 1, False),
            ("Dev", "dev", 2, False),
            ("Sara", "sara", 3, False),
        ]
        guests = [identity for index, identity in enumerate(all_identities) if index != 3]
        identities = guests[: client_count - 1] + [all_identities[3]]
        for index, (name, player_id, color, is_host) in enumerate(identities, start=1):
            log_path = ROOT / "builds" / f"phase2_client_{index}.log"
            logs.append(log_path)
            command = [
                godot,
                "--headless",
                "--path",
                str(ROOT),
                "--log-file",
                str(log_path),
                "--",
                "--address=127.0.0.1",
                f"--port={port}",
                f"--token=dev:{player_id}:{'host' if is_host else 'guest'}",
                f"--name={name}",
                f"--color={color}",
                "--auto-ready",
                "--test-exit-on-match",
            ]
            if is_host:
                command.append("--auto-start")
            processes.append(start_process(command))

        deadline = time.time() + 20
        while time.time() < deadline and any(process.poll() is None for process in processes):
            time.sleep(0.1)
        for process in processes:
            stop(process)

        matches = 0
        killers = 0
        for log_path in logs:
            text = log_path.read_text(encoding="utf-8", errors="replace")
            matches += int("PHASE2_MATCH_STARTED" in text)
            killers += int("role=Killer" in text)
        preferred_camper_ok = True
        if preferred_camper:
            preferred_index = next(index for index, identity in enumerate(identities) if identity[1] == preferred_camper)
            preferred_text = logs[preferred_index].read_text(encoding="utf-8", errors="replace")
            preferred_camper_ok = "role=Camper" in preferred_text
        print(f"PHASE2_E2E room={room_code} clients={matches} killers={killers} preferred_camper_ok={preferred_camper_ok}")
        return 0 if matches == len(identities) and killers == 1 and preferred_camper_ok else 1
    finally:
        for process in processes:
            stop(process)
        stop(server)


if __name__ == "__main__":
    sys.exit(main())
