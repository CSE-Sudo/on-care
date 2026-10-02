"""트레이너 도메인 서비스 — 영역별 모듈. (#2909)

| 모듈 | 영역 |
| --- | --- |
| `_common` | 영역이 함께 쓰는 도우미(날짜·라벨·기록 표기, 루틴·일정 상태, 공용 집계·변환) |
| `roster` | 고객 로스터·식단·기록 집계 |
| `chat` | 트레이너↔회원 채팅 |
| `client_status` | 회원 활성/휴면 관리와 담당 해제 |
| `routines` | 루틴 배정·완료·프로그램 배정 |
| `routine_suggestions` | AI 개인운동 제안 검토 |
| `memos` | 회원별 트레이너 메모 |
| `follow_ups` | 고객 후속 관리 할 일 |
| `programs` | 프로그램 초안 |
| `schedule` | 스케줄(예약→수업→기록 완료 루프) |
| `member_mirror` | 회원측 미러(내 담당 코치·받은 루틴·내 세션) |
| `profile` | 트레이너 프로필·계정 삭제 |
| `gym` | 소속 헬스장 |
| `reports` | 주간 리포트·피드백 초안·주간 목표·보낸 리포트 |
| `notification_settings` | 알림 수신 설정 |
| `weekly_feedback` | 회원 주간 피드백 |

영역 모듈끼리 서로의 비공개 헬퍼를 직접 부르지 않고 `_common` 을 거친다.
예전 경로 `app.services.trainer_service` 는 호환 단계 동안 이 모듈들을 다시 내보낸다.
"""
