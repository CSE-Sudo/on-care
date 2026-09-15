import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_invite_dialog.dart';

/// 받은 담당 요청을 앱 어디서든 가운데 창으로 띄운다. (#1801)
///
/// 회원 셸이 하단 탭 전체를 이것으로 감싼다. 셸은 라우터의 세션 관문을 지난
/// 뒤(데모·로그인)에만 그려지고, 가입 직후 온보딩은 셸 바깥 경로다 — 로그아웃
/// 상태나 온보딩 중에는 이 위젯 자체가 없다.
///
/// - 요청 목록은 [coachInvitesProvider] 가 받는다. 이 위젯이 듣기 시작할 때(앱을 켤
///   때)와 앱으로 돌아올 때 바로, 켜져 있는 동안 15초마다다.
/// - 한 번에 하나만 띄운다. 답하면 다음 요청을 띄운다.
/// - 같은 요청으로 창을 겹쳐 띄우지 않는다. 폴링·복귀로 같은 목록이 다시 와도 떠
///   있는 창이 있으면 기다리고, 이미 답한 요청은 목록이 늦게 갱신돼도 다시 띄우지
///   않는다.
class CoachInvitePrompter extends ConsumerStatefulWidget {
  const CoachInvitePrompter({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CoachInvitePrompter> createState() =>
      _CoachInvitePrompterState();
}

class _CoachInvitePrompterState extends ConsumerState<CoachInvitePrompter> {
  /// 지금 떠 있는 창의 요청 id.
  String? _showingId;

  /// 이 셸에서 답한 요청. 요청 id 는 보낼 때마다 새로 생기므로 거절 뒤 트레이너가
  /// 다시 보낸 요청은 여기에 걸리지 않는다.
  final Set<String> _decided = <String>{};

  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<List<CoachInvite>>>(
      coachInvitesProvider,
      (_, _) => _scheduleNext(),
      fireImmediately: true,
    );
  }

  /// 창은 프레임이 끝난 뒤 띄운다. 목록은 빌드 도중(첫 구독)에도 올 수 있다.
  void _scheduleNext() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        _showNext();
      })
      ..ensureVisualUpdate();
  }

  /// 로그인(또는 데모) 세션에서만 띄운다.
  ///
  /// 셸이 관문 안에서만 그려지므로 보통은 늘 참이다. 로그아웃처럼 세션이 먼저
  /// 바뀌고 셸이 치워지기 전 한 틈에, 떠나는 계정의 요청이 뜨지 않게 한 번 더
  /// 본다. 세션을 아직 아무도 만들지 않았으면(라우터 없이 셸만 세운 테스트)
  /// 여기서 만들지 않는다 — 만들면 저장된 토큰 복구가 시작된다.
  bool get _sessionAllowsPrompt =>
      !ref.exists(sessionControllerProvider) ||
      ref.read(sessionControllerProvider).canEnterApp;

  Future<void> _showNext() async {
    if (!mounted || _showingId != null || !_sessionAllowsPrompt) return;
    final AsyncValue<List<CoachInvite>> invites = ref.read(
      coachInvitesProvider,
    );
    // 새로 받는 중에 들고 있는 옛 목록으로는 띄우지 않는다. 방금 답한 요청이
    // 아직 그 안에 남아 있다.
    if (invites is! AsyncData<List<CoachInvite>>) return;
    final CoachInvite? next = invites.value
        .where((CoachInvite invite) => !_decided.contains(invite.id))
        .firstOrNull;
    if (next == null) return;

    _showingId = next.id;
    final CoachInviteDecision? decision = await showCoachInviteDialog(
      context,
      invite: next,
    );
    _showingId = null;
    if (decision != null) _decided.add(next.id);
    if (!mounted) return;
    // 답했으면 다음 요청을 띄운다. 답 없이 창이 치워졌으면(화면 이동이 창을 함께
    // 걷어 낸 경우) 아직 목록에 남은 같은 요청을 다시 띄운다 — 거둬들여진 요청은
    // 목록에 없으니 다시 뜨지 않는다.
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
