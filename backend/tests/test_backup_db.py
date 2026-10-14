"""운영 DB 백업 작업(`scripts/backup_db.py`) — 실패하면 운영 배포가 멈춘다. (#1552)

DB·S3 가 필요 없다. `pg_dump`·`pg_restore` 호출은 가짜 실행기로, S3 는 업로드만 흉내 낸다.

여기서 지키는 것:

1. SQLAlchemy 형식 `DATABASE_URL` 을 pg_dump 가 읽는 주소로 바꾼다.
2. 키는 백업 접두사 바로 아래 `.dump` 만 — 작업 역할의 쓰기 범위 밖으로 나가지 않는다.
3. pg_dump 실패·빈 파일·읽히지 않는 덤프·업로드 실패는 모두 실패(종료 코드 1)다.
4. 설정이 비면 덤프를 시작하지 않고 종료 코드 2.
"""
from __future__ import annotations

import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

from scripts import backup_db

ENV = {
    "DATABASE_URL": "postgresql+psycopg://u:p@ep-x.ap-southeast-1.aws.neon.tech/oncare?sslmode=require",
    "BACKUP_S3_BUCKET": "oncare-db-backups-test",
    "BACKUP_S3_PREFIX": "db",
    "BACKUP_OBJECT_KEY": "db/20261014T010203Z-0123456789ab.dump",
}


class FakeUploader:
    def __init__(self, fail: Exception | None = None) -> None:
        self.fail = fail
        self.uploaded: list[tuple[str, str, bytes]] = []

    def upload_file(self, filename: str, bucket: str, key: str) -> None:
        if self.fail is not None:
            raise self.fail
        self.uploaded.append((bucket, key, Path(filename).read_bytes()))


class FakeRun:
    """pg_dump 는 `--file=` 에 내용을 쓰고, pg_restore --list 는 목차를 낸다."""

    def __init__(self, *, dump_rc: int = 0, dump_bytes: bytes = b"PGDMP-fake", list_rc: int = 0) -> None:
        self.dump_rc = dump_rc
        self.dump_bytes = dump_bytes
        self.list_rc = list_rc
        self.calls: list[list[str]] = []

    def __call__(self, args: list[str], **kwargs):
        self.calls.append(args)
        if args[0] == "pg_dump":
            if self.dump_rc == -1:
                raise subprocess.TimeoutExpired(args, kwargs["timeout"])
            path = next(a for a in args if a.startswith("--file=")).removeprefix("--file=")
            if self.dump_rc == 0:
                Path(path).write_bytes(self.dump_bytes)
            return SimpleNamespace(returncode=self.dump_rc, stdout="", stderr="server version mismatch")
        if args[0] == "pg_restore":
            out = "; Archive created\n1; TABLE public users\n" if self.list_rc == 0 else ""
            return SimpleNamespace(returncode=self.list_rc, stdout=out, stderr="not an archive")
        raise AssertionError(args)


@pytest.mark.parametrize(
    ("given", "want"),
    [
        ("postgresql+psycopg://u:p@h/db", "postgresql://u:p@h/db"),
        ("postgres://u:p@h/db", "postgresql://u:p@h/db"),
        ("postgresql://u:p@h/db?sslmode=require", "postgresql://u:p@h/db?sslmode=require"),
    ],
)
def test_libpq_url(given: str, want: str) -> None:
    assert backup_db.libpq_url(given) == want


@pytest.mark.parametrize(
    "key",
    [
        "chat-attachments/x.dump",  # 다른 접두사(첨부 버킷 접두사)
        "db/x.sql",
        "db/../x.dump",
        "db/sub/x.dump",
        "db/.dump",
        "x.dump",
    ],
)
def test_object_key_stays_under_backup_prefix(key: str) -> None:
    with pytest.raises(backup_db.ConfigError):
        backup_db.object_key(key, "db")


def test_backup_dumps_checks_and_uploads(tmp_path: Path) -> None:
    run = FakeRun()
    uploader = FakeUploader()
    target = backup_db.run_backup(ENV, client=uploader, run=run, workdir=tmp_path)

    assert target == "s3://oncare-db-backups-test/db/20261014T010203Z-0123456789ab.dump"
    assert uploader.uploaded == [
        ("oncare-db-backups-test", "db/20261014T010203Z-0123456789ab.dump", b"PGDMP-fake")
    ]
    dump_args, list_args = run.calls
    assert dump_args[:2] == ["pg_dump", "--format=custom"]
    assert (
        "--dbname=postgresql://u:p@ep-x.ap-southeast-1.aws.neon.tech/oncare?sslmode=require" in dump_args
    )
    assert list_args[:2] == ["pg_restore", "--list"]
    # 임시 덤프는 남기지 않는다.
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize(
    "run",
    [
        FakeRun(dump_rc=1),
        FakeRun(dump_rc=-1),
        FakeRun(dump_bytes=b""),
        FakeRun(list_rc=1),
    ],
    ids=["pg_dump 실패", "pg_dump 시간 초과", "빈 덤프", "읽히지 않는 덤프"],
)
def test_dump_failures_stop_before_upload(run: FakeRun, tmp_path: Path) -> None:
    uploader = FakeUploader()
    with pytest.raises(backup_db.BackupError):
        backup_db.run_backup(ENV, client=uploader, run=run, workdir=tmp_path)
    assert uploader.uploaded == []


def test_upload_failure_is_a_backup_failure(tmp_path: Path) -> None:
    with pytest.raises(backup_db.BackupError, match="S3 업로드 실패"):
        backup_db.run_backup(
            ENV, client=FakeUploader(fail=RuntimeError("AccessDenied")), run=FakeRun(), workdir=tmp_path
        )


@pytest.mark.parametrize("missing", ["DATABASE_URL", "BACKUP_S3_BUCKET", "BACKUP_OBJECT_KEY"])
def test_missing_setting_is_config_error_and_dumps_nothing(missing: str, tmp_path: Path) -> None:
    run = FakeRun()
    env = {**ENV, missing: ""}
    with pytest.raises(backup_db.ConfigError):
        backup_db.run_backup(env, client=FakeUploader(), run=run, workdir=tmp_path)
    assert run.calls == []


def test_main_exit_codes(monkeypatch: pytest.MonkeyPatch) -> None:
    def fail_config(_env):
        raise backup_db.ConfigError("x")

    def fail_backup(_env):
        raise backup_db.BackupError("x")

    monkeypatch.setattr(backup_db, "run_backup", fail_config)
    assert backup_db.main() == 2
    monkeypatch.setattr(backup_db, "run_backup", fail_backup)
    assert backup_db.main() == 1
    monkeypatch.setattr(backup_db, "run_backup", lambda _env: "s3://b/k")
    assert backup_db.main() == 0
