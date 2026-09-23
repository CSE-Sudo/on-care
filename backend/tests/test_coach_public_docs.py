"""AI 코치의 공개 근거 문서. (#1652)

근거가 손으로 쓴 요약 8건이었고 그중 5건이 고혈압·당뇨 위험군 전제라, 코치가 지금
타깃(PT 회원과 트레이너)과 무관한 근거로 말했다. 여기서 지키는 것은 넷이다.

1. 근거는 공개 문서의 **원문**이고, 파일이 실제로 있다.
2. 제목이 곧 출처 표기다 — 답변에 그대로 나가므로 문서명과 발행처가 들어 있어야 한다.
3. 폐기된 고혈압·당뇨 전제 요약이 남아 있지 않다.
4. 문서 목록이 바뀌면 **이미 떠 있는 DB 도** 새 문서를 받는다.
"""
from __future__ import annotations

from app.data.coach_public_docs import PUBLIC_DOCS


def test_모든_문서가_파일로_있다():
    for doc in PUBLIC_DOCS:
        body = doc.read()
        assert len(body) > 300, f"{doc.file} 의 내용이 너무 짧다"


def test_제목이_출처_표기다():
    # `coach.chat.answer` 가 이 제목을 근거 목록으로 돌려주고 프롬프트에도 붙인다.
    for doc in PUBLIC_DOCS:
        assert "보건복지부" in doc.title, doc.title
        assert len(doc.title) <= 300  # CoachDocument.title 의 길이 제한


def test_도메인은_셋_중_하나다():
    assert {doc.domain for doc in PUBLIC_DOCS} <= {"diet", "exercise", "general"}
    # 식단·운동 코치가 각자 근거를 갖는다. 한쪽이 비면 그 코치는 일반론만 말한다.
    assert {"diet", "exercise"} <= {doc.domain for doc in PUBLIC_DOCS}


def test_폐기된_고혈압_당뇨_전제_요약이_없다():
    titles = [doc.title for doc in PUBLIC_DOCS]
    for gone in ("DASH 식단 개요", "고혈압과 운동", "당뇨와 운동", "당류 관리"):
        assert gone not in titles


def test_운동_권고_원문이_그대로_실린다():
    adult = next(doc for doc in PUBLIC_DOCS if doc.file == "pa_adult.txt")
    body = adult.read()
    # 지침서의 핵심 권고. 요약이 아니라 원문이라야 출처를 대고 인용할 수 있다.
    assert "중강도 유산소 신체활동을 일주일에 150-300분" in body
    assert "근력 운동을 일주일에 2일 이상" in body


def test_나트륨_당류_상한의_근거가_실린다():
    """앱이 식단을 나트륨·당류로 평가하는 근거. (#1652)

    대시보드 주간 점수와 식단 코칭 한 줄이 두 수치를 상한과 견주는데, 그 상한의
    근거가 DASH(고혈압 식이)뿐이었다. 같은 수치를 다루는 국내 기준을 원문으로 싣고
    코치가 그쪽을 인용하게 한다.
    """
    sodium = next(doc for doc in PUBLIC_DOCS if doc.file == "kdri_sodium.txt")
    assert sodium.domain == "diet"
    assert "만성질환위험감소섭취량" in sodium.read()

    carb = next(doc for doc in PUBLIC_DOCS if doc.file == "kdri_carbohydrate.txt")
    assert "첨가당" in carb.read()


def test_공개_문서_시드가_문서_교체를_따라간다(client, db_session, monkeypatch):
    """목록이 바뀌면 이미 적재된 공공 문서를 통째로 바꾼다.

    예전에는 공공 문서가 하나라도 있으면 건너뛰어, 근거를 바꿔도 이미 떠 있는 DB 는
    옛 문서를 그대로 들고 있었다.
    """
    from sqlalchemy import func, select

    from app.data.coach_public_docs import PublicDoc
    from app.db import init_db
    from app.models.models import CoachDocument

    def public_titles() -> set[str]:
        return set(
            db_session.scalars(
                select(CoachDocument.title).where(
                    CoachDocument.user_id.is_(None),
                    CoachDocument.source == init_db.PUBLIC_DOC_SOURCE,
                )
            ).all()
        )

    before = public_titles()
    assert before, "기동 시드가 공개 문서를 넣어야 한다"

    # 다시 불러도 그대로 — 같은 목록이면 임베딩을 다시 돌리지 않는다.
    init_db._seed_public_coach_docs()
    db_session.expire_all()
    assert public_titles() == before

    only_one = (
        PublicDoc("pa_adult.txt", "시험용 근거 문서 · 보건복지부", "exercise"),
    )
    monkeypatch.setattr(
        "app.data.coach_public_docs.PUBLIC_DOCS", only_one, raising=True
    )
    init_db._seed_public_coach_docs()
    db_session.expire_all()
    assert public_titles() == {"시험용 근거 문서 · 보건복지부"}

    # 원래 목록으로 되돌려 다음 시험에 영향이 없게 한다.
    monkeypatch.undo()
    init_db._seed_public_coach_docs()
    db_session.expire_all()
    assert public_titles() == before

    # 관리자가 직접 올린 공공 문서는 시드가 지우지 않는다 — 적재 경로가 다르다.
    uploaded = db_session.scalar(
        select(func.count())
        .select_from(CoachDocument)
        .where(
            CoachDocument.user_id.is_(None),
            CoachDocument.source != init_db.PUBLIC_DOC_SOURCE,
        )
    )
    init_db._seed_public_coach_docs()
    db_session.expire_all()
    assert db_session.scalar(
        select(func.count())
        .select_from(CoachDocument)
        .where(
            CoachDocument.user_id.is_(None),
            CoachDocument.source != init_db.PUBLIC_DOC_SOURCE,
        )
    ) == uploaded
