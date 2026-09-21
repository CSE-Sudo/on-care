#!/usr/bin/env python3
"""김민수 데모 픽스처(`shared/demo_fixture/assets/kim_minsu.json`)를 만든다.

픽스처는 **결과물이 원본**이다 — 사용자앱·트레이너웹·백엔드는 이 JSON 을 읽기만
하고 아무것도 계산하지 않는다. 이 스크립트는 그 JSON 을 처음 짜 넣기 위한
도구이고, 이후 값을 손보고 싶으면 JSON 을 직접 고쳐도 된다. 다시 돌리면 손댄
내용이 날아가므로, 규칙 자체를 바꿀 때만 쓴다.

    python3 tool/gen_demo_fixture.py

날짜는 절대 날짜로 적지 않는다. 달력 주 격자(`weeks`: 몇 주 전 × 요일)가 12주를
채우고, 최근 사흘(`recent`: 오늘·어제·그제)만 큐레이션이 그 위를 덮는다. 주 격자를
쓰는 이유는 리포트·추이 그래프가 달력 주로 묶기 때문이다 — 오늘로부터의 일수만으로
적으면 "회식이 몰린 주" 같은 이야기가 두 주에 걸쳐 잘린다.
"""

from __future__ import annotations

import json
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]

#: 픽스처 원본. 사람이 읽고 고치는 파일이다.
OUT = _ROOT / "shared/demo_fixture/assets/kim_minsu.json"

#: 백엔드가 읽는 같은 파일. 내용은 [OUT] 과 **바이트까지 같아야 한다**
#: (`backend/tests/test_demo_fixture.py` 가 검사한다).
#:
#: 왜 복사본이 있나: 백엔드 이미지는 `docker build .` 을 `backend/` 에서 돌려서
#: 빌드 컨텍스트 밖(`shared/`)의 파일을 담을 수 없다. 컨텍스트를 레포 루트로 올리는
#: 건 배포 워크플로를 건드리는 일이라 여기서 하지 않는다. 대신 이 스크립트가 두
#: 곳에 함께 써서 손으로 맞출 일을 없앤다.
OUT_BACKEND = _ROOT / "backend/app/db/demo_fixture_data.json"

#: 두 Flutter 앱이 읽는 같은 내용. 에셋이 아니라 **Dart 상수**로 심는다.
#:
#: 에셋으로 두면 읽는 데 `rootBundle` 이 필요하고 그건 비동기다. 위젯 테스트는 가짜
#: 비동기 안에서 도는데, 거기서 에셋을 기다리면 펌프될 때까지 풀리지 않아 테스트가
#: 통째로 멈춘다 — 26초에 끝나던 파일이 10분을 넘겨도 끝나지 않았다. 상수로 두면
#: 읽기가 동기라 그 함정이 없고, 새 테스트를 쓰는 사람이 밟을 일도 없다.
OUT_DART = _ROOT / "shared/demo_fixture/lib/src/fixture_json.g.dart"

# 여덟 달치. `전체` 그래프가 1월까지 거슬러 가야 해서 — 넓은 화면(웹)에서도
# 한 화면에 다 들어가지 않아 옆으로 밀 거리가 남는다. 주별 이야기 일곱 가지가
# 그대로 돌며 채운다.
HISTORY_WEEKS = 35

# ── 개인 운동(배정 루틴) ───────────────────────────────────────────────────
# (id, 이름, 분, 유형, 이유, 출처)
#
# 회원 앱 `추천 개인운동`, 트레이너 고객 탭 `아직 하지 않은 개인 운동`, 트레이너
# 프로그램 탭이 **모두 이 목록 하나**를 읽는다(#1170). 예전에는 세 화면이 각자
# 목록을 들고 있어서, 같은 회원의 같은 날에 셋이 서로 다른 운동을 말했다 —
# 회원 화면은 `코어 스트레칭 10분`, 고객 탭은 `코어 서킷 15분`, 프로그램 탭은
# `코어 강화 10분` 이었다.
#
# 값은 백엔드 시드(`seed_member_data._ROUTINES['user-7d4e9a2c5f18']`)를 따른다. 실 API
# 모드에서 두 앱이 실제로 받는 것이 그 목록이므로, 데모가 다른 값을 보여 주면
# 모드를 바꿀 때마다 화면이 달라진다.
#
# 유형은 화면이 그대로 쓰는 한국어다(유산소·근력·스트레칭). 회원 앱은 `스트레칭`,
# 트레이너 그래프는 `스트레칭` 이라 부르지만 재는 값은 같다.
#
# 근력 한 줄은 세트·횟수·중량을 함께 든다(#1276). 유형마다 재는 단위가 달라서,
# 근력 배정이 `10분` 으로만 적히면 회원도 트레이너도 무엇을 몇 번 하라는 것인지
# 화면에서 읽을 수가 없다. 맨몸 운동의 중량은 `0` 이다 — 두 앱의 중량 칸은 비울
# 수 없어(최솟값 0) 근력이면 언제나 값을 하나 든다. 같은 운동(`코어 강화 10분`)의
# 기록이 `RECENT`·`WEEKS` 에도 3세트 · 15회로 있어 두 자리가 같은 수를 말한다.
ROUTINES: list[dict] = [
    {"id": "seed-routine-user-7d4e9a2c5f18-0", "name": "저강도 유산소 (걷기)",
     "minutes": 30, "type": "유산소", "reason": "혈압 안정에 효과적",
     "source": "ai"},
    {"id": "seed-routine-user-7d4e9a2c5f18-1", "name": "하체 스트레칭",
     "minutes": 15, "type": "스트레칭", "reason": "혈액순환 개선",
     "source": "trainer"},
    {"id": "seed-routine-user-7d4e9a2c5f18-2", "name": "코어 강화",
     "minutes": 10, "type": "근력", "reason": "기초대사량 향상",
     "source": "ai", "sets": 3, "reps": 15, "weight": 0},
    {"id": "seed-routine-user-7d4e9a2c5f18-3", "name": "어깨 관절 보호 스트레칭",
     "minutes": 8, "type": "스트레칭",
     "reason": "PT 피드백 반영 · 오른쪽 어깨 보호", "source": "trainer"},
]

# ── 음식 ───────────────────────────────────────────────────────────────────
# (이름, 칼로리, 나트륨mg, 당류g, 탄수g, 단백g, 지방g)
FOODS: dict[str, tuple[str, int, int, float, float, float, float]] = {
    "oatmeal": ("오트밀", 298, 104, 11, 50.2, 11.6, 8.4),
    "banana": ("바나나", 61, 1, 8.2, 15.4, 0.8, 0.1),
    "greek-yogurt": ("그릭 요거트", 146, 52, 5.4, 5.8, 13.5, 7.5),
    "nuts": ("견과류", 175, 4, 2.4, 9.2, 5.2, 12.9),
    "scrambled-egg": ("스크램블 에그", 213, 358, 0.7, 2.1, 15.2, 14.7),
    "strawberry": ("딸기", 34, 1, 6.1, 8.3, 0.8, 0.1),
    "chicken-salad": ("닭가슴살 샐러드", 205, 73, 2.2, 5.4, 25.2, 9.8),
    "bibimbap": ("야채비빔밥", 540, 810, 7.2, 84.8, 16.6, 13.3),
    "jjamppong": ("짬뽕", 707, 4286, 8.6, 95.1, 35.4, 12.7),
    "doenjang-jjigae": ("된장찌개", 180, 1300, 4, 19, 14.9, 5.4),
    "rice": ("잡곡밥", 201, 2, 0.4, 42.3, 4.6, 1),
    "grilled-salmon": ("연어구이", 229, 336, 0, 0.1, 26.5, 13.5),
    "brown-rice": ("현미밥", 180, 2, 0.1, 38.8, 3.4, 0.6),
    "sweet-potato": ("고구마", 339, 111, 43.5, 78.3, 5.2, 0.5),
    "iced-americano": ("아이스 아메리카노", 10, 10, 0, 1.4, 0.3, 0),
    "nut-pack": ("견과류 한 봉", 90, 2, 1.3, 4.7, 2.7, 6.6),
    "samgyeopsal": ("삼겹살 2인분", 1320, 240, 0, 0, 68.8, 113.6),
    "soju": ("소주 1병", 320, 0, 0, 0, 0, 0),
    "choco-cake": ("초코 케이크 한 조각", 338, 121, 21.6, 30.7, 5, 20.9),
    "cafe-latte": ("카페라떼", 153, 60, 15.8, 20.7, 5.1, 5.5),
}

#: 음식별 내용량(g) — 위 영양이 무엇을 재고 나온 값인가(#1876, #2090). 그 음식이 나오는
#: 끼니 **사진에서 읽은 양**이다. 영양은 이 양 × 공공 영양 DB 의 100g 값이다 — 사진 분석과
#: 같은 계산이라, 데모 화면의 숫자가 사진에 담긴 양과 맞는다.
AMOUNTS_G: dict[str, int] = {
    "oatmeal": 250,
    "banana": 70,
    "greek-yogurt": 150,
    "nuts": 30,
    "scrambled-egg": 130,
    "strawberry": 100,
    "chicken-salad": 250,
    "bibimbap": 450,
    "jjamppong": 750,
    "doenjang-jjigae": 400,
    "rice": 150,
    "grilled-salmon": 120,
    "brown-rice": 150,
    "sweet-potato": 250,
    "iced-americano": 350,
    "nut-pack": 20,
    "samgyeopsal": 400,
    "soju": 360,
    "choco-cake": 110,
    "cafe-latte": 300,
}

# ── 끼니 ───────────────────────────────────────────────────────────────────
# (끼니종류, 시각, 사진, AI 코멘트, 음식들)
#
# 사진 에셋이 없는 끼니는 가장 가까운 한식 상차림을 재사용한다. 삼겹살·디저트가
# 그렇다 — 에셋이 생기면 여기만 고치면 세 곳이 함께 따라온다.
MEALS: dict[str, tuple[str, str, str, str, list[str]]] = {
    "breakfast-oatmeal-banana": (
        "breakfast", "08:05", "assets/images/diet-oatmeal-banana.jpeg",
        "오트밀로 식이섬유를 챙긴 아침이에요.",
        ["oatmeal", "banana"],
    ),
    "breakfast-greek-yogurt-nuts": (
        "breakfast", "08:30", "assets/images/diet-greek-yogurt-nuts.jpeg",
        "단백질과 불포화지방을 고르게 섭취했어요.",
        ["greek-yogurt", "nuts"],
    ),
    "breakfast-egg-strawberry": (
        "breakfast", "07:50", "assets/images/breakfast-scrambled-egg-strawberry.jpg",
        "달걀 단백질에 과일로 비타민을 더했어요.",
        ["scrambled-egg", "strawberry"],
    ),
    "lunch-chicken-salad": (
        "lunch", "12:30", "assets/images/diet-chicken-salad.jpg",
        "닭가슴살과 채소로 단백질·식이섬유를 챙겼어요.",
        ["chicken-salad"],
    ),
    "lunch-bibimbap": (
        "lunch", "12:20", "assets/images/diet-vegetable-bibimbap.jpg",
        "야채가 풍부해요. 고추장을 줄이면 나트륨이 더 좋아져요.",
        ["bibimbap"],
    ),
    "lunch-jjamppong": (
        "lunch", "12:50", "assets/images/lunch-jjamppong.jpg",
        "국물 나트륨이 높은 날이에요. 국물은 남기는 편이 좋아요.",
        ["jjamppong"],
    ),
    "lunch-doenjang-rice": (
        "lunch", "12:10", "assets/images/diet-doenjang-rice.jpeg",
        "집밥 한 상이에요. 찌개 국물만 조금 남겨 보세요.",
        ["doenjang-jjigae", "rice"],
    ),
    "dinner-salmon-brown-rice": (
        "dinner", "18:40", "assets/images/diet-salmon-brown-rice.jpeg",
        "연어의 지방과 현미밥의 복합 탄수화물 조합이 좋아요.",
        ["grilled-salmon", "brown-rice"],
    ),
    "dinner-doenjang-rice": (
        "dinner", "19:10", "assets/images/diet-doenjang-rice.jpeg",
        "포만감은 좋지만 국물 나트륨이 높은 편이에요.",
        ["doenjang-jjigae", "rice"],
    ),
    "dinner-chicken-salad-sweet-potato": (
        "dinner", "18:20", "assets/images/diet-chicken-salad-sweet-potato.jpg",
        "가볍게 마무리한 저녁이에요.",
        ["chicken-salad", "sweet-potato"],
    ),
    "dinner-samgyeopsal": (
        "dinner", "19:30", "assets/images/diet-samgyeopsal-rice-soju.jpg",
        "고기와 술이 함께여서 칼로리가 크게 올라갔어요. 다음 날은 가볍게 시작해 보세요.",
        ["samgyeopsal", "rice", "soju"],
    ),
    "snack-coffee-nuts": (
        "snack", "15:40", "assets/images/snack-coffee-nuts.jpg",
        "당류가 낮고 건강한 지방을 채운 간식이에요.",
        ["iced-americano", "nut-pack"],
    ),
    "snack-cake-latte": (
        "snack", "21:10", "assets/images/snack-choco-cake-latte.jpg",
        "디저트로 당류가 하루 목표를 넘었어요.",
        ["choco-cake", "cafe-latte"],
    ),
}

# ── 요일별 루틴 ────────────────────────────────────────────────────────────
# 이행률은 여기 항목의 `done` 개수에서 나온다 — 퍼센트를 따로 적으면 화면의
# "3개 중 2개 완료" 와 숫자가 갈라진다(#754).
#
# (이름, 종류, 분) 또는 근력이면 (이름, 종류, 분, 세트, 횟수). 수요일은 휴식이라
# 항목이 없다 — 사용자앱의 주간 활동 그래프와 백엔드 시드가 이미 쓰던 리듬이다.
#
# 근력에 세트·횟수를 적는 이유: 화면 여러 곳이 근력을 세트로 읽는데(#1262),
# 픽스처가 분만 들고 있으면 저마다 분에서 되짚어 아무도 적은 적 없는 수를
# 그린다. 이름에 적힌 `4세트` 를 화면이 다시 세게 두어도 마찬가지다.
ROUTINE: dict[int, list[tuple]] = {
    0: [("저강도 유산소 (걷기) 30분", "cardio", 30),
        ("코어 강화 10분", "strength", 10, 3, 15),
        ("하체 스트레칭 5분", "stretching", 5)],
    1: [("저강도 유산소 (걷기) 40분", "cardio", 40),
        ("하체 스트레칭 10분", "stretching", 10)],
    2: [],
    3: [("저강도 유산소 (걷기) 35분", "cardio", 35),
        ("코어 강화 20분", "strength", 20, 5, 15),
        ("하체 스트레칭 5분", "stretching", 5)],
    4: [("저강도 유산소 (걷기) 45분", "cardio", 45),
        ("어깨 관절 보호 스트레칭 10분", "stretching", 10)],
    5: [("저강도 유산소 (걷기) 25분", "cardio", 25),
        ("코어 강화 30분", "strength", 30, 8, 12),
        ("하체 스트레칭 15분", "stretching", 15)],
    6: [("저강도 유산소 (걷기) 20분", "cardio", 20),
        ("하체 스트레칭 10분", "stretching", 10)],
}

# ── 과거의 PT 세션 ─────────────────────────────────────────────────────────
# {몇 주 전: (요일, 라벨·피드백·메모, 운동들)}
#
# 데모는 오늘 하루만 보는 것이 아니다. 지난주·전체로 넘겨도 PT 를 받은 날과 그때
# 무엇을 몇 세트 했는지, 회원이 뭐라고 했고 트레이너가 뭘 적어 뒀는지가 보여야
# "충분히 구현된 제품"으로 읽힌다. 예전에는 과거 35주가 전부 `AI 개인운동`
# 한 줄이었고 PT 는 오늘 하나뿐이었다. (#1265)
#
# 수요일에 둔다 — 격자에서 비어 있는 요일이라 그날의 자율 운동과 겹치지 않는다.
# 5~6주 간격으로 흩어 두어 어느 기간을 열어도 하나는 걸린다.
PT_LABEL = "PT 세션 · 트레이너 지도"

PT_SESSIONS: dict[int, tuple[int, str, str, list[tuple]]] = {
    5: (2, "레그프레스 무게가 붙었어요. 마지막 세트가 힘들었어요.",
        "하체 근력 향상 확인. 다음 세션 레그프레스 5kg 증량.",
        [("레그프레스 70kg · 4세트", "strength", 12, 4, 12),
         ("레그컬 35kg · 3세트", "strength", 9, 3, 12),
         ("카프레이즈 자체중량 · 3세트", "strength", 6, 3, 20),
         ("마무리 러닝머신 15분", "cardio", 15),
         ("하체 스트레칭 10분", "stretching", 10)]),
    11: (2, "데드리프트 자세를 잡아주셔서 허리가 편했어요.",
         "데드리프트 힙힌지 안정적. 중량 55kg 유지 후 다음 달 60kg.",
         [("데드리프트 55kg · 4세트", "strength", 12, 4, 8),
          ("루마니안 데드리프트 40kg · 3세트", "strength", 9, 3, 10),
          ("플랭크", "strength", 6, 3, None, 45),
          ("마무리 러닝머신 12분", "cardio", 12),
          ("허리 스트레칭 10분", "stretching", 10)]),
    17: (2, "어깨가 아직 조금 불편해서 무게를 낮췄어요.",
         "오른쪽 어깨 가동범위 제한. 숄더프레스 중량 낮추고 밴드 보강 병행.",
         [("숄더프레스 10kg · 4세트", "strength", 12, 4, 12),
          ("밴드 외전 · 3세트", "strength", 6, 3, 20),
          ("인클라인 푸시업 · 3세트", "strength", 9, 3, 12),
          ("마무리 러닝머신 10분", "cardio", 10),
          ("어깨 관절 보호 스트레칭 12분", "stretching", 12)]),
    23: (2, "벤치프레스가 처음이라 어색했지만 재밌었어요 💪",
         "상체 근력 기초 확인. 벤치프레스 35kg 로 시작해 자세 우선.",
         [("벤치프레스 35kg · 4세트", "strength", 12, 4, 10),
          ("체스트프레스 25kg · 3세트", "strength", 9, 3, 12),
          ("랫풀다운 30kg · 3세트", "strength", 9, 3, 12),
          ("마무리 러닝머신 15분", "cardio", 15),
          ("상체 스트레칭 10분", "stretching", 10)]),
    29: (2, "첫 PT 라 긴장했는데 생각보다 할 만했어요.",
         "첫 세션. 체력 수준 점검 위주로 가볍게 진행.",
         [("고블릿 스쿼트 12kg · 3세트", "strength", 9, 3, 12),
          ("케틀벨 스윙 12kg · 3세트", "strength", 9, 3, 15),
          ("코어 서킷 · 2세트", "strength", 6, 2, 12),
          ("마무리 러닝머신 10분", "cardio", 10),
          ("전신 스트레칭 12분", "stretching", 12)]),
}

# ── 그 밖의 운동 ───────────────────────────────────────────────────────────
# {몇 주 전: (요일, (이름, 종류, 분))}
#
# `other` 는 목표가 없는 나머지 운동이다. 유형이 넷인데 데모에는 셋뿐이라, 유형별
# 분해 화면에서 `기타` 칸이 늘 0 이었다 — 그 칸이 실제로 동작하는지 시연에서 볼 수
# 없었다. 주말에 한 번씩, 서로 다른 주에 둔다. (#1265)
OTHER_ACTIVITIES: dict[int, tuple[int, tuple[str, str, int]]] = {
    3: (5, ("북한산 등산 90분", "other", 90)),
    8: (6, ("탁구 40분", "other", 40)),
    14: (5, ("자전거 라이딩 60분", "other", 60)),
}

#: 분당 칼로리. 종류마다 다르다 — 걷기와 스트레칭을 같은 값으로 두면 주간 활동
#: 그래프의 스택이 실제 운동 강도와 어긋난다.
#:
#: 값은 앱·백엔드의 추정표와 **같아야 한다**(`_estimateCalories`,
#: `exercise_service._KCAL_PER_MIN`). 예전에는 여기만 7.5·5 로 낮아, 데모의 30분
#: 유산소는 225kcal 인데 같은 운동을 회원이 직접 기록하면 270kcal 이 나왔다.
#: 같은 사람의 같은 운동이 기록 경로에 따라 다른 숫자가 되는 셈이다. (#997)
# `other` 는 목표가 없는 나머지 운동(탁구·등산 같은 것)이다. 화면의
# 그래프에는 그리지 않고 분 수만 적는다.
KCAL_PER_MIN = {"cardio": 9, "strength": 6, "stretching": 3, "other": 5}

# ── 주별 이야기 ────────────────────────────────────────────────────────────
# 12주를 7가지 주로 돌려 채운다. 예전에는 주마다 계수 하나를 곱해 흔들었는데,
# 그러면 12주 내내 나트륨은 늘 초과하고 칼로리는 늘 목표 안이었다. 사람은 그렇게
# 살지 않는다 — 회식이 몰린 주는 칼로리도 당류도 같이 넘고, 코칭이 먹힌 주는
# 나트륨이 목표 안으로 들어온다. 그래서 계수가 아니라 **그 주에 뭘 먹었는지** 로
# 적는다.
#
# 값은 요일(월→일)마다 (아침, 점심, 저녁, 간식). None 은 그 끼니를 기록하지 않은
# 것이고, 요일 전체가 None 이면 하루를 통째로 비운다 — "기록이 없는 날" 도 데모에
# 남아 있어야 그 빈 화면이 맞게 동작하는지 볼 수 있다.
B_OAT, B_YOG, B_EGG = (
    "breakfast-oatmeal-banana",
    "breakfast-greek-yogurt-nuts",
    "breakfast-egg-strawberry",
)
# 짬뽕(3,200mg)은 **오늘 하루**에만 쓴다. 한 끼로 하루 나트륨을 다 쓰는 끼니라,
# 격자에 섞으면 그날의 나트륨÷칼로리가 2 를 넘어 `seed_clients.dart` 가 지키라고
# 적어 둔 1.0~1.5 를 깬다. 오늘의 예외라는 점이 코칭 알림의 근거이기도 하다.
L_SAL, L_BIB, L_JJA, L_DOE = (
    "lunch-chicken-salad", "lunch-bibimbap", "lunch-jjamppong", "lunch-doenjang-rice",
)
D_SLM, D_DOE, D_SAL, D_SAM = (
    "dinner-salmon-brown-rice", "dinner-doenjang-rice",
    "dinner-chicken-salad-sweet-potato", "dinner-samgyeopsal",
)
S_NUT, S_CAK = "snack-coffee-nuts", "snack-cake-latte"

WEEK_STORIES: list[tuple[str, list[list[str | None] | None], dict[int, int]]] = [
    # (한 줄 설명, 요일별 끼니, 요일별로 못 한 루틴 항목 수)
    (
        "평소의 한 주 — 국물이 잦지만 기록은 성실하다.",
        [
            [B_YOG, L_SAL, D_SLM, None],
            [B_OAT, L_DOE, D_SAL, S_NUT],
            [B_EGG, L_BIB, D_DOE, None],
            [B_YOG, L_SAL, D_SLM, S_NUT],
            [B_OAT, L_BIB, D_DOE, None],
            [B_EGG, L_DOE, D_SAL, S_NUT],
            [B_YOG, L_DOE, D_SLM, None],
        ],
        # 화·목이 낮다. 트레이너 스레드에서 김민수가 "화요일이랑 목요일이 야근이
        # 많아요" 라고 답하는데, 이행률이 그 요일에 떨어져 있지 않으면 대화가 화면의
        # 숫자와 어긋난다(`seed_clients.dart` 의 chat).
        {1: 1, 3: 1},
    ),
    (
        "가볍게 간 한 주 — 세 지표가 모두 목표 안에 든다.",
        [
            [B_YOG, L_SAL, D_SLM, None],
            [B_YOG, L_SAL, D_SAL, S_NUT],
            [B_OAT, L_BIB, D_SLM, None],
            [B_EGG, L_SAL, D_SAL, S_NUT],
            [B_YOG, L_BIB, D_SLM, None],
            [B_OAT, L_SAL, D_SAL, None],
            [B_EGG, L_SAL, D_SLM, S_NUT],
        ],
        {},
    ),
    (
        "회식이 몰린 주 — 칼로리와 당류가 함께 목표를 넘는다.",
        [
            [B_OAT, L_DOE, D_SAM, S_CAK],
            [B_EGG, L_DOE, D_SAL, S_CAK],
            [B_YOG, L_BIB, D_SAM, None],
            [B_OAT, L_BIB, D_DOE, S_CAK],
            [B_EGG, L_DOE, D_SAM, S_CAK],
            [B_OAT, L_BIB, D_SAL, S_CAK],
            [B_YOG, L_SAL, D_SLM, None],
        ],
        {1: 2, 3: 2, 4: 1, 5: 2},
    ),
    (
        "코칭이 먹힌 주 — 국물을 줄여 나트륨이 목표 안으로 들어온다.",
        [
            [B_YOG, L_SAL, D_SLM, None],
            [B_OAT, L_SAL, D_SAL, S_NUT],
            [B_EGG, L_SAL, D_SLM, None],
            [B_YOG, L_BIB, D_SAL, S_NUT],
            [B_OAT, L_SAL, D_SLM, None],
            [B_EGG, L_SAL, D_SAL, S_NUT],
            [B_YOG, L_SAL, D_SLM, None],
        ],
        {5: 1},
    ),
    (
        "평범한 한 주 — 구내식당 국물이 나트륨을 밀어 올린다.",
        [
            [B_OAT, L_DOE, D_SLM, None],
            [B_EGG, L_BIB, D_DOE, S_NUT],
            [B_YOG, L_DOE, D_SAL, None],
            [B_OAT, L_DOE, D_SLM, S_NUT],
            [B_EGG, L_BIB, D_DOE, None],
            [B_YOG, L_DOE, D_SAL, S_NUT],
            [B_OAT, L_SAL, D_SLM, None],
        ],
        {1: 1, 6: 1},
    ),
    (
        "야근이 많던 주 — 늦은 저녁은 기록이 비어 있다.",
        [
            [B_YOG, L_DOE, D_SLM, None],
            [B_OAT, L_DOE, None, S_NUT],
            [B_EGG, L_BIB, D_DOE, None],
            [B_YOG, L_DOE, None, S_NUT],
            [B_OAT, L_SAL, D_SLM, None],
            [B_EGG, L_BIB, D_SAL, None],
            [B_YOG, L_SAL, D_SLM, S_NUT],
        ],
        {1: 2, 3: 1, 4: 1},
    ),
    (
        "기록을 막 시작한 주 — 아예 빠진 날이 있다.",
        [
            [B_OAT, L_BIB, D_DOE, None],
            None,
            [B_EGG, L_DOE, D_SLM, None],
            [B_YOG, L_DOE, None, None],
            None,
            [B_OAT, L_BIB, D_SAL, S_NUT],
            [B_EGG, L_SAL, D_SLM, None],
        ],
        {0: 1, 1: 1, 3: 2, 4: 1, 5: 2, 6: 1},
    ),
]

# ── 큐레이션 사흘 ──────────────────────────────────────────────────────────
# 시연에 쓰는 오늘·어제·그제. 주 격자 위를 덮는다.
#
# 어제는 약속이 있던 날 — 하루 합이 2,380kcal · 2,261mg · 63.0g 으로 칼로리와
# 당류가 목표(2,000kcal · 50g)를 넘는다. 목표선과 초과 색이 실제로 동작하는지
# 시연에서 눈으로 확인하려면 넘긴 날이 하나는 있어야 하고, **어제**여야 데모를
# 여는 날이 언제든 항상 화면에 들어온다. 오늘은 점심 짬뽕 한 그릇이 나트륨을 다
# 쓴 하루다(3,428mg) — 오늘 코칭 알림의 근거가 그 조합이다.
#
# 어제는 **스트레칭을 하나 한 날**이다. 오늘 PT 가 근력만이라, 어제까지 스트레칭이
# 하나도 없으면 이번 주 운동 현황에서 스트레칭 링만 늘 0 으로 남아 세 링이 함께
# 도는 화면을 시연에서 보여 줄 수 없다. 배정 루틴 목록(`ROUTINES`)에 이미 있는
# `어깨 관절 보호 스트레칭 8분` 을 쓴다 — 화면들이 그 목록 하나를 함께 읽으므로
# 없는 운동을 새로 지어내지 않는다. 못 한 `하체 스트레칭` 은 그대로 남긴다:
# 이행률이 100% 가 아닌 날이 하나는 있어야 목표 대비 화면이 동작하는 것을 볼 수 있다.
#
# 오늘 PT 는 **근력만** 이다. 사용자앱의 `오늘 완료한 PT` 카드가 근력 종목을 줄로
# 세우므로, 여기에 유산소·스트레칭을 얹으면 `운동 현황 · 오늘` 에는 있는데 PT 카드에는
# 없는 운동 시간이 생긴다 — 화면상 출처가 없는 숫자다. 오늘의 마무리 유산소·스트레칭은
# AI 추천 개인운동(`ROUTINES`)이 아직 할 것으로 들고 있다.
#
# `id` 를 못 박은 끼니는 시연 중 화면에서 지목하는 행이라 값이 고정이어야 한다.
RECENT: list[dict] = [
    {
        "offset": 0,
        "label": "PT 세션 · 트레이너 지도",
        "pt": True,
        "clientFeedback": "무릎이 좀 당겼지만 트레이너님 덕분에 잘 마쳤어요 😊",
        "trainerNote": "무릎 가동범위 체크 필요. 다음 세션 중량 조절 예정.",
        "dayMessage": "점심 짬뽕으로 오늘 나트륨 섭취가 많았어요. 저녁은 양념을 줄인 채소와 단백질 위주로 구성해 보세요.",
        # 근력 한 줄은 **세트 · 횟수 · 중량** 순으로 적는다 — 트레이너 웹의 PT
        # 프로그램 줄(`3세트 · 12회 · 80kg`)과 사용자앱 운동 기록 줄이 이미 그
        # 순서다. 예전에는 이름에 중량과 세트만 달려(`벤치프레스 40kg · 4세트`)
        # 사용자앱 `오늘 완료한 PT` 에 몇 회를 했는지가 아예 없었고, 트레이너가
        # 보는 같은 세션에는 있었다.
        #
        # 플랭크는 버티는 운동이라 횟수가 없다 — 한 세트에 얼마나 버텼는지가
        # 값이고, 그 초는 `holdSeconds` 칸에 든다(#1969). 칸이 없던 동안에는
        # 이름에 적을 수밖에 없었다.
        "exercises": [
            ("벤치프레스 4세트 · 10회 · 40kg", "strength", 12, True, 4, 10),
            ("덤벨 숄더프레스 4세트 · 12회 · 10kg", "strength", 10, True, 4, 12),
            ("랫풀다운 4세트 · 12회 · 45kg", "strength", 12, True, 4, 12),
            ("플랭크", "strength", 6, True, 3, None, 60),
        ],
        "meals": [
            (B_EGG, "seed-diet-breakfast", "08:20",
             "단백질과 식이섬유의 깔끔한 조합으로, 소금 간과 기름만 조절하면 혈당과 혈압 모두 잡는 우수한 식단입니다."),
            (L_JJA, "seed-diet-lunch", "12:40",
             "정제 면과 높은 나트륨으로 혈압·혈당 부담이 매우 크니, 국물은 남기고 야채 위주로 드시는 것이 좋습니다."),
            (S_NUT, "seed-diet-snack", "15:30",
             "당류와 칼로리가 낮고 견과류의 건강한 지방이 채워져 완벽한 간식입니다."),
        ],
    },
    {
        "offset": 1,
        "label": "AI 개인운동",
        "pt": False,
        "clientFeedback": "하체 스트레칭은 시간이 없어서 못 했어요",
        "trainerNote": "",
        "dayMessage": "약속이 있어 칼로리와 당류가 목표를 넘은 하루예요. 오늘은 가볍게 시작해 보세요.",
        "exercises": [
            ("저강도 유산소 (걷기) 30분", "cardio", 30, True),
            ("코어 강화 10분", "strength", 10, True, 3, 15),
            ("어깨 관절 보호 스트레칭 8분", "stretching", 8, True),
            ("하체 스트레칭 15분", "stretching", 15, False),
        ],
        "meals": [
            (B_OAT, "seed-diet-yesterday-breakfast", "08:10",
             "오트밀로 식이섬유를 챙겼어요. 바나나가 들어가 당류는 다소 높은 편이에요."),
            (L_BIB, "seed-diet-yesterday-lunch", "12:30",
             "야채가 풍부한 비빔밥이에요. 고추장을 줄이면 나트륨을 더 조절할 수 있어요."),
            (D_SAM, "seed-diet-yesterday-dinner", None, None),
            (S_CAK, "seed-diet-yesterday-snack", None, None),
        ],
    },
    {
        "offset": 2,
        "label": "AI 개인운동",
        "pt": False,
        "clientFeedback": "오늘은 다 했어요! 뿌듯해요 💪",
        "trainerNote": "",
        "dayMessage": "연어와 현미밥으로 탄단지 균형을 잘 맞췄어요.",
        "exercises": [
            ("저강도 유산소 (걷기) 30분", "cardio", 30, True),
            ("코어 강화 10분", "strength", 10, True, 3, 15),
            ("하체 스트레칭 15분", "stretching", 15, True),
        ],
        "meals": [
            (B_YOG, "seed-diet-two-days-ago-breakfast", "08:35",
             "그릭 요거트의 단백질과 견과류의 불포화지방을 고르게 섭취했어요."),
            (L_BIB, "seed-diet-two-days-ago-lunch", "12:20",
             "야채가 풍부한 비빔밥이에요. 고추장을 줄이면 나트륨을 더 조절할 수 있어요."),
            (D_SLM, "seed-diet-two-days-ago-dinner", "18:50",
             "연어의 지방과 현미밥의 복합 탄수화물 조합이 좋아요."),
        ],
    },
]


def _round1(value: float) -> float:
    """당류·탄단지는 소수 한 자리. 부동소수 찌꺼기가 JSON 에 남지 않게 자른다."""
    return round(value + 0.0, 1)


def _meal_entry(
    meal_id: str,
    *,
    row_id: str | None = None,
    time_label: str | None = None,
    ai_comment: str | None = None,
) -> dict:
    entry: dict = {"meal": meal_id}
    if row_id:
        entry["id"] = row_id
    if time_label:
        entry["timeLabel"] = time_label
    if ai_comment:
        entry["aiComment"] = ai_comment
    return entry


def _exercise(
    name: str,
    kind: str,
    minutes: int,
    done: bool,
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
) -> dict:
    entry = {
        "name": name,
        "type": kind,
        "minutes": minutes,
        "calories": round(minutes * KCAL_PER_MIN[kind]),
        "done": done,
    }
    # 근력만 세트·횟수를 갖는다. 유산소·스트레칭·기타는 분이 곧 값이다.
    if sets is not None:
        entry["sets"] = sets
    if reps is not None:
        entry["reps"] = reps
    # 버티는 운동은 회가 아니라 초로 잰다(#1969). `reps` 와 한 자리를 나눠
    # 쓰므로 한 줄이 둘을 함께 들지 않는다 — 담을 칸이 없던 동안 홀드는
    # `플랭크 3세트 · 60초` 처럼 **이름에** 적혀 어떤 집계에도 잡히지 않았다.
    if hold_seconds is not None:
        entry["holdSeconds"] = hold_seconds
    return entry


def _grid_day(
    weeks_ago: int, weekday: int, plan: list[str | None], skipped: int
) -> dict:
    """주 격자의 하루. 그 자리에 PT 가 잡혀 있으면 PT 날이 된다.

    PT 날은 자율 운동 대신 그날 실제로 한 운동이 들어가고, 라벨·피드백·메모가
    함께 붙는다. 끼니는 그 주의 계획을 그대로 쓴다 — PT 를 받았다고 먹은 것이
    달라지지는 않는다.
    """
    meals = [_meal_entry(meal) for meal in plan if meal is not None]
    session = PT_SESSIONS.get(weeks_ago)
    if session is not None and session[0] == weekday:
        _, feedback, note, routine = session
        return {
            "weekday": weekday,
            "label": PT_LABEL,
            "pt": True,
            "clientFeedback": feedback,
            "trainerNote": note,
            # PT 날은 트레이너와 함께 끝까지 한다 — 못 한 항목을 두지 않는다.
            "exercises": [
                _exercise(item[0], item[1], item[2], True, *item[3:])
                for item in routine
            ],
            "meals": meals,
        }

    routine = ROUTINE[weekday]
    kept = len(routine) - skipped
    exercises = [
        _exercise(item[0], item[1], item[2], index < kept, *item[3:])
        for index, item in enumerate(routine)
    ]
    extra = OTHER_ACTIVITIES.get(weeks_ago)
    if extra is not None and extra[0] == weekday:
        name, kind, minutes = extra[1]
        exercises.append(_exercise(name, kind, minutes, True))
    return {
        "weekday": weekday,
        "label": "AI 개인운동",
        "pt": False,
        "exercises": exercises,
        "meals": meals,
    }


def build() -> dict:
    weeks = []
    for index in range(HISTORY_WEEKS):
        note, plans, skips = WEEK_STORIES[index % len(WEEK_STORIES)]
        days = []
        for weekday in range(7):
            plan = plans[weekday]
            session = PT_SESSIONS.get(index)
            if plan is None and not (session and session[0] == weekday):
                # 기록이 아예 없는 날. 루틴도 남기지 않는다 — 식단만 비고 운동만
                # 남으면 그날 화면이 반쪽으로 읽힌다.
                days.append({"weekday": weekday, "exercises": [], "meals": []})
                continue
            plan = plan or []
            days.append(
                _grid_day(index, weekday, plan, skips.get(weekday, 0))
            )
        weeks.append({"weeksAgo": index, "note": note, "days": days})

    recent = []
    for day in RECENT:
        recent.append({
            "offset": day["offset"],
            "label": day["label"],
            "pt": day["pt"],
            "clientFeedback": day["clientFeedback"],
            "trainerNote": day["trainerNote"],
            "dayMessage": day["dayMessage"],
            "exercises": [_exercise(*item) for item in day["exercises"]],
            "meals": [
                _meal_entry(meal, row_id=row_id, time_label=time_label, ai_comment=comment)
                for meal, row_id, time_label, comment in day["meals"]
            ],
        })

    return {
        "version": 1,
        "readme": (
            "김민수 데모 데이터의 단일 원본. 사용자앱·트레이너웹·백엔드가 이 파일만 "
            "읽는다. 날짜는 상대값이다 — weeks[].weeksAgo 는 이번 주 월요일에서 몇 주 "
            "거슬러 올라가는지, days[].weekday 는 월(0)~일(6). recent[].offset 은 "
            "오늘로부터의 일수이고 주 격자 위를 덮는다. 이행률은 exercises[].done "
            "개수에서 계산한다 — 퍼센트를 따로 적지 않는다."
        ),
        "member": {
            "name": "김민수",
            "userAppSeedId": "user-7d4e9a2c5f18",
            "trainerClientId": "seed-client-1",
        },
        "historyWeeks": HISTORY_WEEKS,
        "foods": {
            key: {
                "name": name,
                "amountG": AMOUNTS_G[key],
                "calories": calories,
                "sodiumMg": sodium,
                "sugarG": _round1(sugar),
                "carbsG": _round1(carbs),
                "proteinG": _round1(protein),
                "fatG": _round1(fat),
            }
            for key, (name, calories, sodium, sugar, carbs, protein, fat) in FOODS.items()
        },
        "meals": {
            key: {
                "mealType": meal_type,
                "timeLabel": time_label,
                "photoAsset": photo,
                "aiComment": comment,
                "foods": foods,
            }
            for key, (meal_type, time_label, photo, comment, foods) in MEALS.items()
        },
        "recent": recent,
        "weeks": weeks,
        "routines": [dict(routine) for routine in ROUTINES],
    }


_DART_HEADER = '''// GENERATED — 손으로 고치지 말 것.
//
// `python3 tool/gen_demo_fixture.py` 가
// `shared/demo_fixture/assets/kim_minsu.json` 과 함께 만든다. 고칠 값은 그 JSON 에
// 있고, 두 파일이 어긋나면 패키지 테스트가 잡는다.

/// 김민수 데모 픽스처의 JSON 원문.
const String kimMinsuFixtureJson = r\'\'\'
'''


def main() -> None:
    payload = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
    for path in (OUT, OUT_BACKEND):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload, encoding="utf-8")
        print(f"wrote {path}")

    # raw 문자열(r''')로 감싼다 — JSON 에 백슬래시 이스케이프가 들어와도 Dart 가 다시
    # 해석하지 않는다. JSON 은 작은따옴표 세 개를 만들 수 없어(문자열 값은 큰따옴표로
    # 이스케이프된다) 구분자와 부딪히지 않는다.
    assert "'''" not in payload, "픽스처에 ''' 이 들어가면 raw 문자열이 깨진다"
    OUT_DART.parent.mkdir(parents=True, exist_ok=True)
    OUT_DART.write_text(_DART_HEADER + payload + "''';\n", encoding="utf-8")
    print(f"wrote {OUT_DART}")


if __name__ == "__main__":
    main()
