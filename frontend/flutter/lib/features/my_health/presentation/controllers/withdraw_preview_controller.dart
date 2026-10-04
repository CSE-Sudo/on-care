/// 탈퇴 확인창에 실을 "잃는 것" 건수를 읽는다. (#3006)
///
/// 실서버는 `GET /users/me/deletion-preview` 한 번으로 네 숫자를 모두 준다.
/// 데모는 PT 예약·상담 요청을 목 헬스장·상담 저장소가 들고 있어(로컬 목업 API
/// 를 거치지 않는다), 그 둘은 저장소에서 다시 세어 덮는다 — 데모에서 잡아 둔
/// 예약이 확인창에서 0건으로 보이지 않게.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/observability/handled_error.dart';
import 'package:oncare/features/account/domain/entities/account_deletion_preview.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';

/// 탈퇴 미리보기를 읽는 함수. 실패하면 예외를 그대로 올린다 — 확인창 쪽이
/// 일반 문구로 물러선다.
typedef WithdrawPreviewLoader = Future<AccountDeletionPreview> Function();

/// 확인창이 미리보기를 기다리는 최대 시간. 넘기면 숫자 없이 확인창을 띄운다 —
/// 느린 응답이 탈퇴를 붙잡지 않게.
const Duration withdrawPreviewTimeout = Duration(seconds: 5);

final withdrawPreviewLoaderProvider = Provider<WithdrawPreviewLoader>((ref) {
  return () async {
    final AccountDeletionPreview preview = await ref
        .read(accountRepositoryProvider)
        .fetchDeletionPreview();
    if (!ref.read(appConfigProvider).useMockApi) return preview;
    return preview.copyWith(
      upcomingReservations: await _demoUpcomingReservations(ref),
      pendingConsultations: await _demoPendingConsultations(ref),
    );
  };
}, name: 'withdrawPreviewLoader');

Future<int> _demoUpcomingReservations(Ref ref) async {
  final DateTime now = nowKst();
  final List<MyReservation> mine = await ref
      .read(gymRepositoryProvider)
      .fetchMyReservations();
  return mine.where((MyReservation r) => r.startsAt.isAfter(now)).length;
}

Future<int> _demoPendingConsultations(Ref ref) async {
  final List<ConsultationRequest> mine = await ref
      .read(consultationRepositoryProvider)
      .fetchMine();
  return mine.where((ConsultationRequest c) => c.isPending).length;
}

/// 확인창 본문. 기본 문구 아래에 **0 이 아닌 것만** 한 줄씩 붙인다.
///
/// [preview] 가 없거나(읽기 실패·시간 초과) 잃는 것이 하나도 없으면 기본 문구만
/// 돌려준다 — "포인트 0P가 사라져요" 같은 줄은 겁만 준다.
String withdrawConfirmMessage(
  AppLocalizations l,
  AccountDeletionPreview? preview,
) {
  if (preview == null || !preview.hasLosses) return l.myWithdrawConfirm;
  final List<String> lines = <String>[
    if (preview.points > 0) l.myWithdrawLosePoints(preview.points),
    if (preview.activeCoupons > 0)
      l.myWithdrawLoseCoupons(preview.activeCoupons),
    if (preview.upcomingReservations > 0)
      l.myWithdrawCancelReservations(preview.upcomingReservations),
    if (preview.pendingConsultations > 0)
      l.myWithdrawCancelConsultations(preview.pendingConsultations),
  ];
  return '${l.myWithdrawConfirm}\n\n${lines.join('\n')}';
}

/// 확인창 앞에서 미리보기를 읽는다. 어떤 실패든 `null` — 탈퇴는 막지 않는다.
///
/// 잡은 실패는 [reporter](처리한 오류 창구)로 남긴다. 연결 끊김 같은 예상된
/// 실패는 창구가 로그만 남기고 보고하지 않는다.
Future<AccountDeletionPreview?> loadWithdrawPreview(
  WithdrawPreviewLoader load, {
  Duration timeout = withdrawPreviewTimeout,
  HandledErrorReporter? reporter,
}) async {
  try {
    return await load().timeout(timeout);
  } on Object catch (e, st) {
    reporter?.report(e, st, context: 'account.withdrawPreview');
    return null;
  }
}
