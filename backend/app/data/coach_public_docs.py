"""AI 코치의 공개 근거 문서 목록(RAG 공공 문서, `user_id IS NULL`). (#1652)

예전에는 이 파일이 **손으로 쓴 요약 8건**이었다. 공개 가이드라인의 요지를 문단
하나씩 적어 둔 것이라 출처를 댈 수 없었고, 8건 중 5건이 고혈압·당뇨 위험군 전제라
지금 타깃(PT 를 이용하는 회원과 이들을 관리하는 트레이너)과 어긋났다. 코치가 회원
에게 타깃과 무관한 근거로 말하는 셈이었다.

이제는 공개 문서의 **원문**에서 뽑은 텍스트를 적재한다. 파일은
`app/data/coach_docs/*.txt` 에 있고, 원본 PDF 에서 뽑는 경로는
`backend/scripts/extract_coach_docs.py` 다.

## 출처와 이용허락범위

두 자료 모두 공공누리 제4유형(출처표시 · 비상업적 이용만 · **변경금지**)이다. 이
프로젝트는 비상업이라 이용에 문제가 없고, 원문을 고치지 않는 것이 조건이다. 다만
그 문서를 근거로 코치가 문장을 만드는 것까지 변경금지에 걸리는지는 단정하기 어려워,
**답변에 출처를 함께 표시**하는 쪽으로 설계한다 — `title` 이 곧 그 출처 표기다.
`coach.chat.answer` 가 검색된 공공 문서의 `title` 을 근거 목록으로 돌려주고,
프롬프트 컨텍스트에도 같은 값이 붙는다.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

DOCS_DIR = Path(__file__).resolve().parent / "coach_docs"


@dataclass(frozen=True, slots=True)
class PublicDoc:
    """적재할 공개 문서 한 절."""

    #: `coach_docs/<file>` 의 파일 이름.
    file: str
    #: 답변에 그대로 나가는 출처 표기. 문서명·발행처·절을 한 줄에 담는다.
    title: str
    #: 도메인 필터 — diet|exercise|general. 도메인별 코치가 자기 domain 과
    #: general 을 검색한다.
    domain: str

    def read(self) -> str:
        return (DOCS_DIR / self.file).read_text(encoding="utf-8").strip()


#: 발행처 표기. 제목에 매번 적는 대신 여기서 이어 붙인다.
_PA = "한국인을 위한 신체활동 지침서(2023 개정판) · 보건복지부"
_KDRI = "2025 한국인 영양소 섭취기준 · 보건복지부/한국영양학회"

PUBLIC_DOCS: tuple[PublicDoc, ...] = (
    # --- 운동 ---
    PublicDoc("pa_adult.txt", f"{_PA} — 성인(19~64세) 신체활동 지침", "exercise"),
    PublicDoc("pa_older_adult.txt", f"{_PA} — 노인(65세 이상) 신체활동 지침", "exercise"),
    PublicDoc("pa_intensity.txt", f"{_PA} — 신체활동 강도의 기준과 측정방법", "exercise"),
    PublicDoc("pa_safety.txt", f"{_PA} — 안전하게 신체활동 실천하기", "exercise"),
    # 3개월 안에 그만두는 것을 붙잡는 것이 이 서비스의 문제 정의라, 지속 전략은
    # 운동 코치뿐 아니라 어느 대화에서든 근거가 된다.
    PublicDoc("pa_adherence.txt", f"{_PA} — 신체활동을 지속하기 위한 전략", "general"),
    # --- 식단 ---
    PublicDoc("kdri_energy.txt", f"{_KDRI} — 에너지", "diet"),
    PublicDoc("kdri_carbohydrate.txt", f"{_KDRI} — 탄수화물과 당류", "diet"),
    PublicDoc("kdri_fiber.txt", f"{_KDRI} — 식이섬유", "diet"),
    PublicDoc("kdri_protein.txt", f"{_KDRI} — 단백질과 아미노산", "diet"),
    PublicDoc("kdri_fat.txt", f"{_KDRI} — 지질과 지방산", "diet"),
    PublicDoc("kdri_water.txt", f"{_KDRI} — 수분", "general"),
)
