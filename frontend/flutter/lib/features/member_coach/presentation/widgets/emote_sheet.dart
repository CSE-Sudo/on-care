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
/// 산 이모티콘은 맨 위 `쓰는 중` 에 모은다. 회원이 매번 찾는 것은 산 몇 개인데, 안 산
/// 이모티콘 사이에 흩어 두면 60개를 훑어야 찾는다. 안 산 것은 그 아래 묶음별로 둔다.
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
      // 모자라면 얼마가 모자란지 말한다 — `살 수 없어요` 만으로는 무엇을 해야 하는지
      // 알 수 없다.
      toast.show(l.emoteShortfall(state.shortfall, state.balance));
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
            _Summary(state: state),
            const SizedBox(height: OnCareSpacing.s16),
            Flexible(
              child: _Board(
                state: state,
                onPick: (String id) => Navigator.of(context).pop(id),
                onBuy: _buy,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 사기 전 확인창 — 무엇을 사는지 그림으로 보여 준다.
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
        ],
      ),
    ),
  ).then((bool? ok) => ok ?? false);
}

/// 값·기간과 지금 잔액 두 줄.
class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final EmoteState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      key: const Key('emoteSummary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.emoteSheetInfo(state.cost, state.days),
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.body))
              .copyWith(color: OnCareColors.textPrimary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(
          l.emoteBalance(state.balance),
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textSecondary),
        ),
      ],
    );
  }
}

/// 산 것(`쓰는 중`) 먼저, 그 아래 안 산 것을 묶음별로.
class _Board extends StatelessWidget {
  const _Board({
    required this.state,
    required this.onPick,
    required this.onBuy,
  });

  final EmoteState state;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onBuy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 산 것도 목록 순서대로 둔다 — 산 순서나 남은 기간 순이면 하나를 살 때마다 자리가
    // 바뀌어, 늘 누르던 자리에서 다른 이모티콘이 나온다.
    final List<String> owned = <String>[
      for (final String id in AppEmotes.all)
        if (state.isUnlocked(id)) id,
    ];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (owned.isNotEmpty)
            _Section(
              key: const Key('emoteOwned'),
              title: l.emoteOwnedSection,
              children: <Widget>[
                for (final String id in owned)
                  _Tile(
                    id: id,
                    caption: _leftLabel(l, state.unlocked[id]!),
                    locked: false,
                    onTap: () => onPick(id),
                  ),
              ],
            ),
          for (final AppEmotePack pack in AppEmotes.packs)
            if (pack.emotes.any((String id) => !state.isUnlocked(id)))
              _Section(
                key: Key('emotePack-${pack.id}'),
                title: _packName(l, pack.id),
                children: <Widget>[
                  for (final String id in pack.emotes)
                    if (!state.isUnlocked(id))
                      _Tile(
                        id: id,
                        caption: l.emotePrice(state.cost),
                        // 안 산 것도 무엇인지는 보여 준다 — 가려 두면 무엇을 사는지
                        // 모른 채 사야 한다.
                        locked: true,
                        onTap: () => onBuy(id),
                      ),
                ],
              ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(title: title),
          const SizedBox(height: OnCareSpacing.s8),
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: children,
          ),
        ],
      ),
    );
  }
}

/// 이모티콘 한 칸 — 그림과 그 아래 한 줄(값 또는 남은 기간).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.id,
    required this.caption,
    required this.locked,
    required this.onTap,
  });

  final String id;
  final String caption;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return InkWell(
      key: Key('emote-$id'),
      borderRadius: OnCareRadius.mdAll,
      onTap: onTap,
      child: SizedBox(
        width: OnCareSize.emotePick,
        child: Column(
          children: <Widget>[
            Opacity(
              opacity: locked ? 0.35 : 1,
              child: AppEmote(id: id, size: OnCareSize.emotePick),
            ),
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(
                    color: locked
                        ? OnCareColors.textSecondary
                        : tokens.brand.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 남은 기간 한 줄 — `6일 남음` · `5시간 남음` · `곧 끝나요`.
///
/// 날은 올림으로 센다. 막 산 이모티콘이 `6일 남음` 으로 보이면 하루를 덜 받은 것
/// 같다.
String _leftLabel(AppLocalizations l, Duration left) {
  if (left >= const Duration(days: 1)) {
    final int days = (left.inSeconds / Duration.secondsPerDay).ceil();
    return l.emoteLeftDays(days);
  }
  if (left >= const Duration(hours: 1)) return l.emoteLeftHours(left.inHours);
  return l.emoteLeftSoon;
}

String _packName(AppLocalizations l, String pack) => switch (pack) {
  'owoon' => l.emotePackOwoon,
  'legday' => l.emotePackLegday,
  'diet' => l.emotePackDiet,
  'coach' => l.emotePackCoach,
  'condition' => l.emotePackCondition,
  'react' => l.emotePackReact,
  'dog' => l.emotePackDog,
  'cat' => l.emotePackCat,
  _ => pack,
};
