"""
DB 초기화 + 데모 데이터 시드.

프론트 계약상 사용자 id 는 문자열. 데모 사용자 'user-7d4e9a2c5f18' 를 시드합니다
(프론트 mock 의 _usersMe 가 'user-7d4e9a2c5f18' / '김민수' / 'minsu@oncare.com' 를 쓰므로 호환).
이후 STEP 들에서 이 사용자에 식단/운동/건강 데이터를 붙입니다.
"""
from __future__ import annotations

import logging

from pathlib import Path

from sqlalchemy import select, text
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
            }
            for row in csv.DictReader(fh)
        ]


def _curated_per_100g(items: list[dict]) -> list[dict]:
    """큐레이션 시드(1인분 기준)를 100g 기준으로 환산.

    `food_nutrients` 는 100g 기준이다(공공 원본이 전부 그 형태고, 포장 단위로
    1인분 환산하면 대표값이 3~5배까지 튄다). 큐레이션 43종은 사람이 1인분으로
    정리한 값이라 여기서 맞춰 넣는다 — `serving_size_g` 가 모두 있어 기계적으로
    변환된다. 1회 섭취량 자체는 컬럼에 남겨 인식기가 양을 못 줬을 때 폴백으로
    쓴다.
    """
    scaled: list[dict] = []
    for item in items:
        serving = item.get("serving_size_g")
        if not serving or serving <= 0:
            # 환산 기준이 없으면 값의 의미가 불분명해진다 — 넣지 않는다.
            continue
        factor = 100.0 / float(serving)
        out = dict(item)
        for field in ("calories", "sodium_mg", "sugar_g", "carbs_g", "protein_g", "fat_g"):
            value = item.get(field)
            if value is not None:
                out[field] = round(float(value) * factor, 2)
        scaled.append(out)
    return scaled


def _seed_food_nutrients() -> None:
    """공공 식품영양성분 DB 시드(멱등). name_norm 은 매칭기와 동일 규칙으로 생성.

    큐레이션 43종을 **먼저** 넣고, 공공 표준데이터 집계본에서 이름이 겹치는
    것은 건너뛴다. 큐레이션 값은 고혈압·당뇨 관점으로 따로 검증한 것이라
    공식 중앙값보다 우선한다 — 라면 나트륨이 큐레이션 1,800mg vs 공식 452mg
    처럼 크게 갈리는 항목이 있고, 후자는 급식 라면이 섞인 결과로 보인다.
    """
    from app.data.food_nutrients_seed import FOOD_NUTRIENTS
    from app.services.nutrition.matcher import normalize

    db: Session = SessionLocal()
    try:
        if db.scalar(select(models.FoodNutrient).limit(1)):
            return
        seen: set[str] = set()
        for item in [*_curated_per_100g(FOOD_NUTRIENTS), *_public_food_rows()]:
            norm = normalize(item["name"])
            # 매칭은 name_norm 으로 하므로 중복 norm 은 조회를 모호하게 만든다.
            if not norm or norm in seen:
                continue
            seen.add(norm)
            db.add(models.FoodNutrient(
                name=item["name"],
                name_norm=norm,
                category=item.get("category", ""),
                serving_size_g=item.get("serving_size_g"),
                calories=item.get("calories", 0),
                sodium_mg=item.get("sodium_mg", 0),
                sugar_g=item.get("sugar_g", 0),
                carbs_g=item.get("carbs_g"),
                protein_g=item.get("protein_g"),
                fat_g=item.get("fat_g"),
            ))
        db.commit()
    finally:
        db.close()


def _public_exercise_rows() -> list[dict]:
    """공공 운동 MET 집계본(scripts/import_exercise_catalog.py 산출물)을 읽는다.

    파일이 없으면 빈 목록 — 큐레이션 목록만으로도 서비스는 돈다. 원본 공공데이터는
    이용허락범위(KOGL 제4유형)상 저장소에 담지 않으므로, 이 파일은 받아서 넣는
    사람만 갖고 있다.
    """
    import csv

    path = Path(__file__).resolve().parent.parent / "data" / "exercise_catalog_public.csv"
    if not path.exists():
        return []

    def num(value: str) -> float | None:
        value = (value or "").strip()
        if not value:
            return None
        try:
            return float(value)
        except ValueError:
            return None

    with path.open(encoding="utf-8", newline="") as fh:
        rows = []
        for row in csv.DictReader(fh):
            met = num(row.get("met", ""))
            if not met or met <= 0:
                # 계수가 없으면 이 표에 있을 이유가 없다 — 칼로리가 0 이 된다.
                continue
            rows.append(
                {
                    "name": row["name"],
                    "type": row.get("type", ""),
                    "met": met,
                    "aliases": [
                        a for a in (row.get("aliases", "") or "").split("|") if a
                    ],
                    "source": row.get("source", "khpi"),
                }
            )
        return rows


def _seed_exercise_catalog() -> None:
    """운동 종목 참조표 시드(멱등). name_norm 은 매칭기와 동일 규칙으로 생성.

    큐레이션 목록을 **먼저** 넣고, 공공 집계본에서 이름·별칭이 겹치는 것은
    건너뛴다. 식단 시드와 같은 우선순위다 — 큐레이션 쪽은 회원이 실제로 적는
    말(별칭 포함)로 손질한 것이라, 원본의 긴 항목명보다 이름 매칭이 잘 붙는다.

    정규화 이름이 겹치면 뒤엣것을 버린다. 매칭은 정규화 이름으로 하므로 중복이
    있으면 조회가 모호해진다 — 같은 이름에 계수가 둘이면 값이 흔들린다.
    """
    from app.data.exercise_catalog_seed import EXERCISE_CATALOG
    from app.services import exercise_types
    from app.services.exercise_catalog.matcher import normalize

    db: Session = SessionLocal()
    try:
        if db.scalar(select(models.ExerciseCatalogItem).limit(1)):
            return
        items = [*EXERCISE_CATALOG, *_public_exercise_rows()]
        # 대표 이름을 먼저 전부 잡아 둔다. 별칭이 뒤 항목의 대표 이름을 막으면
        # 목록에 적은 순서가 어느 종목이 살아남는지를 정하게 된다.
        seen: set[str] = set()
        kept: list[tuple[dict, str]] = []
        for item in items:
            norm = normalize(item["name"])
            if not norm or norm in seen:
                continue
            seen.add(norm)
            kept.append((item, norm))

        for item, norm in kept:
            aliases = []
            for alias in item.get("aliases", []):
                alias_norm = normalize(alias)
                if alias_norm and alias_norm not in seen:
                    seen.add(alias_norm)
                    aliases.append(alias_norm)
            db.add(models.ExerciseCatalogItem(
                name=item["name"],
                name_norm=norm,
                aliases_norm="|".join(aliases),
                type=exercise_types.normalize(item.get("type")),
                met=float(item["met"]),
                source=item.get("source", "khpi"),
            ))
        db.commit()
    finally:
        db.close()


def _seed_public_coach_docs() -> None:
    """공공 코칭 가이드라인을 RAG 공공 문서로 적재(멱등). 임베딩 불가 시 경고 로그 후 스킵."""
    from app.data.coach_public_docs import PUBLIC_DOCS
    from app.services.coach.rag import ingest_document

    db: Session = SessionLocal()
    try:
        exists = db.scalar(
            select(models.CoachDocument).where(models.CoachDocument.user_id.is_(None)).limit(1)
        )
        if exists:
            return
        for doc in PUBLIC_DOCS:
            try:
                ingest_document(
                    db, doc["content"], user_id=None,
                    domain=doc["domain"], source="public", title=doc["title"],
                )
            except Exception:  # noqa: BLE001 — 적재 실패가 기동을 막지 않도록
                # 조용히 삼키면 RAG 가 빈 채로 코치가 규칙 폴백에 갇혀 원인 파악이 어렵다.
                logger.warning(
                    "공공 코칭 문서 적재 실패 — 임베딩 제공자(EMBEDDER) 설정 확인 필요: %s",
                    doc.get("title"),
                    exc_info=True,
                )
                db.rollback()
    finally:
        db.close()


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
