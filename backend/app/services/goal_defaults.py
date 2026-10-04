"""목표를 세우지 않은 회원의 기준선 — 서버 쪽 단일 원본. (#2906)

회원이 건강 프로필에 목표를 적지 않았을 때 대시보드·식단 코치·리포트·PT 관리
신호·운동 목표가 견주는 값이다. 예전에는 모듈마다 같은 숫자를 따로 적어 두고
"앱과 같다" 는 주석으로만 묶어, 한 곳만 고치면 같은 회원의 같은 날이 화면마다
다른 목표선으로 보였다.

원본 표는 `shared/oncare_rules/vectors/goal_defaults.json` 이다. 백엔드 이미지는
`backend/` 만 담으므로 값은 여기에 두고, `tests/test_shared_rules_vectors.py` 가
원본과 같은지 본다. 앱 쪽은 공용 패키지 `oncare_ui` 의 `kGoalDefault…` 가 같은 표를
들고 각자의 테스트로 대조한다.

근거: 나트륨은 WHO 성인 2,000mg 미만 권고, 당류는 첨가당 총열량 10% 이내
(2,000kcal 기준 50g), 운동은 WHO 신체활동 지침(주 150분 중강도 유산소·주 2회
이상 근력)을 앱이 재는 단위(분·세트)로 옮긴 값이다.
"""
from __future__ import annotations

DAILY_CALORIES = 2000
DAILY_SODIUM_MG = 2000
DAILY_SUGAR_G = 50
DAILY_CARBS_G = 275
#: 체중도 개인 목표도 없을 때의 단백질 목표. 체중이 있으면 체중 × [PROTEIN_G_PER_KG].
DAILY_PROTEIN_G = 60
PROTEIN_G_PER_KG = 1.2
DAILY_FAT_G = 55

#: 하루 소모 칼로리 목표. 회원이 매일 닿을 수 있는 선이다.
DAILY_BURN_KCAL = 300
WEEKLY_CARDIO_MINUTES = 150
#: 하루 3세트 × 7일.
WEEKLY_STRENGTH_SETS = 21
WEEKLY_FLEXIBILITY_MINUTES = 60
