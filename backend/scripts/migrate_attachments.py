"""로컬 디스크의 채팅 첨부를 운영 저장소(S3)로 옮긴다. (#2817)

첨부 바이트를 컨테이너 디스크에 두던 때 쌓인 파일(`CHAT_IMAGE_STORAGE_DIR`·
`REPORT_PDF_STORAGE_DIR`)을 `ATTACHMENT_S3_BUCKET` 으로 복사한다. 원본은 지우지
않는다 — 전환이 끝나고 확인한 뒤 사람이 지운다.

**DB 가 가리키는 파일만 옮긴다.** 메시지 행이 없는 파일(탈퇴로 행이 사라진 고아,
업로드 도중 실패한 잔여물)은 열 수 있는 경로가 없는 사본이라 운영 저장소로 가져가지
않는다. 반대로 DB 에는 있는데 로컬에 없는 파일은 `missing` 으로 보고한다 — 이미
재배포로 잃은 파일이다.

같은 이름이 대상에 이미 있으면 건너뛴다. 여러 번 돌려도 같다.

    python -m scripts.migrate_attachments --dry-run   # 무엇을 옮길지 본다
    python -m scripts.migrate_attachments             # 실제로 복사한다

`DATABASE_URL` 과 S3 설정(`ATTACHMENT_S3_BUCKET` 등)이 운영 값이어야 한다.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field

from app.services import attachment_store

_LOCAL_NAME = re.compile(r"^(?P<file_id>[0-9a-f]{32})\.(?P<ext>jpg|png|webp|pdf)$")
_MEDIA_TYPES = {
    "jpg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "pdf": "application/pdf",
}
#: DB 의 `attachment_type` → 저장소 종류.
_KIND_OF = {"image": "chat-images", "pdf": "report-pdfs"}


@dataclass
class Report:
    copied: list[str] = field(default_factory=list)
    skipped_existing: list[str] = field(default_factory=list)
    skipped_orphan: list[str] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    failed: list[str] = field(default_factory=list)


def migrate(
    sources: dict[str, attachment_store.LocalDiskStore],
    targets: dict[str, attachment_store.BlobStore],
    referenced: set[tuple[str, str]],
    *,
    dry_run: bool,
) -> Report:
    """[referenced] 의 (종류, file_id) 만 [sources] 에서 [targets] 로 복사한다."""
    report = Report()
    found: set[tuple[str, str]] = set()
    for kind, source in sources.items():
        target = targets[kind]
        for name in source.names():
            match = _LOCAL_NAME.fullmatch(name)
            if match is None:
                continue
            key = (kind, match["file_id"])
            label = f"{kind}/{name}"
            if key not in referenced:
                report.skipped_orphan.append(label)
                continue
            found.add(key)
            if target.exists(name):
                report.skipped_existing.append(label)
                continue
            if dry_run:
                report.copied.append(label)
                continue
            try:
                data = source.open(name).read_all()
                target.put(name, data, content_type=_MEDIA_TYPES[match["ext"]])
            except OSError:
                report.failed.append(label)
                continue
            report.copied.append(label)
    report.missing = sorted(f"{kind}/{file_id}" for kind, file_id in referenced - found)
    return report


def _referenced() -> set[tuple[str, str]]:
    from sqlalchemy import select

    from app.db.session import SessionLocal
    from app.models.models import ChatMessage

    db = SessionLocal()
    try:
        rows = db.execute(
            select(ChatMessage.attachment_type, ChatMessage.attachment_file_id).where(
                ChatMessage.attachment_file_id.is_not(None),
                ChatMessage.attachment_type.in_(tuple(_KIND_OF)),
            )
        ).all()
    finally:
        db.close()
    return {(_KIND_OF[kind], file_id) for kind, file_id in rows}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="복사하지 않고 대상만 출력한다.")
    args = parser.parse_args()

    from app.core.config import get_settings

    settings = get_settings()
    try:
        backend = attachment_store.resolve_backend(settings)
    except RuntimeError as exc:
        print(f"[migrate-attachments] {exc}", file=sys.stderr)
        return 2
    if backend != "s3":
        print(
            "[migrate-attachments] 운영 저장소가 설정되지 않았습니다 — "
            "ATTACHMENT_S3_BUCKET 을 지정하세요.",
            file=sys.stderr,
        )
        return 2

    kinds = ("chat-images", "report-pdfs")
    report = migrate(
        {kind: attachment_store.local_store(kind, settings) for kind in kinds},
        {kind: attachment_store.get_store(kind, settings) for kind in kinds},
        _referenced(),
        dry_run=args.dry_run,
    )
    verb = "옮길" if args.dry_run else "옮긴"
    print(f"[migrate-attachments] {verb} 파일 {len(report.copied)}개")
    for label in report.copied:
        print(f"  + {label}")
    print(f"[migrate-attachments] 이미 있어 건너뜀 {len(report.skipped_existing)}개")
    print(f"[migrate-attachments] DB 에 없는 고아 파일 {len(report.skipped_orphan)}개(옮기지 않음)")
    if report.missing:
        print(f"[migrate-attachments] DB 에는 있는데 로컬에 없는 파일 {len(report.missing)}개:")
        for label in report.missing:
            print(f"  ? {label}")
    if report.failed:
        print(f"[migrate-attachments] 실패 {len(report.failed)}개:", file=sys.stderr)
        for label in report.failed:
            print(f"  ! {label}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
