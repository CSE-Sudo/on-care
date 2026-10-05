# Backend API Catalog — Oncare Flutter ⇆ FastAPI

> **[제안 문서 — 계약의 정답이 아닙니다]** 실제 API 계약은
> **[backend/API_CONTRACT.md](../../../backend/API_CONTRACT.md)** 가 단일 출처입니다.
> 백엔드가 구현된 지금, 엔드포인트·요청/응답 형태를 확인할 때는 그쪽을 보세요.
> 두 문서가 어긋나면 `API_CONTRACT.md` 가 맞습니다.
>
> 아래는 백엔드 구현 **전에** 프런트 도메인 모델을 기준으로 "이런 엔드포인트가
> 필요하다" 고 정리했던 초안입니다.

| 베이스 | `${API_BASE_URL}/api/v1` |
| --- | --- |
| 인증 | `Authorization: Bearer <jwt>` (POST /auth/social 이후 발급) |
| 응답 | `application/json`, snake_case 권장 (Flutter 측에서 camelCase로 매핑) |
| 시간 | ISO 8601 (`2026-05-20T08:00:00+09:00`) |
| 오류 | `{code, message, details?}` + HTTP status (`core/errors/app_error.dart` 매핑) |

---

## 1. Auth (Q4: Google / Kakao / Naver)

| Method | Path | Body | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| POST | `/auth/social` | `{provider, id_token, nonce?}` | `{access_token, refresh_token, user: UserProfile}` | `MockAuthRepository.signIn` |
| POST | `/auth/refresh` | `{refresh_token}` | `{access_token, refresh_token}` | dio interceptor (Stage 4 후속) |
| POST | `/auth/logout` | `{refresh_token}` | `204` | `SessionController.signOut` |

`provider` enum: `google | kakao | naver` (소문자, `AuthProvider.name`). 애플 로그인은 제공하지 않는다(#3218) — `apple` 은 400.

---

## 2. Users / Me

| Method | Path | 응답 | Flutter 사용처 |
| --- | --- | --- | --- |
| GET | `/users/me` | `UserProfile { id, name, email, avatar_url? }` | `AuthUser`, MyHealth `ProfileCard` |
| PATCH | `/users/me` | `UserProfile` | (설정 페이지, 후속) |
| GET | `/users/me/health` | `MyHealthState` payload | `MockMyHealthRepository.fetchState` |
| GET | `/users/me/points` | `{ points, rank, leaderboard?[] }` | MyHealth `PointsCard` |

`MyHealthState` payload (MY 계정 카드 — 필드 전체는 `backend/API_CONTRACT.md` 사용자 절):

```json
{
  "profile": { "id": "user-7d4e9a2c5f18", "name": "김민수", "email": "minsu@oncare.com" },
  "activity_points": 1240
}
```

---

## 3. Dashboard

| Method | Path | Query | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| GET | `/dashboard/summary` | `?date=YYYY-MM-DD` (선택) | `DashboardSummary` | `DioDashboardRepository.fetchSummary` (데모도 같은 경로, 로컬 인터셉터가 응답) |

`DashboardSummary` payload (필드 전체는 `backend/API_CONTRACT.md` 대시보드 절):

```json
{
  "indicators": [
    { "label": "칼로리", "current": 1170, "max": 2000,
      "unit": "kcal", "over_budget": false }
  ],
  "macros": { "carbs_g": 155, "protein_g": 81, "fat_g": 43.8,
    "carbs_pct": 46, "protein_pct": 24, "fat_pct": 30 },
  "diet_entries": 2,
  "exercise_minutes": 45,
  "nutrition_week": [
    { "date": "2026-09-28", "label": "월", "calories": 1650,
      "sodium_mg": 1600, "sugar_g": 30 }
  ],
  "sodium_warning": "라면·김밥 섭취로 나트륨이 높아요.",
  "exercise_feedback": "이번 주 45분 운동했어요. 조금만 더 힘내요!",
  "ai_advice_key": "sodium_over_sources",
  "ai_advice_params": { "foods": ["라면", "김밥"] }
}
```

서버에서는 사실 여러 source(vitals + diet + exercise + schedule)를
조합하므로, **server-side aggregation endpoint**로 두는 게 가장 깔끔.

---

## 4. Diet

| Method | Path | Body / Query | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| GET | `/diet/days/today` | — | `DietDay` | `DioDietRepository.fetchToday` |
| GET | `/diet/days/{date}` | `date=YYYY-MM-DD` | `DietDay` | `fetchByDate` — 날짜 이동 |
| GET | `/diet/recommendations` | — | `MealRecommendations` | 홈 "AI 추천 식단" |
| POST | `/diet/analyze` | `multipart/form-data: image, meal_type, idempotency_key?` | `{entry_id, analysis}` | 사진으로 식단 추가 |
| PUT | `/diet/entries/{id}` | partial `DietEntry` | 갱신된 `DietEntry` | 식사 수정 |
| DELETE | `/diet/entries/{id}` | — | `{status: "deleted"}` | 식사 삭제 |

끼니를 만드는 경로는 **사진 분석 하나뿐이다.** 별도의 생성 엔드포인트는 없다 — 인식
결과가 곧 기록이고, 사용자가 고칠 것은 수정으로 처리한다. `idempotency_key` 는 응답을
잃은 재시도가 같은 끼니를 두 번 남기지 않게 한다(요청당 1회 생성해 재시도에 재사용).

데모 빌드에서는 이 표의 모든 경로를 `LocalApiInterceptor` 가 drift 로 답한다. `REAL_API`
로 분석만 실 백엔드에 맡길 수 있고, 그때도 조회·수정·삭제는 로컬이 답한다.

`DietEntry`:
```json
{
  "id": "...",
  "meal_type": "breakfast",  // breakfast|lunch|dinner|snack
  "time_label": "08:20",
  "foods": [{ "name": "오트밀", "calories": 220 }],
  "total_calories": 315,
  "sodium_mg": 380,
  "sugar_g": 18,
  "ai_comment": "오트밀로 식이섬유를 챙겼어요.",
  "photo_asset": "assets/images/diet-oatmeal-banana.jpeg"
}
```

`DietDay`: `entries[] + totals + macros + ai_coach_message`.

---

## 5. Exercise

| Method | Path | Body / Query | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| GET | `/exercise/weeks/current` | — | `ExerciseWeek` | `MockExerciseRepository.fetchThisWeek` |
| GET | `/exercise/weeks/{week_start}` | `?week_start=YYYY-MM-DD` (월요일) | `ExerciseWeek` | (주간 이동) |
| POST | `/exercise/sessions` | `ExerciseSession` | 생성된 session | "운동 추가" |
| PATCH | `/exercise/sessions/{id}` | partial | 갱신 | |
| DELETE | `/exercise/sessions/{id}` | — | `204` | |

`ExerciseSession`:
```json
{
  "id": "...",
  "day_label": "월", "started_at": "2026-05-12T08:00:00+09:00",
  "type": "cardio",          // cardio|strength|yoga|walking
  "minutes": 30,
  "calories": 250
}
```

`ExerciseWeek`: `sessions[] + daily_minutes + day_labels + totals + streak_days + ai_coach_message`.

---

## 6. Vitals (Quick Input)

| Method | Path | Body | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| POST | `/vitals/weight` | `{kg: number, recorded_at: iso}` | `{id, ...}` | Dashboard quick-input |
| POST | `/vitals/blood-pressure` | `{systolic, diastolic, recorded_at}` | `{id, ...}` | Dashboard quick-input |
| POST | `/vitals/blood-sugar` | `{mg_per_dl, recorded_at}` | `{id, ...}` | Dashboard quick-input |
| GET | `/vitals/{kind}/history` | `?from=&to=` | `[{value, recorded_at}, ...]` | MyHealth sparkline |
| GET | `/vitals/{kind}/latest` | — | `{value, recorded_at}` | MyHealth IndicatorTile |

`kind`: `weight | blood-pressure | blood-sugar`.

---

## 7. Schedule / Events

| Method | Path | Body / Query | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| GET | `/schedule/events` | `?from=YYYY-MM-DD&to=YYYY-MM-DD` | `ScheduleEvent[]` | Calendar 모달 |
| GET | `/schedule/events` | `?date=YYYY-MM-DD` | 해당 일자 events | "오늘의 일정" |
| POST | `/schedule/events` | `ScheduleEvent` (without id) | 생성된 event | "일정 추가" |
| PATCH | `/schedule/events/{id}` | partial | 갱신 | "수정" |
| DELETE | `/schedule/events/{id}` | — | `204` | "삭제" |

`ScheduleEvent`:
```json
{
  "id": "...",
  "title": "병원 정기검진",
  "date": "2026-05-14",
  "time": "10:00",
  "category": "hospital",   // hospital|exercise|meal|medication|other
  "emoji": "🏥",
  "color_hint": "#FEE2E2"
}
```

---

## 8. Notifications

| Method | Path | Query / Body | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| GET | `/notifications` | `?unread_only=true` | `AlertItem[]` | Notification 패널 |
| GET | `/notifications/unread-count` | — | `{count: int}` | Header bell dot |
| PATCH | `/notifications/{id}` | `{read: true}` | 갱신된 item | tile tap |
| POST | `/notifications/read-all` | — | `204` | "모두 읽음" |
| POST | `/notifications/devices` | `{platform, token}` | `204` | FCM 등록 (Stage 후속) |

`AlertItem`:
```json
{
  "id": "...", "title": "...", "body": "...",
  "time_ago": "10분 전", "created_at": "2026-05-20T07:50:00+09:00",
  "category": "reminder",   // reminder|health_check|achievement|system
  "read": false
}
```

> Q9 결정상 실제 push 발송은 시뮬레이션 → 백엔드는 데이터 저장 + 클라이언트가
> 폴링/WebSocket. 실 push 시 FCM 토큰 endpoint 추가.

---

## 9. AI Coach (Q7: mock)

| Method | Path | Body | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| GET | `/ai-coach/feedback` | — | `AiCoachState` | `MockAiCoachRepository.fetchState`, AiCoachCard, AiCoachPanel |
| POST | `/ai-coach/chat` | `{message: string, context?: dict}` | `{reply: string, suggestions?: AiSuggestion[]}` | (추후 채팅 UI) |

`AiCoachState`:
```json
{
  "greeting": "안녕하세요, 오늘 컨디션은 어떠세요?",
  "suggestions": [
    { "tag": "diet", "title": "...", "body": "..." }
  ]
}
```

`tag`: `diet|exercise|sleep|hydration`.

> Q7: 일단은 정적 mock 응답. 실제 LLM/추천 엔진 통합은 별도 후속.

---

## 10. Places (Q8: Google Maps 통합 예정)

| Method | Path | Query | 응답 | Flutter 사용처 |
| --- | --- | --- | --- | --- |
| GET | `/places/nearby` | `?lat=&lng=&category=&radius_m=1000` | `Place[]` | Place 페이지 |
| GET | `/places/{id}` | — | `Place` (상세) | (place 상세, 후속) |

`Place`:
```json
{
  "id": "...", "name": "강남세브란스 가정의학과",
  "category": "medical",       // medical|fitness|healthy_food|pharmacy
  "address": "...",
  "distance_meters": 420,
  "lat": 37.4979, "lng": 127.0276
}
```

---

## 11. Health Check

| Method | Path | 응답 |
| --- | --- | --- |
| GET | `/healthz` | `{status: "ok", version: "..."}` |
| GET | `/version` | `{api_version, commit_sha}` |

데모 모드(`USE_MOCK_API=true`)에서는 `LocalApiInterceptor` 가
`GET /ping → {message: "pong (local)"}` 를 답합니다.

---

## 12. 우선순위 (FastAPI 구현 단계 제안)

| 단계 | 엔드포인트 | 이유 |
| --- | --- | --- |
| **MVP-1** | `GET /healthz`, `GET /dashboard/summary`, `GET /diet/days/today`, `GET /exercise/weeks/current`, `GET /users/me/health` | 첫 빌드에서 4탭 모두 데이터를 그리는 데 필요 |
| **MVP-2** | Vitals POST, Notifications GET/PATCH, Schedule GET/POST | 인터랙티브 카드들이 실제 데이터를 만들 수 있게 |
| **MVP-3** | Auth (social/refresh/logout), Users PATCH, AI Coach | 실 사용자 분리 + 보안 |
| **MVP-4** | Diet/Exercise CRUD 전체, Places, photo-scan | 본격 기록 + 통계 |

---

## 13. 명명/스키마 노트 (FastAPI 측)

- **snake_case** 필드 (Pydantic의 `alias_generator` 또는 응답 serializer로
  통일). Flutter 측은 `freezed` + `@JsonKey(name: '...')` 또는 매뉴얼 매핑.
- **DateTime**: 모두 ISO 8601 + timezone. Asia/Seoul 기준 UTC offset.
- **ID**: UUID v4 권장 (`str(uuid4())`).
- **Pagination**: `?cursor=&limit=` 또는 `?page=&size=` 중 일관되게 — 권장
  `cursor` (notifications/schedule 역방향 스크롤 친화적).
- **Errors**:
  ```json
  { "code": "validation_error",
    "message": "weight must be > 0",
    "details": { "field": "kg" } }
  ```
  HTTP code: 400/401/403/404/409/422/500. `AppError.fromDio`가 이걸 맵핑.
