"""공공 식품영양성분 DB 큐레이션 시드.

식약처(MFDS) 식품영양성분 데이터베이스 / 국가표준식품성분표를 참고해,
국내에서 가장 자주 촬영되는 한식·외식·디저트 메뉴를 **1회 제공량(1인분) 기준**으로
정리한 대표값이다. 시드가 100g 기준으로 환산해 넣고, 이름이 같은 공공 표준 행보다
우선한다(`init_db._seed_food_nutrients`).

나트륨(sodium_mg)·당류(sugar_g)는 회원의 하루 목표와 바로 비교되는 값이라 특히 신중히 채웠다.
값 단위: serving_size_g=g, calories=kcal, sodium_mg=mg, sugar_g/carbs_g/protein_g/fat_g=g.

## 값의 근거 (#2096, #2100)

큐레이션은 **이름과 1회 섭취량**을 정한다. 영양값은 셋 중 하나다.

1. `from_public` — 그 이름의 공공 표준 행에서 100g 당 값을 가져온다. 공공 집계가
   분석값·업체 표시값 5건 이상에서 고른 값일 때만 쓴다(`scripts/import_food_nutrients`
   의 메도이드). 줄 끝 주석이 그 데이터셋·방법·건수다. 공공 집계를 다시 만들면 같이
   따라간다.
2. 출처를 적은 실측값 — 공공 표준에 없는 오트밀·그릭 요거트·닭가슴살(USDA)과 맥주,
   요거트 아이스크림 볼.
3. 예전 큐레이션 값 — 공공 표준이 레시피 계산값뿐이거나(짜장면·잔치국수·물냉면·
   제육볶음 등) 분석값이 5건이 안 되는 것. 계산값은 분석값보다 체계적으로 낮고(열량
   ×0.76) 표본 한두 건은 그 제품이 튀면 그대로 따라가서, 근거가 약해도 사람이 정한
   값을 둔다. 탄·단·지는 참조 행의 비율을 이 칼로리에 맞춰 환산했다(탄수화물·단백질 4,
   지방 9 kcal/g) — 참조 행은 줄 끝 주석이다. 아메리카노·콜라는 값을 그대로 적었다.

## 공공 표준에 없는 항목

오트밀·그릭 요거트·닭가슴살은 PT 회원 식단에 자주 나오지만 공공 표준 집계에 없어,
있을 때는 엉뚱한 행에 붙었다(`오트밀` → `밀`, `닭가슴살` → `닭가슴살 샐러드`).
실측값이 있는 USDA FoodData Central 항목을 쓴다. 조리법·제품마다 값이 크게 갈리는
음식은 **그 범위의 가운데에 드는 측정 항목**을 골랐다 — 어느 쪽으로 틀려도 오차가
가장 작다.
"""
from __future__ import annotations

# name, category, serving_g, 그리고 `from_public` 이거나 kcal·sodium_mg·sugar_g·탄·단·지. 줄 끝 주석이 근거다.
FOOD_NUTRIENTS: list[dict] = [
    # --- 밥·분식 ---
    {"name": "공기밥", "category": "밥류", "serving_size_g": 210, "calories": 310, "sodium_mg": 3, "sugar_g": 0,
     "carbs_g": 69.5, "protein_g": 5.9, "fat_g": 0.9},  # 공공 표준 쌀밥
    {"name": "비빔밥", "category": "밥류", "serving_size_g": 500, "from_public": "비빔밥"},  # 음식 비빔밥 분석 7건
    {"name": "김밥", "category": "분식", "serving_size_g": 200, "from_public": "김밥"},  # 음식 김밥 분석 13건
    {"name": "볶음밥", "category": "밥류", "serving_size_g": 400, "from_public": "볶음밥"},  # 음식 볶음밥 분석 23건
    {"name": "떡볶이", "category": "분식", "serving_size_g": 300, "from_public": "떡볶이"},  # 음식 떡볶이 분석 35건
    {"name": "순대", "category": "분식", "serving_size_g": 200, "calories": 360, "sodium_mg": 900, "sugar_g": 2,
     "carbs_g": 45.4, "protein_g": 12.1, "fat_g": 14.4},  # 공공 표준 순대
    # --- 국·찌개·탕 ---
    {"name": "김치찌개", "category": "국·찌개류", "serving_size_g": 400, "from_public": "김치찌개"},  # 음식 김치찌개 분석 8건
    {"name": "된장찌개", "category": "국·찌개류", "serving_size_g": 400, "from_public": "된장찌개"},  # 음식 된장찌개 분석 8건
    {"name": "순두부찌개", "category": "국·찌개류", "serving_size_g": 400, "from_public": "순두부찌개"},  # 음식 순두부찌개 분석 6건
    {"name": "미역국", "category": "국·찌개류", "serving_size_g": 300, "from_public": "미역국"},  # 음식 미역국 분석 9건
    {"name": "된장국", "category": "국·찌개류", "serving_size_g": 300, "from_public": "된장국"},  # 음식 된장국 분석 19건
    {"name": "갈비탕", "category": "탕류", "serving_size_g": 700, "calories": 430, "sodium_mg": 1500, "sugar_g": 3,
     "carbs_g": 20.5, "protein_g": 30.9, "fat_g": 25.0},  # 공공 표준 갈비탕
    {"name": "설렁탕", "category": "탕류", "serving_size_g": 700, "calories": 400, "sodium_mg": 1400, "sugar_g": 2,
     "carbs_g": 42.9, "protein_g": 27.8, "fat_g": 13.0},  # 공공 표준 설렁탕
    {"name": "삼계탕", "category": "탕류", "serving_size_g": 1000, "calories": 900, "sodium_mg": 1400, "sugar_g": 1,
     "carbs_g": 54.2, "protein_g": 79.3, "fat_g": 40.6},  # 공공 표준 삼계탕
    # --- 면 ---
    {"name": "라면", "category": "면류", "serving_size_g": 550, "from_public": "라면"},  # 음식 라면 분석 17건
    {"name": "짜장면", "category": "면류", "serving_size_g": 650, "calories": 700, "sodium_mg": 2400, "sugar_g": 12,
     "carbs_g": 128.7, "protein_g": 24.0, "fat_g": 9.9},  # 공공 표준 짜장면
    {"name": "짬뽕", "category": "면류", "serving_size_g": 700, "from_public": "짬뽕"},  # 음식 짬뽕 분석 7건
    {"name": "잔치국수", "category": "면류", "serving_size_g": 550, "calories": 480, "sodium_mg": 1900, "sugar_g": 6,
     "carbs_g": 88.7, "protein_g": 17.4, "fat_g": 6.2},  # 공공 표준 잔치국수
    {"name": "물냉면", "category": "면류", "serving_size_g": 600, "calories": 550, "sodium_mg": 2200, "sugar_g": 15,
     "carbs_g": 98.4, "protein_g": 27.0, "fat_g": 5.4},  # 공공 표준 물냉면
    # --- 구이·볶음·고기 ---
    {"name": "삼겹살", "category": "구이류", "serving_size_g": 200, "calories": 660, "sodium_mg": 120, "sugar_g": 0,
     "carbs_g": 0.0, "protein_g": 32.5, "fat_g": 58.9},  # 국가표준식품성분표 삼겹살 구운것(팬) — 공공 표준 `삼겹살구이` 는 양념 탄수화물이 섞였다
    {"name": "제육볶음", "category": "볶음류", "serving_size_g": 250, "calories": 480, "sodium_mg": 1300, "sugar_g": 10,
     "carbs_g": 26.5, "protein_g": 43.6, "fat_g": 22.2},  # 공공 표준 제육볶음
    {"name": "불고기", "category": "구이류", "serving_size_g": 250, "calories": 420, "sodium_mg": 1100, "sugar_g": 14,
     "carbs_g": 14.0, "protein_g": 27.7, "fat_g": 28.1},  # 공공 표준 소불고기
    {"name": "양념갈비", "category": "구이류", "serving_size_g": 250, "calories": 550, "sodium_mg": 1200, "sugar_g": 16,
     "carbs_g": 17.1, "protein_g": 27.6, "fat_g": 41.2},  # 공공 표준 소갈비 구이
    # --- 튀김·외식 ---
    {"name": "후라이드치킨", "category": "튀김류", "serving_size_g": 300, "from_public": "닭튀김"},  # 음식 `닭튀김` 분석 243건
    {"name": "양념치킨", "category": "튀김류", "serving_size_g": 300, "calories": 900, "sodium_mg": 1400, "sugar_g": 20,
     "carbs_g": 85.0, "protein_g": 79.9, "fat_g": 26.7},  # 공공 표준 닭강정
    {"name": "돈까스", "category": "튀김류", "serving_size_g": 250, "from_public": "돈가스"},  # 음식 `돈가스` 분석 8건
    {"name": "감자튀김", "category": "튀김류", "serving_size_g": 130, "from_public": "감자튀김"},  # 음식 감자튀김 분석 22건
    {"name": "피자", "category": "외식", "serving_size_g": 120, "from_public": "피자"},  # 음식 피자 업체 표시 4706건
    {"name": "햄버거", "category": "외식", "serving_size_g": 250, "from_public": "햄버거"},  # 음식 햄버거 분석 126건
    {"name": "초밥", "category": "외식", "serving_size_g": 200, "from_public": "초밥"},  # 음식 초밥 분석 11건
    # --- 반찬·달걀 ---
    {"name": "김치", "category": "반찬", "serving_size_g": 50, "calories": 15, "sodium_mg": 300, "sugar_g": 1,
     "carbs_g": 2.5, "protein_g": 0.8, "fat_g": 0.2},  # 공공 표준 배추김치
    {"name": "계란후라이", "category": "달걀", "serving_size_g": 50, "calories": 90, "sodium_mg": 160, "sugar_g": 0,
     "carbs_g": 1.6, "protein_g": 5.7, "fat_g": 6.8},  # 공공 표준 달걀후라이
    {"name": "계란찜", "category": "달걀", "serving_size_g": 200, "calories": 150, "sodium_mg": 700, "sugar_g": 1,
     "carbs_g": 3.5, "protein_g": 13.6, "fat_g": 9.1},  # 공공 표준 달걀찜
    {"name": "샐러드", "category": "채소", "serving_size_g": 150, "calories": 40, "sodium_mg": 30, "sugar_g": 4,
     "carbs_g": 7.5, "protein_g": 2.2, "fat_g": 0.2},  # 공공 표준 양배추 — `샐러드` 행은 드레싱이 든 값이다
    # --- 음료·과일·빵 ---
    {"name": "아메리카노", "category": "음료", "serving_size_g": 350, "calories": 10, "sodium_mg": 10, "sugar_g": 0,
     "carbs_g": 0.0, "protein_g": 0.4, "fat_g": 0.1},  # 값 그대로: USDA FDC 171890(드립 커피) × 350g
    {"name": "콜라", "category": "음료", "serving_size_g": 355, "calories": 150, "sodium_mg": 15, "sugar_g": 39,
     "carbs_g": 39.0, "protein_g": 0.0, "fat_g": 0.0},  # 값 그대로: 당류 39g 이 곧 탄수화물
    # 가공식품 DB `맥주` 는 제로슈거·라이트 라거 표시값이 대부분이라(25kcal) 공공 집계로는
    # 일반 맥주가 나오지 않는다. 같은 DB 의 분석값 네 건(46~65kcal/100g) 중 메도이드인
    # `맥주`(53kcal)를 쓴다. 열량 대부분이 알코올이라 탄·단·지 합(4·4·9)과는 맞지 않는다.
    # 1회 섭취량은 생맥주 한 잔(500ml, 밀도 1.0)이다.
    {"name": "맥주", "category": "주류", "serving_size_g": 500, "calories": 265, "sodium_mg": 10, "sugar_g": 0,
     "carbs_g": 14.5, "protein_g": 1.2, "fat_g": 0.1},  # 가공식품 `맥주` 분석값 × 500
    {"name": "우유", "category": "음료", "serving_size_g": 200, "calories": 130, "sodium_mg": 100, "sugar_g": 10,
     "carbs_g": 9.7, "protein_g": 6.6, "fat_g": 7.2},  # 공공 표준 우유(멸균) — `우유` 행은 탄수화물이 100g 당 11g 으로 가공우유가 섞였다
    {"name": "사과", "category": "과일", "serving_size_g": 200, "from_public": "사과"},  # 원재료성식품 사과 분석 8건
    {"name": "바나나", "category": "과일", "serving_size_g": 120, "calories": 105, "sodium_mg": 1, "sugar_g": 14,
     "carbs_g": 24.7, "protein_g": 1.2, "fat_g": 0.2},  # 공공 표준 바나나
    {"name": "식빵", "category": "빵류", "serving_size_g": 70, "from_public": "식빵"},  # 음식 식빵 업체 표시 105건
    # --- PT 식단 (공공 표준에 없음 — USDA FoodData Central 실측값) ---
    # 물로 끓인 오트밀(FDC 173905, 71kcal/100g). 우유로 묽게 끓인 것(FNDDS 46~61)부터
    # 귀리 40g 에 우유 200ml(약 117)까지 조리법마다 갈리는데, 어느 쪽으로 틀려도 오차가
    # 가장 작은 값(약 66)에 가장 가까운 실측 항목이다. 얹은 우유·과일·견과는 인식기가
    # 따로 적는다.
    {"name": "오트밀", "category": "곡류", "serving_size_g": 240,
     "calories": 170.4, "sodium_mg": 9.6, "sugar_g": 0.65,
     "carbs_g": 28.8, "protein_g": 6.1, "fat_g": 3.65},
    # 플레인 전지 그릭 요거트(FDC 171304, 97kcal/100g). 국내 제품은 100g 당 55.6~199.7kcal
    # 로 갈리는데(소비자시민모임, 17종) 어느 쪽으로 틀려도 오차가 가장 작은 값(약 87)에
    # 가장 가까운 실측 항목이다. 국내 제품 예(102kcal·단백질 10.3g)와도 거의 같다.
    {"name": "그릭 요거트", "category": "유제품", "serving_size_g": 100,
     "calories": 97, "sodium_mg": 35, "sugar_g": 4.0,
     "carbs_g": 3.98, "protein_g": 9.0, "fat_g": 5.0},
    # 양념해 익힌 닭가슴살(FDC 171445, 144kcal·나트륨 328mg/100g). 시판 가공품(100g 당
    # 105~125kcal·나트륨 300~450mg)과 집에서 구운 것(FDC 171477, 165kcal) 사이에 들어,
    # 어느 쪽으로 틀려도 오차가 가장 작다.
    {"name": "닭가슴살", "category": "육류", "serving_size_g": 100,
     "calories": 144, "sodium_mg": 328, "sugar_g": 0,
     "carbs_g": 0.0, "protein_g": 28.0, "fat_g": 3.57},
    # --- 디저트 ---
    # 요거트 아이스크림 볼은 컵 하나가 베이스 + 과일 + 그래놀라로 갈리므로 세 줄로 둔다.
    # 한 줄로 묶으면 토핑을 바꾼 컵이 전부 같은 값이 된다.
    {"name": "요거트 아이스크림", "category": "디저트", "serving_size_g": 110,
     "calories": 135, "sodium_mg": 55, "sugar_g": 14.5,
     "carbs_g": 26.0, "protein_g": 3.0, "fat_g": 2.0},
    {"name": "과일 토핑", "category": "디저트", "serving_size_g": 90,
     "calories": 55, "sodium_mg": 5, "sugar_g": 9.0,
     "carbs_g": 13.0, "protein_g": 1.0, "fat_g": 0.5},
    {"name": "그래놀라 토핑", "category": "디저트", "serving_size_g": 50,
     "calories": 205, "sodium_mg": 125, "sugar_g": 6.0,
     "carbs_g": 20.0, "protein_g": 5.0, "fat_g": 11.5},
]
