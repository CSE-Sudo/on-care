"""제휴 헬스장 데모 시드 — 회원앱 헬스장·트레이너 디렉터리의 실데이터. (#324)

헬스장은 `places`(category='fitness') 에 넣는다. 상담 검증
(`consultation_service._validate_target`)이 그 테이블을 보므로, 여기 없는 헬스장은
상담 신청이 404 가 난다.

부가 정보(평점·영업시간·전화·태그)는 `gym_profiles` 에 둔다 — `places` 는 병원·약국·
건강식이 함께 쓰는 테이블이라 헬스장 전용 컬럼을 붙이면 오염된다.

멱등: 존재하면 건너뛴다. `seed_demo_data` 가 켜졌을 때만 호출된다.
"""
from __future__ import annotations

import json
import logging

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models import models

logger = logging.getLogger(__name__)

#: 프론트 `MockGymRepository` 와 같은 id·좌표를 쓴다 — 앱이 mock 에서 실 API 로
#: 넘어갈 때 id 가 바뀌면 진행 중인 상담·연결이 끊긴다.
_PARTNER_GYMS: tuple[
    tuple[str, str, str, float, float, float, str, str, str, list[str]], ...
] = (
    (
        "gym-oncare-sinchon", "온케어짐 신촌점", "서울 서대문구 신촌로 120",
        37.5559, 126.9368, 4.7, "06:00 – 23:00", "08:00 - 20:00", "02-1234-5678",
        ["다이어트", "재활운동"],
    ),
    (
        "gym-healthmate", "헬스메이트 신촌점", "서울 서대문구 신촌로 83",
        37.5548, 126.9385, 4.5, "05:30 - 24:00", "07:00 - 22:00", "02-2345-6789",
        ["근력운동", "만성질환 관리"],
    ),
    (
        "gym-bodyandsoul", "바디앤소울 피트니스", "서울 마포구 백범로 23",
        37.5455, 126.9425, 4.8, "06:00 - 22:00", "09:00 - 18:00", "02-3456-7890",
        ["PT", "식단 상담"],
    ),
)

#: 카카오 Local `헬스장` 검색으로 발견한 실재 업체(#329). id·이름·주소·좌표·전화는
#: 카카오 실데이터이고, **확인할 수 없는 값(평점·영업시간·태그)은 비워 둔다.**
#:
#: 지어낸 평점을 넣지 않는 이유: 주석은 DB 와 API 응답에 남지 않는다. `/gyms/{id}` 가
#: 실재 상호·주소·전화와 함께 평점을 내려주면 화면에서는 실제 평점으로 읽힌다(리뷰
#: 지적). 평점 없음은 0 으로 내려가고 UI 가 뱃지를 감춘다.
#:
#: DB 에 넣는 이유: 상담 요청(`POST /consultations`)이 `gym_id` 를 places 에서
#: 검증하고, 헬스장 상세의 상담 버튼은 제휴 여부를 가리지 않는다. 넣지 않으면 이
#: 헬스장들에서 상담이 404 로 실패한다. `is_partner=False` 는 표시상의 구분일 뿐이라
#: 상담 가능 여부를 바꾸지 않는다 — 모델 주석과 같은 정의다(#1626).
_DISCOVERED_GYMS: tuple[
    tuple[str, str, str, float, float, float | None, str, str, str, list[str]], ...
] = (
    (
        "11621774", "휘트니스에이든", "서울 마포구 신촌로 92",
        37.5551767483122, 126.935686079639, None, "", "",
        "02-332-1720", [],
    ),
    (
        "1558845892", "하이핏", "서울 서대문구 연세로4길 19",
        37.5573727191112, 126.937816432934, None, "", "",
        "02-362-7822", [],
    ),
    (
        "328969863", "빌드업짐 PT 신촌점", "서울 서대문구 연세로4길 1",
        37.5570723299884, 126.937142154792, None, "", "",
        "0502-5552-4212", [],
    ),
    (
        "696444256", "신인규피티스튜디오", "서울 서대문구 명물길 10",
        37.5573851891011, 126.937543667755, None, "", "",
        "010-7616-9819", [],
    ),
)

#: 프론트 `MockGymRepository._trainers` 와 같은 id·문안. 화면이 mock 과 실 API 에서
#: 같아야 하므로 한 글자도 달라지면 안 된다.
#:
#: 김태오(`trainer-demo`)는 `seed_trainer.py` 가 만든다 — 담당 회원 링크가 딸려
#: 있어 여기서 중복 생성하지 않는다.
#:
#: **전원 시연용 가상 인물이다.** 로그인은 되지만 담당 회원이 없어, 트레이너 앱으로
#: 들어가면 로스터가 비어 있다. 실 트레이너 온보딩이 생기면 이 시드는 제거한다.
_TRAINERS: tuple[
    tuple[str, str, str, str, str, int, str, list[str]], ...
] = (
    ("trainer-park", "gym-oncare-sinchon", "박소율", "재활 트레이너",
     "무릎·허리 통증 관리 다수 경험", 11,
     "수술 후 회복과 만성 통증 관리를 주로 맡습니다. 무리하지 않는 범위에서 가동 범위를 조금씩 넓혀 갑니다.",
     ["물리치료사", "재활 트레이닝 NASM-CES"]),
    ("trainer-choi", "gym-oncare-sinchon", "최건우", "그룹 PT 트레이너",
     "2~4인 소그룹 수업 운영", 4,
     "2~4인 소그룹 수업을 진행합니다. 혼자서는 운동을 이어 가기 어려운 회원에게 적합한 방식입니다.",
     ["생활스포츠지도사 2급"]),
    ("trainer-kang", "gym-healthmate", "강다인", "퍼스널 트레이너",
     "교대근무 일정 맞춤 설계", 5,
     "불규칙한 근무 일정에 맞춘 운동 설계를 주로 합니다. 짧은 시간에 집중도를 높이는 근력 프로그램을 구성합니다.",
     ["건강운동관리사", "퍼스널트레이닝 CPT"]),
    ("trainer-yoon", "gym-healthmate", "윤재희", "근력 전문 트레이너",
     "기초 근력부터 단계별 지도", 8,
     "기초 근력부터 파워리프팅까지 단계를 나눠 지도합니다. 현재 들 수 있는 무게를 확인한 뒤 다음 단계를 정합니다.",
     ["퍼스널트레이닝 CPT"]),
    ("trainer-lee", "gym-bodyandsoul", "이도경", "퍼스널 트레이너",
     "초심자용 간단 루틴 구성", 9,
     "운동을 처음 시작하는 회원을 오래 지도했습니다. 식단 상담을 함께 진행해 생활 습관부터 조정합니다.",
     ["생활스포츠지도사 2급", "스포츠 영양사", "재활 트레이닝 NASM-CES"]),
    ("trainer-cho", "gym-bodyandsoul", "조민혁", "시니어 운동 트레이너",
     "고령 회원 균형 운동 장기 지도", 12,
     "60대 이상 회원 수업을 오래 맡았습니다. 균형 잡기와 낙상 예방 동작부터 시작해 천천히 강도를 올립니다.",
     ["건강운동관리사", "노인스포츠지도사"]),
    ("trainer-demo-jung", "11621774", "정수빈", "퍼스널 트레이너",
     "감량 정체기 식사·운동량 재조정", 6,
     "체중이 멈춘 시점에 식사량과 운동량을 다시 맞추는 일을 자주 합니다. 몸무게보다 둘레와 체성분 변화를 기준으로 판단합니다.",
     ["생활스포츠지도사 2급"]),
    ("trainer-demo-ha", "11621774", "하윤슬", "체형 교정 트레이너",
     "장시간 착석형 목·어깨 교정", 4,
     "오래 앉아 생긴 목과 어깨 불편을 주로 다룹니다. 스트레칭과 가벼운 근력 운동을 번갈아 배치해 한 시간을 구성합니다.",
     ["필라테스 지도자", "생활스포츠지도사 2급"]),
    ("trainer-demo-han", "1558845892", "한서준", "퍼스널 트레이너",
     "기구 입문자 눈높이 지도", 3,
     "기구 사용법부터 하나씩 익히는 수업입니다. 무게를 올리기 전에 자세가 자리를 잡을 때까지 시간을 들입니다.",
     ["퍼스널트레이닝 CPT"]),
    ("trainer-demo-oh", "1558845892", "오태린", "그룹 PT 트레이너",
     "3~5인 그룹 수업 출석 관리", 5,
     "3~5인 그룹 수업을 맡습니다. 서로 속도를 맞추는 구성이라 혼자 할 때보다 출석이 안정적으로 유지됩니다.",
     ["생활스포츠지도사 2급"]),
    ("trainer-demo-seo", "328969863", "서지안", "재활 전문 트레이너",
     "병원 재활 이후 복귀 단계 관리", 10,
     "병원 재활이 끝난 뒤 일상 운동으로 넘어가는 구간을 담당합니다. 통증 기록을 함께 남기며 주 단위로 강도를 조절합니다.",
     ["물리치료사", "건강운동관리사"]),
    ("trainer-demo-nam", "328969863", "남도윤", "퍼스널 트레이너",
     "스쿼트·데드리프트 영상 자세 교정", 7,
     "스쿼트와 데드리프트 자세 교정을 주로 합니다. 수행 장면을 영상으로 남겨 회차별로 달라진 점을 함께 확인합니다.",
     ["퍼스널트레이닝 CPT"]),
    ("trainer-demo-moon", "696444256", "문하람", "퍼스널 트레이너",
     "주간 식단 기록 점검", 7,
     "1:1 수업만 진행합니다. 매주 식사 기록을 함께 보고 다음 주에 바꿀 항목을 한 가지씩 정합니다.",
     ["스포츠 영양사", "생활스포츠지도사 2급"]),
    ("trainer-demo-bae", "696444256", "배시우", "러닝 코치",
     "무릎 부담 적은 러닝 자세 교정", 5,
     "달리기 자세와 호흡을 함께 점검합니다. 무릎에 부담이 덜 가는 보폭을 찾는 데 수업 시간을 많이 배정합니다.",
     ["생활스포츠지도사 2급"]),
)


def _seed_gyms(db: Session, rows, *, is_partner: bool) -> int:
    """헬스장(Place)과 부가 정보(GymProfile)를 넣는다. 이미 있으면 건너뛴다."""
    created = 0
    # 장소를 먼저 flush 해야 gym_profiles 의 FK 가 성립한다. 한 번에 add 하면
    # 같은 flush 안에서 gym_profiles 가 먼저 나가 FK 위반이 난다.
    for gym_id, name, address, lat, lng, *_ in rows:
        if db.get(models.Place, gym_id) is None:
            db.add(models.Place(
                id=gym_id, name=name, category="fitness", address=address,
                lat=lat, lng=lng,
            ))
            created += 1
    db.flush()

    for (
        gym_id, _name, _address, _lat, _lng, rating,
        weekday, weekend, phone, tags,
    ) in rows:
        if db.get(models.GymProfile, gym_id) is None:
            db.add(models.GymProfile(
                place_id=gym_id, rating=rating, weekday_hours=weekday,
                weekend_hours=weekend, phone=phone,
                tags_json=json.dumps(tags, ensure_ascii=False),
                is_partner=is_partner,
            ))
    return created


def _seed_trainers(db: Session) -> int:
    """트레이너 계정(User)과 프로필을 넣는다.

    이메일이 다른 계정에 선점됐으면 건너뛴다 — users.email 이 유니크라 기동이
    실패하면 안 된다(`seed_trainer.py` 와 같은 방침).
    """
    from app.core.security import hash_password

    password_hash = hash_password(get_settings().demo_login_password)
    created = 0
    for trainer_id, gym_id, name, role, reason, career, intro, certs in _TRAINERS:
        email = f"{trainer_id}@oncare.demo"
        if db.get(models.User, trainer_id) is None:
            taken = db.scalar(
                select(models.User).where(
                    models.User.email == email, models.User.id != trainer_id
                )
            )
            if taken is not None:
                logger.warning(
                    "트레이너 데모 이메일 %s 가 다른 계정에 선점됨 — 스킵.", email
                )
                continue
            db.add(models.User(
                id=trainer_id, email=email, name=name,
                hashed_password=password_hash, role="trainer",
            ))
            created += 1
    db.flush()

    for trainer_id, gym_id, name, role, reason, career, intro, certs in _TRAINERS:
        if db.get(models.User, trainer_id) is None:
            continue  # 위에서 스킵된 계정
        exists = db.scalar(
            select(models.TrainerProfile).where(
                models.TrainerProfile.trainer_id == trainer_id
            )
        )
        if exists is not None:
            continue
        db.add(models.TrainerProfile(
            trainer_id=trainer_id, gym_id=gym_id, specialty=role,
            recommend_reason=reason, career_years=career, intro=intro,
            certifications_json=json.dumps(certs, ensure_ascii=False),
        ))
    return created


def _seed_member_gym_links(db: Session) -> int:
    """회원↔헬스장 링크(멱등). 담당 트레이너의 소속으로 채운다. (#444)

    마이그레이션 `0021_member_gym_link` 의 백필과 같은 규칙이다. 스키마를
    `create_all` 로 만드는 경로(로컬·테스트)에는 그 백필이 돌지 않으므로 여기서도
    채워야 마이그레이션 DB 와 같은 상태가 된다.

    이미 링크가 있는 회원은 건드리지 않는다 — 회원이 트레이너와 다른 헬스장으로
    옮겼을 수 있고, 시드가 그걸 되돌리면 안 된다.
    """
    created = 0
    rows = db.execute(
        select(models.TrainerClient.member_id, models.TrainerProfile.gym_id)
        .join(
            models.TrainerProfile,
            models.TrainerProfile.trainer_id == models.TrainerClient.trainer_id,
        )
        .where(
            models.TrainerClient.active.is_(True),
            models.TrainerProfile.gym_id.is_not(None),
        )
    ).all()
    for member_id, gym_id in rows:
        if db.get(models.MemberGym, member_id) is not None:
            continue
        db.add(models.MemberGym(member_id=member_id, gym_id=gym_id))
        created += 1
    return created


def seed_partner_gyms() -> None:
    db: Session = SessionLocal()
    try:
        partner = _seed_gyms(db, _PARTNER_GYMS, is_partner=True)
        # 카카오 발견 헬스장은 제휴가 아니다. 상담 대상 검증이 places 를 보므로
        # 넣지 않으면 이 헬스장들에서 상담 요청이 404 가 난다.
        discovered = _seed_gyms(db, _DISCOVERED_GYMS, is_partner=False)
        db.commit()

        # 이전 버전 시드가 발견 헬스장에 지어낸 평점·영업시간·태그를 넣어 뒀다.
        # 멱등 시드는 기존 행을 건드리지 않으므로 이미 만들어진 DB 에는 그 값이 남는다.
        # 실재 상호에 붙는 허위 수치라 여기서 지운다(리뷰 지적).
        corrected = 0
        for gym_id, *_ in _DISCOVERED_GYMS:
            profile = db.get(models.GymProfile, gym_id)
            if profile is None:
                continue
            if (
                profile.rating is None
                and not profile.weekday_hours
                and not profile.weekend_hours
                and profile.tags_json in ("[]", "")
            ):
                continue
            profile.rating = None
            profile.weekday_hours = ""
            profile.weekend_hours = ""
            profile.tags_json = "[]"
            corrected += 1
        if corrected:
            db.commit()
            logger.info("발견 헬스장 %d곳의 시연용 수치를 지웠습니다.", corrected)

        trainers = _seed_trainers(db)
        db.commit()

        # seed_trainer.py 가 만든 김태오는 gym_name 문자열만 들고 있어 헬스장
        # 상세의 "소속 트레이너"가 비어 있었다. 이름으로 gym_id 를 이어 준다.
        linked = 0
        by_name = {name: gid for gid, name, *_ in _PARTNER_GYMS}
        for profile in db.scalars(
            select(models.TrainerProfile).where(
                models.TrainerProfile.gym_id.is_(None)
            )
        ).all():
            gym_id = by_name.get(profile.gym_name)
            if gym_id is None:
                continue
            profile.gym_id = gym_id
            linked += 1
        db.commit()

        members = _seed_member_gym_links(db)
        db.commit()

        if partner or discovered or trainers or linked or members:
            logger.info(
                "헬스장 시드: 제휴 %d곳, 발견 %d곳, 트레이너 %d명, 소속 연결 %d명, "
                "회원 헬스장 %d명",
                partner, discovered, trainers, linked, members,
            )
    finally:
        db.close()
