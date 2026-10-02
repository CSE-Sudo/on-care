"""이미 저장된 채팅 사진의 메타데이터(EXIF 위치 등)를 털어 낸다. (#2829)

#2829 이전에는 채팅 사진을 받은 바이트 그대로 저장했다. 새 업로드는 이제 저장 전에
정리되지만, 그 전에 쌓인 파일에는 촬영 위치가 남아 있을 수 있다. 이 스크립트는
채팅 메시지가 가리키는 사진을 하나씩 읽어 업로드와 **같은 정리 함수**
(`chat_image_storage.save` → `image_sanitize.sanitize`)로 다시 쓰고, 메시지의
`attachment_file_size` 를 새 크기로 고친다. 파일 이름(식별자)과 형식은 그대로라
대화·내려받기 경로는 바뀌지 않는다.

기본은 **건수만 세는 점검**이다. 실제로 쓰려면 `--apply` 를 붙인다.

    python -m scripts.sanitize_chat_images          # 점검
    python -m scripts.sanitize_chat_images --apply  # 다시 쓰기

데모 시드 첨부(#2788)는 건너뛴다 — 서버가 뜰 때마다 앱 번들과 같은 바이트로 다시
쓰는 파일이다. 읽을 수 없는 파일은 지우지 않고 목록으로만 알린다. 운영 반영 시점은
배포 담당과 맞춘다.
"""
from __future__ import annotations

import argparse
import sys

from sqlalchemy import select

from app.db.seed_member_data import _CHAT_FILES
from app.db.session import SessionLocal
from app.models.models import ChatMessage
from app.services import chat_image_storage


def _seed_file_ids() -> set[str]:
    return {f.file_id for f in _CHAT_FILES.values() if f.kind == "image"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="점검만 하지 않고 파일을 다시 쓴다",
    )
    args = parser.parse_args(argv)

    skip = _seed_file_ids()
    db = SessionLocal()
    rewritten = missing = unreadable = skipped = 0
    try:
        rows = db.scalars(
            select(ChatMessage).where(
                ChatMessage.attachment_type == "image",
                ChatMessage.attachment_file_id.is_not(None),
            )
        ).all()
        for message in rows:
            file_id = message.attachment_file_id or ""
            if file_id in skip:
                skipped += 1
                continue
            # 로컬 디스크든 S3 든 저장소가 정한 자리에서 읽는다(#2817).
            try:
                opened, _ = chat_image_storage.open_image(file_id)
            except FileNotFoundError:
                missing += 1
                continue
            raw = opened.read_all()
            if not args.apply:
                rewritten += 1
                continue
            try:
                stored = chat_image_storage.save(raw, file_id=file_id)
            except chat_image_storage.UnsupportedImage:
                unreadable += 1
                print(f"읽을 수 없는 파일(그대로 둠): {file_id}", file=sys.stderr)
                continue
            message.attachment_file_size = stored.size
            rewritten += 1
        if args.apply:
            db.commit()
    finally:
        db.close()

    verb = "다시 씀" if args.apply else "다시 쓸 대상"
    print(
        f"{verb} {rewritten}건 · 파일 없음 {missing}건 · 읽을 수 없음 {unreadable}건 · "
        f"시드 건너뜀 {skipped}건"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
