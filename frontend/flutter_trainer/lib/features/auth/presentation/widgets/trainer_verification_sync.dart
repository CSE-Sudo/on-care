import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/network/interceptors/verification_denied_interceptor.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/shared/widgets/trainer_verification_banner.dart';

/// 운영자 승인 상태를 로그인한 채로 따라간다 (#3010).
///
/// 승인·반려는 운영자가 서버에서 바꾼다. 전에는 다시 로그인해야 배너가 바뀌어,
/// 승인된 트레이너가 계속 "승인을 기다리고 있어요" 를 봤다. 셸 안에서 다음 신호에
/// [SessionController.refreshProfile] 을 부른다:
///
/// - 안 읽은 알림 수가 늘었다 — 승인·반려 알림이 그 하나일 수 있다.
/// - 승인되지 않은 동안 탭이 다시 보였다 — 다른 창에서 처리됐을 수 있다.
/// - 승인된 줄 아는 세션이 `trainer_not_approved` 403 을 받았다 — 그사이 반려됐다.
///
/// 데모·로그아웃이면 [SessionController.refreshProfile] 이 아무것도 하지 않는다.
class TrainerVerificationSync extends ConsumerStatefulWidget {
  /// Wraps [child].
  const TrainerVerificationSync({required this.child, super.key});

  /// 셸 본문.
  final Widget child;

  @override
  ConsumerState<TrainerVerificationSync> createState() =>
      _TrainerVerificationSyncState();
}

class _TrainerVerificationSyncState
    extends ConsumerState<TrainerVerificationSync> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<void>? _denied;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _denied = ref.read(verificationDeniedProvider).stream.listen((_) {
      // 이미 승인 아님으로 아는 세션은 다시 읽을 이유가 없다 — 잠긴 화면의 폴링이
      // 403 을 받을 때마다 프로필을 다시 읽지 않게 한다.
      if (ref.read(trainerVerificationProvider).isApproved) _refresh();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_denied?.cancel());
    super.dispose();
  }

  void _onResume() {
    if (!ref.read(trainerVerificationProvider).isApproved) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    unawaited(ref.read(sessionControllerProvider.notifier).refreshProfile());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<int>>(trainerUnreadNotificationsProvider, (
      AsyncValue<int>? previous,
      AsyncValue<int> next,
    ) {
      final int? before = previous?.valueOrNull;
      final int? after = next.valueOrNull;
      if (before != null && after != null && after > before) _refresh();
    });
    return widget.child;
  }
}
