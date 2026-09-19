"""공공 식품영양성분 DB 큐레이션 시드.

국내에서 가장 자주 촬영되는 한식·외식·디저트 메뉴와 PT 회원 식단에 자주 나오는 음식을
사람이 골라, 이름·1회 섭취량·영양값의 근거를 줄마다 적은 것이다. 시드가 100g 기준으로
넣고, 이름이 같은 공공 표준 행보다 우선한다(`init_db._seed_food_nutrients`).

값 단위: serving_size_g=g, calories=kcal, sodium_mg=mg, sugar_g/carbs_g/protein_g/fat_g=g.

## 영양값의 근거 (#2096, #2100, #2102)

셋 중 하나다. 줄마다 `source` 가 그 출처다.

1. `from_public` — 그 이름의 공공 표준 행에서 100g 당 값을 가져온다. 공공 집계가
   분석값·업체 표시값 5건 이상에서 고른 값일 때만 쓴다(`scripts/import_food_nutrients`
   의 메도이드). 공공 집계를 다시 만들면 같이 따라간다.
2. `per_100g` — 원본 한 행의 100g 당 값을 그대로 적는다. 우선순위는
   - 농촌진흥청 국가표준식품성분표(원본에 `출처명` 이 농촌진흥청인 행). **조리 상태까지**
     맞춘다 — 삼겹살은 `구운것(팬)`, 밥은 `멥쌀밥`.
   - 성분표에 없는 요리는 식약처 음식 DB 의 분석값(가정식·외식 분석). 레시피 계산값은
     분석값보다 체계적으로 낮아(열량 ×0.76) 쓰지 않는다. 한 요리에 분석값이 여럿이면
     공공 집계와 같은 메도이드다.
   - 공공 DB 에 없는 PT 식단(오트밀·그릭 요거트·닭가슴살)은 USDA FoodData Central.
   식품코드는 K-FIND·공공데이터포털 원본의 `식품코드` 다.
3. 1인분 값 — 데모 메뉴(요거트 아이스크림 볼)만. 스텁 인식기와 `tests/test_diet.py` 의
   395kcal·탄단지 59/9/14 가 이 값에 기댄다.

국물 요리(갈비탕·설렁탕·삼계탕)의 분석값은 **소금 치기 전**이다. 식당에서도 간을 하지
않고 내며(원본의 외식 레시피도 `갈비탕_소금제외`), 식탁에서 치는 소금은 사진으로 알 수
없다.

## 1회 섭취량의 근거 (#2102)

`serving_size_g` 는 인식기가 양을 주지 않았을 때만 쓰는 폴백이다(`enrich._grams`).
줄마다 `serving_basis` 가 그 근거이고, **100g 당 값과 같은 조리 상태의 무게**다.

- 식약처 「식품등의 표시기준」 [표3] 1회 섭취참고량 — 밥 210g, 배추김치 40g, 우유·
  탄산음료 200ml, 커피 240ml, 빵류 70g 처럼 식품유형에 값이 있는 것. ml 는 공공 집계와
  같은 FAO 밀도로 g 이 된다.
- 식약처 음식 DB **가정식 분석**의 무게 — 가정 1인분을 조리해 잰 무게라 요리의 1인분에
  가장 가깝다. 삼겹살 200g 은 구운 뒤 무게다. 외식 분석은 판매 메뉴 하나(여럿이 나눠
  먹는 판 포함)를 산 무게라, 1인 메뉴인 돈가스에만 쓴다.
- USDA FoodData Central 의 1회 분량 — [표3] 이 값을 두지 않는 자연상태 과일과 오트밀.

근거가 없으면 비운다(맥주 — [표3] 은 주류에 1회 섭취참고량을 두지 않는다). 그러면 양을
모를 때 인식기 추정치를 그대로 둔다.
"""
from __future__ import annotations

# name, category, serving_size_g, serving_basis, 그리고 from_public 이거나 per_100g+source.
FOOD_NUTRIENTS: list[dict] = [
    # --- 밥·분식 ---
    {"name": "공기밥", "category": "밥류", "serving_size_g": 210,
     "serving_basis": "표시기준 1회 섭취참고량 — 즉석조리식품 밥 210g",
     "source": "농진청 성분표 `멥쌀밥_백미` R101-013000300-0000",
     "per_100g": {"calories": 146, "sodium_mg": 0, "sugar_g": 0.01,
                  "carbs_g": 31.71, "protein_g": 2.65, "fat_g": 0.33}},
    {"name": "비빔밥", "category": "밥류", "serving_size_g": 380,
     "serving_basis": "가정식 분석 `비빔밥` 3건 중앙값", "from_public": "비빔밥"},  # 음식 비빔밥 분석 7건
    {"name": "김밥", "category": "분식", "serving_size_g": 270,
     "serving_basis": "가정식 분석 `김밥` 9건 중앙값", "from_public": "김밥"},  # 음식 김밥 분석 13건
    {"name": "볶음밥", "category": "밥류", "serving_size_g": 280,
     "serving_basis": "가정식 분석 `볶음밥` 8건 중앙값", "from_public": "볶음밥"},  # 음식 볶음밥 분석 23건
    {"name": "떡볶이", "category": "분식", "serving_size_g": 190,
     "serving_basis": "가정식 분석 `떡볶이` 2건 중앙값", "from_public": "떡볶이"},  # 음식 떡볶이 분석 35건
    {"name": "순대", "category": "분식", "serving_size_g": 220,
     "serving_basis": "가정식 분석 `순대` 1건",
     "source": "농진청 성분표 `순대` P123-218020300-0083 (가공식품 분석 2019)",
     "per_100g": {"calories": 178, "sodium_mg": 506, "sugar_g": 1.09,
                  "carbs_g": 32.28, "protein_g": 3.18, "fat_g": 3.96}},
    # --- 국·찌개·탕 ---
    {"name": "김치찌개", "category": "국·찌개류", "serving_size_g": 270,
     "serving_basis": "가정식 분석 `김치찌개` 5건 중앙값", "from_public": "김치찌개"},  # 음식 김치찌개 분석 8건
    {"name": "된장찌개", "category": "국·찌개류", "serving_size_g": 300,
     "serving_basis": "가정식 분석 `된장찌개` 5건 중앙값", "from_public": "된장찌개"},  # 음식 된장찌개 분석 8건
    {"name": "순두부찌개", "category": "국·찌개류", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `순두부찌개` 1건", "from_public": "순두부찌개"},  # 음식 순두부찌개 분석 6건
    {"name": "미역국", "category": "국·찌개류", "serving_size_g": 400,
     "serving_basis": "가정식 분석 `미역국` 4건 중앙값", "from_public": "미역국"},  # 음식 미역국 분석 9건
    {"name": "된장국", "category": "국·찌개류", "serving_size_g": 400,
     "serving_basis": "가정식 분석 `된장국` 14건 중앙값", "from_public": "된장국"},  # 음식 된장국 분석 19건
    {"name": "갈비탕", "category": "탕류", "serving_size_g": 670,
     "serving_basis": "가정식 분석 `갈비탕` 1건(같은 행)",
     "source": "식약처 가정식 분석 `갈비탕` D105-199000000-0001 (2018, 소금 치기 전)",
     "per_100g": {"calories": 54, "sodium_mg": 199, "sugar_g": 0.11,
                  "carbs_g": 0.40, "protein_g": 8.51, "fat_g": 2.06}},
    {"name": "설렁탕", "category": "탕류", "serving_size_g": 500,
     "serving_basis": "가정식 분석 `설렁탕` 1건(같은 행)",
     "source": "식약처 가정식 분석 `설렁탕` D105-231000000-0001 (2018, 소금 치기 전)",
     "per_100g": {"calories": 24, "sodium_mg": 22, "sugar_g": 0,
                  "carbs_g": 0.36, "protein_g": 4.26, "fat_g": 0.58}},
    {"name": "삼계탕", "category": "탕류", "serving_size_g": 900,
     "serving_basis": "가정식 분석 `삼계탕` 1건(같은 행)",
     "source": "식약처 가정식 분석 `삼계탕` D105-228000000-0001 (2018, 소금 치기 전)",
     "per_100g": {"calories": 101, "sodium_mg": 82, "sugar_g": 0.45,
                  "carbs_g": 3.84, "protein_g": 10.68, "fat_g": 4.80}},
    # --- 면 ---
    {"name": "라면", "category": "면류", "serving_size_g": 550,
     "serving_basis": "가정식 분석 `라면` 3건 중앙값(조리 후)", "from_public": "라면"},  # 음식 라면 분석 17건
    # 공공 표준 `짜장면` 은 레시피 계산값뿐이다. 분석값은 옛 표기 `자장면` 에 있다.
    {"name": "짜장면", "category": "면류", "serving_size_g": 600,
     "serving_basis": "가정식 분석 `자장면` 1건",
     "source": "식약처 외식 분석 `자장면` D303-168000000-0001 (2012, 분석 3건의 메도이드)",
     "per_100g": {"calories": 123, "sodium_mg": 368, "sugar_g": 1.20,
                  "carbs_g": 20.56, "protein_g": 3.04, "fat_g": 3.13}},
    {"name": "짬뽕", "category": "면류", "serving_size_g": 800,
     "serving_basis": "가정식 분석 `짬뽕` 1건", "from_public": "짬뽕"},  # 음식 짬뽕 분석 7건
    # 공공 표준 `잔치국수` 는 레시피 계산값뿐이다. 분석값은 `국수` 묶음에 있다.
    {"name": "잔치국수", "category": "면류", "serving_size_g": 700,
     "serving_basis": "가정식 분석 `국수_잔치국수` 1건(같은 행)",
     "source": "식약처 가정식 분석 `국수_잔치국수` D103-142410000-0001 (2018)",
     "per_100g": {"calories": 44, "sodium_mg": 216, "sugar_g": 0.04,
                  "carbs_g": 8.05, "protein_g": 1.93, "fat_g": 0.49}},
    # 분석값이 가정식(2018)·외식(2022) 둘이다. 가정식은 나트륨이 161mg 으로 레시피 계산값
    # (`물냉면` 4종)을 체계적 차이만큼 보정한 값(약 510mg)의 3분의 1이라, 열량·나트륨이 모두
    # 그 2배 안에 드는 외식을 쓴다.
    {"name": "물냉면", "category": "면류", "serving_size_g": 700,
     "serving_basis": "가정식 분석 `냉면_물냉면` 1건",
     "source": "식약처 외식 분석 `냉면_물냉면` D303-144180000-0001 (2022)",
     "per_100g": {"calories": 66, "sodium_mg": 347, "sugar_g": 2.52,
                  "carbs_g": 13.12, "protein_g": 1.99, "fat_g": 0.63}},
    # --- 구이·볶음·고기 ---
    # 구운 뒤의 값과 구운 뒤의 무게다. 식약처 가정식 분석 `삼겹살구이`(467kcal·단백질
    # 22.56g·지방 41.69g)와 4% 안에서 맞는다. 공공 표준 `삼겹살구이` 는 고추장 양념 행이다.
    {"name": "삼겹살", "category": "구이류", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `삼겹살구이` 2건 중앙값(구운 뒤)",
     "source": "농진청 성분표 `돼지고기_삼겹살(삼겹살)_구운것(팬)` R209-014001251-0000",
     "per_100g": {"calories": 484, "sodium_mg": 80, "sugar_g": 0,
                  "carbs_g": 0.0, "protein_g": 22.78, "fat_g": 41.2}},
    # 공공 표준 `제육볶음` 은 레시피 계산값뿐이다.
    {"name": "제육볶음", "category": "볶음류", "serving_size_g": 250,
     "serving_basis": "가정식 분석 `돼지고기볶음(제육볶음)` 1건(같은 행)",
     "source": "식약처 가정식 분석 `돼지고기볶음(제육볶음)` D110-465000000-0001 (2018)",
     "per_100g": {"calories": 195, "sodium_mg": 501, "sugar_g": 0.38,
                  "carbs_g": 4.73, "protein_g": 12.15, "fat_g": 14.19}},
    {"name": "불고기", "category": "구이류", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `소불고기` 1건",
     "source": "농진청 성분표 `소불고기` D308-386000000-0001",
     "per_100g": {"calories": 186, "sodium_mg": 468, "sugar_g": 3.34,
                  "carbs_g": 6.73, "protein_g": 10.33, "fat_g": 13.10}},
    # "양념갈비" 는 소·돼지 어느 쪽인지 사진으로 가를 수 없다. `갈비구이` 분석 5건(소고기 3·
    # 돼지고기 1·왕갈비 1, 양념 2)의 메도이드가 그 가운데다.
    {"name": "양념갈비", "category": "구이류", "serving_size_g": 300,
     "serving_basis": "가정식 분석 `갈비구이_소고기` 1건", "from_public": "갈비구이"},  # 음식 갈비구이 분석 5건
    # --- 튀김·외식 ---
    {"name": "후라이드치킨", "category": "튀김류", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `닭튀김_날개` 1건", "from_public": "닭튀김"},  # 음식 `닭튀김` 분석 243건
    {"name": "양념치킨", "category": "튀김류", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `닭튀김_날개` 1건",
     "source": "식약처 외식 분석 `닭튀김_양념` D312-549160000-0001 (2015)",
     "per_100g": {"calories": 276, "sodium_mg": 403, "sugar_g": 6.25,
                  "carbs_g": 21.15, "protein_g": 17.75, "fat_g": 13.40}},
    {"name": "돈까스", "category": "튀김류", "serving_size_g": 225,
     "serving_basis": "외식 분석 `돈가스` 4건 중앙값(1인 메뉴 — 가정식·급식 1인분 없음)",
     "from_public": "돈가스"},  # 음식 `돈가스` 분석 8건
    {"name": "감자튀김", "category": "튀김류", "serving_size_g": 150,
     "serving_basis": "가정식 분석 `감자튀김` 1건", "from_public": "감자튀김"},  # 음식 감자튀김 분석 22건
    {"name": "피자", "category": "외식", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `피자` 1건", "from_public": "피자"},  # 음식 피자 업체 표시 4706건
    {"name": "햄버거", "category": "외식", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `햄버거` 2건 중앙값", "from_public": "햄버거"},  # 음식 햄버거 분석 126건
    {"name": "초밥", "category": "외식", "serving_size_g": 290,
     "serving_basis": "가정식 분석 `초밥` 2건 중앙값", "from_public": "초밥"},  # 음식 초밥 분석 11건
    # --- 반찬·달걀 ---
    {"name": "김치", "category": "반찬", "serving_size_g": 40,
     "serving_basis": "표시기준 1회 섭취참고량 — 배추김치 40g",
     "source": "농진청 성분표 `배추김치` D315-670000000-0001",
     "per_100g": {"calories": 38, "sodium_mg": 551, "sugar_g": 2.40,
                  "carbs_g": 6.49, "protein_g": 1.98, "fat_g": 0.43}},
    {"name": "계란후라이", "category": "달걀", "serving_size_g": 60,
     "serving_basis": "가정식 분석 `달걀부침(달걀후라이)` 1건(같은 행)",
     "source": "식약처 가정식 분석 `달걀부침(달걀후라이)` D109-417000000-0001 (2017)",
     "per_100g": {"calories": 208, "sodium_mg": 161, "sugar_g": 0.03,
                  "carbs_g": 5.15, "protein_g": 15.73, "fat_g": 13.78}},
    {"name": "계란찜", "category": "달걀", "serving_size_g": 200,
     "serving_basis": "가정식 분석 `달걀찜` 2건 중앙값",
     "source": "식약처 외식 분석 `달걀찜_채소` D307-317210000-0001 (2022, 분석 4건의 메도이드)",
     "per_100g": {"calories": 89, "sodium_mg": 329, "sugar_g": 0,
                  "carbs_g": 4.46, "protein_g": 4.76, "fat_g": 5.77}},
    # 드레싱 없는 채소다. 공공 표준 `샐러드` 는 드레싱·토핑이 든 판매 샐러드(124kcal/100g)다.
    {"name": "샐러드", "category": "채소", "serving_size_g": 150,
     "serving_basis": "가정식 분석 `샐러드` 8건 중앙값",
     "source": "농진청 성분표 `양배추_생것` R106-129000001-0000",
     "per_100g": {"calories": 29, "sodium_mg": 9, "sugar_g": 4.40,
                  "carbs_g": 6.98, "protein_g": 1.36, "fat_g": 0.12}},
    # --- 음료·과일·빵 ---
    {"name": "아메리카노", "category": "음료", "serving_size_g": 240,
     "serving_basis": "표시기준 1회 섭취참고량 — 커피 240ml(밀도 1.0)",
     "source": "USDA FDC 171890 드립 커피",
     "per_100g": {"calories": 1, "sodium_mg": 2, "sugar_g": 0,
                  "carbs_g": 0.0, "protein_g": 0.12, "fat_g": 0.02}},
    {"name": "콜라", "category": "음료", "serving_size_g": 208,
     "serving_basis": "표시기준 1회 섭취참고량 — 탄산음료 200ml × 밀도 1.04",
     "source": "농진청 성분표 `콜라` P109-401040100-0483 (100ml 값 ÷ 밀도 1.04)",
     "per_100g": {"calories": 36.54, "sodium_mg": 1.92, "sugar_g": 8.68,
                  "carbs_g": 9.10, "protein_g": 0.0, "fat_g": 0.0}},
    # 열량 대부분이 알코올이라 탄·단·지 합(4·4·9)과는 맞지 않는다.
    {"name": "맥주", "category": "주류", "serving_size_g": None,
     "serving_basis": "없음 — 표시기준 [표3] 은 주류에 1회 섭취참고량을 두지 않는다",
     "source": "농진청 성분표 `맥주(알코올 4.5)` (가공식품 분석, 100g 기준)",
     "per_100g": {"calories": 46, "sodium_mg": 2, "sugar_g": 0.17,
                  "carbs_g": 3.27, "protein_g": 0.21, "fat_g": 0.01}},
    {"name": "우유", "category": "음료", "serving_size_g": 206,
     "serving_basis": "표시기준 1회 섭취참고량 — 우유 200ml × 밀도 1.03",
     "source": "농진청 성분표 `우유` R213-009000000-0000",
     "per_100g": {"calories": 67, "sodium_mg": 40, "sugar_g": 4.81,
                  "carbs_g": 4.86, "protein_g": 3.09, "fat_g": 3.85}},
    {"name": "사과", "category": "과일", "serving_size_g": 182,
     "serving_basis": "USDA FDC 171688 `1 medium` 182g", "from_public": "사과"},  # 원재료성식품 사과 분석 8건
    {"name": "바나나", "category": "과일", "serving_size_g": 118,
     "serving_basis": "USDA FDC 173944 `1 medium` 118g(먹는 부분)",
     "source": "농진청 성분표 `바나나_생것` R108-037000001-0000",
     "per_100g": {"calories": 77, "sodium_mg": 0, "sugar_g": 14.40,
                  "carbs_g": 20.00, "protein_g": 1.11, "fat_g": 0.20}},
    {"name": "식빵", "category": "빵류", "serving_size_g": 70,
     "serving_basis": "표시기준 1회 섭취참고량 — 빵류 70g", "from_public": "식빵"},  # 음식 식빵 업체 표시 105건
    # --- PT 식단 (공공 표준에 없음 — USDA FoodData Central 실측값) ---
    # 공공 표준에 없어, 있을 때는 엉뚱한 행에 붙었다(`오트밀` → `밀`, `닭가슴살` →
    # `닭가슴살 샐러드`). 조리법·제품마다 값이 크게 갈리는 음식은 **그 범위의 가운데에 드는
    # 측정 항목**을 골랐다 — 어느 쪽으로 틀려도 오차가 가장 작다.
    #
    # 물로 끓인 오트밀(71kcal/100g). 우유로 묽게 끓인 것(FNDDS 46~61)부터 귀리 40g 에
    # 우유 200ml(약 117)까지 조리법마다 갈리는데, 어느 쪽으로 틀려도 오차가 가장 작은
    # 값(약 66)에 가장 가까운 실측 항목이다. 얹은 우유·과일·견과는 인식기가 따로 적는다.
    {"name": "오트밀", "category": "곡류", "serving_size_g": 234,
     "serving_basis": "USDA FDC 173905 `1 cup` 234g(끓인 뒤)",
     "source": "USDA FDC 173905 물로 끓인 오트밀",
     "per_100g": {"calories": 71, "sodium_mg": 4, "sugar_g": 0.27,
                  "carbs_g": 12.0, "protein_g": 2.54, "fat_g": 1.52}},
    # 플레인 전지 그릭 요거트(97kcal/100g). 국내 제품은 100g 당 55.6~199.7kcal 로 갈리는데
    # (소비자시민모임, 17종) 어느 쪽으로 틀려도 오차가 가장 작은 값(약 87)에 가장 가까운
    # 실측 항목이다. 국내 제품 예(102kcal·단백질 10.3g)와도 거의 같다.
    {"name": "그릭 요거트", "category": "유제품", "serving_size_g": 100,
     "serving_basis": "표시기준 1회 섭취참고량 — 발효유류 호상 100g",
     "source": "USDA FDC 171304 플레인 전지 그릭 요거트",
     "per_100g": {"calories": 97, "sodium_mg": 35, "sugar_g": 4.0,
                  "carbs_g": 3.98, "protein_g": 9.0, "fat_g": 5.0}},
    # 양념해 익힌 닭가슴살(144kcal·나트륨 328mg/100g). 시판 가공품(100g 당 105~125kcal·
    # 나트륨 300~450mg)과 집에서 구운 것(FDC 171477, 165kcal) 사이에 들어, 어느 쪽으로
    # 틀려도 오차가 가장 작다.
    {"name": "닭가슴살", "category": "육류", "serving_size_g": 100,
     "serving_basis": "표시기준 1회 섭취참고량 — 양념육 100g",
     "source": "USDA FDC 171445 바비큐 로티세리 닭가슴살",
     "per_100g": {"calories": 144, "sodium_mg": 328, "sugar_g": 0,
                  "carbs_g": 0.0, "protein_g": 28.0, "fat_g": 3.57}},
    # --- 디저트(데모 메뉴) ---
    # 요거트 아이스크림 볼은 컵 하나가 베이스 + 과일 + 그래놀라로 갈리므로 세 줄로 둔다.
    # 한 줄로 묶으면 토핑을 바꾼 컵이 전부 같은 값이 된다. 스텁 인식기가 이 양 그대로
    # 내므로 1인분 값으로 적는다.
    {"name": "요거트 아이스크림", "category": "디저트", "serving_size_g": 110,
     "serving_basis": "데모 메뉴 — 스텁 인식기의 양", "source": "데모 메뉴",
     "calories": 135, "sodium_mg": 55, "sugar_g": 14.5,
     "carbs_g": 26.0, "protein_g": 3.0, "fat_g": 2.0},
    {"name": "과일 토핑", "category": "디저트", "serving_size_g": 90,
     "serving_basis": "데모 메뉴 — 스텁 인식기의 양", "source": "데모 메뉴",
     "calories": 55, "sodium_mg": 5, "sugar_g": 9.0,
     "carbs_g": 13.0, "protein_g": 1.0, "fat_g": 0.5},
    {"name": "그래놀라 토핑", "category": "디저트", "serving_size_g": 50,
     "serving_basis": "데모 메뉴 — 스텁 인식기의 양", "source": "데모 메뉴",
     "calories": 205, "sodium_mg": 125, "sugar_g": 6.0,
     "carbs_g": 20.0, "protein_g": 5.0, "fat_g": 11.5},
]
