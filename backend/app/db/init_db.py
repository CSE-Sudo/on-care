"""
DB 초기화 + 데모 데이터 시드.

프론트 계약상 사용자 id 는 문자열. 데모 사용자 'user-7d4e9a2c5f18' 를 시드합니다
(프론트 mock 의 _usersMe 가 'user-7d4e9a2c5f18' / '김민수' / 'minsu@oncare.com' 를 쓰므로 호환).
이후 STEP 들에서 이 사용자에 식단/운동/건강 데이터를 붙입니다.
"""
from __future__ import annotations

import hashlib
import json
import logging

from pathlib import Path

from sqlalchemy import delete, select, text
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import hash_password
from app.db.session import Base, SessionLocal, engine
from app.models import models  # noqa: F401

logger = logging.getLogger(__name__)

DEMO_USER_ID = "user-7d4e9a2c5f18"


def init_db() -> None:
    settings = get_settings()

    with engine.connect() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        conn.commit()

    # 개발 편의: create_all(멱등). 운영은 Alembic(`alembic upgrade head`)을 정답으로 삼고
    # AUTO_CREATE_TABLES=false 로 꺼둔다.
    if settings.auto_create_tables:
        Base.metadata.create_all(bind=engine)
        _relax_points_coupon_cost()

    # 참조 데이터: 공공 식품영양성분 DB(데모/운영 무관, 멱등)
    _seed_food_nutrients()
    # 참조 데이터: 운동 종목별 단위체중당 소모 계수(멱등). 식단과 같은 자리다 —
    # 이 표가 비어 있으면 운동 이름이 칼로리에 반영되지 못하고 유형 평균으로
    # 떨어진다(#1312).
    _seed_exercise_catalog()
    # 참조 데이터: 공공 코칭 가이드라인(RAG 공공 문서, 멱등·best-effort)
    _seed_public_coach_docs()

    if settings.seed_demo_data:
        _seed_demo_user()
        _seed_demo_places()
        _seed_demo_notifications()
        # 트레이너 데모(계정·프로필·담당 회원·링크). 데모 사용자 시드 뒤에 호출해야
        # 김민수(user-7d4e9a2c5f18) 링크가 성립한다.
        from app.db.seed_trainer import seed_trainer_domain
        seed_trainer_domain()
        # 제휴 헬스장(#324). 트레이너 시드 뒤에 호출해야 gym_name → gym_id 연결이
        # 걸린다. places 에 fitness 로 들어가므로 상담 대상 검증도 통과한다.
        from app.db.seed_gyms import seed_partner_gyms
        seed_partner_gyms()
        # 데모 트레이너의 예약 자리(#2067). 상담 신청은 트레이너가 연 자리를
        # 고르는 방식이라(#1873) 자리가 없으면 아무도 신청할 수 없다. 트레이너
        # 계정이 모두 생긴 뒤에 깐다(외래 키).
        from app.db.seed_slots import seed_demo_slots
        seed_demo_slots()
        # 담당 회원 실데이터(식단·운동기록) — 트레이너 로스터/식단/기록을 실데이터로 채운다.
        # 회원 계정 시드(seed_trainer_domain) 뒤에 호출.
        from app.db.seed_member_data import seed_member_health_data
        seed_member_health_data()
        # 확장 회원(4~15)의 주간 지표. 상세 기록은 위 3명만 가지므로, 로스터·차트·
        # 경고가 동작할 최소 기록만 따로 채운다(#572).
        from app.db.seed_roster import seed_roster_metrics
        seed_roster_metrics()
        # 시드 기록을 개인 RAG 문서로 적재(#604). **모든 시드가 끝난 뒤**여야 한다 —
        # 확장 회원(4~15)의 기록은 바로 위에서 만들어지므로, 앞에서 훑으면 첫 기동에
        # 그들 문서가 통째로 빠지고 재기동해야 채워진다.
        from app.db.seed_member_data import ingest_seeded_documents
        ingest_seeded_documents()

    _promote_admins()  # ADMIN_EMAILS 사용자를 관리자로 승격(멱등)


def _relax_points_coupon_cost() -> None:
    """create_all 로 만든 옛 DB 의 `cost > 0` 제약을 `cost >= 0` 으로 바꾼다(#2150).

    create_all 은 이미 있는 표의 제약을 고치지 않는다. 식판 수령 쿠폰은 0P 라 옛
    제약이 남은 로컬·테스트 DB 에서는 받기가 깨진다. 운영은 Alembic
    `0087_points_coupons_zero_cost` 가 같은 일을 한다. 이미 바뀌었으면 아무것도 하지
    않는다.
    """
    with engine.begin() as conn:
        current = conn.scalar(
            text(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
                "WHERE conname = 'ck_points_coupons_cost'"
            )
        )
        if current is None or ">=" in current:
            return
        conn.execute(
            text("ALTER TABLE points_coupons DROP CONSTRAINT ck_points_coupons_cost")
        )
        conn.execute(
            text(
                "ALTER TABLE points_coupons ADD CONSTRAINT ck_points_coupons_cost "
                "CHECK (cost >= 0)"
            )
        )


def _seed_demo_user() -> None:
    db: Session = SessionLocal()
    try:
        existing = db.scalar(select(models.User).where(models.User.id == DEMO_USER_ID))
        if existing is None:
            user = models.User(
                id=DEMO_USER_ID,
                email="minsu@oncare.com",
                name="김민수",
                # 다른 데모 계정과 같은 비밀번호로 로그인된다. 예전에는 빈 문자열이었는데,
                # 이 시드가 seed_trainer 보다 먼저 돌고 seed_trainer 는 기존 사용자를
                # 건너뛰기 때문에 김민수만 영영 로그인할 수 없었다.
                hashed_password=hash_password(get_settings().demo_login_password),
            )
            db.add(user)
            db.commit()
    finally:
        db.close()


def _promote_admins() -> None:
    """ADMIN_EMAILS(콤마구분)에 있는 사용자를 관리자로 승격(멱등)."""
    from sqlalchemy import func

    emails = get_settings().admin_email_set
    if not emails:
        return
    db: Session = SessionLocal()
    try:
        users = db.scalars(
            select(models.User).where(func.lower(models.User.email).in_(emails))
        ).all()
        changed = False
        for u in users:
            if not u.is_admin:
                u.is_admin = True
                changed = True
        if changed:
            db.commit()
    finally:
        db.close()


def _public_food_rows() -> list[dict]:
    """공공 표준데이터 집계본(scripts/import_food_nutrients.py 산출물)을 읽는다.

    파일이 없으면 빈 목록 — 큐레이션 43종만으로도 서비스는 돈다.
    """
    import csv

    path = Path(__file__).resolve().parent.parent / "data" / "food_nutrients_public.csv"
    if not path.exists():
        return []

    def num(value: str):
        value = (value or "").strip()
        if not value:
            return None
        try:
            return float(value)
        except ValueError:
            return None

    with path.open(encoding="utf-8", newline="") as fh:
        return [
            {
                "name": row["name"],
                "category": row.get("category", ""),
                "serving_size_g": num(row.get("serving_size_g", "")),
                "calories": num(row.get("calories", "")) or 0,
                "sodium_mg": num(row.get("sodium_mg", "")) or 0,
                "sugar_g": num(row.get("sugar_g", "")) or 0,
                "carbs_g": num(row.get("carbs_g", "")),
                "protein_g": num(row.get("protein_g", "")),
                "fat_g": num(row.get("fat_g", "")),
                # 근거 열 — DB 에는 넣지 않고 검사·확인에만 쓴다(#2102).
                "source_dataset": row.get("source_dataset", ""),
                "method": row.get("method", ""),
                "serving_basis": row.get("serving_basis", ""),
            }
            for row in csv.DictReader(fh)
        ]


_NUTRIENT_FIELDS = ("calories", "sodium_mg", "sugar_g", "carbs_g", "protein_g", "fat_g")


def _curated_per_100g(items: list[dict], public: dict[str, dict] | None = None) -> list[dict]:
    """큐레이션 시드를 100g 기준 행으로.

    `food_nutrients` 는 100g 기준이다(공공 원본이 전부 그 형태고, 포장 단위로
    1인분 환산하면 대표값이 3~5배까지 튄다). 영양값은 셋 중 하나로 온다
    (`food_nutrients_seed` 설명):

    - `from_public` — 그 이름의 공공 표준 행의 100g 당 값(#2100). `public` 은 정규화
      이름 → 공공 행이다.
    - `per_100g` — 출처 행의 100g 당 값을 그대로(#2102). 1인분으로 적었다가 다시
      나누면 반올림이 끼고, 1회 섭취량을 바꿀 때마다 값을 다시 셈해야 한다.
    - 1인분 값(데모 메뉴) — `serving_size_g` 로 나눠 100g 기준으로 바꾼다.

    1회 섭취량 자체는 컬럼에 남겨 인식기가 양을 못 줬을 때 폴백으로 쓴다. 근거가 없어
    비운 항목(`None`)은 폴백 없이 들어간다.
    """
    from app.services.nutrition.matcher import normalize

    scaled: list[dict] = []
    for item in items:
        serving = item.get("serving_size_g")
        out = {
            k: v
            for k, v in item.items()
            if k not in {"from_public", "per_100g", "source", "serving_basis"}
        }
        source = item.get("from_public")
        if source:
            row = (public or {}).get(normalize(source))
            if row is None:
                raise ValueError(f"큐레이션 {item['name']} 의 from_public 행이 없다: {source}")
            for field in _NUTRIENT_FIELDS:
                out[field] = row.get(field)
            scaled.append(out)
            continue
        if "per_100g" in item:
            out.update(item["per_100g"])
            scaled.append(out)
            continue
        if not serving or serving <= 0:
            # 1인분 값인데 환산 기준이 없으면 값의 의미가 불분명해진다 — 넣지 않는다.
            continue
        factor = 100.0 / float(serving)
        for field in _NUTRIENT_FIELDS:
            value = item.get(field)
            if value is not None:
                out[field] = round(float(value) * factor, 2)
        scaled.append(out)
    return scaled


def _food_nutrient_seed_rows() -> list[dict]:
    """`food_nutrients` 에 들어갈 행. name_norm 은 매칭기와 동일 규칙으로 생성.

    큐레이션을 **먼저** 넣고, 공공 표준데이터 집계본에서 이름이 겹치는 것은
    건너뛴다. 큐레이션은 이름·1회 섭취량을 정하고, 영양값은 근거가 있는 공공 행에서
    가져오거나(`from_public`) 출처를 적어 직접 둔다.
    """
    from app.data.food_nutrients_seed import FOOD_NUTRIENTS
    from app.services.nutrition.matcher import normalize

    public = _public_food_rows()
    by_norm: dict[str, dict] = {}
    for row in public:
        by_norm.setdefault(normalize(row["name"]), row)

    rows: list[dict] = []
    seen: set[str] = set()
    for item in [*_curated_per_100g(FOOD_NUTRIENTS, by_norm), *public]:
        norm = normalize(item["name"])
        # 매칭은 name_norm 으로 하므로 중복 norm 은 조회를 모호하게 만든다.
        if not norm or norm in seen:
            continue
        seen.add(norm)
        rows.append({
            "name": item["name"],
            "name_norm": norm,
            "category": item.get("category", ""),
            "serving_size_g": item.get("serving_size_g"),
            "calories": item.get("calories") or 0,
            "sodium_mg": item.get("sodium_mg") or 0,
            "sugar_g": item.get("sugar_g") or 0,
            "carbs_g": item.get("carbs_g"),
            "protein_g": item.get("protein_g"),
            "fat_g": item.get("fat_g"),
        })
    return rows


def _fingerprint(rows: list[dict]) -> str:
    payload = json.dumps(rows, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


_FOOD_NUTRIENTS_VERSION = "food_nutrients"


def _seed_food_nutrients() -> None:
    """`food_nutrients` 를 시드 데이터와 맞춘다(멱등). (#2100)

    예전에는 표가 비었을 때만 채워서, 큐레이션 값이나 공공 표준 집계본을 고쳐도
    이미 떠 있는 DB 에는 닿지 않았다. 이제 시드 행으로 만든 지문을
    `reference_data_versions` 에 적어 두고, 다르면 표를 **통째로** 새 시드로 바꾼다.
    읽기 전용 참조표이고 다른 표가 참조하지 않으므로(행 id 도 저장하는 곳이 없다)
    통째로 바꿔도 회원 기록에 영향이 없다.

    같은 DB 를 쓰는 인스턴스가 동시에 뜨면 advisory lock 으로 한 곳만 바꾸고,
    나머지는 lock 을 얻은 뒤 지문을 다시 읽어 그대로 둔다.
    """
    from app.services.nutrition.table import invalidate

    rows = _food_nutrient_seed_rows()
    fingerprint = _fingerprint(rows)

    def up_to_date(db: Session) -> bool:
        stored = db.get(models.ReferenceDataVersion, _FOOD_NUTRIENTS_VERSION)
        return (
            stored is not None
            and stored.fingerprint == fingerprint
            and db.scalar(select(models.FoodNutrient.id).limit(1)) is not None
        )

    db: Session = SessionLocal()
    try:
        if up_to_date(db):
            return
        db.execute(
            text("SELECT pg_advisory_xact_lock(hashtext(:key))"),
            {"key": "seed:food_nutrients"},
        )
        db.expire_all()
        if up_to_date(db):
            db.rollback()
            return
        db.execute(delete(models.FoodNutrient))
        db.add_all(models.FoodNutrient(**row) for row in rows)
        db.merge(models.ReferenceDataVersion(
            name=_FOOD_NUTRIENTS_VERSION, fingerprint=fingerprint
        ))
        db.commit()
    finally:
        db.close()
    # 표를 Core `DELETE` 로 비웠으므로 캐시 무효화 훅만 믿지 않고 직접 비운다.
    invalidate()
    logger.info("food_nutrients 를 시드 데이터로 다시 맞췄다(%d행)", len(rows))


#: 원본 컬럼명 후보. 공공데이터 파일은 배포 회차마다 표기가 조금씩 다르다.
_PUBLIC_NAME_KEYS = ("운동명", "운동 명", "name")
_PUBLIC_MET_KEYS = ("단위체중당에너지소비량", "METS", "METs", "MET", "met")

#: 이름 조각 → 집계 유형. 위에서부터 먼저 걸리는 것을 쓴다. 원본에는 우리 집계
#: 축(유산소/근력/스트레칭/기타)이 없으므로 **적재할 때** 이름으로 짐작한다 —
#: 원본 파일에 열을 더해 두면 그것이 곧 변경이라 KOGL 제4유형에 걸린다(#1651).
#: 모르면 `other` 다. 잘못된 유형으로 우겨 넣으면 주간 그래프의 버킷이 틀어지는데,
#: 유형을 못 정해도 계수는 맞으므로 칼로리 계산에는 지장이 없다.
_PUBLIC_TYPE_HINTS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("stretching", ("스트레칭", "요가", "필라테스", "체조", "이완", "태극권")),
    (
        "strength",
        ("근력", "웨이트", "덤벨", "바벨", "머신", "스쿼트", "프레스", "리프트",
         "턱걸이", "팔굽혀", "윗몸", "플랭크", "런지", "케틀벨"),
    ),
    (
        "cardio",
        ("걷기", "달리기", "뛰기", "조깅", "러닝", "자전거", "사이클", "수영",
         "등산", "줄넘기", "에어로빅", "계단", "유산소", "로잉", "스피닝"),
    ),
)

#: 공공데이터 원본. 받은 바이트 그대로 커밋해 둔 파일이다(#1651).
PUBLIC_EXERCISE_CSV = (
    Path(__file__).resolve().parent.parent / "data" / "exercise_met_public.csv"
)


def public_exercise_type(name: str) -> str:
    """종목 이름에서 집계 유형을 짐작한다. 모르면 `other`."""
    for code, tokens in _PUBLIC_TYPE_HINTS:
        if any(token in name for token in tokens):
            return code
    return "other"


def _read_public_exercise_csv(path: Path) -> list[dict[str, str]]:
    """원본 CSV 를 읽는다. 공공데이터포털 파일은 CP949 로 내려오는 일이 잦다.

    인코딩 때문에 빈 결과를 내고 조용히 끝나는 것이 가장 알아채기 어려우므로,
    UTF-8 을 먼저 보고 실패하면 CP949 로 되읽는다.
    """
    import csv

    for encoding in ("utf-8-sig", "cp949"):
        try:
            with path.open(encoding=encoding, newline="") as fh:
                return list(csv.DictReader(fh))
        except UnicodeDecodeError:
            continue
    logger.warning("공공 운동 데이터의 인코딩을 읽지 못했다(UTF-8/CP949 아님): %s", path)
    return []


def _pick(row: dict[str, str], keys: tuple[str, ...]) -> str:
    for key in keys:
        if key in row and (row[key] or "").strip():
            return row[key].strip()
    return ""


def _public_exercise_rows() -> list[dict]:
    """공공 운동 MET 원본(`app/data/exercise_met_public.csv`)을 읽는다. (#1651)

    한국건강증진개발원 `보건소 모바일 헬스케어 운동`(공공데이터포털) 파일을 받은
    **그대로** 커밋해 두고, 여기서 읽는다. 예전에는 임포트 스크립트가 유형 열을
    붙이고 행을 걸러 낸 산출본을 만들었는데, 그 가공이야말로 KOGL 제4유형의
    변경금지에 걸리는 쪽이었다. 재배포 자체는 막지 않으므로, 원본을 그대로 두고
    유형 매핑·정규화는 이 적재 시점의 코드로 붙인다.

    파일이 없으면 빈 목록 — 큐레이션 목록만으로도 서비스는 돈다.
    """
    if not PUBLIC_EXERCISE_CSV.exists():
        return []

    rows: list[dict] = []
    seen: set[str] = set()
    for raw in _read_public_exercise_csv(PUBLIC_EXERCISE_CSV):
        name = _pick(raw, _PUBLIC_NAME_KEYS)
        met_text = _pick(raw, _PUBLIC_MET_KEYS)
        if not name or not met_text or name in seen:
            continue
        try:
            met = float(met_text)
        except ValueError:
            continue
        # 계수가 없거나 0 이면 칼로리가 0 이 된다 — 표에 있을 이유가 없다.
        if met <= 0:
            continue
        seen.add(name)
        rows.append(
            {
                "name": name,
                "type": public_exercise_type(name),
                # 원본 값 그대로. 반올림·환산하지 않는다(변경금지).
                "met": met,
                "aliases": [],
                "source": "khpi",
            }
        )
    return rows


def _exercise_catalog_seed_rows() -> list[dict]:
    """운동 종목 참조표에 넣을 행. 큐레이션 목록이 **먼저** 다.

    식단 시드와 같은 우선순위다 — 큐레이션 쪽은 회원이 실제로 적는 말(별칭 포함)로
    손질한 것이라, 원본의 긴 항목명보다 이름 매칭이 잘 붙는다.

    정규화 이름이 겹치면 뒤엣것을 버린다. 매칭은 정규화 이름으로 하므로 중복이
    있으면 조회가 모호해진다 — 같은 이름에 계수가 둘이면 값이 흔들린다.
    """
    from app.data.exercise_catalog_seed import EXERCISE_CATALOG
    from app.services import exercise_types
    from app.services.exercise_catalog.matcher import normalize

    seen: set[str] = set()
    rows: list[dict] = []

    def take(items: list[dict], default_source: str, *, with_aliases: bool) -> None:
        # 대표 이름을 먼저 전부 잡는다. 별칭이 같은 묶음 뒤 항목의 대표 이름을 막으면
        # 목록에 적은 순서가 어느 종목이 살아남는지를 정하게 된다.
        kept: list[tuple[dict, str]] = []
        for item in items:
            norm = normalize(item["name"])
            if not norm or norm in seen:
                continue
            seen.add(norm)
            kept.append((item, norm))

        for item, norm in kept:
            aliases = []
            if with_aliases:
                for alias in item.get("aliases", []):
                    alias_norm = normalize(alias)
                    if alias_norm and alias_norm not in seen:
                        seen.add(alias_norm)
                        aliases.append(alias_norm)
            rows.append({
                "name": item["name"],
                "name_norm": norm,
                "aliases_norm": "|".join(aliases),
                "type": exercise_types.normalize(item.get("type")),
                "met": float(item["met"]),
                "isometric": bool(item.get("isometric", False)),
                # 어디서 온 행인지는 `source` 로만 구분된다 — 큐레이션은 두 자료를
                # 참고해 손으로 추린 값이라 원본(khpi)과 같은 출처로 적을 수 없다.
                "source": item.get("source", default_source),
            })

    # 큐레이션은 **별칭까지** 먼저 잡는다. 별칭을 나중에 잡으면 원본의 같은 이름
    # 항목이 먼저 들어가, 손질해 둔 별칭이 통째로 떨어져 나간다("걷기"의 "산책").
    take(EXERCISE_CATALOG, "curated", with_aliases=True)
    # 원본은 운동명과 계수 두 열뿐이라 별칭이 없다.
    take(_public_exercise_rows(), "khpi", with_aliases=False)
    return rows


_EXERCISE_CATALOG_VERSION = "exercise_catalog"


def _seed_exercise_catalog() -> None:
    """`exercise_catalog` 를 시드 행과 맞춘다(멱등). (#1651)

    식단 참조표(`_seed_food_nutrients`, #2100)와 같은 방식이다 — 예전에는 표가
    비었을 때만 채워서, 공공데이터 전건을 얹어도 이미 떠 있는 DB 에는 닿지 않고
    큐레이션 60종에 머물렀다. 시드 행의 지문을 `reference_data_versions` 에 적어
    두고, 다르면 표를 **통째로** 새 시드로 바꾼다. 읽기 전용 참조표이고 다른 표가
    이 행을 참조하지 않으므로(행 id 를 저장하는 곳이 없다) 통째로 바꿔도 회원
    기록에 영향이 없다.
    """
    from app.services.exercise_catalog.table import invalidate

    rows = _exercise_catalog_seed_rows()
    fingerprint = _fingerprint(rows)

    def up_to_date(db: Session) -> bool:
        stored = db.get(models.ReferenceDataVersion, _EXERCISE_CATALOG_VERSION)
        return (
            stored is not None
            and stored.fingerprint == fingerprint
            and db.scalar(select(models.ExerciseCatalogItem.id).limit(1)) is not None
        )

    db: Session = SessionLocal()
    try:
        if up_to_date(db):
            return
        # 같은 DB 를 쓰는 인스턴스가 동시에 뜨면 한 곳만 바꾼다.
        db.execute(
            text("SELECT pg_advisory_xact_lock(hashtext(:key))"),
            {"key": "seed:exercise_catalog"},
        )
        db.expire_all()
        if up_to_date(db):
            db.rollback()
            return
        db.execute(delete(models.ExerciseCatalogItem))
        db.add_all(models.ExerciseCatalogItem(**row) for row in rows)
        db.merge(models.ReferenceDataVersion(
            name=_EXERCISE_CATALOG_VERSION, fingerprint=fingerprint
        ))
        db.commit()
    finally:
        db.close()
    # 표를 Core `DELETE` 로 비웠으므로 캐시 무효화 훅만 믿지 않고 직접 비운다.
    invalidate()
    logger.info("exercise_catalog 를 시드 데이터로 다시 맞췄다(%d행)", len(rows))


_PUBLIC_COACH_DOCS_VERSION = "coach_public_docs"

#: 시드가 넣은 공개 문서의 `source`. 관리자가 직접 올린 공공 문서
#: (`POST /coach/documents/public`, 기본 `source="public"`)와 구분하려고 따로 둔다 —
#: 다시 적재할 때 지우는 것은 시드가 넣은 것뿐이어야 한다.
PUBLIC_DOC_SOURCE = "public_seed"


def _seed_public_coach_docs() -> None:
    """공개 근거 문서를 RAG 공공 문서로 적재(멱등). (#1652)

    예전에는 공공 문서가 **하나라도** 있으면 건너뛰어서, 근거 문서를 바꿔도 이미
    떠 있는 DB 는 새 문서를 영영 받지 못했다. 고혈압·당뇨 전제의 옛 요약이 그대로
    남아 코치가 타깃과 무관한 근거로 말하게 된다. 참조표 시드(#2100, #1651)와 같이
    문서 목록의 지문을 `reference_data_versions` 에 적어 두고, 다르면 공공 문서를
    **통째로** 새 목록으로 바꾼다. 지우는 것은 `user_id IS NULL` 뿐이라 회원 개인
    문서는 건드리지 않는다. 관리자가 직접 올린 공공 문서도 남는다 — 지우는 대상을
    시드가 넣은 `source` 로 좁힌다.

    임베딩이 안 되면(제공자 키 없음·장애) 경고만 남기고 넘어간다. 기동을 막을
    일이 아니고, 코치는 규칙 폴백으로 답한다. 이때 지문을 적지 않으므로 다음
    기동에서 다시 시도한다 — 여기서 적어 두면 빈 근거가 최신 상태로 굳는다.
    """
    from app.data.coach_public_docs import PUBLIC_DOCS
    from app.services.coach.rag import ingest_document

    docs = [
        {"title": doc.title, "domain": doc.domain, "content": doc.read()}
        for doc in PUBLIC_DOCS
    ]
    fingerprint = _fingerprint(docs)

    def up_to_date(db: Session) -> bool:
        stored = db.get(models.ReferenceDataVersion, _PUBLIC_COACH_DOCS_VERSION)
        return (
            stored is not None
            and stored.fingerprint == fingerprint
            and db.scalar(
                select(models.CoachDocument.id)
                .where(
                    models.CoachDocument.user_id.is_(None),
                    models.CoachDocument.source == PUBLIC_DOC_SOURCE,
                )
                .limit(1)
            ) is not None
        )

    db: Session = SessionLocal()
    try:
        if up_to_date(db):
            return
        # 같은 DB 를 쓰는 인스턴스가 동시에 뜨면 한 곳만 바꾼다. 임베딩까지 잠금
        # 안에서 도는데, 경쟁하는 쪽은 같이 기동하는 인스턴스뿐이다.
        db.execute(
            text("SELECT pg_advisory_xact_lock(hashtext(:key))"),
            {"key": "seed:coach_public_docs"},
        )
        db.expire_all()
        if up_to_date(db):
            db.rollback()
            return

        db.execute(
            delete(models.CoachDocument).where(
                models.CoachDocument.user_id.is_(None),
                models.CoachDocument.source == PUBLIC_DOC_SOURCE,
            )
        )
        failed = 0
        for doc in docs:
            try:
                ingest_document(
                    db, doc["content"], user_id=None,
                    domain=doc["domain"], source=PUBLIC_DOC_SOURCE,
                    title=doc["title"],
                )
            except Exception:  # noqa: BLE001 — 적재 실패가 기동을 막지 않도록
                # 조용히 삼키면 RAG 가 빈 채로 코치가 규칙 폴백에 갇혀 원인 파악이
                # 어렵다.
                logger.warning(
                    "공개 근거 문서 적재 실패 — 임베딩 제공자(EMBEDDER) 설정 확인 필요: %s",
                    doc["title"],
                    exc_info=True,
                )
                failed += 1
                db.rollback()
        if failed:
            return
        db.merge(models.ReferenceDataVersion(
            name=_PUBLIC_COACH_DOCS_VERSION, fingerprint=fingerprint
        ))
        db.commit()
    finally:
        db.close()
    logger.info("공개 근거 문서를 다시 적재했다(%d건)", len(docs))


def _seed_demo_places() -> None:
    """서울시청 인근 데모 장소 (카카오맵 실연동 전까지 사용)."""
    db: Session = SessionLocal()
    try:
        if db.scalar(select(models.Place).limit(1)):
            return
        demo = [
            ("place-1", "온케어 내과의원", "medical", "서울 중구 세종대로 110", 37.5660, 126.9785),
            ("place-2", "헬스플러스 피트니스", "fitness", "서울 중구 을지로 50", 37.5663, 126.9820),
            ("place-3", "그린샐러드 키친", "healthy_food", "서울 중구 명동길 20", 37.5638, 126.9850),
            ("place-4", "건강약국", "pharmacy", "서울 중구 태평로 30", 37.5650, 126.9770),
            ("place-5", "한강공원 러닝트랙", "fitness", "서울 영등포구 여의동로 330", 37.5283, 126.9325),
        ]
        for pid, name, cat, addr, lat, lng in demo:
            db.add(models.Place(id=pid, name=name, category=cat, address=addr, lat=lat, lng=lng))
        db.commit()
    finally:
        db.close()


def _seed_demo_notifications() -> None:
    # 목록과 멱등 규칙은 `seed_notifications` 에 있다 — 회원앱 데모 알림과 같은 목록(#1812).
    from app.db.seed_notifications import seed_demo_notifications

    db: Session = SessionLocal()
    try:
        seed_demo_notifications(db, DEMO_USER_ID)
    finally:
        db.close()
