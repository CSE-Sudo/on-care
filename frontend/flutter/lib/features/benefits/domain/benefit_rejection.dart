/// 포인트 교환·식판 받기·챌린지 참가가 실패한 까닭. (#3363)
///
/// 서버는 규칙에 막힌 요청을 모두 409 와 한국어 사유 한 문장(`detail`)으로
/// 돌려준다 — 코드가 따로 없다. 화면이 원인에 맞는 말을 하려면 그 문장을 갈라야
/// 해서, 서버 문장을 여기 한곳에 모아 둔다. 문장의 출처는 백엔드
/// `points_service.InsufficientPoints`, `points_coupon_service`,
/// `streak_shield_service`, `graph_color_service`, `profile_pet_service`,
/// `weekly_report_purchase_service`, `diet_tray_service`,
/// `weekly_challenge_service` 이고, 목업(`core/points/demo_*`)도 같은 문장을 준다.
/// 서버가 안정적인 오류 코드를 주게 되면 코드 매핑으로 대체한다.
library;

import 'package:oncare/core/errors/app_error.dart';

enum BenefitRejectionKind {
  /// 잔액이 모자란다. 모자란 만큼은 [BenefitRejection.shortfall].
  insufficientPoints,

  /// 이미 가지고 있다 — 사용하지 않은 쿠폰, 연 색, 달고 있는 펫, 받은 주의 리포트,
  /// 받은 식판, 참가한 챌린지. 회원이 바란 상태가 이미 서 있으므로 실패가 아니라
  /// 완료로 다룬다.
  alreadyOwned,

  /// 연속 기록 보호권을 최대로 가지고 있다.
  shieldLimit,

  /// 이번 달 교환 한도를 채웠다.
  monthlyLimit,

  /// 그 밖의 규칙에 막혔다(담당 트레이너 없음, 참가 요일 아님, 없는 항목 등).
  /// 다시 눌러도 같은 답이다.
  blocked,

  /// 서버의 답을 받지 못했다(네트워크·시간 초과·5xx). 요청이 처리됐는지 알 수
  /// 없으므로 같은 요청 키로 다시 보낸다.
  retryable,
}

class BenefitRejection {
  const BenefitRejection(this.kind, {this.shortfall = 0, this.detail});

  final BenefitRejectionKind kind;

  /// 모자란 포인트. 서버가 수를 주지 않았으면 0.
  final int shortfall;

  /// 서버가 준 사유 문장. 없으면 null.
  final String? detail;

  /// 요청이 처리됐는지 알 수 없는 실패인가. 참이면 요청 키를 남겨 둔다.
  bool get retryable => kind == BenefitRejectionKind.retryable;

  static final RegExp _shortfall = RegExp(r'포인트가 (\d+)P 부족해요');

  static const Set<String> _owned = <String>{
    '사용하지 않은 쿠폰이 이미 있어요.',
    '이미 가지고 있는 색이에요.',
    '이미 달고 있는 펫이 있어요.',
    '이 주의 리포트는 이미 받았어요.',
    '식판은 이미 받았어요.',
    '받지 않은 식판 쿠폰이 이미 있어요.',
    '이번 주 챌린지에 이미 참가했어요.',
  };

  static const String _monthly = '이번 달에는 이미 교환했어요.';

  /// 보호권 한도 문장은 최대 보유 수를 품는다(`보호권은 최대 4개까지 …`).
  static const String _shieldPrefix = '보호권은 최대 ';

  /// 저장소가 던진 [error] 를 가른다. [AppError] 가 아닌 것은 [retryable] 이다.
  factory BenefitRejection.of(Object error) {
    if (error is! AppError) {
      return const BenefitRejection(BenefitRejectionKind.retryable);
    }
    final String? detail = error.detail;
    final bool conflict = error is ServerError && error.statusCode == 409;
    if (!conflict) {
      // 404(없는 항목)·400·422·403 은 서버가 요청을 받아 보고 거절한 것이다.
      final bool refused =
          error is NotFoundError ||
          error is ValidationError ||
          error is ForbiddenError;
      return BenefitRejection(
        refused ? BenefitRejectionKind.blocked : BenefitRejectionKind.retryable,
        detail: detail,
      );
    }
    final String text = detail ?? '';
    final RegExpMatch? short = _shortfall.firstMatch(text);
    if (short != null || text == '포인트가 부족해요.') {
      return BenefitRejection(
        BenefitRejectionKind.insufficientPoints,
        shortfall: short == null ? 0 : int.parse(short.group(1)!),
        detail: detail,
      );
    }
    if (_owned.contains(text)) {
      return BenefitRejection(
        BenefitRejectionKind.alreadyOwned,
        detail: detail,
      );
    }
    if (text.startsWith(_shieldPrefix)) {
      return BenefitRejection(BenefitRejectionKind.shieldLimit, detail: detail);
    }
    if (text == _monthly) {
      return BenefitRejection(
        BenefitRejectionKind.monthlyLimit,
        detail: detail,
      );
    }
    return BenefitRejection(BenefitRejectionKind.blocked, detail: detail);
  }
}
