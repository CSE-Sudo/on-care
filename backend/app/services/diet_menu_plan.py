"""최근 4주 기록으로 만든 끼니별 추천 메뉴 리스트. (#2250)

식단 탭 `오늘` AI 맞춤 조언은 "다음 식사로 무엇을 먹을까" 를 이 리스트에서 고른다.
끼니를 기록할 때마다 AI 를 부르면 비용이 들고 같은 날에도 메뉴가 출렁이므로,
**AI 에게 한 번 받아 4주 동안 보관**한다(스케줄러 없이 조회할 때 필요하면 만든다).

리스트는 아침·점심·저녁 5개씩과 간식 3개다. 메뉴마다 추천 이유 태그가 하나 붙는다
(`저나트륨`·`고단백` …). `오늘` 조언이 "그 이유가 충족되면 다른 메뉴로" 바꾸려면
메뉴가 무엇을 채우려고 추천됐는지가 하나로 정해져 있어야 한다.

다시 만드는 때:
  * 리스트가 없을 때 — 기록이 없어도 목표·프로필로 만든다.
  * 만든 지 28일이 지났을 때.
  * 목표(건강 목표 칩·수치 목표)가 바뀌었을 때.
  * 기록이 7일 미만일 때 만든 리스트인데 최근 28일 기록이 7일 이상 쌓였을 때.
  * 앱 언어가 바뀌었을 때 — 메뉴 이름을 그 언어로 받는다.
  * AI 가 실패해 카탈로그로 채운 리스트이고 재시도 시각(1시간 뒤)이 지났을 때.

담당 트레이너가 바뀌는 것은 계기가 아니다. 트레이너 메시지는 만들 때 프롬프트에
들어가고, 조언 문장을 만들 때마다 다시 들어간다.

**AI 는 품질을 올리는 층이지 가용성의 전제가 아니다.** 키가 없거나 AI 가 늦거나
틀린 형식을 내면 내장 카탈로그(`diet_menu_catalog`)로 채운다. 끼니 하나가 모자라도
그 칸만 카탈로그로 채운다.
"""
from __future__ import annotations

import json
import logging
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core import clock, metrics
from app.data import diet_menu_catalog as catalog
from app.models.models import DietMenuPlan
from app.services import diet_coach_inputs as inputs
from app.services.coach.llm import DEFAULT_THINKING_BUDGET, get_coach_llm
from app.services.coach.prompt_safety import FOOD_NAME_GUARD, TRAINER_DIET_GUARD

logger = logging.getLogger(__name__)

#: 리스트를 보관하는 날 수이자 AI 가 읽는 기록의 길이.
PLAN_DAYS = 28
#: 이만큼 기록이 쌓이기 전에 만든 리스트는, 쌓인 뒤 한 번 다시 만든다.
MIN_BASIS_DAYS = 7
#: AI 가 실패해 카탈로그로 채운 뒤 다시 시도하기까지. 조회마다 부르면 장애 동안
#: 매 요청이 타임아웃까지 기다린다.
RETRY_AFTER = timedelta(hours=1)

LANGS = ("ko", "en")
#: 메뉴 이름·키워드 길이 한도. 카드의 두 문장이 합쳐 45자 안팎이라 이름이 길면
#: 문장이 넘친다 — 한도까지 채운 이름에 네 자리 수가 붙어도 50자를 넘지 않는 값이다.
NAME_MAX = {"ko": 10, "en": 28}
KEYWORD_MAX = {"ko": 5, "en": 16}
#: 1인분 추정치로 받아들일 범위. 벗어나면 그 메뉴를 버린다(단위를 헷갈린 값이다).
_KCAL_RANGE = (20, 1500)
_PROTEIN_RANGE = (0, 100)
_SODIUM_RANGE = (0, 4000)

#: AI 응답을 기다리는 시간. 18개를 JSON 으로 받아 홈 추천보다 길다. 4주에 한 번이라
#: 조금 기다려도 되지만, 요청 스레드를 오래 잡지 않도록 끊는다.
LLM_TIMEOUT_SEC = 15.0
LLM_MAX_CONCURRENCY = 2

_executor = ThreadPoolExecutor(
    max_workers=LLM_MAX_CONCURRENCY, thread_name_prefix="diet-menu-plan-llm"
)
#: 진행 중인 호출 수 제한 — 홈 추천(`diet_recommendation_service._llm_slots`)과 같은
#: 이유다. 빈 자리가 없으면 기다리지 않고 카탈로그로 내려간다.
_llm_slots = threading.BoundedSemaphore(LLM_MAX_CONCURRENCY)


class LLMBusyError(RuntimeError):
    """동시 호출 한도가 차서 AI 를 부르지 않았다(실패와 구분한다)."""


@dataclass(frozen=True)
class PlanMenu:
    slot: str
    name: str
    tag: str
    keyword: str
    kcal: int
    protein_g: int
    sodium_mg: int


@dataclass(frozen=True)
class MenuPlan:
    id: str
    lang: str
    source: str
    items: tuple[PlanMenu, ...]
    basis_days: int
    created_on: str
    expires_on: str

    def for_slot(self, slot: str) -> list[PlanMenu]:
        return [m for m in self.items if m.slot == slot]


# ── 조회·재생성 ──────────────────────────────────────────────────────────


def _latest(db: Session, user_id: str) -> DietMenuPlan | None:
    return db.scalar(
        select(DietMenuPlan)
        .where(DietMenuPlan.user_id == user_id)
        .order_by(DietMenuPlan.created_at.desc())
        .limit(1)
    )


def _load_items(row: DietMenuPlan) -> tuple[PlanMenu, ...]:
    try:
        raw = json.loads(row.items_json or "[]")
    except ValueError:
        return ()
    items = []
    for it in raw if isinstance(raw, list) else []:
        try:
            items.append(PlanMenu(**it))
        except TypeError:
            continue
    return tuple(items)


def _to_plan(row: DietMenuPlan) -> MenuPlan:
    return MenuPlan(
        id=row.id, lang=row.lang, source=row.source, items=_load_items(row),
        basis_days=row.basis_days, created_on=row.created_on, expires_on=row.expires_on,
    )


def _aware(ts: datetime) -> datetime:
    return ts if ts.tzinfo is not None else ts.replace(tzinfo=clock.SEOUL)


def regeneration_reason(
    row: DietMenuPlan | None,
    *,
    lang: str,
    today: date,
    fingerprint: str,
    recent_days: int,
) -> str | None:
    """다시 만들어야 하면 그 이유, 아니면 None. (재시도는 따로 본다.)"""
    if row is None:
        return "missing"
    if row.lang != lang:
        return "lang"
    if today.isoformat() >= row.expires_on:
        return "expired"
    if row.goal_fingerprint != fingerprint:
        return "goal"
    if row.basis_days < MIN_BASIS_DAYS <= recent_days:
        return "records"
    return None


def get_plan(
    db: Session,
    user_id: str,
    *,
    lang: str = "ko",
    use_llm: bool = True,
    today: date | None = None,
    now: datetime | None = None,
) -> MenuPlan:
    """지금 리스트. 없거나 다시 만들 때가 되었으면 만들어 저장한다(커밋한다)."""
    lang = lang if lang in LANGS else "ko"
    now = now or clock.now()
    today = today or now.date()

    row = _latest(db, user_id)
    profile = inputs.load_profile(db, user_id)
    fingerprint = inputs.goal_fingerprint(profile)
    start = today - timedelta(days=PLAN_DAYS - 1)
    entries = inputs.entries_between(db, user_id, start, today)
    recent = inputs.digest(entries)

    reason = regeneration_reason(
        row, lang=lang, today=today, fingerprint=fingerprint,
        recent_days=recent.days_logged,
    )
    if reason is None:
        assert row is not None
        retry_due = (
            use_llm
            and row.source == "rules"
            and row.retry_after is not None
            and _aware(row.retry_after) <= now
        )
        if not retry_due:
            return _to_plan(row)
        reason = "retry"

    previous = _load_items(row) if row is not None and reason != "retry" else ()
    if reason == "retry":
        # 같은 리스트를 AI 로 다시 채우는 것이다 — 제외할 것은 그 앞 리스트다.
        previous = _previous_items(db, user_id, exclude_id=row.id)  # type: ignore[union-attr]
    excluded = {_norm(m.name) for m in previous}

    targets = inputs.targets_of(profile)
    source, items = _generate(
        db, user_id, lang=lang, use_llm=use_llm, profile=profile, targets=targets,
        recent=recent, excluded=excluded, previous=previous,
    )
    metrics.incr("diet_menu_plan.generated", by=source, reason=reason)

    retry_after = now + RETRY_AFTER if source == "rules" and use_llm else None
    items_json = json.dumps([asdict(m) for m in items], ensure_ascii=False)

    if reason == "retry":
        assert row is not None
        row.source = source
        row.items_json = items_json
        row.retry_after = retry_after
        db.commit()
        return _to_plan(row)

    new_row = DietMenuPlan(
        id=f"menuplan-{uuid.uuid4().hex[:16]}",
        user_id=user_id,
        lang=lang,
        source=source,
        items_json=items_json,
        basis_days=recent.days_logged,
        goal_fingerprint=fingerprint,
        created_on=today.isoformat(),
        expires_on=(today + timedelta(days=PLAN_DAYS)).isoformat(),
        retry_after=retry_after,
        # created_at 은 DB 시각에 맡긴다 — 최근 행을 가리는 순서라, 주입한 `now` 로
        # 채우면 같은 시각에 만든 두 행의 순서가 정해지지 않는다.
    )
    db.add(new_row)
    # 바로 앞 리스트만 남긴다 — "이전 리스트의 메뉴는 빼기" 에 필요한 것은 그것뿐이다.
    if row is not None:
        db.execute(
            delete(DietMenuPlan)
            .where(DietMenuPlan.user_id == user_id)
            .where(DietMenuPlan.id != row.id)
            .where(DietMenuPlan.id != new_row.id)
        )
    db.commit()
    return _to_plan(new_row)


def _previous_items(db: Session, user_id: str, *, exclude_id: str) -> tuple[PlanMenu, ...]:
    row = db.scalar(
        select(DietMenuPlan)
        .where(DietMenuPlan.user_id == user_id)
        .where(DietMenuPlan.id != exclude_id)
        .order_by(DietMenuPlan.created_at.desc())
        .limit(1)
    )
    return _load_items(row) if row is not None else ()


# ── 만들기 ──────────────────────────────────────────────────────────────


def _norm(name: str) -> str:
    return "".join(name.split()).lower()


def needs_of(recent: inputs.DietDigest, targets: inputs.DietTargets) -> list[str]:
    """최근 기록이 가리키는 태그를 급한 순서로. 기록이 없으면 빈 목록."""
    if not recent.days_logged:
        return []
    needs: list[str] = []
    if recent.avg_sodium_mg >= targets.sodium_mg * 0.9:
        needs.append(catalog.TAG_SODIUM_LOW)
    if recent.avg_protein_g <= targets.protein_g * 0.8:
        needs.append(catalog.TAG_PROTEIN_HIGH)
    if recent.avg_calories >= targets.calories * 1.1:
        needs.append(catalog.TAG_CALORIE_LOW)
    elif recent.avg_calories <= targets.calories * 0.7:
        needs.append(catalog.TAG_CALORIE_HIGH)
    if recent.avg_sugar_g >= targets.sugar_g * 0.9:
        needs.append(catalog.TAG_SUGAR_LOW)
    return needs


def _tag_order(needs: list[str]) -> list[str]:
    """급한 태그를 앞에, 나머지는 기본 순서로. 과잉 섭취가 없는데 `든든한` 을 앞에
    두지 않도록 `calorie_high` 는 필요할 때만 앞으로 온다."""
    return needs + [t for t in catalog.TAGS if t not in needs]


def catalog_fill(
    slot: str,
    count: int,
    *,
    lang: str,
    needs: list[str],
    taken: set[str],
    excluded: set[str],
) -> list[PlanMenu]:
    """카탈로그에서 한 끼니의 메뉴를 고른다.

    급한 태그부터 하나씩 돌아가며 뽑아 태그가 한쪽에 몰리지 않게 한다. 이전 리스트의
    메뉴는 빼되, 그러면 모자랄 때만 다시 쓴다(빈 칸보다 반복이 낫다).
    """
    order = _tag_order(needs)
    menus = catalog.for_slot(slot)
    menus.sort(key=lambda m: order.index(m.tag))

    def pick(allow_excluded: bool) -> list[PlanMenu]:
        out: list[PlanMenu] = []
        pools = {tag: [m for m in menus if m.tag == tag] for tag in order}
        while len(out) < count and any(pools.values()):
            for tag in order:
                pool = pools[tag]
                while pool:
                    m = pool.pop(0)
                    key = _norm(m.name(lang))
                    if key in taken or (key in excluded and not allow_excluded):
                        continue
                    out.append(_from_catalog(m, lang))
                    taken.add(key)
                    break
                if len(out) >= count:
                    break
        return out

    picked = pick(allow_excluded=False)
    if len(picked) < count:
        picked += pick(allow_excluded=True)[: count - len(picked)]
    return picked


def _from_catalog(m: catalog.CatalogMenu, lang: str) -> PlanMenu:
    return PlanMenu(
        slot=m.slot, name=m.name(lang), tag=m.tag,
        keyword=catalog.TAG_KEYWORDS[lang][m.tag],
        kcal=m.kcal, protein_g=m.protein_g, sodium_mg=m.sodium_mg,
    )


def rules_plan(
    *, lang: str, needs: list[str], excluded: set[str]
) -> tuple[PlanMenu, ...]:
    taken: set[str] = set()
    items: list[PlanMenu] = []
    for slot in catalog.SLOTS:
        items += catalog_fill(
            slot, catalog.SLOT_COUNTS[slot], lang=lang, needs=needs,
            taken=taken, excluded=excluded,
        )
    return tuple(items)


def _generate(
    db: Session,
    user_id: str,
    *,
    lang: str,
    use_llm: bool,
    profile,
    targets: inputs.DietTargets,
    recent: inputs.DietDigest,
    excluded: set[str],
    previous: tuple[PlanMenu, ...],
) -> tuple[str, tuple[PlanMenu, ...]]:
    needs = needs_of(recent, targets)
    if use_llm:
        try:
            notes = inputs.trainer_notes(db, user_id)
            system, user = build_prompt(
                lang=lang, profile=profile, targets=targets, recent=recent,
                needs=needs, notes=notes, previous=previous,
            )
            raw = _call_llm(system, user)
            return "llm", parse_items(raw, lang=lang, needs=needs, excluded=excluded)
        except LLMBusyError:
            metrics.incr("diet_menu_plan.fallback", reason="busy")
            logger.info("diet menu plan LLM 포화 — 카탈로그로 채움")
        except FutureTimeout:
            metrics.incr("diet_menu_plan.fallback", reason="timeout")
            logger.warning("diet menu plan LLM timeout (%.1fs) — 카탈로그로 채움", LLM_TIMEOUT_SEC)
        except Exception:  # noqa: BLE001 - AI 장애 종류와 무관하게 리스트는 있어야 한다
            metrics.incr("diet_menu_plan.fallback", reason="error")
            logger.warning("diet menu plan LLM 실패 — 카탈로그로 채움", exc_info=True)
    return "rules", rules_plan(lang=lang, needs=needs, excluded=excluded)


_SLOT_LABELS = {"breakfast": "아침", "lunch": "점심", "dinner": "저녁", "snack": "간식"}
_TAG_LABELS = {
    catalog.TAG_SODIUM_LOW: "나트륨을 줄이는",
    catalog.TAG_PROTEIN_HIGH: "단백질을 채우는",
    catalog.TAG_CALORIE_LOW: "열량이 가벼운",
    catalog.TAG_CALORIE_HIGH: "열량을 채우는",
    catalog.TAG_SUGAR_LOW: "당류를 줄이는",
    catalog.TAG_FIBER_HIGH: "식이섬유를 채우는",
}


def build_prompt(
    *,
    lang: str,
    profile,
    targets: inputs.DietTargets,
    recent: inputs.DietDigest,
    needs: list[str],
    notes: list[str],
    previous: tuple[PlanMenu, ...],
) -> tuple[str, str]:
    language = "영어(English)" if lang == "en" else "한국어"
    counts = ", ".join(
        f"{_SLOT_LABELS[s]}({s}) {n}개" for s, n in catalog.SLOT_COUNTS.items()
    )
    tags = "\n".join(f"- {t}: {_TAG_LABELS[t]} 메뉴" for t in catalog.TAGS)
    system = (
        "너는 PT(개인 트레이닝)를 받는 회원의 식단을 돕는 영양 코치다. 회원의 최근 4주 "
        "식단 기록과 목표를 보고, 앞으로 4주 동안 끼니별로 추천할 메뉴 리스트를 만든다.\n"
        "규칙:\n"
        f"1. {counts}. 모든 메뉴 이름이 서로 달라야 한다.\n"
        "2. 한국에서 쉽게 사 먹거나 만들 수 있는 구체적인 1인분 메뉴 이름을 쓴다"
        f"(예: 구운 고등어 정식). 이름은 {NAME_MAX[lang]}자 이내.\n"
        "3. [이전 추천]에 있는 메뉴는 다시 넣지 않는다.\n"
        "4. 메뉴마다 tag 를 하나 붙인다. 회원에게 급한 태그([급한 태그])를 우선하되, "
        "한 끼니 안에서 태그가 한쪽에 몰리지 않게 섞는다. tag 는 아래 값 중 하나다:\n"
        f"{tags}\n"
        f"5. keyword 는 추천 이유를 한눈에 보여 주는 말(예: 저나트륨, 고단백), {KEYWORD_MAX[lang]}자 이내.\n"
        "6. kcal·protein_g·sodium_mg 는 1인분 기준 추정 정수다.\n"
        "7. 의학적 진단·치료를 단정하지 않는다. 식단 제안에 그친다.\n"
        f"8. name 과 keyword 는 {language}로 쓴다.\n"
        f"{TRAINER_DIET_GUARD}\n{FOOD_NAME_GUARD}\n"
        'JSON 만 출력한다: {"items":[{"slot":"breakfast","name":"...","tag":"...",'
        '"keyword":"...","kcal":0,"protein_g":0,"sodium_mg":0}]}'
    )

    lines = [
        "[목표 — 하루]",
        f"- 칼로리 {targets.calories}kcal, 단백질 {targets.protein_g}g, "
        f"나트륨 {targets.sodium_mg}mg, 당류 {targets.sugar_g}g",
        f"- 건강 목표: {(profile.conditions if profile else '') or '정보 없음'}",
        f"- 목표 메모: {(profile.goals if profile else '') or '정보 없음'}",
        "",
        f"[최근 {PLAN_DAYS}일 기록]",
    ]
    if recent.days_logged:
        slots = ", ".join(
            f"{_SLOT_LABELS.get(s, s)} {recent.slot_days.get(s, 0)}일"
            for s in ("breakfast", "lunch", "dinner", "snack")
        )
        lines += [
            f"- 기록한 날 {recent.days_logged}일. 하루 평균 칼로리 {recent.avg_calories}kcal, "
            f"단백질 {recent.avg_protein_g}g, 나트륨 {recent.avg_sodium_mg}mg, 당류 {recent.avg_sugar_g}g",
            f"- 끼니별 기록한 날: {slots}",
        ]
    else:
        lines.append("- 기록 없음. 목표만 보고 고른다.")
    lines += ["", f"[급한 태그] {', '.join(needs) or '없음'}", "", "[자주 먹은 음식]"]
    lines += [f"- {name} {n}회" for name, n in recent.top_foods] or ["- 없음"]
    lines += ["", "[이전 추천]"]
    lines += [f"- {m.name}" for m in previous] or ["- 없음"]
    lines += ["", "[트레이너 메시지]"]
    lines += [f"- 트레이너: {note}" for note in notes] or ["- 없음"]
    return system, "\n".join(lines)


def _strip_code_fence(text: str) -> str:
    t = text.strip()
    if not t.startswith("```"):
        return t
    body = t.split("\n", 1)[1] if "\n" in t else ""
    return body.rsplit("```", 1)[0].strip()


def _int_in(value, lo: int, hi: int) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        n = round(float(value))
    except (TypeError, ValueError):
        return None
    return n if lo <= n <= hi else None


def parse_items(
    raw: str, *, lang: str, needs: list[str], excluded: set[str]
) -> tuple[PlanMenu, ...]:
    """AI 응답 → 검증된 리스트. 모자란 칸은 카탈로그로 채운다.

    끼니·태그가 틀리거나, 이름이 길거나 겹치거나 이전 리스트에 있거나, 영양 추정이
    범위를 벗어난 메뉴는 버린다. 하나도 남지 않으면 예외 — 호출부가 카탈로그 리스트로
    내려간다.
    """
    data = json.loads(_strip_code_fence(raw))
    rows = data.get("items") if isinstance(data, dict) else data
    if not isinstance(rows, list):
        raise ValueError("items 가 배열이 아님")

    by_slot: dict[str, list[PlanMenu]] = {s: [] for s in catalog.SLOTS}
    taken: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            continue
        slot = str(row.get("slot", "")).strip()
        tag = str(row.get("tag", "")).strip()
        name = " ".join(str(row.get("name", "")).split())
        if slot not in by_slot or tag not in catalog.TAGS:
            continue
        if not name or len(name) > NAME_MAX[lang]:
            continue
        key = _norm(name)
        if key in taken or key in excluded:
            continue
        if len(by_slot[slot]) >= catalog.SLOT_COUNTS[slot]:
            continue
        kcal = _int_in(row.get("kcal"), *_KCAL_RANGE)
        protein = _int_in(row.get("protein_g"), *_PROTEIN_RANGE)
        sodium = _int_in(row.get("sodium_mg"), *_SODIUM_RANGE)
        if kcal is None or protein is None or sodium is None:
            continue
        keyword = " ".join(str(row.get("keyword") or "").split())
        if not keyword or len(keyword) > KEYWORD_MAX[lang]:
            keyword = catalog.TAG_KEYWORDS[lang][tag]
        by_slot[slot].append(
            PlanMenu(slot=slot, name=name, tag=tag, keyword=keyword,
                     kcal=kcal, protein_g=protein, sodium_mg=sodium)
        )
        taken.add(key)

    if not any(by_slot.values()):
        raise ValueError("쓸 수 있는 메뉴가 하나도 없음")

    items: list[PlanMenu] = []
    for slot in catalog.SLOTS:
        got = by_slot[slot]
        missing = catalog.SLOT_COUNTS[slot] - len(got)
        if missing > 0:
            got = got + catalog_fill(
                slot, missing, lang=lang, needs=needs, taken=taken, excluded=excluded
            )
        items += got
    return tuple(items)


def _call_llm(system: str, user: str) -> str:
    if not _llm_slots.acquire(blocking=False):
        raise LLMBusyError("LLM 동시 호출 한도 초과")

    def _call():
        try:
            return get_coach_llm().generate(
                system, user, json_mode=True,
                thinking_budget=DEFAULT_THINKING_BUDGET,
                timeout_seconds=LLM_TIMEOUT_SEC,
            )
        finally:
            _llm_slots.release()

    future = _executor.submit(_call)
    return future.result(timeout=LLM_TIMEOUT_SEC).text
