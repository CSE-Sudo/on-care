"""컨테이너 기동 스크립트(`scripts/start.sh`) — DB 불필요. (#2821)

`ENV` 가 비어 있으면 마이그레이션도 서버도 띄우지 않고 멈추는지 본다. 실제
`python`·`uvicorn` 대신 PATH 앞에 둔 가짜 실행 파일이 불렸는지만 기록한다.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[1]
SCRIPT = BACKEND / "scripts" / "start.sh"

pytestmark = pytest.mark.skipif(shutil.which("bash") is None, reason="bash 필요")


def _fake_bin(tmp_path: Path) -> Path:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log = tmp_path / "calls.log"
    for name in ("python", "uvicorn"):
        path = bin_dir / name
        path.write_text(f'#!/usr/bin/env bash\necho "{name} $*" >> "{log}"\n')
        path.chmod(0o755)
    return bin_dir


def _run(tmp_path: Path, **env: str) -> tuple[subprocess.CompletedProcess, str]:
    bin_dir = _fake_bin(tmp_path)
    base = {k: v for k, v in os.environ.items() if k not in {"ENV", "PORT"}}
    base["PATH"] = f"{bin_dir}{os.pathsep}{base.get('PATH', '')}"
    base.update(env)
    result = subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=BACKEND,
        env=base,
        capture_output=True,
        text=True,
        timeout=30,
    )
    log = tmp_path / "calls.log"
    return result, log.read_text() if log.exists() else ""


def test_missing_env_refuses_to_start(tmp_path):
    result, calls = _run(tmp_path)
    assert result.returncode != 0
    assert "ENV" in result.stderr
    # 마이그레이션도 서버도 시작하지 않는다.
    assert calls == ""


@pytest.mark.parametrize("blank", ["", "   ", "\t"])
def test_blank_env_refuses_to_start(tmp_path, blank):
    result, calls = _run(tmp_path, ENV=blank)
    assert result.returncode != 0
    assert calls == ""


def test_explicit_env_migrates_then_serves(tmp_path):
    result, calls = _run(tmp_path, ENV="prod", PORT="8123")
    assert result.returncode == 0, result.stderr
    lines = calls.splitlines()
    assert lines[0] == "python scripts/migrate.py"
    assert lines[1].startswith("uvicorn app.main:app")
    assert "--port 8123" in lines[1]
    assert "[start] ENV=prod" in result.stdout


def test_env_check_runs_before_port_validation(tmp_path):
    """두 값이 모두 틀리면 ENV 를 먼저 알린다 — 더 위험한 쪽이다."""
    result, _ = _run(tmp_path, PORT="not-a-port")
    assert result.returncode != 0
    assert "ENV" in result.stderr
