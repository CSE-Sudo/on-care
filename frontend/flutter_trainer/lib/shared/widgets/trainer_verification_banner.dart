import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 로그인한 트레이너의 운영자 승인 상태 (#2825).
///
/// 세션 프로필(`GET /trainer/me`)에서 읽는다. 프로필이 없으면(로그인 전·복원 중)
/// 승인으로 둔다 — 그 사이에 안내를 깜빡이게 띄울 이유가 없고, 실제 차단은 서버가
/// 한다. 데모 프로필은 승인 상태다.
final trainerVerificationProvider = Provider<TrainerVerification>((ref) {
  final TrainerProfile? profile = ref.watch(
    sessionControllerProvider.select((state) => state.profile),
  );
  return profile?.verification ?? TrainerVerification.approved;
}, name: 'trainerVerification');

/// 승인 대기·반려가 막는 기능이 어디인가 — 같은 상태라도 자리마다 할 말이 다르다.
enum TrainerVerificationScope {
  /// 대시보드 머리 — 무엇이 막히는지 전부 말한다.
  overview,

  /// 고객 화면의 `신규 회원 등록` — 회원 연결이 막힌 이유.
  connect,

  /// 상담 요청함 — 상담 요청이 오지 않는 이유.
  consultations,

  /// 담당 회원 상세·메시지 — 기록이 잠긴 이유 (#3009). 반려일 때만 보인다:
  /// 서버는 반려만 기록을 잠그고, 승인 대기 트레이너에게는 담당 회원이 없다.
  records,
}

/// 승인 대기·반려 안내 배너 (#2825). 승인된 트레이너에게는 아무것도 그리지 않는다.
///
/// 트레이너 웹은 가입·로그인·프로필 작성이 승인과 무관하게 되지만, 승인 전에는
/// 회원 앱 트레이너 찾기에 나오지 않고 상담 요청·회원 연결을 받을 수 없다. 이유를
/// 모르면 "왜 아무도 신청하지 않지"·"왜 연결이 안 되지" 로 읽히므로, 막히는 자리마다
/// 이 배너가 이유를 적는다.
class TrainerVerificationBanner extends ConsumerWidget {
  /// Creates the banner for [scope].
  const TrainerVerificationBanner({
    super.key,
    this.scope = TrainerVerificationScope.overview,
    this.bottomGap = 0,
  });

  /// 이 배너가 선 자리.
  final TrainerVerificationScope scope;

  /// 배너 아래 띄울 간격. 배너가 없을 때는 간격도 없다.
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainerVerification verification = ref.watch(
      trainerVerificationProvider,
    );
    if (verification.isApproved) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final bool rejected =
        verification.status == TrainerVerificationStatus.rejected;
    if (scope == TrainerVerificationScope.records && !rejected) {
      return const SizedBox.shrink();
    }
    final String body = switch (scope) {
      TrainerVerificationScope.overview =>
        rejected ? l.verifyRejectedBody : l.verifyPendingBody,
      TrainerVerificationScope.connect => l.verifyConnectDisabled,
      TrainerVerificationScope.consultations => l.verifyConsultDisabled,
      TrainerVerificationScope.records => l.verifyRecordsLocked,
    };
    final String note = verification.note.trim();
    final Widget banner = AppBanner(
      key: ValueKey<String>('trainer-verification-${scope.name}'),
      title: rejected ? l.verifyRejectedTitle : l.verifyPendingTitle,
      message: rejected && note.isNotEmpty
          ? '$body\n${l.verifyRejectedReason(note)}'
          : body,
      icon: rejected ? AppIcons.warning : AppIcons.info,
      tone: rejected ? AppBannerTone.danger : AppBannerTone.caution,
    );
    if (bottomGap <= 0) return banner;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: banner,
    );
  }
}
