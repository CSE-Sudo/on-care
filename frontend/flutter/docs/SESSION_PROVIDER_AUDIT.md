# Session provider state audit

Issue #318 audits Riverpod state that can outlive an account transition. A
provider is reset when it caches account-specific server data or owns mutable
demo data that one account must not expose to the next account.

Account-specific leaf/controller providers are registered explicitly in
`app/session_feature_reset.dart`. Stateful mock repository roots are also
recreated so their local mutations cannot cross a session boundary. Explicit
leaf invalidation is necessary because a repository can rebuild to the same
const instance, in which case Riverpod may leave its dependents unchanged.

## Reset on account transition

| Provider group | Why state can cross accounts | Reset decision |
| --- | --- | --- |
| `profileProvider` | Non-auto-dispose account profile cache | Invalidate the cached profile |
| `aiCoachStateProvider`, `chatControllerProvider` | Non-auto-dispose personalized suggestions and in-memory chat | Invalidate both leaves |
| `dashboardSummaryProvider` | An active watcher can retain the previous account summary | Invalidate the summary |
| `dietRepositoryProvider`, `dietTodayProvider`, `dietRecommendationsProvider` | The mock repository mutates meals in memory; the leaves cache today's diet and personalized recommendations | Recreate the mock root and invalidate both leaves |
| `exerciseRepositoryProvider`, `exerciseWeekProvider` | The mock repository mutates sessions in memory; the leaf caches the week | Recreate the mock root and invalidate the leaf |
| `exerciseRoutineDoneProvider` | Non-auto-dispose local completion flags | Restore the initial flags |
| `gymRepositoryProvider`, `myGymProvider`, `myTrainerProvider` | The mock repository mutates membership links; leaves cache account links | Recreate the mock root and invalidate account leaves |
| `myReservationsProvider` | Reservations are per account. The leaf already refetches through the gym repository root, but relying on that propagation is fragile | Invalidate the leaf explicitly, like the other gym leaves |
| `consultationRequestControllerProvider` | Non-auto-dispose in-memory requests and pending state | Recreate the controller |
| `memberCoachRepositoryProvider` and its leaf providers | The mock repository mutates chat; leaves cache coach, routines, sessions, chat, unread state, and received trainer invites (the invite list stays alive while the member shell listens, #1801) | Recreate the mock root and invalidate every leaf |
| `myHealthStateProvider` | Non-auto-dispose profile, health risk, points, and settings cache | Invalidate the cached state |
| `demoPointsLedgerProvider` (not reset) | Demo-only point ledger shared by the local API, the mock exercise/coach repositories, and the mock MY repository (#1786) | Kept for the app lifetime like the drift demo database: clearing it alone would leave stored meals whose awards can no longer be revoked. The demo has a single member account |
| `pointsShopProvider`, `myCouponsProvider` | Auto-dispose, but an open points or benefits page survives a demo-to-login transition and would keep the previous account's balance, exchange eligibility, and coupons (#1787) | Invalidate both leaves |
| `weeklyChallengeProvider`, `myChallengesProvider` | Auto-dispose, but an open points, benefits, or exercise page survives a demo-to-login transition and would keep the previous account's challenge, progress, and join eligibility (#1789) | Invalidate both leaves |
| `demoWeeklyChallengeProvider` (not reset) | Demo-only weekly challenge shared by the local API and the mock exercise repository (which attaches the days it has records for); stakes and rewards move `demoPointsLedgerProvider` (#1789) | Kept for the app lifetime together with the point ledger, for the same reason as the coupon book. The demo has a single member account |
| `demoCouponBookProvider` (not reset) | Demo-only coupon book shared by the local API and the mock gym repository (disconnecting the gym or trainer cancels the locker or PT renewal coupon); exchanges spend from `demoPointsLedgerProvider` (#1787) | Kept for the app lifetime together with the point ledger it spends from: resetting one without the other would leave coupons whose points are gone, or refunds with no spend. The demo has a single member account |
| Notification controller/list | The controller retains read and simulated-push state; an active list watcher can retain fetched items | Recreate the controller and invalidate the list |
| `notificationSettingsProvider` | Delivery settings are stored per account on the real backend; the cached toggles otherwise survive until an app restart | Invalidate the cached settings |
| Schedule date/month families | Active family instances can retain account schedule entries | Invalidate every family instance |

Auto-dispose alone is not a sufficient boundary: demo-to-login authentication
can succeed without leaving the current page, so an actively watched provider
can survive the transition. Authentication success therefore publishes the new
access token before resetting feature state, ensuring immediate refetches use
the new account.

## How to decide

두 개가 조용히 빠져 있었던 이유는 기준이 글로 없었기 때문이다(#634). 새 provider 를
만들 때 아래를 순서대로 묻는다.

1. **이 값이 계정마다 다른가?** 다르면 등록한다. 서버가 계정별로 주는 것(예약, 알림 수신
   설정, 프로필)과 데모 저장소가 계정별로 들고 있는 것 모두 해당한다.
2. **자동 폐기(auto-dispose)에 기대도 되는가?** 안 된다. 데모에서 로그인으로 넘어가는
   전환은 화면을 떠나지 않고도 성립하므로, 보고 있는 provider 는 전환을 그대로 살아남는다.
3. **뿌리(저장소)만 무효화하면 되는가?** 안 된다. 저장소가 같은 const 인스턴스로 다시
   만들어지면 Riverpod 이 그 의존자를 그대로 둘 수 있다. 화면이 읽는 잎도 함께 적는다.
   `myReservationsProvider` 는 뿌리(`gymRepositoryProvider`)를 통해 이미 다시 조회되고
   있었지만, 그 전이는 뿌리 구조가 바뀌면 조용히 끊긴다. 같은 뿌리를 보는 다른 잎들처럼
   명시적으로 적었다.
4. **다른 곳에서 이미 무효화하니 괜찮은가?** 그 무효화가 **세션 전환에서** 일어나는지
   확인한다. 화면 안의 갱신(예약 직후 목록 새로고침 같은)은 계정이 바뀔 때 돌지 않는다.
   `notificationSettingsProvider` 가 그렇게 빠져 있었다 — 잎도 그 저장소도 레지스트리에
   없어 전이조차 일어나지 않았고, 앞 계정의 토글이 앱을 다시 켤 때까지 남았다.

계정과 무관한 것(기기 표시 설정, 공개 장소 검색, 앱 인프라)은 아래 표에 남긴다.

## Intentionally retained

| Provider | Reason |
| --- | --- |
| `themeModeProvider`, `localeProvider` | Device/app display preferences, not account data |
| `placeQueryProvider`, place providers | Map position, filter, and public place search results |
| `appConfigProvider`, logger, preferences, database | App infrastructure; account transitions must not recreate the container or delete persisted local data |
| `appRouterProvider` | App navigation infrastructure |
| `authAccessTokenProvider` | Written directly by `SessionController` before feature reset |
| `authControllerProvider` | Legacy mock controller with no production consumer; the active session uses `SessionController` |

Server records are never deleted by this reset. Providers are only disposed and
recreated so the next read uses the current session.

In mock builds, account and schedule requests can be served from the same Drift
database by `LocalApiInterceptor`. Resetting their providers clears cached
responses, but the next read can return the same persisted rows. Deleting or
partitioning that local database is outside this provider-cache reset.
