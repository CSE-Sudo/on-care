import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 탭 제목에 붙일 안 읽은 알림 수(#3285). 로그인한 콘솔의
/// `DesktopAlertsHost` 가 채우고, 콘솔을 떠나면 0 으로 되돌린다.
final tabUnreadCountProvider = StateProvider<int>(
  (ref) => 0,
  name: 'tabUnreadCount',
);

/// 탭 제목 — 안 읽은 알림이 있으면 앞에 수를 붙인다: `(3) On-Care 트레이너`.
///
/// 다른 탭을 보는 중에도 탭 줄에서 새 알림을 알아볼 수 있게 한다(#3285). 앱의
/// 기본 제목(`MaterialApp.onGenerateTitle`) 아래에 서서 그것을 덮어쓴다 — 바깥
/// 제목이 다시 그려지면 이 위젯도 뒤따라 다시 그려지므로 늘 이쪽이 이긴다.
class TabUnreadTitle extends ConsumerWidget {
  const TabUnreadTitle({required this.child, super.key});

  final Widget child;

  /// 100건 이상은 `99+` 로 줄인다 — 탭이 좁아도 제목이 남게.
  static String titleFor(String base, int count) {
    if (count <= 0) return base;
    return '(${count > 99 ? '99+' : count}) $base';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int count = ref.watch(tabUnreadCountProvider);
    return Title(
      title: titleFor(AppLocalizations.of(context).appTitle, count),
      color: OnCareBrand.trainer.primary,
      child: child,
    );
  }
}
