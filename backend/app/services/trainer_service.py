"""
트레이너 도메인 서비스 — 호환 경로. (#2909)

로직은 `app.services.trainer` 패키지의 영역별 모듈에 있다. 이 모듈은 호환 단계 동안
그 모듈들의 이름을 같은 객체로 다시 내보내 기존 호출부(`trainer_service.X`)와 테스트의
monkeypatch 대상이 그대로 동작하게 한다(`app.core.module_reexport`). 영역별로 호출부
import 를 옮긴 뒤 마지막 단계에서 지운다.
"""
from __future__ import annotations

from app.core.module_reexport import reexport
from app.services.trainer import (
    _common,
    chat,
    client_status,
    follow_ups,
    gym,
    member_mirror,
    memos,
    notification_settings,
    profile,
    programs,
    reports,
    roster,
    routine_suggestions,
    routines,
    schedule,
    weekly_feedback,
)

reexport(
    __name__,
    (
        _common,
        roster,
        chat,
        client_status,
        routines,
        routine_suggestions,
        memos,
        follow_ups,
        programs,
        schedule,
        member_mirror,
        profile,
        gym,
        reports,
        notification_settings,
        weekly_feedback,
    ),
)
