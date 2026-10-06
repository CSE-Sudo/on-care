"""홈 AI 추천 식단(GET /diet/recommendations).

핵심 계약 세 가지를 고정한다:
1. 어떤 경우에도 카드 수가 줄지 않는다(화면이 흔들리면 안 된다).
2. 근거가 없으면 결과가 정확히 현재 홈 화면 순서(DEFAULT_ORDER)다.
3. 나트륨 과다 같은 신호가 있으면 그에 맞는 요리가 앞으로 온다.

LLM 은 붙이지 않고(=use_llm=False 또는 monkeypatch) 결정론적으로 검증한다. 실 Gemini
호출은 CI 에 키가 없어 재현이 안 되고, 여기서 보려는 건 LLM 품질이 아니라 계약이다.
"""
from __future__ import annotations

import threading
import time
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import delete

from app.core import clock
from app.data.meal_catalog import CATALOG, DEFAULT_ORDER, RECOMMENDATION_COUNT
from app.services import diet_recommendation_service as svc


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    return client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]


def _make_high_sodium_member(db_session) -> tuple:
    """나트륨 과다 신호가 확실히 뜨는 회원을 만든다. (user, email) 반환.

    시드 사용자를 쓰면 그 사용자의 최근 식단 유무에 따라 신호가 안 뜰 수 있고, 그러면
    서비스가 LLM 경로를 아예 타지 않아 폴백 계약이 검증되지 않은 채 통과한다.

    나트륨 신호만 뜨도록 나머지는 평범한 하루로 맞춘다. 칼로리를 너무 낮게 넣으면
    calorie_low 신호가 같이 떠서 다른 요리가 끼어든다(그건 그것대로 옳은 동작).
    """
    from app.core.security import hash_password
    from app.models.models import DietEntry, User

    email = f"rec-sodium-{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email, name="나트륨 과다",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.commit()

    today = clock.today()
    for offset in range(svc.LOOKBACK_DAYS):
        day = (today - timedelta(days=offset)).isoformat()
        for meal, cal, sodium in (
            ("breakfast", 450, 800), ("lunch", 700, 1100), ("dinner", 650, 950)
        ):
            db_session.add(
                DietEntry(
                    id=f"diet-{uuid.uuid4().hex[:12]}", user_id=user.id, date=day,
                    meal_type=meal, foods_json="[]", total_calories=cal,
                    sodium_mg=sodium, sugar_g=5.0, protein_g=25.0,
                )
            )
    db_session.commit()
    return user, email


def _cleanup_member(db_session, user) -> None:
    from app.models.models import DietEntry, User

    db_session.execute(delete(DietEntry).where(DietEntry.user_id == user.id))
    db_session.execute(delete(User).where(User.id == user.id))
    db_session.commit()


@pytest.fixture
def member_token(client) -> str:
    """로그인 가능한 시드 회원.

    user-7d4e9a2c5f18(minsu)는 hashed_password 가 빈 값이라 로그인 계정이 아니다(데모 폴백
    전용 신원). 시드가 비밀번호까지 만들어 주는 회원을 쓴다.
    """
    return client.post(
        "/v1/auth/login", data={"username": "sungho@oncare.com", "password": "oncare123"}
    ).json()["access_token"]


@pytest.fixture(autouse=True)
def _clear_cache():
    svc.clear_cache()
    yield
    svc.clear_cache()


# ─────────────────────────────────────────────────────── 순수 로직(DB 불필요) ──


def test_catalog_keys_are_unique_and_default_order_matches_catalog():
    keys = [i.key for i in CATALOG]
    assert len(keys) == len(set(keys))
    assert DEFAULT_ORDER == tuple(keys)
    assert RECOMMENDATION_COUNT == len(keys)


def test_catalog_good_for_only_uses_signals_that_are_actually_generated():
    """카탈로그의 `good_for` 는 build_context 가 만드는 신호의 부분집합이어야 한다.

    생성되지 않는 신호를 적어 두면 점수에 영영 반영되지 않으면서 읽는 사람만 헷갈린다
    (실제로 `fiber_low` 가 그랬다 — 식이섬유는 DietEntry 에 컬럼이 없어 신호를 만들 수
    없다). 신호를 늘릴 때 이 테스트가 짝을 맞추도록 강제한다.
    """
    generated = {
        "sodium_high", "sugar_high", "calorie_high", "calorie_low", "protein_low",
    }
    used = {signal for item in CATALOG for signal in item.good_for}
    assert used <= generated, f"생성되지 않는 신호: {sorted(used - generated)}"


def test_fingerprint_changes_when_displayed_numbers_change():
    """신호가 같아도 화면에 뜨는 수치가 바뀌면 캐시가 갈려야 한다.

    응답이 평균 나트륨을 그대로 노출하므로, 사용자가 식단을 새로 기록했는데 예전
    수치가 남아 있으면 방금 입력한 값과 어긋나 보인다.
    """
    def _ctx(avg_sodium: int) -> svc.NutritionContext:
        return svc.NutritionContext(
            days_with_data=3, avg_sodium_mg=avg_sodium, avg_sugar_g=10.0,
            avg_calories=1500, avg_protein_g=60.0, sodium_limit_mg=2000,
            sugar_limit_g=50, calorie_limit=2000, conditions="", goals="",
            signals=("sodium_high",),
        )

    assert _ctx(2850).fingerprint() != _ctx(2400).fingerprint()
    # 잔변동으로 캐시가 매번 깨지지는 않는다(100mg 단위로 뭉뚱그림).
    assert _ctx(2850).fingerprint() == _ctx(2870).fingerprint()


def test_rule_rank_without_signals_is_exactly_current_home_order():
    """근거가 없으면 지금 화면 그대로여야 한다 — 목업/신규 가입자 경로."""
    ctx = svc.NutritionContext(
        days_with_data=0, avg_sodium_mg=0, avg_sugar_g=0.0, avg_calories=0,
        avg_protein_g=0.0, sodium_limit_mg=2000, sugar_limit_g=50,
        calorie_limit=2000, conditions="", goals="", signals=(),
    )
    assert [i.key for i in svc._rule_rank(ctx)] == list(DEFAULT_ORDER)


def test_rule_rank_puts_low_sodium_dishes_first_when_sodium_is_high():
    ctx = svc.NutritionContext(
        days_with_data=3, avg_sodium_mg=2600, avg_sugar_g=10.0, avg_calories=1500,
        avg_protein_g=60.0, sodium_limit_mg=2000, sugar_limit_g=50,
        calorie_limit=2000, conditions="고혈압", goals="", signals=("sodium_high",),
    )
    ranked = [i.key for i in svc._rule_rank(ctx)]
    # good_for 에 sodium_high 가 있는 두 요리가 상위로 올라온다.
    assert set(ranked[:2]) == {"chicken_salad", "salmon"}
    assert len(ranked) == RECOMMENDATION_COUNT


def test_parse_llm_items_drops_hallucinated_keys_and_backfills():
    """카탈로그 밖 요리를 지어내도 버리고, 부족분은 규칙 순서로 채운다."""
    ctx = svc.NutritionContext(
        days_with_data=3, avg_sodium_mg=2600, avg_sugar_g=10.0, avg_calories=1500,
        avg_protein_g=60.0, sodium_limit_mg=2000, sugar_limit_g=50,
        calorie_limit=2000, conditions="", goals="", signals=("sodium_high",),
    )
    raw = """```json
    {"items": [
      {"key": "truffle_pasta", "reason_key": "sodium", "reason_text": "지어낸 요리"},
      {"key": "salmon", "reason_key": "omega", "reason_text": "나트륨 2,600mg"},
      {"key": "salmon", "reason_key": "omega"}
    ]}
    ```"""
    items = svc._parse_llm_items(raw, ctx)
    keys = [i.key for i in items]

    assert "truffle_pasta" not in keys           # 카탈로그 밖 → 폐기
    assert keys[0] == "salmon"                   # 유효한 선택은 순서 유지
    assert len(keys) == len(set(keys))           # 중복 제거
    assert len(keys) == RECOMMENDATION_COUNT     # 폴백으로 5장 채움
    assert items[0].reason_text == "나트륨 2,600mg"


def test_parse_llm_items_rejects_unusable_output():
    ctx = svc.NutritionContext(
        days_with_data=1, avg_sodium_mg=2600, avg_sugar_g=0.0, avg_calories=0,
        avg_protein_g=0.0, sodium_limit_mg=2000, sugar_limit_g=50,
        calorie_limit=2000, conditions="", goals="", signals=("sodium_high",),
    )
    # ValueError 로 좁힌다. Exception 으로 두면 나중에 TypeError/AttributeError 가 나도
    # 통과해 버려 버그를 잡지 못한다(json.JSONDecodeError 도 ValueError 하위 클래스다).
    with pytest.raises(ValueError):
        svc._parse_llm_items('{"items": [{"key": "nope"}]}', ctx)
    with pytest.raises(ValueError):
        svc._parse_llm_items("not json at all", ctx)


def test_reason_key_always_comes_from_catalog_not_the_llm():
    """LLM 이 이유 코드를 골라도 무시한다.

    실측에서 LLM 은 순서는 잘 잡으면서 reason_key 를 본문과 어긋나게 골랐다.
    reason_key 는 reason_text 가 없을 때 화면에 뜨는 값이라 틀리면 오답이 보인다.
    """
    ctx = svc.NutritionContext(
        days_with_data=1, avg_sodium_mg=2600, avg_sugar_g=0.0, avg_calories=0,
        avg_protein_g=0.0, sodium_limit_mg=2000, sugar_limit_g=50,
        calorie_limit=2000, conditions="", goals="", signals=("sodium_high",),
    )
    # 유효한 다른 코드를 줘도, 지어낸 코드를 줘도 결과는 카탈로그 기본값이다.
    for supplied in ("fiber", "made_up_reason"):
        items = svc._parse_llm_items(
            '{"items": [{"key": "tofu", "reason_key": "%s"}]}' % supplied, ctx
        )
        assert items[0].key == "tofu"
        assert items[0].reason_key == "low_cal"


# ─────────────────────────────────────────────────────────── 엔드포인트(DB) ──


def test_endpoint_follows_the_shared_demo_fallback(client):
    """개발/스테이징에선 토큰 없이도 데모 사용자로 폴백한다(deps.get_current_user).

    이 엔드포인트만 다르게 굴지 않는다는 걸 고정한다. 운영(is_prod)에서는
    demo_fallback_enabled 가 꺼져 401 이 되며, 그 경계는 test_security 가 다룬다.
    """
    res = client.get("/v1/diet/recommendations?use_llm=false")
    assert res.status_code == 200
    assert len(res.json()["items"]) == RECOMMENDATION_COUNT


def test_endpoint_always_returns_full_card_set(client, member_token):
    res = client.get("/v1/diet/recommendations?use_llm=false", headers=_h(member_token))
    assert res.status_code == 200
    body = res.json()
    assert len(body["items"]) == RECOMMENDATION_COUNT
    assert all(i["key"] in DEFAULT_ORDER for i in body["items"])
    assert all(i["reason_key"] for i in body["items"])


def test_user_without_diet_history_gets_current_home_order(client, db_session):
    """신규 가입자 — 실 모드여도 화면이 지금과 같아야 한다."""
    from app.models.models import User
    from app.core.security import hash_password

    email = f"rec-empty-{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email, name="추천 테스트",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.commit()
    try:
        token = client.post(
            "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
        ).json()["access_token"]
        body = client.get(
            "/v1/diet/recommendations?use_llm=false", headers=_h(token)
        ).json()

        assert [i["key"] for i in body["items"]] == list(DEFAULT_ORDER)
        assert body["personalized"] is False
        assert body["basis"] is None
    finally:
        db_session.execute(delete(User).where(User.id == user.id))
        db_session.commit()


def test_high_sodium_history_surfaces_low_sodium_recommendation(client, db_session):
    """#275 수용 기준: 나트륨 과다 → 저염 추천이 근거와 함께 드러난다."""
    user, email = _make_high_sodium_member(db_session)
    try:
        token = _login(client, email)
        body = client.get(
            "/v1/diet/recommendations?use_llm=false", headers=_h(token)
        ).json()

        keys = [i["key"] for i in body["items"]]
        assert set(keys[:2]) == {"chicken_salad", "salmon"}
        assert body["personalized"] is True
        assert body["basis"] and "2,850mg" in body["basis"]  # 하루 합 800+1100+950
        assert "초과" in body["basis"]
        assert len(keys) == RECOMMENDATION_COUNT
    finally:
        _cleanup_member(db_session, user)


def test_llm_failure_degrades_to_rule_recommendations(client, db_session, monkeypatch):
    """LLM 이 죽어도 화면은 그대로 뜬다 — graceful degrade.

    신호가 확실히 뜨는 사용자를 직접 만든다. 시드 사용자를 쓰면 그 사용자에게 최근
    식단이 없을 때 서비스가 `_llm_items` 를 아예 호출하지 않고 곧장 fallback 을
    반환해, "LLM 이 죽어도 규칙으로 내려간다"는 계약이 검증되지 않은 채 통과한다.
    """
    calls: list[str] = []

    def _boom(ctx):
        calls.append("called")
        raise RuntimeError("Gemini down")

    monkeypatch.setattr(svc, "_llm_items", _boom)

    user, email = _make_high_sodium_member(db_session)
    try:
        token = _login(client, email)
        res = client.get("/v1/diet/recommendations", headers=_h(token))

        assert res.status_code == 200
        body = res.json()
        assert calls, "LLM 경로를 타지 않아 폴백이 검증되지 않았다"
        assert body["source"] == "rules"       # fallback 이 아니라 신호를 반영한 규칙 추천
        assert body["personalized"] is True
        assert len(body["items"]) == RECOMMENDATION_COUNT
        assert set(i["key"] for i in body["items"][:2]) == {"chicken_salad", "salmon"}
    finally:
        _cleanup_member(db_session, user)


def test_llm_saturation_falls_back_without_waiting(client, db_session, monkeypatch):
    """워커가 꽉 차면 큐에서 기다리지 않고 즉시 규칙 폴백으로 내려간다.

    기다리면 어차피 타임아웃인데 요청 스레드만 붙잡혀, 부하 시 모든 응답이 느려진다.
    """
    monkeypatch.setattr(svc, "_llm_slots", threading.BoundedSemaphore(1))
    svc._llm_slots.acquire()  # 유일한 자리를 미리 점유 → 포화 상태 재현

    user, email = _make_high_sodium_member(db_session)
    try:
        token = _login(client, email)
        started = time.monotonic()
        body = client.get("/v1/diet/recommendations", headers=_h(token)).json()
        elapsed = time.monotonic() - started

        assert body["source"] == "rules"
        assert len(body["items"]) == RECOMMENDATION_COUNT
        # 타임아웃(6초)만큼 기다리지 않고 곧바로 폴백했는지
        assert elapsed < svc.LLM_TIMEOUT_SEC
    finally:
        _cleanup_member(db_session, user)


# ──────────────────────────────── 단백질 부족 신호는 실효 목표로 본다(#3270) ──


def _make_protein_member(
    db_session, *, protein_per_meal: float, weight_kg=None, daily_protein_g=None
):
    """끼니마다 단백질이 [protein_per_meal]g 인 사흘 기록과 프로필을 가진 회원.

    칼로리·나트륨·당류는 평범한 하루라 단백질 신호만 갈린다.
    """
    from app.core.security import hash_password
    from app.models.models import DietEntry, HealthProfile, User

    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}",
        email=f"rec-protein-{uuid.uuid4().hex[:8]}@example.com",
        name="단백질",
        hashed_password=hash_password("test-pw-1234"),
        role="member",
    )
    db_session.add(user)
    db_session.commit()
    if weight_kg is not None or daily_protein_g is not None:
        db_session.add(
            HealthProfile(
                user_id=user.id, weight_kg=weight_kg, daily_protein_g=daily_protein_g
            )
        )
    today = clock.today()
    for offset in range(svc.LOOKBACK_DAYS):
        day = (today - timedelta(days=offset)).isoformat()
        # 하루 1,700kcal — 칼로리 과다(목표의 90%)·부족(60%) 사이다.
        for meal, cal in (("breakfast", 500), ("lunch", 600), ("dinner", 600)):
            db_session.add(
                DietEntry(
                    id=f"diet-{uuid.uuid4().hex[:12]}", user_id=user.id, date=day,
                    meal_type=meal, foods_json="[]", total_calories=cal,
                    sodium_mg=500, sugar_g=5.0, protein_g=protein_per_meal,
                )
            )
    db_session.commit()
    return user


def _cleanup_protein_member(db_session, user) -> None:
    from app.models.models import HealthProfile

    db_session.execute(delete(HealthProfile).where(HealthProfile.user_id == user.id))
    db_session.commit()
    _cleanup_member(db_session, user)


def test_protein_low_uses_weight_when_no_personal_goal(db_session):
    """개인 목표 없이 체중만 있는 회원 — 체중 × 1.2g 의 60% 이하면 부족 신호다.

    80kg → 실효 96g, 문턱 57.6g. 하루 45g(끼니 15g × 3)은 부족이다. 예전에는
    개인 목표가 없으면 아예 보지 않아 이 회원에게 단백질 메뉴가 앞으로 오지 않았다.
    """
    user = _make_protein_member(db_session, protein_per_meal=15, weight_kg=80)
    try:
        ctx = svc.build_context(db_session, user.id)
        assert "protein_low" in ctx.signals
        ranked = [m.key for m in svc._rule_rank(ctx)]
        assert set(ranked[:2]) == {"chicken_salad", "salmon"}
    finally:
        _cleanup_protein_member(db_session, user)


def test_protein_low_uses_default_target_without_profile(db_session):
    """프로필도 체중도 없으면 60g 의 60%(36g) 이하가 부족이다."""
    low = _make_protein_member(db_session, protein_per_meal=10)  # 하루 30g
    enough = _make_protein_member(db_session, protein_per_meal=15)  # 하루 45g
    try:
        assert "protein_low" in svc.build_context(db_session, low.id).signals
        assert "protein_low" not in svc.build_context(db_session, enough.id).signals
    finally:
        _cleanup_protein_member(db_session, low)
        _cleanup_protein_member(db_session, enough)


def test_personal_protein_goal_still_comes_first(db_session):
    """개인 목표가 있으면 그것이 기준이다 — 기존 동작 그대로.

    하루 45g 은 체중(80kg → 96g)으로는 부족이지만, 개인 목표 50g 의 60%(30g)는 넘는다.
    """
    user = _make_protein_member(
        db_session, protein_per_meal=15, weight_kg=80, daily_protein_g=50
    )
    try:
        assert "protein_low" not in svc.build_context(db_session, user.id).signals
    finally:
        _cleanup_protein_member(db_session, user)


def test_protein_low_ratio_is_the_shared_coaching_threshold():
    """추천 식단의 단백질 문턱은 회원 코칭 문턱 한 곳(`diet_coach_inputs`)의 값이다."""
    from app.services import diet_coach_inputs, diet_period_advice, diet_week_advice
    from app.services import diet_all_advice, diet_trainer_analysis

    assert svc._PROTEIN_LOW_RATIO == diet_coach_inputs.COACH_PROTEIN_LOW_RATIO == 0.6
    assert diet_period_advice.PROTEIN_GAP_G == diet_coach_inputs.COACH_PROTEIN_GAP_G == 10
    # 트레이너 식단 분석의 "오늘 단백질 부족" 도 회원 앱과 같은 값이다.
    assert diet_trainer_analysis.PROTEIN_GAP_G == diet_coach_inputs.COACH_PROTEIN_GAP_G
    assert (
        diet_week_advice.PROTEIN_SHORT_RATIO
        == diet_coach_inputs.COACH_PROTEIN_SHORT_RATIO
        == 0.8
    )
    assert (
        diet_all_advice.PROTEIN_MET_RATIO == diet_coach_inputs.COACH_PROTEIN_MET_RATIO == 0.9
    )
