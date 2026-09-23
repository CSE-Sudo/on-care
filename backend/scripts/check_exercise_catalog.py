"""운동 종목 참조표 점검 — 무엇이 몇 건 적재되고 이름이 얼마나 붙는지 본다. (#1651)

예전 `import_exercise_catalog.py` 는 공공데이터 원본을 받아 유형 열을 붙이고 행을
걸러 낸 산출본(`app/data/exercise_catalog_public.csv`)을 만들었다. 그 가공이야말로
원본의 이용허락범위(**KOGL 제4유형** — 출처표시·상업적 이용금지·**변경금지**)에
걸리는 쪽이었다. 재배포 자체는 막지 않으므로 지금은 원본을 받은 **그대로**
`app/data/exercise_met_public.csv` 에 두고, 유형 매핑·이름 정규화는 적재 시점
(`app.db.init_db._seed_exercise_catalog`)의 코드로 붙인다.

그래서 이 스크립트는 더 이상 파일을 만들지 않는다. DB 없이 시드 행만 만들어 보고
무엇이 들어가는지 눈으로 확인한다 — 출처·유형 분포와, 회원이 실제로 적는 말이
얼마나 표에 붙는지(이름 매칭율)다. 매칭 실패율이 곧 기능 실패율이다(#1312).

사용법:
    cd backend && python -m scripts.check_exercise_catalog
    cd backend && python -m scripts.check_exercise_catalog --probe 러닝머신 계단오르기

출처: 한국건강증진개발원 `보건소 모바일 헬스케어 운동`(공공데이터포털
https://www.data.go.kr/data/15068730/fileData.do) · Compendium of Physical Activities.
"""
from __future__ import annotations

import argparse
import collections
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

#: 회원이 실제로 적을 법한 말. 붙어야 정상인 것들만 둔다 — 여기가 비면 이름
#: 해석이 유형 표 폴백으로 내려가 체중이 빠진 값이 적힌다.
PROBES = (
    "러닝머신", "걷기", "달리기", "자전거", "수영", "줄넘기", "등산", "계단오르기",
    "스쿼트", "데드리프트", "벤치프레스", "랫풀다운", "레그프레스", "플랭크",
    "요가", "필라테스", "스트레칭", "복싱", "배드민턴", "축구", "농구", "테니스",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--probe", nargs="*", default=None, help="이름 매칭을 시험할 말(기본: 내장 목록)"
    )
    args = parser.parse_args()

    from app.db.init_db import PUBLIC_EXERCISE_CSV, _exercise_catalog_seed_rows
    from app.services.exercise_catalog.matcher import normalize

    if not PUBLIC_EXERCISE_CSV.exists():
        print(f"공공데이터 원본이 없습니다: {PUBLIC_EXERCISE_CSV}", file=sys.stderr)
        return 1

    rows = _exercise_catalog_seed_rows()
    by_source = collections.Counter(row["source"] for row in rows)
    by_type = collections.Counter(row["type"] for row in rows)

    print(f"적재 대상 {len(rows)}종")
    print("  출처: " + ", ".join(f"{k} {v}" for k, v in by_source.most_common()))
    print("  유형: " + ", ".join(f"{k} {v}" for k, v in by_type.most_common()))

    index: dict[str, dict] = {}
    for row in rows:
        index[row["name_norm"]] = row
        for alias in row["aliases_norm"].split("|"):
            if alias:
                index.setdefault(alias, row)

    probes = tuple(args.probe) if args.probe else PROBES
    hit = 0
    print(f"\n이름 매칭 {len(probes)}건")
    for probe in probes:
        row = index.get(normalize(probe))
        if row is None:
            print(f"  ✗ {probe}")
            continue
        hit += 1
        print(f"  ✓ {probe} → {row['name']} ({row['type']}, {row['met']} MET)")
    print(f"\n매칭율 {hit}/{len(probes)} ({hit / len(probes) * 100:.0f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
