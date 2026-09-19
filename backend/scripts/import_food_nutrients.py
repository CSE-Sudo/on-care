"""공공 식품영양성분 표준데이터 → `app/data/food_nutrients_public.csv` 생성.

원본(2026-08-28 기준 행 수):
  음식          19,617행  K-FIND 식품영양성분 DB → "음식 DB"
  가공식품      316,734행  K-FIND 식품영양성분 DB → "가공식품 DB"
  원재료성식품    3,704행  공공데이터포털 전국통합식품영양성분정보(원재료성식품)표준데이터

  K-FIND  https://various.foodsafetykorea.go.kr/nutrient/general/down/historyList.do
          "최신 DB 다운로드" 표에서 받는다(엑셀, 활용정보 입력 후). 원재료성식품은
          여기에 파일이 없다.
  공공데이터포털 https://www.data.go.kr/data/15100065/standard.do
          "활용 정보 → 파일 다운로드 → CSV".

받은 파일은 `backend/data/raw/` 에 **이름을 바꾸지 않고** 넣는다. 데이터셋마다
`{이름}.csv` → `{이름}.xlsx` → K-FIND 이름(`20260828_가공식품DB_316734건.xlsx`) 중
가장 최근 것 순서로 찾는다. 엑셀은 표준 라이브러리로 읽는다(추가 설치 없음).

사용법:
    python -m scripts.import_food_nutrients            # data/raw 전체
    python -m scripts.import_food_nutrients --only 음식
    python -m scripts.import_food_nutrients --raw-dir C:/경로/raw

원본(총 약 220MB)은 저장소에 넣지 않는다(`backend/data/raw/` 는 gitignore).
이 스크립트가 만든 집계본만 커밋해 CI·팀원·배포가 같은 데이터를 쓴다.

## 공공데이터포털의 음식·가공식품은 쓰지 않는다 (#2100)

공공데이터포털은 **파일 다운로드도 5만 건에서 자른다.** 가공식품(30만 행 넘음)을
거기서 받으면 앞 5만 행만 온다. 오류 없이 잘리므로, 정확히 5만 행인 파일은
잘린 것으로 보고 멈춘다(`_TRUNCATED_AT`). 음식은 5만 건이 안 돼 잘리지는 않지만,
K-FIND 쪽이 더 자주 갱신되고 두 데이터셋의 기준일을 맞출 수 있어 K-FIND 를 쓴다.

## 값은 100g 기준으로 넣는다

원본은 **전 데이터셋이 100% `100g`/`100ml` 기준**이다. 예전에는 이를
`식품중량` 으로 1인분 환산해서 넣었는데, 그게 문제의 근원이었다.

`식품중량` 은 "판매 포장 단위" 다 — 라지 피자 1,640g, 우유 1L 팩. 환산하면
피자 한 조각을 찍은 사용자에게 2,092kcal 이 붙는다. 실제로 1인분 환산 후
분산을 재보면 대표식품 안에서 3사분위가 중앙값의 3~5배까지 벌어졌다.

같은 항목을 **100g 기준 그대로** 재보면:

    피자    n=4692   232 / 252 / 274 kcal/100g   3Q÷중앙 1.09
    케이크  n= 657   271 / 307 / 352             3Q÷중앙 1.15
    김치찌개 n=  34    37 /  42 /  48             3Q÷중앙 1.16

분산은 음식이 아니라 포장 단위에 있었다. 100g 기준이면 프랜차이즈 4,692건도
서로 ±10% 안에서 일치한다. 그래서:

  - **환산하지 않는다** — 원본 형태 그대로라 손실도 추측도 없다
  - **프랜차이즈를 제외할 이유가 없다** — 포장 크기가 값에 영향을 주지 않는다
  - **`식품중량` 이 없는 데이터셋(원재료성식품)도 쓸 수 있다**

양(g)은 사진에서 인식기가 추정한다(`RecognizedFood.amount_g`). 밀도는 공공
DB 가, 양은 비전 모델이 대는 역할 분담이다.

## 대표식품 단위로 모으는 이유

원본 `식품명` 은 개별 상품이다(`피자_점보스테이크불갈비피자 (L)`). 인식기는
"피자" 라고만 하므로 상품명을 그대로 넣으면 질의가 수천 개 이름의 부분이 되어
매칭기 3단계에서 모호 판정 → 폴백한다. 데이터를 잔뜩 넣고도 흔한 음식이
안 잡힌다. `대표식품명` 이 인식기가 말하는 층이다.

## 대표식품 하나의 값은 원본 한 행에서 가져온다 (#2100)

같은 대표식품에 여러 행이 있고 편차가 있다. 예전에는 영양소마다 따로 중앙값을
냈는데, 그러면 열량은 A 제품, 탄수화물은 B 제품의 값이 한 행에 섞여 탄·단·지로
다시 셈한 열량이 표시 열량과 어긋났다(`감자튀김` 231kcal ↔ 4·4·9 합 131).

그래서 **실제 원본 한 행의 값 한 벌**을 쓴다. 고르는 기준은 "모든 영양소가
동시에 가장 전형적인 행"(메도이드)이다 — 영양소마다 그 대표식품 안의 중앙값에서
얼마나 떨어졌는지를 흩어진 정도(MAD)로 나눠 더하고, 합이 가장 작은 행을 쓴다.
평균을 쓰지 않는 이유와 같다 — 이상치에 끌려가지 않는다.

열량만 보고 고르면 그 제품의 나트륨·당류가 치우쳐 있을 수 있다. 실제 원본으로
재면 고른 행의 나트륨이 중앙값에서 평균 33% 떨어졌고, 메도이드는 11% 다.
빈 칸은 `_MISSING_PENALTY` 만큼 떨어진 것으로 친다 — 탄·단·지가 찬 행이 극단값이
아니면 그 행을 고른다.

고르기 전에 두 가지를 거른다.

- **레시피 계산값은 다른 값이 없을 때만 쓴다**(`데이터생성방법명` 이 `산출`).
  분석값과 다른 방법이 함께 있는 음식에서 중앙값 비율을 재면, 업체 표시값(수집)은
  분석값과 거의 같고(열량 ×0.96, 나트륨 ×0.95), 레시피 계산값은 체계적으로
  낮다(열량 ×0.76, 나트륨 ×0.71, 지방 ×0.65, 당류 ×0.58 · 313종). 업체 표시값은
  탄·단·지가 빠진 일이 많지만, 다 찬 계산값을 쓰는 것보다 낫다 — 빈 칸은 인식기
  값이 채운다(`enrich.apply_match` 의 "mixed").
- **이름과 영양값이 똑같은 행은 한 번만 센다.** 급식 계산값은 한 줄이 급식 종류마다
  복제돼 있다.

## 분석값이 한 건뿐이면 계산값과 맞춰 본다 (#2102)

분석·표시값이 한 건뿐인 대표식품이 192개 있다(나머지는 계산값). 한 건은 그 집의
레시피가 튀면 그대로 따라간다 — `오이무침` 은 부추를 넣은 한 건이 나트륨 1,070mg 이고
계산값 6건은 보정해도 333mg 안팎이다. 계산값이 `_LONE_MIN_CALCULATED` 건 이상이면
그 중앙값을 위의 체계적 차이(`_CALCULATED_BIAS`)로 보정해 비교하고, 열량이나 나트륨이
`_LONE_RATIO` 배 넘게 어긋나면 그 한 건 대신 계산값에서 고른다. 계산값이 몇 건 안 되면
중앙값도 흔들려 비교하지 않는다.

## 1회 섭취량은 1인분으로 정한 값만 쓴다 (#2102)

`serving_size_g` 는 인식기가 양을 주지 않았을 때만 쓰는 폴백이다(`enrich._grams`).
예전에는 `식품중량` 중앙값이었는데, 그 칸은 판매 포장(`우유(멸균)` 1,000g)이거나
여럿이 나눠 먹는 한 판(외식 분석 `해물파전` 1,330g)이거나 영양 기준량을 그대로 적은
것(2022년 외식 분석은 모두 `100g`)이라 1인분이 아닌 값이 섞였다. 이제:

- **가공식품**: 원본의 `1회 섭취참고량` 열. 식약처 「식품등의 표시기준」 [표3] 1회
  섭취참고량을 식품유형마다 적은 것이다. 판매 형태 그대로의 무게라 100g 당 값과 같은
  상태다. ml 은 위 밀도로 g 이 된다.
- **음식**: 1인분을 담아 만든 행의 무게(`_SERVING_ORIGINS`). 가정식 분석이 가정 1인분을
  조리해 잰 무게라 가장 가깝고, 다음이 성인 급식·외식 레시피 1인분이다. 조리된 음식의
  무게라 100g 당 값과 같은 상태다. 그런 행이 없으면 그 분류의 [표3] 값(배추김치 40g·
  밥 210g·떡 100g, `_DISH_REFERENCES`)을 쓴다.
- **원재료성식품**: 비운다. [표3] 도 자연상태 식품에는 값을 두지 않는다.

정할 수 없으면 비운다 — 틀린 1인분으로 환산한 값이 "공공 DB 근거" 로 표시되는 것보다
인식기 추정치를 두는 편이 낫다(`enrich` 의 폴백 원칙). `serving_basis` 열이 그 근거다.
"""
from __future__ import annotations

import argparse
import csv
import io
import pathlib
import re
import statistics
import sys
import zipfile
import xml.etree.ElementTree as ET

#: 음식 데이터셋에서 1인분으로 읽을 `식품기원명`(앞일수록 우선)과 `serving_basis` 표기.
#: 1인분을 담아 만든 행만 쓴다 — 외식 분석은 판매 메뉴 하나를 산 무게라 여럿이 나눠 먹는
#: 것(해물파전 1,330g·닭튀김 652g)이 섞이고, 프랜차이즈는 판매 단위(라지 피자 1,640g)다.
#: 학교 급식은 학년별 배식 기준이라 뺀다(중고등 `쌀밥` 450g). 무게가 있는 첫 층의
#: 중앙값을 쓴다.
_SERVING_ORIGINS: tuple[tuple[str, str], ...] = (
    ("가정식", "가정식 분석"),
    ("산업체급식", "산업체 급식"),
    ("외식(재료량", "외식 레시피"),
)

#: 1인분 행이 없는 음식에 쓰는 [표3] 1회 섭취참고량 — (음식 분류, 이름 패턴, g). 위에서부터
#: 처음 맞는 것. [표3] 은 가공식품 표시용이지만 "그 식품을 한 번에 먹는 양" 이라 같은
#: 식품이면 집에서 만든 것에도 맞는다(배추김치 40g, 떡 100g). 즉석조리식품의 국·탕·찌개·
#: 죽 값은 1인분 그릇이다. 이름만으로 식품유형을 가를 수 없는 것(음료·튀김·면)은 두지 않는다.
_DISH_REFERENCES: tuple[tuple[str, re.Pattern[str], float], ...] = (
    ("김치류", re.compile(r"물김치|동치미|나박김치"), 80.0),     # 물김치
    ("김치류", re.compile(r""), 40.0),                            # 배추김치·기타김치
    ("장아찌·절임류", re.compile(r"장아찌"), 15.0),              # 장류절임 중 장아찌
    ("장아찌·절임류", re.compile(r""), 25.0),                     # 그밖의 절임식품
    ("밥류", re.compile(r"(?<!덮)밥$"), 210.0),                   # 즉석조리식품 밥
    ("죽 및 스프류", re.compile(r"스프"), 150.0),
    ("죽 및 스프류", re.compile(r""), 250.0),
    ("국 및 탕류", re.compile(r""), 250.0),
    ("찌개 및 전골류", re.compile(r""), 200.0),
    ("면 및 만두류", re.compile(r"만두"), 150.0),
    ("빵 및 과자류", re.compile(r"떡|송편|절편|인절미|백설기|경단|증편|기피편|부꾸미|약식"), 100.0),
    ("빵 및 과자류", re.compile(r"빵|바게트|치아바타|번$|스콘|케이크|타르트|토스트|와플|크로플|파이|프레즐"), 70.0),
    ("빵 및 과자류", re.compile(r"과자|쿠키|비스킷|크래커|웨이퍼|약과|유과|산자|매작과|다식|마카롱|다쿠아즈"), 30.0),
)

# "300g", "350ml", "1000m"(ml 절단), "201.7"(무단위) 를 모두 받는다.
_WEIGHT = re.compile(r"^\s*([\d.]+)\s*([a-zA-Z]*)")

# 단위 → 그램 환산 계수. ml·L 은 밀도 1.0 을 가정한다 — 이 데이터의 액체는
# 국·찌개 국물과 음료라 대부분 물이고(오차 수 %), 제외하면 김치찌개처럼
# 100ml 기준으로 등록된 한식이 1회 섭취량 힌트를 통째로 잃는다.
# "1000m" 은 원본에 실재하는 ml 절단 표기다(65건).
_UNIT_TO_G = {"": 1.0, "g": 1.0, "kg": 1000.0, "ml": 1.0, "m": 1.0, "l": 1000.0}

_SOURCES = ("음식", "가공식품", "원재료성식품")

_OUT_COLUMNS = [
    "name",
    "category",
    "serving_size_g",
    "calories",
    "sodium_mg",
    "sugar_g",
    "carbs_g",
    "protein_g",
    "fat_g",
    "sample_count",
    "source_dataset",
    "method",
    "serving_basis",
]


#: 집계가 읽는 열. 원본은 150여 열이라 이것만 남겨야 가공식품 30만 행이
#: 메모리에 들어간다.
_USED_COLUMNS = (
    "식품명",
    "영양성분함량기준량",
    "대표식품명",
    "식품기원명",
    "데이터생성방법명",
    "식품대분류명",
    "식품소분류명",
    "식품중량",
    "1회 섭취참고량",
    "에너지(kcal)",
    "나트륨(mg)",
    "당류(g)",
    "탄수화물(g)",
    "단백질(g)",
    "지방(g)",
)

#: 공공데이터포털이 다운로드를 자르는 행 수. 이 수와 정확히 같으면 잘린 파일이다.
_TRUNCATED_AT = 50_000

_KFIND_URL = "https://various.foodsafetykorea.go.kr/nutrient/general/down/historyList.do"

_XLSX_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_XLSX_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"


def _project(row: dict[str, str]) -> dict[str, str]:
    return {c: row.get(c) or "" for c in _USED_COLUMNS}


def _read_csv(path: pathlib.Path) -> list[dict[str, str]]:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "cp949", "utf-8"):
        try:
            text = raw.decode(encoding)
        except UnicodeDecodeError:
            continue
        return [_project(r) for r in csv.DictReader(io.StringIO(text))]
    raise ValueError(f"인코딩을 판별하지 못했습니다: {path}")


def _xlsx_column(ref: str) -> int:
    """`AB12` → 27. 셀 주소의 열 부분만 본다."""
    n = 0
    for ch in re.match(r"[A-Z]+", ref).group(0):
        n = n * 26 + ord(ch) - 64
    return n - 1


def _xlsx_rows(path: pathlib.Path):
    """첫 시트의 행을 값 목록으로 하나씩 낸다. 빈 셀은 ""."""
    with zipfile.ZipFile(path) as z:
        workbook = ET.fromstring(z.read("xl/workbook.xml"))
        rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        targets = {r.get("Id"): r.get("Target") for r in rels}
        first = next(workbook.iter(_XLSX_NS + "sheet"))
        target = targets[first.get(_XLSX_REL + "id")].lstrip("/")
        sheet = target if target.startswith("xl/") else f"xl/{target}"

        shared: list[str] = []
        if "xl/sharedStrings.xml" in z.namelist():
            for _, el in ET.iterparse(z.open("xl/sharedStrings.xml")):
                if el.tag == _XLSX_NS + "si":
                    shared.append("".join(t.text or "" for t in el.iter(_XLSX_NS + "t")))
                    el.clear()

        for _, el in ET.iterparse(z.open(sheet)):
            if el.tag != _XLSX_NS + "row":
                continue
            values: dict[int, str] = {}
            index = -1
            for cell in el.iter(_XLSX_NS + "c"):
                ref = cell.get("r")
                index = _xlsx_column(ref) if ref else index + 1
                kind = cell.get("t")
                if kind == "inlineStr":
                    value = "".join(t.text or "" for t in cell.iter(_XLSX_NS + "t"))
                else:
                    v = cell.find(_XLSX_NS + "v")
                    value = "" if v is None or v.text is None else v.text
                    if kind == "s" and value:
                        value = shared[int(value)]
                values[index] = value
            el.clear()
            if values:
                yield [values.get(i, "") for i in range(max(values) + 1)]


def _read_xlsx(path: pathlib.Path) -> list[dict[str, str]]:
    rows = _xlsx_rows(path)
    header = next(rows, [])
    return [_project(dict(zip(header, r))) for r in rows]


def _read(path: pathlib.Path) -> list[dict[str, str]]:
    rows = _read_xlsx(path) if path.suffix.lower() == ".xlsx" else _read_csv(path)
    if len(rows) == _TRUNCATED_AT:
        raise SystemExit(
            f"{path.name}: 정확히 {_TRUNCATED_AT:,}행이다 — 공공데이터포털 다운로드에서 "
            f"잘린 파일로 보인다. 전체는 K-FIND 에서 받는다: {_KFIND_URL}"
        )
    return rows


def _find_source(raw_dir: pathlib.Path, dataset: str) -> pathlib.Path | None:
    """데이터셋 원본 파일. 직접 이름 붙인 것이 우선, 없으면 K-FIND 파일 중 최신."""
    for name in (f"{dataset}.csv", f"{dataset}.xlsx"):
        if (raw_dir / name).exists():
            return raw_dir / name
    # K-FIND 는 `20260828_가공식품DB_316734건.xlsx` 로 준다. 날짜가 앞에 있어
    # 이름순 마지막이 최신이다.
    kfind = sorted(raw_dir.glob(f"*_{dataset}DB_*.xlsx"))
    return kfind[-1] if kfind else None


def _number(raw: str) -> float | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def _weight_g(raw: str) -> float | None:
    """`식품중량` → 그램 수. 1인분 힌트로만 쓴다.

    단위를 **명시적으로** 읽는다. 예전에는 앞 숫자만 취해 단위를 무시했는데,
    그러면 알 수 없는 단위가 조용히 그램으로 쓰인다. 모르는 단위는 None 이다.
    """
    match = _WEIGHT.match(raw or "")
    if not match:
        return None
    try:
        value = float(match.group(1))
    except ValueError:
        return None
    factor = _UNIT_TO_G.get(match.group(2).lower())
    if factor is None:
        return None
    grams = value * factor
    # 5kg 넘는 값은 대형 포장(선물세트 등)이라 1인분 힌트가 못 된다.
    return grams if 0 < grams <= 5000 else None


#: 대표 행을 고를 때 보는 영양소.
_NUTRIENT_COLUMNS = (
    "에너지(kcal)",
    "나트륨(mg)",
    "당류(g)",
    "탄수화물(g)",
    "단백질(g)",
    "지방(g)",
)

#: `데이터생성방법명` 의 믿을 만한 순서. 레시피로 계산한 값(산출)만 뒤로 미룬다 —
#: 분석값과 비교하면 업체 표시값(수집)은 거의 같고(열량 ×0.96) 계산값은 체계적으로
#: 낮다(×0.76). 분석과 수집은 같은 등급이다. 가공식품의 분석 행은 30만 행 중 735개뿐이라
#: 분석을 앞세우면 `카레` 가 고형 카레(425kcal·나트륨 4,059mg)로 뽑힌다.
#: 모르는 값은 수집과 같다.
_METHOD_RANK = {"분석": 0, "수집": 0, "산출": 1}

#: 빈 칸을 중앙값에서 MAD 몇 배만큼 떨어진 것으로 칠지. 3 이면 탄·단·지가 빈 행이
#: 원래 방식보다 19개 늘고, 20 부터는 늘지 않는다(그 위로는 전형성만 나빠진다).
_MISSING_PENALTY = 20.0

#: 레시피 계산값이 분석값보다 체계적으로 낮은 정도(위 설명의 313종 중앙값 비율).
#: 분석값이 한 건뿐일 때 계산값 중앙값을 이만큼 나눠 "분석했다면 나왔을 값" 으로 본다.
_CALCULATED_BIAS = {"에너지(kcal)": 0.76, "나트륨(mg)": 0.71}

#: 한 건뿐인 분석값을 계산값과 맞춰 볼 최소 계산값 수. 5 건 미만이면 계산값 중앙값도
#: 한두 레시피에 끌려가 비교의 기준이 못 된다. 분석값이 한 건뿐인 192종 중 29종이 든다 —
#: 급식 식단에 자주 오르는, 흔히 먹는 이름들이다.
_LONE_MIN_CALCULATED = 5

#: 보정한 계산값에서 몇 배 넘게 벗어나면 그 한 건을 믿지 않을지. 계산값이 5건 이상인
#: 101종에서 레시피끼리 갈리는 폭(3사분위÷중앙값)은 열량 1.22·나트륨 1.26(중앙값)이라,
#: 2 배는 레시피 차이로 설명되지 않는다.
_LONE_RATIO = 2.0

#: 비율만 보면 값이 아주 작을 때 잡음이 걸린다(`잡곡밥` 나트륨 3mg ↔ 1.4mg). 이 차이보다
#: 작으면 어긋난 것으로 치지 않는다(100g 당).
_LONE_FLOOR = {"에너지(kcal)": 20.0, "나트륨(mg)": 100.0}


def _rank(row: dict[str, str]) -> int:
    return _METHOD_RANK.get(row.get("데이터생성방법명", "").strip(), 1)


def _unique(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """이름과 영양값이 모두 같은 행은 하나만.

    급식 데이터는 같은 레시피 계산값 한 줄을 초등·중고등·산업체·외식 급식으로
    복제해 싣는다(`호떡` 147kcal 네 줄). 그대로 세면 복제된 값이 "전형" 이 된다.
    이름까지 보는 것은 라벨 값이 우연히 같은 서로 다른 제품(차 음료 0kcal 여러 개)을
    합치지 않으려는 것이다.
    """
    unique: dict[tuple[str, ...], dict[str, str]] = {}
    for r in rows:
        key = (r.get("식품명", "").strip(),) + tuple(
            str(_number(r.get(c, ""))) for c in _NUTRIENT_COLUMNS
        )
        unique.setdefault(key, r)
    return list(unique.values())


def _lone_is_atypical(row: dict[str, str], calculated: list[dict[str, str]]) -> bool:
    """한 건뿐인 분석·표시값이 같은 음식의 레시피 계산값들과 크게 어긋나는가."""
    if len(calculated) < _LONE_MIN_CALCULATED:
        return False
    for column, bias in _CALCULATED_BIAS.items():
        value = _number(row.get(column, ""))
        values = [v for r in calculated if (v := _number(r.get(column, ""))) is not None]
        if value is None or not values:
            continue
        expected = statistics.median(values) / bias
        if abs(value - expected) < _LONE_FLOOR[column]:
            continue
        if expected <= 0 or not 1 / _LONE_RATIO <= value / expected <= _LONE_RATIO:
            return True
    return False


def _representative(group: list[dict[str, str]]) -> dict[str, str] | None:
    """대표식품 하나의 값 한 벌을 낼 원본 행(메도이드). 열량이 있는 행이 없으면 None.

    영양소마다 |값 − 중앙값| ÷ 흩어진 정도를 더해 가장 작은 행. 흩어진 정도는
    MAD 인데, 값이 모두 같으면 0 이 되므로 중앙값의 5% 와 0.1 을 하한으로 둔다.
    합이 같으면 열량이 낮은 행(결정적으로 고르기 위해).
    """
    rows = [r for r in group if _number(r.get("에너지(kcal)", "")) is not None]
    if not rows:
        return None

    # 가장 믿을 만한 방법으로 만든 행만 남긴다. 레시피 계산값은 양념 나트륨이 빠지는
    # 일이 흔하다 — `라면` 은 분석값 270~491mg 인데 계산값은 58~128mg 이다.
    best = min(_rank(r) for r in rows)
    chosen = _unique([r for r in rows if _rank(r) == best])
    # 다만 분석·표시값이 한 건뿐이고 계산값이 충분하면, 그 한 건이 튀었는지 본다(#2102).
    if best == 0 and len(chosen) == 1:
        calculated = _unique([r for r in rows if _rank(r) == 1])
        if _lone_is_atypical(chosen[0], calculated):
            chosen = calculated
    rows = chosen

    centre: dict[str, tuple[float, float]] = {}
    for column in _NUTRIENT_COLUMNS:
        values = [v for r in rows if (v := _number(r.get(column, ""))) is not None]
        if not values:
            continue
        median = statistics.median(values)
        mad = statistics.median([abs(v - median) for v in values])
        centre[column] = (median, max(mad, abs(median) * 0.05, 0.1))

    def distance(r: dict[str, str]) -> float:
        total = 0.0
        for column, (median, spread) in centre.items():
            v = _number(r.get(column, ""))
            total += _MISSING_PENALTY if v is None else abs(v - median) / spread
        return total

    return min(rows, key=lambda r: (distance(r), _number(r["에너지(kcal)"])))


#: 100ml 기준 값을 100g 기준으로 바꿀 밀도(g/ml). 값은 FAO/INFOODS Density Database
#: v2.0(2012)에 실린 같은 종류 항목들의 중앙값이다 — 괄호 안이 그 항목과 범위.
#: 위에서부터 처음 맞는 규칙을 쓴다(대표식품명, 없으면 식품대분류명).
#:
#: FAO 에 항목이 없는 식초·케첩·기타 소스·액젓·소주·막걸리·빙과는 환산하지 않는다 —
#: 근거 없는 밀도로 바꾸는 것보다 1.0 으로 두는 편이 오차를 설명할 수 있다.
_DENSITY_RULES: tuple[tuple[re.Pattern[str], float], ...] = (
    (re.compile(r"아이스크림|아이스밀크"), 0.56),   # Ice cream 8종 0.51~0.62
    (re.compile(r"마요네즈"), 0.91),               # Mayonnaise, traditional
    (re.compile(r"두유"), 1.05),                   # Soy drink·Soya+milk 1.05~1.08
    (re.compile(r"가공우유"), 1.06),               # Milk, chocolate milk 1.056
    (re.compile(r"발효유|요구르트|요거트"), 1.06),  # Yoghurt 6종 1.03~1.08
    (re.compile(r"우유"), 1.03),                   # Milk, liquid 6종 1.030~1.036
    (re.compile(r"주스|과.채음료|탄산음료"), 1.04),  # Fruit juice 1.04, Cola 1.04
    (re.compile(r"드레싱"), 1.10),                 # Salad dressing
    (re.compile(r"간장"), 1.12),                   # Sauce, soy
    (re.compile(r"시럽|물엿|올리고당|조청|당류가공품"), 1.32),  # Syrup 7종 1.18~1.40
    (re.compile(r"^잼$"), 1.38),                   # Jam 1.333~1.43
    (re.compile(r"증류주|위스키|고량주|보드카|브랜디|^럼$"), 0.95),  # Spirits, 40% alcohol
)
_DENSITY_BY_CATEGORY = {"식용유지류": 0.92}        # Oil 6종 0.914~0.927


def _density(row: dict[str, str]) -> float | None:
    name = (row.get("대표식품명") or "").strip()
    for pattern, density in _DENSITY_RULES:
        if pattern.search(name):
            return density
    return _DENSITY_BY_CATEGORY.get((row.get("식품대분류명") or "").strip())


def _per_100g(row: dict[str, str]) -> dict[str, str]:
    """100ml 기준 행을 100g 기준으로. 밀도를 모르거나 이미 100g 이면 그대로.

    앱은 **그램**을 곱한다(`amount_g`). 100ml 값을 100g 값으로 쓰면 식용유는 열량이
    8% 작고, 아이스크림은 절반 가까이 작고(공기가 들어 밀도 0.56), 간장은 나트륨이
    12% 크다.

    급식 계산값(`데이터생성방법명` 산출)의 100ml 는 환산하지 않는다. 3,140행 전부가
    음식 종류와 상관없이 100ml 로 적혀 있어(밥·나물까지) 실제 부피 기준이 아니다.
    """
    if (row.get("영양성분함량기준량") or "").strip().lower() != "100ml":
        return row
    if (row.get("데이터생성방법명") or "").strip() == "산출":
        return row
    density = _density(row)
    if density is None:
        return row
    out = dict(row)
    for column in _NUTRIENT_COLUMNS:
        v = _number(row.get(column, ""))
        if v is not None:
            out[column] = str(v / density)
    # 1회 섭취량 힌트도 같은 밀도로 그램이 된다(`_weight_g` 는 ml 를 g 로 읽는다).
    weight = _WEIGHT.match(row.get("식품중량") or "")
    if weight and weight.group(2).lower() in {"ml", "m", "l"}:
        grams = _weight_g(row["식품중량"])
        if grams is not None:
            out["식품중량"] = f"{grams * density}g"
    out["영양성분함량기준량"] = "100g"
    return out


#: 원재료성식품에서 이름만 불렀을 때 보통 뜻하지 않는 가공·부위 변형.
#: `브로콜리` 에는 `브로콜리_싹`·`브로콜리_잎_말린것`(271kcal)·`브로콜리_분말화한것` 이
#: 함께 모여 있다.
_RAW_VARIANT = re.compile(r"말린것|분말|가루|동결건조|농축|_잎|_줄기|_싹|_씨")

#: 생것이 기본형인 분류. 곡류·두류·견과·해조류는 말린 것이 기본형이라(`땅콩` 567kcal,
#: `팥` 335kcal, `김` 200kcal 대) 이 규칙을 쓰면 오히려 틀린다 — 그대로 메도이드로 고른다.
_FRESH_BY_DEFAULT = {"채소류", "과일류", "버섯류"}

#: 대표식품명이 일상어와 다른 것을 가리키는 묶음. 이름을 바꿔 일상어를 비워 두고,
#: 일상어는 매칭기 별칭(`nutrition.matcher.ALIASES`)이 맞는 행으로 보낸다.
_RENAMES: dict[tuple[str, str], str] = {
    # 건면 제품(350kcal/100g)이다. "파스타" 는 삶은 요리를 뜻한다.
    ("가공식품", "파스타"): "파스타 건면",
    ("원재료성식품", "파스타"): "파스타 건면",   # 같은 건면(365kcal) — 가공식품이 우선한다
    # 포장 가공품(너겟·스낵류)이다. "치킨" 은 치킨집 치킨을 뜻한다.
    ("가공식품", "치킨"): "치킨 가공품",
    # 프랜차이즈 커피 음료(라떼·프라푸치노)가 모인 묶음이다.
    ("음식", "커피"): "커피 음료",
    # 원두 추출액(에스프레소·아메리카노 용액)이다. "커피" 는 별칭으로 아메리카노에 보낸다.
    ("원재료성식품", "커피"): "커피 추출액",
}


#: 원재료성식품 한 묶음에 서로 다른 일상 음식이 함께 든 것. `호박` 에는 단호박(57kcal)·
#: 애호박(22)·늙은호박(38)·쥬키니가 모여 있어, 어느 것을 골라도 나머지는 틀린다.
#: (대표식품명, 식품명 두 번째 칸) → 따로 세울 이름. 식품명은 `호박_단호박_생것` 꼴이다.
_RAW_SPLITS: dict[tuple[str, str], str] = {
    ("호박", "단호박"): "단호박",
    ("호박", "애호박"): "애호박",
    ("호박", "늙은호박"): "늙은호박",
    ("호박", "쥬키니"): "쥬키니",
    ("토마토", "방울토마토"): "방울토마토",
}


def _group_key(row: dict[str, str], dataset: str) -> tuple[str, str]:
    """(묶을 이름, 그 묶음의 기본형 식품명). 기본형은 `{…}_생것` 이다."""
    rep = (row.get("대표식품명") or "").strip()
    if dataset == "원재료성식품":
        parts = [p.strip() for p in (row.get("식품명") or "").split("_")]
        if len(parts) >= 3 and (split := _RAW_SPLITS.get((rep, parts[1]))):
            return split, f"{rep}_{parts[1]}_생것"
    return rep, f"{rep}_생것"


def _plain_rows(canonical_name: str, rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """원재료성식품에서 이름만 불렀을 때 뜻하는 행.

    국가표준식품성분표는 기본형을 `{대표식품명}_생것` 으로 적는다(`사과_생것`). 그런
    행이 있으면 그것만, 없으면 말린것·분말·잎·싹 같은 변형을 뺀 행을 본다.
    """
    canonical = [r for r in rows if (r.get("식품명") or "").strip() == canonical_name]
    if canonical:
        return canonical
    plain = [r for r in rows if not _RAW_VARIANT.search(r.get("식품명") or "")]
    return plain or rows


def _portion_g(row: dict[str, str]) -> float | None:
    """음식 행의 `식품중량` → 1인분 g. 영양 기준량을 그대로 적은 칸(`100g`)은 1인분이 아니다."""
    raw = (row.get("식품중량") or "").strip()
    if raw.lower() in {"100g", "100ml"}:
        return None
    return _weight_g(raw)


def _dish_serving(
    group: list[dict[str, str]], name: str, category: str
) -> tuple[float | None, str]:
    """음식 1인분: 1인분을 담아 만든 행의 무게 중앙값(`_SERVING_ORIGINS` 순서), 없으면
    그 분류의 [표3] 값(`_DISH_REFERENCES`)."""
    for prefix, basis in _SERVING_ORIGINS:
        weights = [
            w
            for r in group
            if (r.get("식품기원명") or "").startswith(prefix)
            and (w := _portion_g(r)) is not None
        ]
        if weights:
            return statistics.median(weights), basis
    for kind, pattern, grams in _DISH_REFERENCES:
        if category == kind and pattern.search(name):
            return grams, "표시기준 1회 섭취참고량"
    return None, ""


#: `1회 섭취참고량` 한 칸의 값. "200ml", "5g(ml)", "250ml(g)", "100g(ml)" 꼴이다.
#: 괄호는 "g 이나 ml" 라는 뜻이라 앞의 숫자를 g 로 읽는다(국·음료처럼 물이 대부분인 것).
_REFERENCE = re.compile(r"^([\d.]+)(g|ml)(\((?:g|ml)\))?$")


def _reference_detail(raw: str, row: dict[str, str]) -> str | None:
    """식품유형 하나에 세부가 여럿이면 원본은 한 칸에 모두 적는다 — 그 행의 세부를 고른다.

    원본으로 가를 수 없는 것(유탕면의 봉지 120g·용기 80g)은 None — 추측하지 않는다.
    """
    kind = (row.get("식품소분류명") or "").strip()
    name = f"{row.get('대표식품명') or ''} {row.get('식품명') or ''}"
    if raw.startswith("생·숙면"):
        if kind in {"생면", "숙면"}:
            return "200g"
        if kind == "건면":
            return "30g" if "당면" in name else "100g"
        return None
    if raw.startswith("드레싱"):
        if "드레싱" in name:
            return "15g"
        return "165g" if "덮밥" in name else None
    if raw.startswith("액상"):
        if re.search(r"호상|떠먹", name):
            return "100g"
        return "150ml" if re.search(r"액상|마시는|드링크", name) else None
    if raw.startswith("레토르트"):
        if re.search(r"레토르트|3분", name):
            return "200g"
        return "25g" if re.search(r"분말|가루|고형", name) else None
    return None


#: [표3] 이 1회 섭취참고량을 **타거나 우려 마신 양**으로 정한 식품유형. 원본의 100g 당
#: 값은 판매 형태(분말·청·원액)라 곱하면 조리 상태가 어긋난다 — 고형차는 380kcal/100g
#: 인데 1회 섭취참고량은 200ml 다.
_PREPARED_REFERENCE_KINDS = {
    "침출차",
    "고형차",
    "액상차",
    "음료베이스",
    "농축과·채즙(또는 과·채분)",
}


def _reference_g(row: dict[str, str]) -> float | None:
    """가공식품 행의 1회 섭취참고량(식약처 「식품등의 표시기준」 [표3]) → g."""
    if (row.get("식품소분류명") or "").strip() in _PREPARED_REFERENCE_KINDS:
        return None
    raw = re.sub(r"\s+", "", row.get("1회 섭취참고량") or "")
    if not raw:
        return None
    match = _REFERENCE.match(raw)
    if match is None:
        detail = _reference_detail(raw, row)
        match = _REFERENCE.match(detail) if detail else None
    if match is None:
        # "1식"(도시락 한 개)처럼 무게가 아닌 단위다.
        return None
    value = float(match.group(1))
    if match.group(2) == "ml" and not match.group(3):
        value *= _density(row) or 1.0
    return value


def _serving(
    group: list[dict[str, str]], dataset: str, row: dict[str, str]
) -> tuple[float | None, str]:
    """(1회 섭취량 g, 그 근거). 정할 수 없으면 (None, ""). `row` 는 값을 가져온 대표 행이다."""
    if dataset == "음식":
        category = _mode([(r.get("식품대분류명") or "").strip() for r in group])
        return _dish_serving(group, (row.get("대표식품명") or "").strip(), category)
    if dataset == "가공식품":
        # 값을 가져온 행의 것을 쓴다. 한 대표식품에 식품유형이 섞이면(`기타 라면` 은 건조
        # 유탕면과 숙면) 다른 행의 1회 섭취참고량은 다른 상태의 무게다.
        value = _reference_g(row)
        return (value, "표시기준 1회 섭취참고량") if value is not None else (None, "")
    # 원재료성식품: [표3] 도 자연상태 식품에는 1회 섭취참고량을 두지 않는다.
    return None, ""


def aggregate(rows: list[dict[str, str]], dataset: str) -> list[dict[str, object]]:
    """원본 행 → 대표식품 단위 **100g 기준** 집계."""
    groups: dict[str, list[dict[str, str]]] = {}
    canonical: dict[str, str] = {}
    for row in rows:
        key, plain = _group_key(row, dataset)
        if key:
            groups.setdefault(key, []).append(_per_100g(row))
            canonical.setdefault(key, plain)

    out: list[dict[str, object]] = []
    for source_name, group in sorted(groups.items()):
        name = _RENAMES.get((dataset, source_name), source_name)
        fresh = _mode([(r.get("식품대분류명") or "").strip() for r in group]) in _FRESH_BY_DEFAULT
        candidates = (
            _plain_rows(canonical[source_name], group)
            if dataset == "원재료성식품" and fresh
            else group
        )
        row = _representative(candidates)
        if row is None:
            # 열량조차 없으면 보정 값으로 쓸 수 없다.
            continue

        def value(column: str) -> float | None:
            return _number(row.get(column, ""))

        # 1인분 힌트: 인식기가 양을 못 줬을 때만 쓰는 폴백. 근거가 없으면 비운다.
        serving, serving_basis = _serving(group, dataset, row)

        out.append(
            {
                "name": name,
                "category": _mode([(r.get("식품대분류명") or "").strip() for r in group]),
                "serving_size_g": None if serving is None else round(serving, 1),
                "calories": round(value("에너지(kcal)"), 1),
                "sodium_mg": _round_or_none(value("나트륨(mg)"), 1),
                "sugar_g": _round_or_none(value("당류(g)"), 2),
                "carbs_g": _round_or_none(value("탄수화물(g)"), 2),
                "protein_g": _round_or_none(value("단백질(g)"), 2),
                "fat_g": _round_or_none(value("지방(g)"), 2),
                "sample_count": len(group),
                "source_dataset": dataset,
                "method": (row.get("데이터생성방법명") or "").strip(),
                "serving_basis": serving_basis,
            }
        )
    return out


def _mode(values: list[str]) -> str:
    values = [v for v in values if v]
    return statistics.mode(values) if values else ""


def _round_or_none(value: float | None, digits: int) -> float | None:
    return None if value is None else round(value, digits)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--raw-dir", type=pathlib.Path, default=pathlib.Path("data/raw")
    )
    parser.add_argument(
        "--out",
        type=pathlib.Path,
        default=pathlib.Path("app/data/food_nutrients_public.csv"),
    )
    parser.add_argument("--only", choices=_SOURCES, help="한 데이터셋만 처리")
    args = parser.parse_args(argv)

    wanted = (args.only,) if args.only else _SOURCES
    merged: dict[str, dict[str, object]] = {}
    for dataset in wanted:
        path = _find_source(args.raw_dir, dataset)
        if path is None:
            print(f"건너뜀(파일 없음): {args.raw_dir / dataset}.*", file=sys.stderr)
            continue
        rows = _read(path)
        aggregated = aggregate(rows, dataset)
        # 앞선 데이터셋이 우선한다(음식 > 가공식품 > 원재료성식품). 사용자가
        # 사진으로 찍는 것에 가까운 순서다.
        added = 0
        for item in aggregated:
            if item["name"] not in merged:
                merged[item["name"]] = item
                added += 1
        print(
            f"{dataset}({path.name}): {len(rows)}행 → 대표식품 "
            f"{len(aggregated)}종 (신규 {added})"
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8", newline="") as fh:
        # 저장소의 집계본은 LF 다. csv 기본값(CRLF)으로 쓰면 줄마다 diff 가 난다.
        writer = csv.DictWriter(fh, fieldnames=_OUT_COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(merged[name] for name in sorted(merged))

    print(f"합계 {len(merged)}종 → {args.out}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
