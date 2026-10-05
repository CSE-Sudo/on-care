"""보존 기간이 지난 **읽은** 알림을 지운다. (#965)

알림은 식단·운동·일정 훅에서 계속 만들어지는데 지우는 경로가 없었다. 목록에
상한을 두어도(#965 의 페이지네이션) 테이블 자체는 계속 자란다.

지우는 대상은 `notification_service.expired_notifications` 가 고른다 —
**읽은 알림 중 만들어진 지 90일이 지난 것**뿐이다. 미확인 알림은 아무리 오래돼도
남긴다(사용자가 못 본 알림을 서버가 지우면 무엇이 사라졌는지 알 길이 없다).

기본 기준(90일)의 정리는 백엔드가 기동 때와 하루마다 스스로 돈다
(`app/services/retention.py`, #3144). 이 명령은 대상을 먼저 보거나(`--dry-run`), 기준을
바꾸거나, 한 사람만 정리할 때 쓴다.

    python -m scripts.purge_notifications --dry-run     # 대상만 본다
    python -m scripts.purge_notifications               # 실제로 지운다
    python -m scripts.purge_notifications --days 180    # 기준을 늘려서
    python -m scripts.purge_notifications --user u-123  # 한 사람만

`DATABASE_URL` 이 가리키는 DB 에 그대로 적용된다. 공유 DB 를 향한 채 실행하는
것이라면 `--dry-run` 으로 먼저 보고 하는 편이 낫다.
"""
from __future__ import annotations

import argparse
import sys

from app.db.session import SessionLocal
from app.services import notification_service


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--days",
        type=int,
        default=notification_service.READ_RETENTION_DAYS,
        help=f"읽은 알림 보존 기간(일). 기본 {notification_service.READ_RETENTION_DAYS}.",
    )
    parser.add_argument(
        "--user",
        default=None,
        help="이 사용자 것만 정리한다. 없으면 전체.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="지우지 않고 대상만 출력한다.",
    )
    args = parser.parse_args()

    db = SessionLocal()
    try:
        try:
            targets = notification_service.expired_notifications(
                db, days=args.days, user_id=args.user
            )
        except ValueError as exc:
            print(exc, file=sys.stderr)
            return 2

        cutoff = notification_service.retention_cutoff(args.days)
        scope = args.user or "전체 사용자"
        print(f"기준: {cutoff.isoformat()} 이전에 만들어진 읽은 알림 · 대상 {scope}")
        for row in targets:
            print(f"  {row.created_at.isoformat()}  {row.id}  {row.user_id}  {row.title}")

        if args.dry_run:
            print(f"dry-run — 지우지 않았습니다. 대상 {len(targets)}건")
            return 0

        # 고른 것을 그대로 지운다. 두 번 조회하면 그 사이에 읽음으로 바뀐 알림이
        # 위에 출력한 목록과 달라진다 — 출력과 삭제가 어긋나면 안 된다.
        for row in targets:
            db.delete(row)
        db.commit()
        print(f"지웠습니다: {len(targets)}건")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
