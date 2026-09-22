/// 분석용 식판 — `GET /me/diet-tray` 의 진행 상황과 상태. (#2150)
///
/// 식단 사진을 꾸준히 남긴 회원에게 주는 달성 보상이다. 포인트로 교환하지 않는다.
/// 조건(최근 28일 중 사진 기록 20일, 담당 트레이너)은 서버가 들고 있고, 앱은 받은
/// 값으로 카드만 그린다.
library;

import 'package:oncare/features/benefits/domain/entities/coupon.dart';

/// `progress` 조건을 채우는 중(또는 담당 없음) · `claimable` 지금 받을 수 있음 ·
/// `issued` 수령 쿠폰을 받았고 아직 헬스장에서 쓰지 않음 · `received` 식판을 받음.
enum DietTrayStatus { progress, claimable, issued, received }

/// 모르는 상태는 진행 중으로 읽는다 — 받기 버튼이 잘못 열리는 것보다 낫다.
DietTrayStatus _statusFrom(Object? raw) => switch (raw) {
  'claimable' => DietTrayStatus.claimable,
  'issued' => DietTrayStatus.issued,
  'received' => DietTrayStatus.received,
  _ => DietTrayStatus.progress,
};

class DietTray {
  const DietTray({
    required this.status,
    required this.photoDays,
    required this.requiredDays,
    required this.windowDays,
    required this.hasTrainer,
    this.coupon,
  });

  final DietTrayStatus status;

  /// 최근 [windowDays]일(오늘 포함) 중 식단 사진을 남긴 날 수.
  final int photoDays;
  final int requiredDays;
  final int windowDays;
  final bool hasTrainer;

  /// 받은 식판 수령 쿠폰 — [DietTrayStatus.issued]·[DietTrayStatus.received] 에만 있다.
  final Coupon? coupon;

  /// 조건까지 남은 날. 채웠으면 0.
  int get daysLeft => photoDays >= requiredDays ? 0 : requiredDays - photoDays;

  factory DietTray.fromJson(Map<String, Object?> json) => DietTray(
    status: _statusFrom(json['status']),
    photoDays: (json['photo_days'] as num?)?.toInt() ?? 0,
    requiredDays: (json['required_days'] as num?)?.toInt() ?? 20,
    windowDays: (json['window_days'] as num?)?.toInt() ?? 28,
    hasTrainer: (json['has_trainer'] as bool?) ?? false,
    coupon: json['coupon'] is Map
        ? Coupon.fromJson(
            (json['coupon']! as Map<Object?, Object?>).cast<String, Object?>(),
          )
        : null,
  );
}
