import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/design_system/tokens/colors.dart';
import 'package:oncare/design_system/tokens/spacing.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 트레이너에게 불러 줄 6자리 동기화 코드를 띄우는 시트. (#1634)
///
/// **이 화면을 여는 것이 데이터 공유 동의다.** 코드를 입력한 트레이너는 그
/// 자리에서 담당이 되어 회원의 식단·운동·건강 기록을 읽는다. 그래서 코드보다
/// 먼저 무엇이 공유되는지 말하고, 회원이 닫으면 코드를 즉시 버린다.
///
/// 코드를 크게 띄우고 자간을 벌리는 것은 마주 앉아 불러 주거나 받아 적는
/// 값이기 때문이다. 남은 시간을 함께 보여 주지 않으면, 트레이너가 늦게
/// 입력했을 때 회원은 왜 안 되는지 알 수 없다.
Future<void> showTrainerSyncSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // 탭 페이지마다 Navigator 가 있고 MainShell 은 `extendBody` 라, 기본값으로
    // 열면 시트가 브랜치 Navigator 안에 뜬다 — 하단 바와 + 버튼이 시트 위에
    // 그려지고 스크림도 걸리지 않은 채 눌린다(#791).
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _TrainerSyncSheet(),
  );
}

class _TrainerSyncSheet extends ConsumerStatefulWidget {
  const _TrainerSyncSheet();

  @override
  ConsumerState<_TrainerSyncSheet> createState() => _TrainerSyncSheetState();
}

class _TrainerSyncSheetState extends ConsumerState<_TrainerSyncSheet> {
  String? _code;
  int _remaining = 0;
  bool _failed = false;
  Timer? _ticker;

  /// 저장소를 미리 붙들어 둔다 — [dispose] 에서 `ref` 를 읽을 수 없다.
  late final TrainerSyncRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(trainerSyncRepositoryProvider);
    _issue();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // 화면을 닫으면 코드를 버린다. 발급이 동의였으니 취소도 즉시 반영돼야
    // 한다. 시트는 이미 사라지는 중이라 결과를 기다리지 않고, 실패해도
    // 서버가 만료로 정리한다.
    unawaited(_revokeQuietly());
    super.dispose();
  }

  Future<void> _revokeQuietly() async {
    try {
      await _repository.revoke();
    } catch (_) {
      // 네트워크가 끊겼다고 시트가 안 닫히면 안 된다.
    }
  }

  Future<void> _issue() async {
    setState(() => _failed = false);
    try {
      final issued = await _repository.issue();
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
    final AppLocalizations l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bool expired = _code != null && _remaining <= 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l.trainerSyncTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // 코드보다 먼저 무엇이 공유되는지 말한다 — 이 시트를 여는 것이
            // 동의라, 동의하는 내용이 코드 아래에 있으면 안 된다.
            Text(
              l.trainerSyncConsent,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_failed)
              _Message(text: l.trainerSyncFailed, onRetry: _issue)
            else if (_code == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              _CodeDisplay(code: _code!, dimmed: expired),
              const SizedBox(height: AppSpacing.md),
              if (expired)
                _Message(text: l.trainerSyncExpired, onRetry: _issue)
              else
                Text(
                  l.trainerSyncCountdown(_countdown),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text(
              l.trainerSyncHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
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
          for (int i = 0; i < code.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _DigitBox(
                key: ValueKey<String>('sync-digit-$i'),
                digit: code[i],
                dimmed: dimmed,
              ),
            ),
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
    return Container(
      width: 46,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        digit,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          // 자리마다 폭이 달라 보이면 상자 안에서 숫자가 흔들린다.
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          color: dimmed ? AppColors.mutedForeground : AppColors.foreground,
        ),
      ),
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
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRetry, child: Text(l.trainerSyncRetry)),
      ],
    );
  }
}
