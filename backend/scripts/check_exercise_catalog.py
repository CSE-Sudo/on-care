"""공공 운동 MET 데이터 → `app/data/exercise_catalog_public.csv` 생성. (#1312)

원본(공공데이터포털):
  data/raw/보건소_모바일_헬스케어_운동.csv
      한국건강증진개발원 `보건소 모바일 헬스케어 운동`
      컬럼: 운동명, 운동설명, METS(단위체중당에너지소비량) — 376행

사용법:
    python -m scripts.import_exercise_catalog
    python -m scripts.import_exercise_catalog --src data/raw/내려받은파일.csv

## 원본을 저장소에 넣지 않는 이유 — 식단과 다른 점

식단 원본(식약처)은 용량 때문에 뺐지만, 이쪽은 **이용허락범위** 때문이다. 이
데이터의 공공저작물 유형은 **KOGL 제4유형(출처표시 · 상업적 이용금지 · 변경금지)**
이다. 값을 바꾸지 않고 그대로 옮기는 것이 전제이므로:

  - MET 값을 **가공하지 않는다.** 중앙값으로 모으거나 반올림하지 않는다
    (식단 임포트가 대표식품 중앙값을 취하는 것과 다른 점이다).
  - 원본 파일은 커밋하지 않는다. 받은 사람이 이 스크립트로 산출본을 만든다.
  - 출처를 남긴다 — 산출본의 `source` 열과 `app/data/exercise_catalog_seed.py`
    머리말이 그 자리다.

집계본도 커밋하지 않는다(`app/data/exercise_catalog_public.csv` 는 gitignore).
없으면 큐레이션 목록만으로 돌고, 이름 매칭율만 낮아진다.

## 운동 유형은 이름에서 짐작한다

원본에는 우리 집계 축(유산소/근력/스트레칭/기타)이 없다. 이름의 조각으로 접되,
모르면 `기타` 다 — 잘못된 유형으로 우겨 넣으면 주간 그래프의 버킷이 틀어진다.
유형을 못 정한 항목도 계수는 맞으므로 칼로리 계산에는 지장이 없다.
"""
from __future__ import annotations

import argparse
import csv
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_SRC = ROOT / "data" / "raw" / "보건소_모바일_헬스케어_운동.csv"
OUT = ROOT / "app" / "data" / "exercise_catalog_public.csv"

#: 원본 컬럼명 후보. 공공데이터 파일은 배포 회차마다 표기가 조금씩 다르다.
_NAME_KEYS = ("운동명", "운동 명", "name")
_MET_KEYS = ("METS", "METs", "MET", "단위체중당에너지소비량", "met")

#: 이름 조각 → 집계 유형. 위에서부터 먼저 걸리는 것을 쓴다.
_TYPE_HINTS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("stretching", ("스트레칭", "요가", "필라테스", "체조", "이완", "태극권")),
    (
        "strength",
        ("근력", "웨이트", "덤벨", "바벨", "머신", "스쿼트", "프레스", "리프트",
         "턱걸이", "팔굽혀", "윗몸", "플랭크", "런지", "케틀벨"),
    ),
    (
        "cardio",
        ("걷기", "달리기", "뛰기", "조깅", "러닝", "자전거", "사이클", "수영",
         "등산", "줄넘기", "에어로빅", "계단", "유산소", "로잉", "스피닝"),
    ),
)


def _type_of(name: str) -> str:
    for code, tokens in _TYPE_HINTS:
        if any(token in name for token in tokens):
            return code
    return "other"


def _pick(row: dict, keys: tuple[str, ...]) -> str:
    for key in keys:
        if key in row and (row[key] or "").strip():
            return row[key].strip()
    return ""


def _read(src: pathlib.Path) -> list[dict]:
    # 공공데이터포털 CSV 는 CP949 로 내려오는 일이 잦다. UTF-8 을 먼저 보고
    # 실패하면 CP949 로 되읽는다 — 인코딩 때문에 빈 결과를 내고 조용히
    # 끝나는 것이 가장 알아채기 어렵다.
    for encoding in ("utf-8-sig", "cp949"):
        try:
            with src.open(encoding=encoding, newline="") as fh:
                return list(csv.DictReader(fh))
        except UnicodeDecodeError:
            continue
    raise SystemExit(f"인코딩을 읽지 못했습니다(UTF-8/CP949 아님): {src}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", type=pathlib.Path, default=DEFAULT_SRC)
    args = parser.parse_args()

    if not args.src.exists():
        print(f"원본이 없습니다: {args.src}", file=sys.stderr)
        print(
            "공공데이터포털 '한국건강증진개발원_보건소 모바일 헬스케어 운동' 을 "
            "내려받아 위 경로에 두세요.",
            file=sys.stderr,
        )
        return 1

    seen: set[str] = set()
    rows: list[dict] = []
    for raw in _read(args.src):
        name = _pick(raw, _NAME_KEYS)
        met_text = _pick(raw, _MET_KEYS)
        if not name or not met_text:
            continue
        try:
            met = float(met_text)
        except ValueError:
            continue
        # 계수가 없거나 0 이면 칼로리가 0 이 된다 — 표에 있을 이유가 없다.
        if met <= 0 or name in seen:
            continue
        seen.add(name)
        rows.append(
            {
                "name": name,
                "type": _type_of(name),
                # 원본 값 그대로. 반올림·환산하지 않는다(변경금지).
                "met": met_text,
                "aliases": "",
                "source": "khpi",
            }
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh, fieldnames=["name", "type", "met", "aliases", "source"]
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"{len(rows)}종 → {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
