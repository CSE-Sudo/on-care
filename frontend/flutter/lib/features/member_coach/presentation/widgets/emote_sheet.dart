import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이모티콘을 고르는 창. 고른 id 를 돌려주고 닫는다. (#2020, #2153)
///
/// 이모티콘은 **하나씩 사서 7일 동안** 쓴다. 사는 자리도 여기뿐이다 — 60개 중 무엇을
/// 사는지는 그림을 보며 골라야 알 수 있고, 채팅을 하다 MY 탭까지 다녀오라고 하면
/// 하려던 말을 놓친다.
///
/// 한 판에 이모티콘만 늘어놓고, 산 것을 맨 앞으로 올린다. 회원이 매번 찾는 것은 산
/// 몇 개인데, 안 산 이모티콘 사이에 흩어 두면 60개를 훑어야 찾는다.
Future<String?> showEmoteSheet(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    builder: (BuildContext _) => const _EmoteSheet(),
  );
}

class _EmoteSheet extends ConsumerStatefulWidget {
  const _EmoteSheet();

  @override
  ConsumerState<_EmoteSheet> createState() => _EmoteSheetState();
}

class _EmoteSheetState extends ConsumerState<_EmoteSheet> {
  /// 남은 기간은 창이 열려 있는 동안 스스로 센다. 서버에 다시 물으면 같은 답을
  /// 받으려고 망을 쓰는 셈이고, 기기 시계로 재면 시계가 틀어진 기기에서 어긋난다.
  Timer? _ticker;
  EmoteState? _state;
  bool _busy = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final EmoteState? now = _state;
      if (now == null || now.unlocked.isEmpty) return;
      setState(() => _state = now.tick(const Duration(seconds: 1)));
    });
  }

  Future<void> _buy(String id) async {
    if (_busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final EmoteState? state = _state;
    if (state == null) return;
    if (state.shortfall > 0) {
      // 모자라면 확인창을 띄우지 않는다 — 누를 수 없는 `사기` 가 있는 창을 한 번 더
      // 닫게 된다.
      toast.show(l.emoteShortfall);
      return;
    }
    final bool ok = await _confirmBuy(context, id, state);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final EmoteState bought = await ref
          .read(emoteRepositoryProvider)
          .unlock(id);
      if (!mounted) return;
      setState(() => _state = bought);
      // 포인트가 빠졌으니 다음에 열 때 다시 읽는다.
      ref.invalidate(emoteStateProvider);
      toast.show(l.emoteBought, type: AppToastType.success);
    } on Object {
      if (!mounted) return;
      toast.show(l.emoteBuyFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<EmoteState> async = ref.watch(emoteStateProvider);
    async.whenData((EmoteState value) {
      // 창이 열릴 때 한 번만 받아 두고, 그 뒤로는 창이 센 값을 쓴다.
      _state ??= value;
      _startTicker();
    });
    final EmoteState? state = _state;
    return AppSheet(
      key: const Key('emoteSheet'),
      showClose: false,
      title: l.emoteSheetTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (async.hasError && state == null)
            AppErrorState(
              title: l.emoteLoadFailed,
              retryLabel: l.actionRetry,
              onRetry: () => ref.invalidate(emoteStateProvider),
            )
          else if (state == null)
            const AppLoading()
          else
            Flexible(
              child: _Grid(
                state: state,
                onPick: (String id) => Navigator.of(context).pop(id),
                onBuy: _buy,
              ),
            ),
        ],
      ),
    );
  }
}

/// 사기 전 확인창 — 무엇을 사는지 그림으로 보여 주고, 보유 포인트를 적는다.
Future<bool> _confirmBuy(BuildContext context, String id, EmoteState state) {
  final AppLocalizations l = AppLocalizations.of(context);
  return showAppDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      key: const Key('emoteBuyDialog'),
      title: l.emoteBuyTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.myCancel,
        onCancel: () => Navigator.pop(dialogContext, false),
        confirmLabel: l.emoteBuyAction,
        confirmKey: const Key('emoteBuyConfirm'),
        onConfirm: () => Navigator.pop(dialogContext, true),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppEmote(id: id, size: OnCareSize.emotePick),
          const SizedBox(height: OnCareSpacing.s12),
          Text(
            l.emoteBuyConfirm(state.cost, state.days),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // 지금 잔액만 적는다 — 값이 50P 로 늘 같아 산 뒤 잔액은 바로 셀 수 있다.
          Text(
            l.myPointsBalance(state.balance),
            key: const Key('emoteBuyBalance'),
            textAlign: TextAlign.center,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ),
    ),
  ).then((bool? ok) => ok ?? false);
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.state,
    required this.onPick,
    required this.onBuy,
  });

  final EmoteState state;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onBuy;

  @override
  Widget build(BuildContext context) {
    // 원래 순서에서 산 것만 맨 앞으로 — 산 것끼리, 안 산 것끼리는 원래 순서 그대로다.
    // 산 순서나 남은 기간 순이면 하나를 살 때마다 자리가 바뀐다.
    final List<String> ordered = <String>[
      for (final String id in AppEmotes.all)
        if (state.isUnlocked(id)) id,
      for (final String id in AppEmotes.all)
        if (!state.isUnlocked(id)) id,
    ];
    return SingleChildScrollView(
      child: Wrap(
        spacing: OnCareSpacing.s8,
        runSpacing: OnCareSpacing.s8,
        children: <Widget>[
          for (final String id in ordered)
            _Tile(
              id: id,
              // 안 산 것도 무엇인지는 보여 준다 — 가려 두면 무엇을 사는지 모른 채
              // 사야 한다. 흐리게만 둔다.
              locked: !state.isUnlocked(id),
              onTap: () =>
                  state.isUnlocked(id) ? onPick(id) : onBuy(id),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.id, required this.locked, required this.onTap});

  final String id;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('emote-$id'),
      borderRadius: OnCareRadius.mdAll,
      onTap: onTap,
      child: Opacity(
        opacity: locked ? 0.35 : 1,
        child: AppEmote(id: id, size: OnCareSize.emotePick),
      ),
    );
  }
}
