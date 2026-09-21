"""운동 종목 참조표 큐레이션 시드 — 식단의 `food_nutrients_seed` 와 같은 자리.

식단은 **무엇을 먹었는지**(인식기)와 **영양 수치**(공공 식품영양성분 DB)를 나눠
본다. 운동도 같게 나눈다 — **무엇을 했는지**(이름 해석)와 **단위체중당 소모**(이
표)다. 이름만 보고 칼로리를 지어내지 않으려면 종목별 계수가 어딘가에 있어야
한다. 여기가 그 자리다.

## 값의 정체 — 단위체중당 에너지 소비 계수

`met` 은 체중 1kg·1시간당 소모 kcal 에 해당하는 계수다(안정 상태 = 1.0). 실제
소모는 `met × 체중(kg) × 시간(h)` 으로 나온다 — **체중이 곱해져야 값이 사람마다
갈린다.** 지금 쓰던 유형별 고정 분당 kcal 은 이 자리에 체중이 없어서, 50kg 회원과
90kg 회원의 `유산소 30분` 이 같은 값으로 적혔다.

이 계수는 화면에 꺼내지 않는다(#1276) — 집계 축은 칼로리 하나다. 회원도 트레이너도
`5.0 MET` 를 읽을 이유가 없고, 중간 단위가 화면에 있으면 두 앱이 서로 다른 단위로
같은 운동을 부르게 된다.

## 출처

- 한국건강증진개발원 `보건소 모바일 헬스케어 운동`(공공데이터포털, 운동명 + METS
  376건). 국내에서 실제로 쓰이는 운동 이름과 계수라 이름 매칭이 가장 잘 붙는다.
  이용허락범위가 **KOGL 제4유형(출처표시·상업적 이용금지·변경금지)** 이므로 원본
  파일은 저장소에 담지 않는다 — 받아서 넣는 경로는
  `backend/scripts/import_exercise_catalog.py` 다.
- Compendium of Physical Activities (pacompendium.com). 국제 표준 계수로, 위
  데이터에 없는 종목을 메운다.

아래 목록은 두 자료를 **참고해 손으로 추린 대표값**이다. 식단 시드(43종)와 같은
성격 — 시딩만으로도 데모·오프라인에서 동작하게 하고, 운영에서는 위 임포트
스크립트로 전건을 얹는다. 계수를 임의로 바꾸지 않는다: 같은 종목이 자료마다 다르면
국내 자료를 따른다.

## 무엇을 담고 무엇을 담지 않나

회원이 실제로 적는 말을 담는다 — `러닝머신`, `랫풀다운`, `줄넘기` 같은 종목 이름
이다. `PT 하체날`, `오늘 운동` 처럼 종목이 아닌 말은 여기 없고, 이름 해석
(`exercise_catalog.resolver`)이 종목으로 접지 못하면 유형 표로 폴백한다.

`aliases` 는 같은 종목의 다른 표기다. 매칭기가 정규화 후 이름과 별칭을 같은
자격으로 보므로, `사이클`·`싸이클`·`실내자전거` 가 한 행을 가리킨다.

`isometric` 은 **버티는 운동인가** 다(#1969). 플랭크처럼 자세를 유지하는 종목은
한 세트를 몇 회가 아니라 몇 초로 재므로, 폼이 `횟수` 칸을 `초` 칸으로 바꿔
보여야 한다. 표시가 없으면 `False` 다 — 대부분의 종목은 회로 센다. 이 값은
**폼의 기본값**일 뿐이고, 표에 없는 자유 입력 이름도 있으므로 트레이너·회원이
폼에서 직접 바꿀 수 있다.
"""
from __future__ import annotations

from app.services import exercise_types

_CARDIO = exercise_types.CARDIO
_STRENGTH = exercise_types.STRENGTH
_STRETCHING = exercise_types.STRETCHING
_OTHER = exercise_types.OTHER

#: name, type, met, aliases, isometric(기본 False)
EXERCISE_CATALOG: list[dict] = [
    # --- 걷기·달리기 ---
    {"name": "걷기", "type": _CARDIO, "met": 3.5, "aliases": ["산책", "워킹", "walking"]},
    {"name": "빠르게 걷기", "type": _CARDIO, "met": 5.0, "aliases": ["파워워킹", "속보"]},
    {"name": "트레드밀 걷기", "type": _CARDIO, "met": 4.3, "aliases": ["워킹머신", "런닝머신 걷기"]},
    {"name": "달리기", "type": _CARDIO, "met": 8.3, "aliases": ["러닝", "running", "구보"]},
    {"name": "조깅", "type": _CARDIO, "met": 7.0, "aliases": ["가볍게 뛰기"]},
    {"name": "러닝머신", "type": _CARDIO, "met": 8.3, "aliases": ["런닝머신", "트레드밀", "treadmill"]},
    {"name": "계단 오르기", "type": _CARDIO, "met": 8.8, "aliases": ["계단운동", "스텝밀", "천국의 계단"]},
    {"name": "등산", "type": _CARDIO, "met": 6.0, "aliases": ["하이킹", "트레킹", "산행"]},
    # --- 자전거·유산소 기구 ---
    {"name": "자전거", "type": _CARDIO, "met": 6.8, "aliases": ["사이클", "싸이클", "라이딩", "cycling"]},
    {"name": "실내자전거", "type": _CARDIO, "met": 7.0, "aliases": ["헬스자전거", "고정식 자전거", "바이크"]},
    {"name": "스피닝", "type": _CARDIO, "met": 8.5, "aliases": ["spinning"]},
    {"name": "일립티컬", "type": _CARDIO, "met": 5.0, "aliases": ["엘립티컬", "크로스트레이너", "사이클론"]},
    {"name": "로잉머신", "type": _CARDIO, "met": 7.0, "aliases": ["로잉", "조정", "rowing"]},
    {"name": "줄넘기", "type": _CARDIO, "met": 11.8, "aliases": ["점프로프", "2단뛰기", "쌍줄넘기"]},
    {"name": "수영", "type": _CARDIO, "met": 5.8, "aliases": ["자유형", "접영", "배영", "평영", "swimming"]},
    {"name": "아쿠아로빅", "type": _CARDIO, "met": 5.3, "aliases": ["아쿠아", "수중운동"]},
    {"name": "에어로빅", "type": _CARDIO, "met": 7.3, "aliases": ["에어로빅스"]},
    {"name": "줌바", "type": _CARDIO, "met": 6.5, "aliases": ["zumba", "댄스운동"]},
    {"name": "버피", "type": _CARDIO, "met": 8.0, "aliases": ["버피테스트", "burpee"]},
    {"name": "서킷 트레이닝", "type": _CARDIO, "met": 8.0, "aliases": ["써킷", "크로스핏", "circuit"]},
    {"name": "인터벌 러닝", "type": _CARDIO, "met": 9.8, "aliases": ["인터벌", "hiit", "고강도 인터벌"]},
    # --- 근력 ---
    {"name": "웨이트 트레이닝", "type": _STRENGTH, "met": 5.0, "aliases": ["웨이트", "헬스", "근력운동", "머신운동"]},
    {"name": "스쿼트", "type": _STRENGTH, "met": 5.0, "aliases": ["squat", "바벨스쿼트", "고블릿스쿼트"]},
    {"name": "데드리프트", "type": _STRENGTH, "met": 6.0, "aliases": ["deadlift", "루마니안 데드리프트"]},
    {"name": "벤치프레스", "type": _STRENGTH, "met": 5.0, "aliases": ["벤치", "bench press", "체스트프레스"]},
    {"name": "숄더프레스", "type": _STRENGTH, "met": 5.0, "aliases": ["오버헤드프레스", "밀리터리프레스"]},
    {"name": "랫풀다운", "type": _STRENGTH, "met": 5.0, "aliases": ["랫풀", "lat pulldown"]},
    {"name": "레그프레스", "type": _STRENGTH, "met": 5.0, "aliases": ["leg press", "레그익스텐션", "레그컬"]},
    {"name": "런지", "type": _STRENGTH, "met": 4.0, "aliases": ["lunge", "워킹런지"]},
    {"name": "푸시업", "type": _STRENGTH, "met": 8.0, "aliases": ["팔굽혀펴기", "push up"]},
    {"name": "턱걸이", "type": _STRENGTH, "met": 8.0, "aliases": ["풀업", "친업", "pull up"]},
    {"name": "딥스", "type": _STRENGTH, "met": 8.0, "aliases": ["dips", "평행봉"]},
    {"name": "윗몸일으키기", "type": _STRENGTH, "met": 8.0, "aliases": ["싯업", "크런치", "복근운동"]},
    {"name": "플랭크", "type": _STRENGTH, "met": 3.8, "aliases": ["plank", "사이드플랭크"], "isometric": True},
    {"name": "케틀벨", "type": _STRENGTH, "met": 8.0, "aliases": ["케틀벨 스윙", "kettlebell"]},
    {"name": "맨몸운동", "type": _STRENGTH, "met": 3.8, "aliases": ["체조", "칼리스데닉스", "홈트"]},
    # --- 스트레칭·이완 ---
    {"name": "스트레칭", "type": _STRETCHING, "met": 2.3, "aliases": ["정적 스트레칭", "stretching", "유연성 운동"]},
    {"name": "요가", "type": _STRETCHING, "met": 2.5, "aliases": ["하타요가", "yoga"]},
    {"name": "필라테스", "type": _STRETCHING, "met": 3.0, "aliases": ["pilates", "기구필라테스"]},
    {"name": "폼롤러", "type": _STRETCHING, "met": 2.3, "aliases": ["폼롤링", "마사지볼"]},
    {"name": "태극권", "type": _STRETCHING, "met": 3.0, "aliases": ["기공", "타이치"]},
    # --- 구기·기타 종목 ---
    {"name": "배드민턴", "type": _OTHER, "met": 5.5, "aliases": ["badminton"]},
    {"name": "탁구", "type": _OTHER, "met": 4.0, "aliases": ["핑퐁", "table tennis"]},
    {"name": "테니스", "type": _OTHER, "met": 7.3, "aliases": ["tennis"]},
    {"name": "스쿼시", "type": _OTHER, "met": 7.3, "aliases": ["squash"]},
    {"name": "축구", "type": _OTHER, "met": 7.0, "aliases": ["풋살", "soccer"]},
    {"name": "농구", "type": _OTHER, "met": 6.5, "aliases": ["basketball"]},
    {"name": "배구", "type": _OTHER, "met": 4.0, "aliases": ["volleyball"]},
    {"name": "야구", "type": _OTHER, "met": 5.0, "aliases": ["소프트볼", "baseball"]},
    {"name": "볼링", "type": _OTHER, "met": 3.8, "aliases": ["bowling"]},
    {"name": "골프", "type": _OTHER, "met": 4.8, "aliases": ["golf", "스크린골프"]},
    {"name": "클라이밍", "type": _OTHER, "met": 8.0, "aliases": ["암벽등반", "볼더링", "climbing"]},
    {"name": "복싱", "type": _OTHER, "met": 7.8, "aliases": ["boxing", "샌드백"]},
    {"name": "킥복싱", "type": _OTHER, "met": 10.3, "aliases": ["무에타이"]},
    {"name": "태권도", "type": _OTHER, "met": 10.3, "aliases": ["유도", "합기도", "주짓수", "무술"]},
    {"name": "스케이팅", "type": _OTHER, "met": 7.0, "aliases": ["인라인", "롤러스케이트"]},
    {"name": "스키", "type": _OTHER, "met": 7.0, "aliases": ["스노보드", "보드"]},
    {"name": "댄스", "type": _OTHER, "met": 5.0, "aliases": ["방송댄스", "사교댄스", "dance"]},
]
