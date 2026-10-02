"""
트레이너 라우터 — 트레이너 앱 전용(role == 'trainer'). (#2909)

영역별 `APIRouter` 로 나뉘어 있고 `app/main.py` 가 [routers] 를 같은 prefix 로
차례대로 마운트한다. 모든 엔드포인트는 RequireTrainer 로 보호되며 데모 폴백이 없다
(회원 데모 사용자 유입 차단).

| 모듈 | 영역 |
| --- | --- |
| `_common` | 담당 고객·프로필 확인, 열람 감사, 날짜 형식 검사 |
| `profile` | 내 계정(프로필·소속 헬스장·비밀번호·탈퇴·알림 설정) |
| `clients` | 담당 고객 목록·상태와 고객 기록 열람 |
| `chat` | 채팅(사진 메시지 포함) |
| `routines` | 루틴 배정·루틴 선택지 |
| `routine_suggestions` | AI 개인운동 제안 검토 |
| `memos` | 회원별 트레이너 메모 |
| `follow_ups` | 고객 후속 관리 할 일 |
| `programs` | 프로그램 초안·템플릿 |
| `task_progress` | 대시보드 오늘 할 일 진행 상태 |
| `schedule` | 스케줄 |
| `ai_coach` | AI 코칭 |
| `reports` | 주간 리포트 |
| `client_invites` | 담당 요청·연결 코드 |
| `consultations` | 상담 인박스 |
| `notifications` | 알림함 |

이 패키지는 [routers] 만 낸다. 엔드포인트·상수는 각 영역 모듈에서 가져온다.
"""
from __future__ import annotations

from app.api.v1.trainer import (
    ai_coach,
    chat,
    client_invites,
    clients,
    consultations,
    follow_ups,
    memos,
    notifications,
    profile,
    programs,
    reports,
    routine_suggestions,
    routines,
    schedule,
    task_progress,
)

#: 마운트 순서. 영역 안의 라우트 순서는 그대로이고, 영역 사이 순서는 나누기 전
#: 단일 파일에서 각 영역이 처음 나오던 순서를 따른다.
routers = (
    profile.router,
    clients.router,
    chat.router,
    routines.router,
    routine_suggestions.router,
    memos.router,
    follow_ups.router,
    programs.router,
    task_progress.router,
    schedule.router,
    ai_coach.router,
    reports.router,
    client_invites.router,
    consultations.router,
    notifications.router,
)

