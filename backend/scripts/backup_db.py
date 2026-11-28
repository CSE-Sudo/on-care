"""운영 DB 백업 — 배포 직전 일회성 ECS 작업으로 돈다(#1552).

`pg_dump --format=custom` 으로 덤프를 뜨고, `pg_restore --list` 로 읽히는 덤프인지 확인한 뒤
S3 백업 버킷에 올린다. 하나라도 실패하면 0 이 아닌 값으로 끝나고, 배포 워크플로
(`.github/scripts/backend_db_backup.sh`)는 그 종료 코드를 보고 운영 배포를 멈춘다.

서비스 스택(`infra/backend-service.yml` `BackupTaskDefinition`)이 서비스와 같은 이미지·같은
Secrets Manager 비밀의 `DATABASE_URL` 로 이 작업을 정의한다 — 운영 DB 자격 증명을 GitHub 에
따로 두지 않는다. 객체 키는 워크플로가 정해 `BACKUP_OBJECT_KEY` 로 넘긴다.

    python -m scripts.backup_db

환경변수
    DATABASE_URL            덤프할 DB(서비스와 같은 값)
    BACKUP_S3_BUCKET        백업 버킷
    BACKUP_S3_PREFIX        키 접두사(기본 `db`). 작업 역할은 이 접두사에만 쓸 수 있다
    BACKUP_OBJECT_KEY       올릴 키. `<접두사>/<파일 이름>.dump` 꼴만 받는다
    BACKUP_TIMEOUT_SECONDS  pg_dump 한도(기본 1800초)

종료 코드: 0 성공, 1 덤프·검증·업로드 실패, 2 설정 오류.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

_KEY_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*\.dump$")


class ConfigError(Exception):
    """설정이 비었거나 형식이 틀렸다(종료 코드 2)."""


class BackupError(Exception):
    """덤프·검증·업로드 중 하나가 실패했다(종료 코드 1)."""


def libpq_url(url: str) -> str:
    """SQLAlchemy 형식 주소를 libpq(pg_dump)가 읽는 주소로 바꾼다.

    `config.sqlalchemy_database_url` 의 반대 방향이다. 서비스 비밀에는 Neon 이 준 그대로의
    `postgresql://…` 나 `postgresql+psycopg://…` 가 들어 있다.
    """
    for prefix in ("postgresql+psycopg://", "postgres://"):
        if url.startswith(prefix):
            return "postgresql://" + url[len(prefix):]
    return url


def object_key(key: str, prefix: str) -> str:
    """워크플로가 넘긴 키가 백업 접두사 바로 아래의 `.dump` 파일인지 본다."""
    head, sep, name = key.partition("/")
    if not sep or head != prefix or not _KEY_NAME.match(name):
        raise ConfigError(f"BACKUP_OBJECT_KEY 는 '{prefix}/<이름>.dump' 꼴이어야 한다: '{key}'")
    return key


def _required(env: Mapping[str, str], name: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise ConfigError(f"{name} 이 비어 있다.")
    return value


def _tail(text: str, limit: int = 2000) -> str:
    return text.strip()[-limit:]


def dump(url: str, path: Path, timeout: float, run: Callable[..., Any] = subprocess.run) -> None:
    """`pg_dump` 로 덤프를 뜨고 `pg_restore --list` 로 읽히는지 확인한다."""
    try:
        result = run(
            [
                "pg_dump",
                "--format=custom",
                "--no-owner",
                "--no-privileges",
                f"--file={path}",
                f"--dbname={url}",
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise BackupError(f"pg_dump 가 {timeout:.0f}초 안에 끝나지 않았다.") from exc
    if result.returncode != 0:
        # 서버보다 옛 pg_dump 면 여기서 버전 불일치로 멈춘다 — Dockerfile 의 PG_CLIENT_MAJOR.
        raise BackupError(f"pg_dump 실패(종료 코드 {result.returncode}): {_tail(result.stderr)}")
    if not path.exists() or path.stat().st_size == 0:
        raise BackupError("pg_dump 가 빈 파일을 남겼다.")

    listed = run(
        ["pg_restore", "--list", str(path)],
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    if listed.returncode != 0 or not listed.stdout.strip():
        raise BackupError(f"덤프를 pg_restore 가 읽지 못한다: {_tail(listed.stderr)}")


def upload(client: Any, path: Path, bucket: str, key: str) -> int:
    """덤프를 올리고 크기를 돌려준다. 실패하면 boto3 예외를 BackupError 로 바꾼다."""
    size = path.stat().st_size
    try:
        client.upload_file(str(path), bucket, key)
    except Exception as exc:  # noqa: BLE001 — boto3·S3 전송 오류를 모두 실패로 본다
        raise BackupError(f"S3 업로드 실패: {exc}") from exc
    return size


def run_backup(
    env: Mapping[str, str],
    *,
    client: Any | None = None,
    run: Callable[..., Any] = subprocess.run,
    workdir: Path | None = None,
) -> str:
    """백업 한 번. 성공하면 올린 `s3://버킷/키` 를 돌려준다."""
    url = libpq_url(_required(env, "DATABASE_URL"))
    bucket = _required(env, "BACKUP_S3_BUCKET")
    prefix = env.get("BACKUP_S3_PREFIX", "").strip() or "db"
    key = object_key(_required(env, "BACKUP_OBJECT_KEY"), prefix)
    try:
        timeout = float(env.get("BACKUP_TIMEOUT_SECONDS", "") or 1800)
    except ValueError as exc:
        raise ConfigError("BACKUP_TIMEOUT_SECONDS 는 숫자여야 한다.") from exc

    if client is None:
        import boto3

        client = boto3.client("s3")

    with tempfile.TemporaryDirectory(dir=workdir) as tmp:
        path = Path(tmp) / "backup.dump"
        dump(url, path, timeout, run)
        size = upload(client, path, bucket, key)
    print(f"[backup] {size} bytes → s3://{bucket}/{key}", flush=True)
    return f"s3://{bucket}/{key}"


def main() -> int:
    try:
        run_backup(os.environ)
    except ConfigError as exc:
        print(f"[backup] ERROR: {exc}", file=sys.stderr, flush=True)
        return 2
    except BackupError as exc:
        print(f"[backup] ERROR: {exc}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
