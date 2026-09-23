"""공개 PDF → 코치 근거 문서 텍스트. (#1652)

AI 코치의 검색 근거(`coach_documents`, `user_id IS NULL`)는 손으로 쓴 요약 8건이었다.
공개 가이드라인의 요지를 문단 하나씩 적어 둔 것이라 출처를 댈 수 없었고, 8건 중 5건은
고혈압·당뇨 위험군 전제라 지금 타깃(PT 회원과 트레이너)과 어긋났다. 이 스크립트가
공개 문서의 **원문**을 받아 적재할 텍스트로 만든다.

원본 PDF 는 저장소에 담지 않는다(합쳐 16MB). 아래 경로에 받아 두고 이 스크립트를
돌리면, 뽑아낸 텍스트가 `app/data/coach_docs/*.txt` 로 떨어진다 — 커밋되는 것은 그쪽이다.

    backend/data/raw/신체활동지침서_2023.pdf
        한국인을 위한 신체활동 지침서(2023 개정판) · 보건복지부/한국건강증진개발원
        https://www.mohw.go.kr/board.es?act=view&bid=0019&list_no=1479208&mid=a10411010100
    backend/data/raw/KDRI_2025_국문요약본.pdf
        2025 한국인 영양소 섭취기준 국문 요약본 · 보건복지부/한국영양학회
        https://www.kns.or.kr/fileroom/fileroom_view.asp?idx=167&BoardID=Kdr

사용법(텍스트 추출에 poppler 의 `pdftotext` 가 필요하다):
    cd backend && python -m scripts.extract_coach_docs

## 무엇을 뽑고 무엇을 버리나

문서 전체가 아니라 **회원 코칭에 답이 되는 절**만 뽑는다. 비타민·무기질 권장량 표나
연구 방법론은 코치가 인용할 자리가 없고, 청크만 늘려 정작 필요한 절의 검색 순위를
떨어뜨린다. 절의 경계는 쪽번호가 아니라 제목 문구로 잡는다 — 판형이 바뀌어도 같은
제목이면 따라간다.

머리말·꼬리말(각 쪽에 반복되는 문서 제목과 쪽번호)은 걷어 낸다. 청킹이 문장 단위라
반복 문구가 남으면 청크마다 같은 말이 섞여 검색이 둔해진다.

## 라이선스

두 자료 모두 공공누리 제4유형(출처표시·비상업적 이용만·**변경금지**)이다. 이
프로젝트는 비상업이므로 이용에 문제가 없고, 원문을 고치지 않는 것이 조건이다.
여기서 하는 일은 서식 제거와 절 단위 발췌뿐이고, 문장은 손대지 않는다. 출처는
`app/data/coach_public_docs.py` 의 메타에 남아 답변에 함께 표시된다.
"""
from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "app" / "data" / "coach_docs"

#: 각 쪽에 반복되는 머리말·꼬리말. 본문과 구분되는 고정 문구만 적는다.
_RUNNING = (
    "한국인을 위한 신체활동 지침서",
    "2025 한국인 영양소 섭취기준",
)


def _pdf_text(pdf: pathlib.Path) -> str:
    if shutil.which("pdftotext") is None:
        raise SystemExit(
            "pdftotext 가 없습니다. poppler 를 설치하세요(brew install poppler)."
        )
    # -layout 은 표의 열이 한 줄로 뭉개지는 것을 막는다. 본문 문장은 그대로다.
    result = subprocess.run(
        ["pdftotext", "-layout", str(pdf), "-"],
        capture_output=True,
        check=True,
    )
    return result.stdout.decode("utf-8", errors="replace")


def _clean(text: str) -> str:
    lines: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line in _RUNNING:
            continue
        # 홀로 선 쪽번호.
        if line.isdigit():
            continue
        # 그림·표 제목(본문이 아니라 도판의 이름이다). 그림 자체는 텍스트로
        # 넘어오지 않으므로 제목만 남으면 청크에 맥락 없는 한 줄이 섞인다.
        if line.startswith("❙"):
            continue
        # 절 머리말("1-1. 에너지")도 각 쪽에 반복된다. 본문 첫 줄의 같은 제목은
        # 뒤에 문장이 이어지므로 걸리지 않는다.
        if re.fullmatch(r"\d-\d+(-\d+)?\.\s*\S{0,12}", line):
            continue
        lines.append(line)

    body = "\n".join(lines)
    # 줄바꿈으로 끊긴 문장을 잇는다. 문장이 끝난 자리(마침표·물음표)는 그대로 둔다 —
    # 청킹이 문장 단위라 그 경계가 곧 청크 경계다.
    body = re.sub(r"(?<![.!?:•])\n(?![•·※\-\d])", " ", body)
    body = re.sub(r"[ \t]{2,}", " ", body)
    return re.sub(r"\n{2,}", "\n", body).strip()


def _slice(text: str, start: str, end: str) -> str:
    """[start] 가 걸리는 곳부터 [end] 직전까지. 못 찾으면 빈 문자열.

    경계는 줄머리에 고정한 정규식으로 잡는다. 제목만으로 찾으면 목차가 먼저
    걸린다 — 목차에도 같은 제목이 있고, 그쪽이 문서 앞에 있다.
    """
    head = re.search(start, text, re.M)
    if head is None:
        return ""
    tail = re.search(end, text[head.start():], re.M)
    return text[head.start() : head.start() + tail.start()] if tail else text[head.start():]


#: (파일 이름, 원본 PDF, 시작 정규식, 끝 정규식)
SECTIONS: tuple[tuple[str, str, str, str], ...] = (
    # --- 한국인을 위한 신체활동 지침서(2023 개정판) ---
    # 강도 어휘가 앱의 `가벼움·보통·높음` 과 회원이 느끼는 강도를 잇는 자리다.
    (
        "pa_intensity.txt", "신체활동지침서_2023.pdf",
        r"^신체활동 강도의 기준과 측정방법 본 지침", r"^‘신체활동의 부족",
    ),
    # 성인·노인 지침이 `주 150분·근력 주 2일` 권고의 국내 공식 근거다.
    (
        "pa_adult.txt", "신체활동지침서_2023.pdf",
        r"^생애주기별 신체활동 지침 성인 \(만 19~64세\)", r"^신체활동 실천사례",
    ),
    (
        "pa_older_adult.txt", "신체활동지침서_2023.pdf",
        r"^생애주기별 신체활동 지침 노인 \(만 65세 이상\)", r"^신체활동 실천사례",
    ),
    (
        "pa_safety.txt", "신체활동지침서_2023.pdf",
        r"^안전하게 신체활동 실천하기 신체활동에 참여할 때", r"^신체활동 예시별 강도표",
    ),
    # 지속 전략. 3개월 안에 63% 가 그만두는 것이 이 서비스가 붙잡으려는 문제다.
    (
        "pa_adherence.txt", "신체활동지침서_2023.pdf",
        r"② 계획 단계 < 장애 요소 극복하기 >", r"^신체활동 실천 일지",
    ),
    # --- 2025 한국인 영양소 섭취기준(국문 요약본) ---
    # 고혈압·당뇨 특화가 아닌 일반 에너지·탄단지 기준이다. 비타민·무기질 절은
    # 빼 둔다 — 코치가 인용할 자리가 없고 청크만 늘려 검색을 둔하게 만든다.
    ("kdri_energy.txt", "KDRI_2025_국문요약본.pdf", r"^1-1 에너지 에너지는", r"참고문헌 [A-Z]"),
    ("kdri_carbohydrate.txt", "KDRI_2025_국문요약본.pdf", r"^1-2 탄수화물 탄수화물은", r"참고문헌 [A-Z]"),
    ("kdri_fiber.txt", "KDRI_2025_국문요약본.pdf", r"^1-3 식이섬유 식이섬유", r"참고문헌 [A-Z]"),
    ("kdri_protein.txt", "KDRI_2025_국문요약본.pdf", r"^1-4 단백질/아미노산 단백질은", r"참고문헌 [A-Z]"),
    ("kdri_fat.txt", "KDRI_2025_국문요약본.pdf", r"^1-5 지질/지방산 지질은", r"참고문헌 [A-Z]"),
    ("kdri_water.txt", "KDRI_2025_국문요약본.pdf", r"^1-6 수분 수분은", r"참고문헌 [A-Z]"),
)


def main() -> int:
    missing = {name for _, name, _, _ in SECTIONS if not (RAW / name).exists()}
    if missing:
        for name in sorted(missing):
            print(f"원본이 없습니다: {RAW / name}", file=sys.stderr)
        print(__doc__.split("사용법")[0].split("원본 PDF")[1], file=sys.stderr)
        return 1

    texts = {name: _clean(_pdf_text(RAW / name)) for _, name, _, _ in SECTIONS}

    OUT.mkdir(parents=True, exist_ok=True)
    failed = 0
    for out_name, pdf_name, start, end in SECTIONS:
        body = _slice(texts[pdf_name], start, end)
        if not body:
            print(f"!! 절을 찾지 못했습니다: {out_name} ({start!r})", file=sys.stderr)
            failed += 1
            continue
        (OUT / out_name).write_text(body + "\n", encoding="utf-8")
        print(f"{out_name}: {len(body):,}자")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
