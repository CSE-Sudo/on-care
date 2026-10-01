import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_emote_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/points/demo_weekly_challenge.dart';

/// 데모 회원(김민수)의 혜택 장부 시드(#2664). [DemoBenefitsStore] 의 구획 모양이다.
///
/// 실서버의 데모 계정은 쌓인 포인트 내역과 쿠폰·보호권을 들고 있는데, 목업 장부는
/// 빈 채로 시작해 내역·쿠폰 화면이 비었다. 값을 손으로 적지 않고 **장부의 규칙을
/// 지난 시각으로 돌려** 만든다 — 한도·가격·쿠폰 기한이 규칙과 어긋날 수 없다.
///
/// 채우는 것:
/// - 포인트: 지난 13일의 식단·운동·루틴 적립과 아래 교환의 사용 줄
/// - 쿠폰: 지난달에 쓴 락커 쿠폰 한 장, 사흘 전에 받은 락커 쿠폰 한 장(사용 가능).
///   PT 재등록은 비워 둔다 — 데모에서 바로 교환해 볼 수 있게.
/// - 받은 주간 리포트: 2주 전 한 주. 지난주는 비워 둔다 — 교환해 볼 수 있게.
/// - 주간 챌린지: 지난주 참가(진행 중). 주가 끝났으니 첫 조회에서 운동한 날로 판정돼
///   결과 알림과 보상 적립이 생긴다 — 실서버의 늦은 판정과 같은 길이다.
/// - 보호권 두 장(보유), 채팅 이모티콘 둘(남은 기간 사흘·엿새)
///
/// 잔액은 시작 잔액([kDemoOpeningPoints])으로 맞춘다 — 백엔드 시드와 같은 값이고,
/// 내역은 그 잔액에 이른 최근 줄들이다.
Future<Map<String, Map<String, Object?>>> buildDemoBenefitsSeed(
  DateTime now,
) async {
  final DateTime today = DateTime(now.year, now.month, now.day);
  DateTime clock = now;
  DateTime clockNow() => clock;
  DateTime at(int daysAgo, int hour, [int minute = 0]) =>
      DateTime(today.year, today.month, today.day - daysAgo, hour, minute);

  // 교환이 잔액에 막히지 않게 넉넉히 시작하고, 끝에 시작 잔액으로 맞춘다.
  final DemoPointsLedger ledger = DemoPointsLedger(
    openingBalance: kDemoOpeningPoints * 2,
    now: clockNow,
  );
  final DemoStreakShieldBook shields = DemoStreakShieldBook(
    ledger: ledger,
    now: clockNow,
  );
  // 받은 주간 리포트는 담당이 없을 때 산다 — 트레이너와 연결하기 전에 산 한 주다.
  final DemoCouponBook coupons = DemoCouponBook(
    ledger: ledger,
    now: clockNow,
    hasTrainer: false,
    shields: shields,
  );
  final DemoWeeklyChallenge challenges = DemoWeeklyChallenge(
    ledger: ledger,
    now: clockNow,
  );
  final DemoEmoteBook emotes = DemoEmoteBook(ledger: ledger, now: clockNow);

  // ---- 지난달 락커 쿠폰 — 받고 이틀 뒤 헬스장에서 썼다 ----
  clock = at(40, 10, 5);
  final Object? used = coupons.exchange(kDemoLockerMonth.id).body;
  clock = at(38, 19, 20);
  if (used is Map<String, Object?>) {
    final Object? coupon = used['coupon'];
    if (coupon is Map<String, Object?>) coupons.use(coupon['id']! as String);
  }

  // ---- 지난 13일의 적립 ----
  for (int d = 13; d >= 1; d--) {
    final int meals = d % 3 + 1;
    const List<(int, int)> mealTimes = <(int, int)>[
      (8, 10),
      (12, 40),
      (19, 20),
    ];
    for (int i = 0; i < meals; i++) {
      clock = at(d, mealTimes[i].$1, mealTimes[i].$2);
      ledger.award(PointsRule.dietEntry, 'seed-points-diet-$d-$i');
    }
    if (d.isEven) {
      clock = at(d, 20, 30);
      ledger.award(PointsRule.exerciseManual, 'seed-points-exercise-$d');
    }
    if (d % 3 == 1) {
      clock = at(d, 18, 10);
      ledger.award(PointsRule.routineComplete, 'seed-points-routine-$d');
    }
  }

  // ---- 보호권 두 장 ----
  clock = at(9, 21, 15);
  shields.exchange();
  clock = at(5, 22);
  shields.exchange();

  // ---- 지난주 월요일: 챌린지 참가, 2주 전 리포트 받기 ----
  final DateTime lastMonday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - DateTime.monday) - 7,
  );
  clock = DateTime(lastMonday.year, lastMonday.month, lastMonday.day, 8, 40);
  await challenges.join(daysOf: (_) async => <DateTime>{});
  clock = DateTime(lastMonday.year, lastMonday.month, lastMonday.day, 9, 30);
  coupons.reports.exchange();

  // ---- 채팅 이모티콘 둘 ----
  clock = at(4, 21, 5);
  emotes.unlock('oni_owoon');
  clock = at(1, 20, 45);
  emotes.unlock('oni_thanks');

  // ---- 이번 달 락커 쿠폰 — 아직 쓰지 않았다 ----
  clock = at(3, 11);
  coupons.exchange(kDemoLockerMonth.id);

  return <String, Map<String, Object?>>{
    'points': ledger.toJson()..['balance'] = kDemoOpeningPoints,
    'coupons': coupons.toJson(),
    'challenges': challenges.toJson(),
    'shields': shields.toJson(),
    'emotes': emotes.toJson(),
  };
}
