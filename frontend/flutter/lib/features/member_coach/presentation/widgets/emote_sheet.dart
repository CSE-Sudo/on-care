import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이모티콘을 고르는 창. 고른 id 를 돌려주고 닫는다. (#2020)
///
/// 사는 자리도 여기다 — 채팅을 하다 이모티콘을 누른 사람에게 MY 탭까지 다녀오라고
/// 하면 하려던 말을 놓친다. MY 탭의 포인트 사용처에서도 같은 항목을 살 수 있다.
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
  /// 남은 시간은 창이 열려 있는 동안 스스로 센다. 서버에 1초마다 물으면 같은 답을
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
      if (now == null || !now.active) return;
      setState(() => _state = now.tick(const Duration(seconds: 1)));
    });
  }

  Future<void> _buy() async {
    if (_busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final EmoteState? state = _state;
    if (state == null) return;
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.emoteBuyTitle,
      message: l.emoteBuyConfirm(state.cost, state.hours),
      confirmLabel: l.emoteBuyAction,
      cancelLabel: l.myCancel,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final EmoteState bought = await ref
          .read(emoteRepositoryProvider)
          .buyPass();
      if (!mounted) return;
      setState(() => _state = bought);
      // 포인트가 빠졌으니 MY 잔액도 다시 읽는다.
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
          else ...<Widget>[
            _PassBar(state: state, busy: _busy, onBuy: _buy),
            const SizedBox(height: OnCareSpacing.s12),
            Flexible(child: _Grid(locked: !state.active)),
          ],
        ],
      ),
    );
  }
}

/// 이용권 줄 — 이용 중이면 남은 시간, 아니면 값과 사는 버튼.
class _PassBar extends StatelessWidget {
  const _PassBar({
    required this.state,
    required this.busy,
    required this.onBuy,
  });

  final EmoteState state;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    if (state.active) {
      return AppBanner(
        key: const Key('emotePassActive'),
        tone: AppBannerTone.success,
        title: l.emotePassActive,
        message: l.emotePassRemaining(_remainingLabel(l, state.remaining!)),
      );
    }
    return AppCard(
      key: const Key('emotePassBuy'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.emotePassOffer(state.cost, state.hours),
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.body))
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            // 모자라면 얼마가 모자란지 말한다 — `살 수 없어요` 만으로는 무엇을
            // 해야 하는지 알 수 없다.
            state.shortfall > 0
                ? l.emotePassShortfall(state.shortfall, state.balance)
                : l.emotePassBalance(state.balance),
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppButton(
            key: const Key('emoteBuyButton'),
            label: l.emoteBuyAction,
            fullWidth: true,
            loading: busy,
            onPressed: state.canBuy ? onBuy : null,
          ),
        ],
      ),
    );
  }
}

/// 남은 시간 한 줄 — `3시간 12분` · `12분`.
String _remainingLabel(AppLocalizations l, Duration left) {
  final int hours = left.inHours;
  final int minutes = left.inMinutes % 60;
  if (hours > 0) return l.emoteRemainingHm(hours, minutes);
  if (minutes > 0) return l.emoteRemainingM(minutes);
  return l.emoteRemainingSoon;
}

class _Grid extends StatelessWidget {
  const _Grid({required this.locked});

  /// 이용권이 없으면 고를 수 없다. 그래도 **무엇이 있는지는 보여 준다** —
  /// 가려 두면 무엇을 사는지 모른 채 사야 한다.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    // 묶음으로 나누지 않는다 — 이용권은 24시간 전체 사용이라 묶음이 고르는 데
    // 보탬이 되지 않고, 제목이 끼면 한 화면에 보이는 이모티콘만 줄어든다.
    return SingleChildScrollView(
      child: Wrap(
        spacing: OnCareSpacing.s8,
        runSpacing: OnCareSpacing.s8,
        children: <Widget>[
          for (final String id in AppEmotes.all)
            Opacity(
              opacity: locked ? 0.35 : 1,
              child: InkWell(
                key: Key('emote-$id'),
                borderRadius: OnCareRadius.mdAll,
                onTap: locked ? null : () => Navigator.of(context).pop(id),
                child: AppEmote(id: id, size: OnCareSize.emotePick),
              ),
            ),
        ],
      ),
    );
  }
}

