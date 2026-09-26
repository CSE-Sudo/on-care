/// 일요일에 들어오면 한 주 피드백을 묻는다. (#2232)
///
/// 회원 셸이 하단 탭 전체를 이것으로 감싼다. 피드백은 **주에 한 번**이라
/// 화면 어딘가에 버튼으로 두면 그 화면에 들어온 주만 답이 쌓인다. 물어야 할
/// 때 앱이 먼저 묻는 편이 맞다.
///
/// 언제 묻는지는 [askableWeek] 가 정한다 — 일요일, 그리고 놓친 회원을 위해
/// 월요일에 한 번 더(그때는 끝난 지난 주를 묻는다). 이미 답한 주는 묻지 않고,
/// `나중에` 를 누르면 이 세션에서는 다시 묻지 않는다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_sheet.dart';

/// 물을 것이 있으면 시트를 한 번 띄운다.
class WeeklyFeedbackPrompter extends ConsumerStatefulWidget {
  /// Creates the prompter.
  const WeeklyFeedbackPrompter({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<WeeklyFeedbackPrompter> createState() =>
      _WeeklyFeedbackPrompterState();
}

class _WeeklyFeedbackPrompterState
    extends ConsumerState<WeeklyFeedbackPrompter> {
  /// 지금 떠 있는가 — 폴링·복귀로 같은 값이 다시 와도 두 겹으로 띄우지 않는다.
  bool _showing = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<DateTime?>>(
      weeklyFeedbackPromptProvider,
      (_, _) => _schedule(),
      fireImmediately: true,
    );
  }

  /// 시트는 프레임이 끝난 뒤 띄운다. 값은 빌드 도중(첫 구독)에도 올 수 있다.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        _show();
      })
      ..ensureVisualUpdate();
  }

  /// 로그인(또는 데모) 세션에서만 띄운다. 로그아웃처럼 세션이 먼저 바뀌고 셸이
  /// 치워지기 전 한 틈에, 떠나는 계정에게 묻지 않게 한 번 더 본다.
  bool get _sessionAllowsPrompt =>
      !ref.exists(sessionControllerProvider) ||
      ref.read(sessionControllerProvider).canEnterApp;

  Future<void> _show() async {
    if (!mounted || _showing || !_sessionAllowsPrompt) return;
    final AsyncValue<DateTime?> prompt = ref.read(weeklyFeedbackPromptProvider);
    // 아직 읽는 중이면 기다린다 — 옛 값으로 띄우면 방금 낸 주를 다시 묻는다.
    if (prompt is! AsyncData<DateTime?>) return;
    final DateTime? week = prompt.value;
    if (week == null) return;

    _showing = true;
    final bool? sent = await openWeeklyFeedbackSheet(context, weekStart: week);
    _showing = false;
    // 보내지 않고 닫았으면 이 세션에서는 다시 묻지 않는다. 같은 날 앱을 몇 번
    // 열어도 매번 창이 뜨면, 회원은 답하기보다 닫는 법을 먼저 익힌다.
    if (sent != true) {
      ref.read(weeklyFeedbackDismissedProvider.notifier).state = true;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
