"""회원↔트레이너 전 경로를 실 API 로 훑어 끊긴 곳을 찾는다 (#479).

단위 테스트는 각 조각이 도는 것만 보증한다. 이 스크립트는 **두 역할이 같은 DB 를
사이에 두고 실제로 이어지는지** 를 본다 — 회원이 남긴 것이 트레이너에게 보이고,
트레이너가 한 일이 회원에게 돌아오는지.

전 항목을 손으로 밟지 않는 이유는 재현 때문이다. 여기서 걸린 것만 화면으로 확인하면
된다(#479 의 검증 방법 참고).

사용법 (backend/ 디렉터리에서, 로컬 스택이 떠 있는 상태):
  docker compose up -d
  python -m scripts.e2e_sweep
  python -m scripts.e2e_sweep --base http://localhost:8000/v1

만든 것은 모두 되돌린다 — 식단·운동 세션은 DELETE, 건강 목표는 원래 값으로 복구,
채팅과 거기서 파생된 개인 RAG 문서(#580)는 DB 에서 제거(둘 다 삭제 API 가 없다).
그래서 몇 번을 돌려도 데모 DB 가 그대로다. 정리에 실패하면 조용히 넘어가지 않고
FAIL 로 보고한다. DB 정리는 항상 로컬 DATABASE_URL 로 붙으므로 --allow-remote 로
원격을 때릴 때는 아예 건너뛴다(SKIP) — 그러지 않으면 검증 대상도 아닌 로컬 문서를
지운다. 대신 원격에는 채팅과 RAG 문서가 남는다.

혼자 쓰는 로컬 데모 DB 를 전제로 한다. 자세한 이유는 purge_sweep_traces 참고.

AI 루틴 경로(A/B 생성 → 편집 → 배정 → 회원 수신)도 훑는다(#589). 키가 없으면 규칙
폴백이 200 을 돌려주므로, 계약 검사와 "AI 가 실제로 돌았는가" 를 분리해 뒤쪽은
`generated_by` 로 판정한다 — 폴백이면 SKIP 이라 조용히 초록불이 되지 않는다.
"""
from __future__ import annotations

import argparse
import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

DEFAULT_BASE = "http://localhost:8000/v1"
DEMO_PASSWORD = "oncare123"
MEMBER_EMAIL = "jisu@oncare.com"
MEMBER_ID = "user-jisu"
TRAINER_EMAIL = "trainer@oncare.com"
# urlsplit(...).hostname 은 대괄호를 벗겨 '::1' 로 돌려준다. '[::1]' 로 적으면 영원히
# 매칭되지 않아 IPv6 루프백이 원격 취급된다.
LOCAL_HOSTS = ("localhost", "127.0.0.1", "::1", "host.docker.internal")

# 16×16 진짜 JPEG. 서버가 인식 전에 픽셀까지 읽어 정리하므로(#3041) 매직 넘버만
# 맞춘 가짜 바이트는 415 로 끝난다.
_JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcU"
    "FhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgo"
    "KCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAAQABADASIA"
    "AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA"
    "AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3"
    "ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm"
    "p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA"
    "AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx"
    "BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK"
    "U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3"
    "uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwC5RRRX"
    "xx9mf//Z"
)
_BOUNDARY = "----e2esweep"

# 실행마다 다른 키를 쓴다. 고정 키면 정리(DELETE)가 실패했을 때 다음 실행이 기존
# 엔트리를 그대로 돌려받아(find_by_idempotency), 식단이 안 늘어난 것처럼 보인다.
_RUN_TAG = str(int(time.time()))
_MARKER = "e2e-sweep-" + _RUN_TAG

#: 스윕이 적재를 유발하는 경로. 정리 범위를 이 둘로 좁혀 다른 문서를 건드리지 않는다.
SWEEP_DOC_SOURCES = ("chat", "diet")


class Result:
    """시나리오 하나의 결과. 실패는 '무엇이 기대와 달랐는지'까지 남긴다."""

    def __init__(self, group: str, name: str, status: str, detail: str = "") -> None:
        self.group = group
        self.name = name
        self.status = status  # PASS | FAIL | SKIP
        self.detail = detail


class Api:
    def __init__(self, base: str) -> None:
        self.base = base.rstrip("/")

    def _call(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        json_body: Any = None,
        form: dict[str, str] | None = None,
        multipart: tuple[str, bytes, str] | None = None,
    ) -> tuple[int, Any]:
        url = f"{self.base}{path}"
        data: bytes | None = None
        headers: dict[str, str] = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if json_body is not None:
            data = json.dumps(json_body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        elif form is not None:
            data = urllib.parse.urlencode(form).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif multipart is not None:
            field, blob, extra = multipart
            body = (
                f"--{_BOUNDARY}\r\n"
                f'Content-Disposition: form-data; name="{field}"; filename="meal.jpg"\r\n'
                "Content-Type: image/jpeg\r\n\r\n"
            ).encode() + blob + f"\r\n{extra}--{_BOUNDARY}--\r\n".encode()
            data = body
            headers["Content-Type"] = f"multipart/form-data; boundary={_BOUNDARY}"

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as res:
                raw = res.read().decode("utf-8")
                return res.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(raw)
            except json.JSONDecodeError:
                return e.code, raw
        except Exception as e:  # noqa: BLE001 — 연결 실패도 결과로 보고한다
            return 0, str(e)

    def get(self, path, **kw):
        return self._call("GET", path, **kw)

    def post(self, path, **kw):
        return self._call("POST", path, **kw)

    def put(self, path, **kw):
        return self._call("PUT", path, **kw)

    def delete(self, path, **kw):
        return self._call("DELETE", path, **kw)

    def login(self, email: str) -> str | None:
        code, body = self.post(
            "/auth/login", form={"username": email, "password": DEMO_PASSWORD}
        )
        if code == 200 and isinstance(body, dict):
            return body.get("access_token")
        return None


def multipart_fields(pairs: dict[str, str]) -> str:
    out = ""
    for k, v in pairs.items():
        out += (
            f"--{_BOUNDARY}\r\n"
            f'Content-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'
        )
    return out

# ─────────────────────────────────────────────── 시나리오 ──


def scenario_auth(api: Api, m: str, t: str, out: list[Result]) -> None:
    g = "인증·계정"
    code, _ = api.get("/users/me", token=m)
    out.append(Result(g, "회원 /users/me", "PASS" if code == 200 else "FAIL", str(code)))

    code, _ = api.get("/users/me/health", token=m)
    out.append(Result(g, "건강정보 조회", "PASS" if code == 200 else "FAIL", str(code)))

    # 목표는 PUT 전용이라 GET 이 없지만 /users/me/profile 이 같은 값을 노출한다.
    # 원래 값을 먼저 읽어 두고 끝나면 되돌린다 — 스윕이 데모 DB 를 바꿔 놓으면
    # 반복 실행할수록 시연 데이터가 실제와 어긋난다.
    #
    # 읽지 못했으면 아예 건드리지 않는다. 조회 실패를 None 으로 뭉개고 진행하면
    # 원래 값을 덮어쓴 뒤 None 으로 "복구" 해서, 있던 목표를 지워 버린다.
    prof_code, profile = api.get("/users/me/profile", token=m)
    readable = prof_code == 200 and isinstance(profile, dict) and "daily_calories" in profile
    if not readable:
        out.append(Result(
            g, "건강 목표 저장", "FAIL",
            f"원래 값을 못 읽어 변경하지 않음 (프로필 조회 {prof_code})",
        ))
    else:
        original = profile["daily_calories"]
        probe = 1800 if original != 1800 else 1900

        code, _ = api.put(
            "/users/me/health-goals", token=m, json_body={"daily_calories": probe}
        )
        _, after = api.get("/users/me/profile", token=m)
        saved = after.get("daily_calories") if isinstance(after, dict) else None
        dash_code, _ = api.get("/dashboard/summary", token=m)
        ok = code in (200, 201) and saved == probe and dash_code == 200
        out.append(Result(
            g, "건강 목표 저장", "PASS" if ok else "FAIL",
            f"{code} daily_calories -> {saved} (기대 {probe})",
        ))

        code, _ = api.put(
            "/users/me/health-goals", token=m, json_body={"daily_calories": original}
        )
        _, restored = api.get("/users/me/profile", token=m)
        back = restored.get("daily_calories") if isinstance(restored, dict) else None
        out.append(Result(
            g, "건강 목표 원복(정리)", "PASS" if back == original else "FAIL",
            f"{back} (원래 {original})",
        ))

    code, _ = api.get("/trainer/me", token=t)
    out.append(Result(g, "트레이너 /trainer/me", "PASS" if code == 200 else "FAIL", str(code)))

    # 권한: 회원 토큰으로 트레이너 API 는 막혀야 한다
    code, _ = api.get("/trainer/clients", token=m)
    out.append(Result(
        g, "회원 토큰으로 트레이너 API 차단",
        "PASS" if code in (401, 403) else "FAIL", f"{code} (401/403 기대)",
    ))


def scenario_diet(api: Api, m: str, t: str, out: list[Result]) -> None:
    from datetime import date

    g = "식단"
    code, before = api.get("/trainer/clients/" + MEMBER_ID + "/diet", token=t)
    n_before = len(before) if code == 200 and isinstance(before, list) else -1

    code, body = api.post(
        "/diet/analyze",
        token=m,
        multipart=("image", _JPEG, multipart_fields(
            {"meal_type": "dinner", "idempotency_key": _MARKER}
        )),
    )
    out.append(Result(g, "사진 업로드·분석", "PASS" if code == 200 else "FAIL", str(code)))
    entry_id = body.get("entry_id") if code == 200 and isinstance(body, dict) else None

    code, day = api.get("/diet/days/today", token=m)
    entries = (day or {}).get("entries", []) if isinstance(day, dict) else []
    has = code == 200 and any(e.get("id") == entry_id for e in entries)
    out.append(Result(g, "오늘 식단에 반영", "PASS" if has else "FAIL", str(code)))

    # #516 이 구현한 일별 복원 — 실 API 기준으로 다시 확인
    code, _ = api.get("/diet/days/" + date.today().isoformat(), token=m)
    out.append(Result(g, "일별 복원 /diet/days/{date}", "PASS" if code == 200 else "FAIL", str(code)))

    code, after = api.get("/trainer/clients/" + MEMBER_ID + "/diet", token=t)
    n_after = len(after) if code == 200 and isinstance(after, list) else -1
    grew = n_before >= 0 and n_after > n_before
    out.append(Result(
        g, "회원 식단 → 트레이너 화면", "PASS" if grew else "FAIL", f"{n_before} -> {n_after}",
    ))

    # 정리는 조용히 건너뛰면 안 된다. 남은 엔트리는 시드 개수를 단언하는 pytest 를
    # 깨뜨리므로(docs/local_fullstack.md '알려진 함정'), 못 지웠으면 FAIL 로 알린다.
    if entry_id:
        code, _ = api.delete("/diet/entries/" + entry_id, token=m)
        out.append(Result(g, "식단 삭제(정리)", "PASS" if code in (200, 204) else "FAIL", str(code)))
    else:
        out.append(Result(g, "식단 삭제(정리)", "FAIL", "entry_id 를 못 받아 정리 못 함"))


def _db_session():
    """로컬 DB 세션. reembed.py 와 같은 방식이며, 열 수 없으면 사유를 돌려준다."""
    try:
        from app.db.session import SessionLocal
    except Exception as e:  # noqa: BLE001 - 임포트 실패도 결과로 보고한다
        return None, f"임포트 실패: {e!r}"
    try:
        return SessionLocal(), ""
    except Exception as e:  # noqa: BLE001
        return None, repr(e)


def latest_document_id() -> tuple[int, str]:
    """개인 RAG 문서의 현재 최대 id. 이후 생긴 문서를 가려내는 기준선이다."""
    db, err = _db_session()
    if db is None:
        return -1, err
    try:
        from sqlalchemy import func, select

        from app.models.models import CoachDocument

        return int(db.execute(select(func.coalesce(func.max(CoachDocument.id), 0))).scalar_one()), ""
    except Exception as e:  # noqa: BLE001
        return -1, repr(e)
    finally:
        db.close()


def purge_sweep_traces(marker: str, doc_baseline: int) -> tuple[int, int, str]:
    """스윕이 남긴 채팅과 그로부터 파생된 개인 RAG 문서를 지운다.

    채팅에는 삭제 API 가 없다(coach/trainer 라우터 모두 GET·POST 뿐). 게다가 #580
    이후 식단·채팅이 개인 RAG 문서로 적재되므로(personal_ingest), 원본을 지워도
    문서는 남아 AI 코칭 근거를 오염시킨다. 문서 본문에는 마커가 없는 것도 있어
    (식단 문서는 분석 결과 그대로다) 문자열이 아니라 **실행 전 최대 id** 를
    기준으로, 스윕이 실제로 만드는 source('chat'·'diet') 만 지운다.

    기준선은 '누가 만들었는지' 를 증명하지 못한다. 같은 회원이 그 사이에 앱을
    쓰고 있었다면 그 문서도 범위에 든다. 이 스윕은 **혼자 쓰는 로컬 데모 DB** 를
    전제로 한다(pytest 도 같은 DB 를 쓰므로 원래 그렇다 — docs/local_fullstack.md).
    삭제 건수를 기대값과 대조하므로, 예상 밖이 섞이면 FAIL 로 드러난다.

    호출자가 로컬 대상일 때만 부른다. DB 접속은 항상 로컬 DATABASE_URL 이라
    원격 스윕에서 부르면 엉뚱한(로컬) 데이터를 지운다.
    """
    db, err = _db_session()
    if db is None:
        return -1, -1, err
    try:
        from sqlalchemy import delete

        from app.models.models import ChatMessage, CoachDocument

        chats = db.execute(
            # 마커는 글자 그대로 찾는다 — `%`·`_` 가 와일드카드가 되지 않게(#3251).
            delete(ChatMessage).where(ChatMessage.body.contains(marker, autoescape=True))
        ).rowcount or 0
        docs = 0
        if doc_baseline >= 0:
            docs = db.execute(
                delete(CoachDocument).where(
                    CoachDocument.user_id == MEMBER_ID,
                    CoachDocument.id > doc_baseline,
                    CoachDocument.source.in_(SWEEP_DOC_SOURCES),
                )
            ).rowcount or 0
        db.commit()
        return chats, docs, ""
    except Exception as e:  # noqa: BLE001
        return -1, -1, repr(e)
    finally:
        db.close()


def scenario_chat(api: Api, m: str, t: str, out: list[Result]) -> None:
    g = "채팅"
    from_member = "e2e sweep from member " + _MARKER
    from_trainer = "e2e sweep from trainer " + _MARKER

    code, _ = api.post("/me/coach/chat", token=m, json_body={"text": from_member})
    out.append(Result(g, "회원 발신", "PASS" if code in (200, 201) else "FAIL", str(code)))

    code, msgs = api.get("/trainer/clients/" + MEMBER_ID + "/chat", token=t)
    items = msgs if isinstance(msgs, list) else (msgs or {}).get("messages", [])
    seen = code == 200 and any(from_member in (x.get("body") or "") for x in items)
    out.append(Result(g, "트레이너 수신", "PASS" if seen else "FAIL", str(code)))

    code, _ = api.post(
        "/trainer/clients/" + MEMBER_ID + "/chat", token=t,
        json_body={"text": from_trainer},
    )
    out.append(Result(g, "트레이너 발신", "PASS" if code in (200, 201) else "FAIL", str(code)))

    code, msgs = api.get("/me/coach/chat", token=m)
    items = msgs if isinstance(msgs, list) else (msgs or {}).get("messages", [])
    seen = code == 200 and any(from_trainer in (x.get("body") or "") for x in items)
    out.append(Result(g, "회원 수신", "PASS" if seen else "FAIL", str(code)))

    code, _ = api.get("/me/coach/chat/unread", token=m)
    out.append(Result(g, "회원 미읽음 수", "PASS" if code == 200 else "FAIL", str(code)))

    code, _ = api.get("/trainer/chat/unread", token=t)
    out.append(Result(g, "트레이너 미읽음 수", "PASS" if code == 200 else "FAIL", str(code)))


def scenario_roster(api: Api, m: str, t: str, out: list[Result]) -> None:
    g = "트레이너 로스터·고객 상세"
    code, rows = api.get("/trainer/clients", token=t)
    n = len(rows) if isinstance(rows, list) else 0
    out.append(Result(g, "고객 목록", "PASS" if code == 200 else "FAIL", f"{code} n={n}"))

    for path, label in (
        ("/diet", "고객 식단"),
        ("/history", "고객 운동 이력"),
        ("/routines", "고객 루틴"),
        ("/report", "고객 리포트"),
    ):
        code, _ = api.get("/trainer/clients/" + MEMBER_ID + path, token=t)
        out.append(Result(g, label, "PASS" if code == 200 else "FAIL", str(code)))


def scenario_exercise(api: Api, m: str, t: str, out: list[Result]) -> None:
    g = "운동"
    code, week_before = api.get("/exercise/weeks/current", token=m)
    out.append(Result(g, "주간 조회", "PASS" if code == 200 else "FAIL", str(code)))

    code, created = api.post(
        "/exercise/sessions",
        token=m,
        # 추가는 목록으로 보낸다(#2544) — 한 건도 `sessions` 로 감싼다.
        json_body={"sessions": [
            {"type": "cardio", "intensity": "moderate", "minutes": 30, "calories": 210},
        ]},
    )
    out.append(Result(g, "세션 저장", "PASS" if code in (200, 201) else "FAIL", str(code)))
    saved = created.get("sessions") if isinstance(created, dict) else None
    session_id = saved[0].get("id") if saved else None

    # 응답 전체를 비교하면 '무언가 바뀌었다' 밖에 못 본다. 방금 넣은 30분·210kcal 이
    # 그대로 더해졌는지 집계 필드로 확인해야 실제로 반영된 것이다.
    code, week_after = api.get("/exercise/weeks/current", token=m)
    before_min = (week_before or {}).get("total_minutes") if isinstance(week_before, dict) else None
    after_min = (week_after or {}).get("total_minutes") if isinstance(week_after, dict) else None
    delta = (after_min - before_min) if isinstance(before_min, int) and isinstance(after_min, int) else None
    out.append(Result(
        g, "주간 집계에 반영", "PASS" if delta == 30 else "FAIL",
        f"{code} total_minutes {before_min} -> {after_min} (+30 기대)",
    ))

    # 트레이너가 회원 운동 이력을 읽는 경로
    code, _ = api.get("/trainer/clients/" + MEMBER_ID + "/history", token=t)
    out.append(Result(g, "트레이너가 운동 이력 조회", "PASS" if code == 200 else "FAIL", str(code)))

    if session_id:
        code, _ = api.delete("/exercise/sessions/" + session_id, token=m)
        out.append(Result(g, "세션 삭제(정리)", "PASS" if code in (200, 204) else "FAIL", str(code)))
    else:
        out.append(Result(g, "세션 삭제(정리)", "FAIL", "id 를 못 받아 정리 못 함"))


def scenario_reservation(api: Api, m: str, t: str, out: list[Result]) -> None:
    g = "예약·일정"
    for path, tok, label in (
        ("/reservations/me", m, "내 예약"),
        ("/schedule/events", m, "회원 일정"),
        ("/trainer/schedule", t, "트레이너 일정"),
        ("/trainer/reservation-slots", t, "트레이너 슬롯 관리"),
        ("/trainer/schedule/booked-dates", t, "예약된 날짜"),
    ):
        code, _ = api.get(path, token=tok)
        out.append(Result(g, label, "PASS" if code == 200 else "FAIL", str(code)))


def scenario_consultation(api: Api, m: str, t: str, out: list[Result]) -> None:
    g = "상담"
    for path, tok, label in (
        ("/consultations/me", m, "회원 상담 내역"),
        ("/trainer/consultations", t, "트레이너 상담 목록"),
        ("/trainer/consultations/pending-count", t, "대기 건수"),
    ):
        code, _ = api.get(path, token=tok)
        out.append(Result(g, label, "PASS" if code == 200 else "FAIL", str(code)))


def scenario_ai_routine(api: Api, m: str, t: str, out: list[Result]) -> None:
    """AI 루틴 A/B 생성 → 편집 → 배정 → 회원 수신 (#589).

    이 경로를 스윕에 넣지 못했던 이유가 있다: 키가 없으면 규칙 폴백이 200 을
    돌려주어 **AI 가 죽어도 통과처럼 보인다**. 그래서 계약 검사(A/B 모양·시간 상한)와
    "AI 가 실제로 돌았는가" 를 분리한다. 앞은 어느 경우든 PASS 여야 하고, 뒤는
    `generated_by` 로 판정해 규칙 폴백이면 SKIP 으로 남긴다 — 조용히 초록불이
    되지 않게.
    """
    g = "AI 루틴"
    available = 40
    code, options = api.post(
        "/trainer/clients/" + MEMBER_ID + "/routine-options",
        token=t,
        json_body={
            "available_minutes": available,
            "intensity_preference": "moderate",
            "trainer_note": _MARKER + " 무릎 부담 낮게",
        },
    )
    ok = code == 200 and isinstance(options, dict)
    out.append(Result(g, "A/B 생성", "PASS" if ok else "FAIL", str(code)))
    if not ok:
        return

    plan_a = options.get("plan_a") or {}
    plan_b = options.get("plan_b") or {}
    shape_ok = (
        plan_a.get("key") == "A" and plan_b.get("key") == "B"
        and bool(plan_a.get("exercises")) and bool(plan_b.get("exercises"))
    )
    out.append(Result(
        g, "A/B 계약", "PASS" if shape_ok else "FAIL",
        "key=" + str(plan_a.get("key")) + "/" + str(plan_b.get("key")),
    ))

    # 트레이너가 입력한 가능 시간을 넘는 계획은 그대로 배정될 수 없다.
    totals = [p.get("total_minutes") for p in (plan_a, plan_b)]
    within_limit = all(
        type(minutes) is int and minutes <= available
        for minutes in totals
    )
    out.append(Result(
        g, "가능 시간 상한", "PASS" if within_limit else "FAIL",
        f"available={available} total_minutes={totals}",
    ))

    generated_by = options.get("generated_by")
    if generated_by == "ai":
        out.append(Result(g, "AI 가 실제로 생성", "PASS", "generated_by=ai"))
    else:
        out.append(Result(
            g, "AI 가 실제로 생성", "SKIP",
            "generated_by=" + str(generated_by) + " - LLM 키가 없거나 폴백. "
            "코치 키를 넣고 다시 돌려야 이 경로가 검증된다",
        ))

    # #580: 채팅이 근거로 실렸는지. 앞선 채팅 시나리오가 남긴 메시지가 있어야 한다.
    recent = (options.get("analysis") or {}).get("recent_messages")
    evidence_ok = (
        isinstance(recent, list)
        and any(
            isinstance(message, str) and _MARKER in message
            for message in recent
        )
    )
    out.append(Result(
        g, "채팅 근거 반영(#580)",
        "PASS" if evidence_ok else "FAIL",
        f"recent_messages={len(recent) if isinstance(recent, list) else 'none'}",
    ))

    # 트레이너가 A안을 손봐서 배정한다 — 생성 결과를 그대로 보내는 게 아니라
    # 편집이 반영되는지까지 봐야 화면과 같은 경로다.
    first = (plan_a.get("exercises") or [{}])[0]
    routine = {
        "name": _MARKER + " 편집한 루틴",
        "minutes": max(1, int(first.get("minutes") or 10)),
        "type": first.get("type") or "유산소",
        "reason": "스윕이 배정",
        "source": "ai",
        "client_request_id": "sweep-" + _RUN_TAG,
    }
    code, assigned = api.post(
        "/trainer/clients/" + MEMBER_ID + "/routines", token=t, json_body=routine
    )
    created = code in (200, 201) and isinstance(assigned, dict)
    out.append(Result(g, "편집 후 배정", "PASS" if created else "FAIL", str(code)))
    routine_id = assigned.get("id") if created else None

    # #581: 같은 키로 재전송해도 하나만 남아야 한다. 끊긴 전송을 다시 누르는 상황이다.
    code, again = api.post(
        "/trainer/clients/" + MEMBER_ID + "/routines", token=t, json_body=routine
    )
    same = isinstance(again, dict) and again.get("id") == routine_id
    out.append(Result(
        g, "재전송 멱등(#581)", "PASS" if same else "FAIL",
        f"{code} id={again.get('id') if isinstance(again, dict) else again} (같아야 함)",
    ))

    # 회원 쪽에서 실제로 받았는가 — 여기까지 와야 루프가 닫힌다.
    code, mine = api.get("/me/coach/routines", token=m)
    names = [r.get("name") for r in mine] if isinstance(mine, list) else []
    received = routine["name"] in names
    out.append(Result(
        g, "회원이 수신", "PASS" if received else "FAIL",
        f"{code} n={len(names)}",
    ))
    # 배정이 하나만 갔는지 — 멱등이 깨지면 여기서 2건으로 보인다.
    out.append(Result(
        g, "중복 배정 없음", "PASS" if names.count(routine["name"]) == 1 else "FAIL",
        f"{names.count(routine['name'])}건 (1건 기대)",
    ))

    if routine_id:
        code, _ = api.delete(
            "/trainer/clients/" + MEMBER_ID + "/routines/" + routine_id, token=t
        )
        out.append(Result(
            g, "루틴 철회(정리)", "PASS" if code in (200, 204) else "FAIL", str(code)
        ))
    else:
        out.append(Result(g, "루틴 철회(정리)", "FAIL", "id 를 못 받아 정리 못 함"))


def scenario_misc(api: Api, m: str, t: str, out: list[Result]) -> None:
    g = "회원 화면"
    for path, label in (
        ("/dashboard/summary", "홈 대시보드"),
        ("/exercise/weeks/current", "운동 주간"),
        ("/notifications", "알림함"),
        ("/me/coach", "담당 코치"),
        ("/me/coach/routines", "배정 루틴"),
        ("/me/coach/sessions", "PT 세션"),
        ("/diet/recommendations", "식단 추천"),
        ("/trainers/recommended", "추천 트레이너"),
        ("/gyms", "헬스장"),
    ):
        code, _ = api.get(path, token=m)
        out.append(Result(g, label, "PASS" if code == 200 else "FAIL", str(code)))

    g2 = "트레이너 화면"
    for path, label in (
        ("/trainer/notifications", "알림함"),
        ("/trainer/notifications/unread-count", "미읽음 수"),
        ("/trainer/me/settings", "설정"),
    ):
        code, _ = api.get(path, token=t)
        out.append(Result(g2, label, "PASS" if code == 200 else "FAIL", str(code)))


def is_local(base: str) -> bool:
    host = urllib.parse.urlsplit(base).hostname or ""
    return host in LOCAL_HOSTS or host.endswith(".localhost")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument(
        "--allow-remote",
        action="store_true",
        help="로컬이 아닌 --base 를 허용한다(데이터를 쓰고 지우므로 기본은 거부).",
    )
    args = ap.parse_args()

    # 이 스크립트는 읽기만 하지 않는다. 식단·운동 세션·채팅을 만들고 DELETE 까지 한다.
    # 배포 환경을 실수로 가리키면 실제 사용자 데이터를 건드리므로 기본은 로컬만 허용.
    if not is_local(args.base) and not args.allow_remote:
        print("거부: " + args.base + " 은 로컬이 아닙니다.")
        print("  이 스크립트는 식단/운동/채팅을 생성하고 삭제합니다.")
        print("  정말 이 대상에 쓰려면 --allow-remote 를 붙이세요.")
        return 2

    api = Api(args.base)
    member = api.login(MEMBER_EMAIL)
    trainer = api.login(TRAINER_EMAIL)
    if not member or not trainer:
        print("로그인 실패 - 백엔드가 " + args.base + " 에 떠 있는지 확인하세요.")
        print("  member=" + str(bool(member)) + " trainer=" + str(bool(trainer)))
        return 2

    # DB 정리는 언제나 로컬 DATABASE_URL 로 붙는다. 원격을 훑는 중에 부르면
    # 검증 대상이 아닌 로컬 데모 문서를 지우므로, 로컬일 때만 손댄다.
    local = is_local(args.base)
    doc_baseline, base_err = latest_document_id() if local else (-1, "")

    out: list[Result] = []
    for fn in (
        scenario_auth, scenario_diet, scenario_exercise, scenario_chat,
        # AI 루틴은 채팅 뒤에 둔다 — 채팅이 남긴 메시지가 생성 근거로 실렸는지
        # (#580) 함께 보기 때문이다.
        scenario_roster, scenario_ai_routine, scenario_reservation,
        scenario_consultation, scenario_misc,
    ):
        try:
            fn(api, member, trainer, out)
        except Exception as e:  # noqa: BLE001 - 한 그룹이 죽어도 나머지는 계속
            out.append(Result(fn.__name__, "실행 중 예외", "FAIL", repr(e)))

    # 채팅 2건과, 채팅이 파생시킨 개인 RAG 문서 2건을 지운다.
    #
    # 식단 문서는 여기까지 오지 않는다. `DELETE /diet/entries/{id}` 가 그 기록의
    # 문서까지 함께 지우기 때문이다(#603 `personal_ingest.forget`). 기대값이 3이던
    # 시절은 삭제가 원본만 지우던 때다 — 그대로 두면 이 스윕이 매번 FAIL 로 뜬다.
    g = "정리"
    if not local:
        note = "원격 대상 - 로컬 DB 를 건드리지 않음. 채팅·RAG 문서가 남는다"
        out.append(Result(g, "채팅 삭제", "SKIP", note))
        out.append(Result(g, "개인 RAG 문서 삭제", "SKIP", note))
    else:
        chats, docs, err = purge_sweep_traces(_MARKER, doc_baseline)
        out.append(Result(
            g, "채팅 삭제", "PASS" if chats == 2 else "FAIL",
            f"{chats}건 (2건 기대)" + (" - " + err if err else ""),
        ))
        out.append(Result(
            g, "개인 RAG 문서 삭제", "PASS" if docs == 2 else "FAIL",
            f"{docs}건 (2건 기대 - 식단 문서는 DELETE 가 이미 정리)"
            + (" - " + (err or base_err) if (err or base_err) else ""),
        ))

    group = None
    for r in out:
        if r.group != group:
            group = r.group
            print("")
            print("[" + group + "]")
        print("  " + r.status.ljust(4) + " " + r.name.ljust(30) + " " + r.detail)

    failed = [r for r in out if r.status == "FAIL"]
    skipped = [r for r in out if r.status == "SKIP"]
    print("")
    summary = ("총 " + str(len(out)) + "건 · 통과 "
               + str(len(out) - len(failed) - len(skipped))
               + " · 실패 " + str(len(failed)))
    if skipped:
        summary += " · 건너뜀 " + str(len(skipped))
    print(summary)
    if failed:
        print("")
        print("실패 목록 (화면 확인 대상):")
        for r in failed:
            print("  - [" + r.group + "] " + r.name + " - " + r.detail)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
