"""보존 기한이 지난 감사 로그·읽은 알림을 한 번 정리한다. (#3144)

백엔드는 기동 때와 그 뒤 하루마다 같은 정리를 스스로 돈다(`app/services/retention.py`).
이 명령은 그 정리를 지금 바로 한 번 돌릴 때 쓴다 — 보존 기한 설정을 바꾼 직후, 서버가
오래 꺼져 있다 다시 뜰 때, 외부 스케줄러에서 같은 이미지로 돌릴 때.

    python -m scripts.purge_retention

`DATABASE_URL` 이 가리키는 DB 에 그대로 적용된다. 지우는 대상은 서버의 정기 정리와 같다.

* 감사 로그: 접속 기록은 `AUDIT_RETENTION_DAYS`, 건강정보 열람·공유 동의·탈퇴 기록은
  `AUDIT_SENSITIVE_RETENTION_DAYS` 가 지난 것.
* 알림: 읽은 알림 중 만들어진 지 90일이 지난 것(미확인 알림은 남긴다).

무엇이 지워질지 먼저 보려면 알림은 `python -m scripts.purge_notifications --dry-run` 을 쓴다.

서버가 이미 정리 중이면(같은 DB 의 다른 인스턴스) 건너뛰고 0 으로 끝난다. 한 단계라도
실패하면 1 로 끝나 스케줄러·작업 기록에 실패로 남는다.
"""
from __future__ import annotations

import argparse
import sys

from app.services import retention


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)

    report = retention.run_purge()
    if report.skipped:
        print("다른 인스턴스가 정리 중이라 건너뛰었습니다.")
        return 0
    for name, count in report.removed.items():
        print(f"{name}: {count}건 지움")
    if report.failed:
        print(f"실패: {', '.join(report.failed)}", file=sys.stderr)
        return 1
    print(f"완료 — 모두 {report.total}건")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
