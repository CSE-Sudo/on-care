import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_share_consent_details.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/active_polling_stream.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 시트가 떠 있는 동안 연결됐는지 확인하는 주기. (#3342)
///
/// 회원과 트레이너가 마주 앉아 코드를 주고받는 자리라, 트레이너가 입력을 마친 뒤
/// 회원 화면이 바뀌기까지 오래 걸리면 결국 "됐나요?" 를 묻게 된다. 실시간 푸시가
/// 아직 없어(#474) 짧게 묻는다 — 시트가 떠 있는 몇 분 동안만 도는 요청이다.
const Duration trainerSyncPollInterval = Duration(seconds: 3);

/// 한 번 확인한 연결 상태 — 담당 코치와, 수락을 기다리는 담당 요청.
typedef _LinkSnapshot = ({MemberCoach? coach, List<CoachInvite> invites});

/// 트레이너에게 불러 줄 6자리 동기화 코드를 띄우는 시트. (#1634)
///
/// **코드를 받는 것이 데이터 공유 동의다.** 코드를 입력한 트레이너는 그
/// 자리에서 담당이 되어 회원의 식단·운동·건강 기록을 읽는다. 상담 수락은 담당
/// 연결이 아니어서(#2584) 이 코드가 등록의 유일한 문이고, 식단·기록 공유에
/// 동의받는 자리도 여기다. 그래서 시트는 **공유 범위 → `동의하고 코드 받기` →
/// 코드** 순서로 연다 — 여는 것만으로 코드를 발급하면 무엇에 동의하는지 읽기
/// 전에 동의가 끝난다. 서버는 발급 시각을 동의 시각으로 적는다. 회원이 닫으면
/// 코드를 즉시 버린다.
///
/// 코드를 크게 띄우고 자리마다 나누는 것은 마주 앉아 불러 주거나 받아 적는
/// 값이기 때문이다. 남은 시간을 함께 보여 주지 않으면, 트레이너가 늦게
/// 입력했을 때 회원은 왜 안 되는지 알 수 없다.
///
/// **코드를 띄워 둔 동안 연결됐는지 스스로 확인한다(#3342).** 트레이너가 코드를
/// 넣는 순간 서버에서는 연결이 끝나는데, 시트가 코드와 남은 시간만 보여 주면
/// 회원은 닫고 알림을 보기 전까지 알 수 없다. 연결되면 내용이 `연결됐어요` 로
/// 바뀌고, 그 관계 위에 있는 화면들을 다시 읽는다. 코드 대신 담당 요청이 오면
/// 앱 어디서든 뜨는 담당 요청 창(`CoachInvitePrompter`)이 곧바로 받게 한다 —
/// 동의는 그 창이 받는다.
Future<void> showTrainerSyncSheet(BuildContext context) {
  return showAppSheet<void>(
    // 탭 페이지마다 Navigator 가 있고 MainShell 은 `extendBody` 라, 가까운
    // Navigator 로 열면 시트가 브랜치 Navigator 안에 뜬다 — 하단 바와 + 버튼이
    // 시트 위에 그려지고 스크림도 걸리지 않은 채 눌린다(#791). 루트 Navigator 로 연다.
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (_) => const _TrainerSyncSheet(),
  );
}

class _TrainerSyncSheet extends ConsumerStatefulWidget {
  const _TrainerSyncSheet();

  @override
  ConsumerState<_TrainerSyncSheet> createState() => _TrainerSyncSheetState();
}

class _TrainerSyncSheetState extends ConsumerState<_TrainerSyncSheet> {
  /// 공유 범위를 읽고 `동의하고 코드 받기` 를 눌렀는가. 누르기 전에는 코드를
  /// 발급하지 않는다(#2584).
  bool _agreed = false;
  String? _code;
  int _remaining = 0;
  bool _failed = false;
  Timer? _ticker;

  /// 저장소를 미리 붙들어 둔다 — [dispose] 에서 `ref` 를 읽을 수 없다.
  late final TrainerSyncRepository _repository;

  /// 진행 중인 발급 요청. 시트를 닫을 때 이것이 끝난 뒤에 버린다(#3244).
  Future<void>? _issuing;

  /// 연결 상태를 묻는 곳. 저장소를 직접 부른다 — 화면들이 보고 있는
  /// `memberCoachProvider` 를 몇 초마다 비우면 헤더와 카드가 그때마다 깜빡인다.
  late final MemberCoachRepository _coachRepository;

  /// 연결 확인 구독. 시트가 떠 있고 앱이 앞에 있을 때만 돈다 — 닫거나 연결이
  /// 확인되면 끊는다.
  StreamSubscription<_LinkSnapshot>? _watch;

  /// 코드를 받을 때의 담당. 이 값과 달라져야 **이 시트에서** 연결된 것이다 —
  /// 이미 담당이 있는 회원이 시트를 열자마자 `연결됐어요` 를 보면 안 된다.
  String? _baselineTrainerId;
  bool _baselineKnown = false;

  /// 연결이 확인된 담당. 있으면 시트는 코드 대신 연결 완료를 보여 준다.
  MemberCoach? _connected;

  /// 담당 요청 창으로 넘긴 요청. 같은 요청으로 목록을 거듭 새로 받지 않는다.
  final Set<String> _handedOffInvites = <String>{};

  @override
  void initState() {
    super.initState();
    _repository = ref.read(trainerSyncRepositoryProvider);
    _coachRepository = ref.read(memberCoachRepositoryProvider);
  }

  void _agree() {
    setState(() => _agreed = true);
    // 발급과 함께 묻기 시작한다 — 첫 답이 기준이 되므로, 트레이너가 코드를
    // 받아 적기 전에 받아 둬야 한다.
    _startWatching();
    _issue();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopWatching();
    // 화면을 닫으면 코드를 버린다. 발급이 동의였으니 취소도 즉시 반영돼야
    // 한다. 시트는 이미 사라지는 중이라 결과를 기다리지 않고, 실패해도
    // 서버가 만료로 정리한다. 동의하지 않고 닫았으면 버릴 코드가 없다.
    // 연결된 뒤에는 버리지 않는다 — 코드는 이미 쓰였다.
    if (_agreed && _connected == null) unawaited(_revokeQuietly());
    super.dispose();
  }

  void _startWatching() {
    if (_watch != null) return;
    _watch =
        activePollingStream<_LinkSnapshot>(
          load: _loadLink,
          interval: trainerSyncPollInterval,
        ).listen(
          _onLink,
          // 한 번 못 읽은 것은 연결 실패가 아니다. 다음 주기에 다시 묻는다.
          onError: (Object _) {},
        );
  }

  void _stopWatching() {
    unawaited(_watch?.cancel());
    _watch = null;
  }

  Future<_LinkSnapshot> _loadLink() async {
    final MemberCoach? coach = await _coachRepository.fetchCoach();
    List<CoachInvite> invites = const <CoachInvite>[];
    // 연결됐으면 요청 목록은 볼 것이 없다.
    if (coach == null) {
      try {
        invites = await _coachRepository.fetchInvites();
      } on Object {
        // 요청 목록을 못 읽었다고 담당 확인까지 버리지 않는다.
      }
    }
    return (coach: coach, invites: invites);
  }

  void _onLink(_LinkSnapshot link) {
    if (!mounted || _connected != null) return;
    final MemberCoach? coach = link.coach;
    if (!_baselineKnown) {
      _baselineKnown = true;
      _baselineTrainerId = coach?.trainerId;
    } else if (coach != null && coach.trainerId != _baselineTrainerId) {
      _onConnected(coach);
      return;
    } else if (coach == null) {
      // 있던 담당이 끊겼다. 같은 트레이너가 다시 이어도 새 연결이다.
      _baselineTrainerId = null;
    }
    _handOffInvites(link.invites);
  }

  void _onConnected(MemberCoach coach) {
    _ticker?.cancel();
    _stopWatching();
    setState(() => _connected = coach);
    // 담당 요청 수락과 같은 목록이다 — MY·운동 탭·헤더가 그 관계를 보여 준다.
    refreshAfterCoachLinked(ref.invalidate);
  }

  /// 코드 대신 담당 요청이 왔다. 수락과 데이터 공유 동의는 담당 요청 창이
  /// 받는다(#1022, #1801) — 그 창이 듣는 목록을 지금 다시 받게만 한다. 창의
  /// 주기를 기다리면 마주 앉은 자리에서 한참 뒤에야 뜬다. 수락하면 다음 확인에서
  /// 이 시트도 연결 완료로 바뀐다.
  void _handOffInvites(List<CoachInvite> invites) {
    final List<String> fresh = <String>[
      for (final CoachInvite invite in invites)
        if (_handedOffInvites.add(invite.id)) invite.id,
    ];
    if (fresh.isEmpty) return;
    // 듣는 곳(회원 셸)이 없으면 띄울 창도 없다.
    if (!ref.exists(coachInvitesProvider)) return;
    final List<CoachInvite> known =
        ref.read(coachInvitesProvider).valueOrNull ?? const <CoachInvite>[];
    // 창이 이미 받은 요청이면 다시 받지 않는다 — 떠 있는 창을 건드리지 않는다.
    if (fresh.every((String id) => known.any((CoachInvite i) => i.id == id))) {
      return;
    }
    ref.invalidate(coachInvitesProvider);
  }

  Future<void> _revokeQuietly() async {
    // 발급 중에 닫으면 폐기가 발급보다 먼저 서버에 닿을 수 있다. 그러면 뒤늦게
    // 발급된 코드가 만료까지 살아 있다 — 발급이 끝나기를 기다린 뒤 버린다.
    try {
      await _issuing;
    } catch (_) {
      // 발급 실패는 [_issue] 가 이미 다뤘다.
    }
    try {
      await _repository.revoke();
    } catch (_) {
      // 네트워크가 끊겼다고 시트가 안 닫히면 안 된다.
    }
  }

  Future<void> _issue() async {
    setState(() => _failed = false);
    try {
      final issuing = _repository.issue();
      _issuing = issuing;
      final issued = await issuing;
      if (!mounted) return;
      setState(() {
        _code = issued.code;
        _remaining = issued.expiresInSeconds;
      });
      _startTicker();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
      if (_remaining == 0) timer.cancel();
    });
  }

  /// `4:59` — 남은 시간을 분:초로. 0 아래로 내려가지 않는다.
  String get _countdown {
    final int seconds = _remaining < 0 ? 0 : _remaining;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final bool expired = _code != null && _remaining <= 0;
    final TextStyle secondary = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);

    if (_connected case final MemberCoach coach) {
      return AppSheet(
        showClose: false,
        title: l.trainerSyncTitle,
        child: SafeArea(top: false, child: _Connected(coach: coach)),
      );
    }

    return AppSheet(
      showClose: false,
      title: l.trainerSyncTitle,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 코드보다 먼저 무엇이 공유되는지 말한다 — 코드를 받는 것이
            // 동의라, 동의하는 내용이 코드 아래에 있으면 안 된다.
            Text(l.trainerSyncConsent, style: secondary),
            // 목적·기간·거부권을 펼쳐 볼 수 있게 둔다(#2826).
            const SizedBox(height: OnCareSpacing.s4),
            const TrainerShareConsentDetails(),
            const SizedBox(height: OnCareSpacing.s20),
            if (!_agreed)
              AppButton(
                key: const ValueKey<String>('trainer-sync-agree'),
                label: l.trainerSyncAgree,
                onPressed: _agree,
              )
            else if (_failed)
              _Message(text: l.trainerSyncFailed, onRetry: _issue)
            else if (_code == null)
              const AppLoading(placement: AppStatePlacement.card)
            else ...<Widget>[
              _CodeDisplay(code: _code!, dimmed: expired),
              const SizedBox(height: OnCareSpacing.s12),
              if (expired)
                _Message(text: l.trainerSyncExpired, onRetry: _issue)
              else
                Text(
                  l.trainerSyncCountdown(_countdown),
                  textAlign: TextAlign.center,
                  style: secondary,
                ),
            ],
            if (_agreed) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s24),
              Text(l.trainerSyncHint, style: secondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 한 자리씩 상자에 담아 보여 준다 — 마주 앉아 불러 주거나 받아 적는 값이라
/// 글자가 서로 갈려야 한다. 자간만 벌린 한 줄은 `0`·`8`, `1`·`7` 처럼 붙어
/// 보이는 조합에서 몇 번째 자리를 읽고 있는지 놓치기 쉽다.
class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.code, required this.dimmed});

  final String code;

  /// 만료됐다. 지우지 않고 흐리게만 두는 것은, 방금 불러 준 값이 무엇이었는지
  /// 회원이 확인할 수 있어야 하기 때문이다.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // 스크린리더가 "구십칠만…" 으로 읽지 않게 한 자씩 끊어 준다.
      label: code.split('').join(' '),
      // 자리마다 Text 가 하나씩 생기므로, 읽어 주는 것은 이 라벨 하나로 둔다.
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < code.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: OnCareSpacing.s4),
            _DigitBox(
              key: ValueKey<String>('sync-digit-$i'),
              digit: code[i],
              dimmed: dimmed,
            ),
          ],
        ],
      ),
    );
  }
}

/// 코드 한 자리.
class _DigitBox extends StatelessWidget {
  const _DigitBox({super.key, required this.digit, required this.dimmed});

  final String digit;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // 여섯 칸이 360 폭 시트 안에 한 줄로 들어가야 한다 — 칸 폭은 터치 영역과
    // 같은 44, 높이는 가장 큰 아바타와 같은 56 을 쓴다. 입력칸과 같은 흰 채움 +
    // 회색 테두리다(#1776).
    return Container(
      width: tokens.density.minTouchTarget,
      height: OnCareSize.avatarXLarge,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: Border.fromBorderSide(
          BorderSide(color: OnCareColors.lineStrong),
        ),
        borderRadius: OnCareRadius.mdAll,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          digit,
          // 자리마다 폭이 달라 보이면 상자 안에서 숫자가 흔들린다.
          style: OnCareTypography.numeric(tokens.text(OnCareTypography.display))
              .copyWith(
                color: dimmed
                    ? OnCareColors.textDisabled
                    : OnCareColors.textPrimary,
              ),
        ),
      ),
    );
  }
}

/// 연결이 확인됐다 — 누구와 연결됐는지 말하고 닫게 한다. (#3342)
///
/// 코드와 공유 범위 안내는 치운다. 코드는 이미 쓰였고, 동의는 코드를 받을 때
/// 끝났다.
class _Connected extends StatelessWidget {
  const _Connected({required this.coach});

  final MemberCoach coach;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey<String>('trainer-sync-connected'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(child: AppAvatar(name: coach.name)),
        const SizedBox(height: OnCareSpacing.s12),
        // 보고 있지 않아도 바뀐 것을 알 수 있게 스크린리더에 알린다.
        Semantics(
          liveRegion: true,
          child: Text(
            l.trainerSyncConnected(coach.name),
            textAlign: TextAlign.center,
            style: tokens
                .text(OnCareTypography.titleSmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(
          l.trainerSyncConnectedBody,
          textAlign: TextAlign.center,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s24),
        AppButton(
          key: const ValueKey<String>('trainer-sync-done'),
          label: l.actionConfirm,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 실패·만료를 말하고 다시 받게 한다.
class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        Text(
          text,
          textAlign: TextAlign.center,
          style: context.oncare
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppButton(
          label: l.trainerSyncRetry,
          onPressed: onRetry,
          variant: AppButtonVariant.text,
        ),
      ],
    );
  }
}
