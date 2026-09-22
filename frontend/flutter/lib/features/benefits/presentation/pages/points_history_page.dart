import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/benefits/domain/entities/points_history.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 포인트 내역 — 무엇으로 얼마가 쌓이고 쓰였는가. (#2146)
///
/// 포인트 화면의 `포인트 내역` 에서 들어온다. 기록이 있는 날 기준 최근 며칠치를
/// 날짜로 묶어 보여 주고, 더 앞의 날은 `더 보기` 로 이어 받는다. AI 코치 대화는
/// 서버가 하루 한 줄로 묶어 준다.
///
/// 화면을 떠나면 버린다 — 다시 열 때 새로 읽어야 그사이 쌓이고 쓴 것이 보인다.
class PointsHistoryPage extends ConsumerStatefulWidget {
  const PointsHistoryPage({super.key});

  @override
  ConsumerState<PointsHistoryPage> createState() => _PointsHistoryPageState();
}

class _PointsHistoryPageState extends ConsumerState<PointsHistoryPage> {
  final List<PointsHistoryEntry> _entries = <PointsHistoryEntry>[];
  int? _balance;
  String? _nextBefore;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [more] 면 지금까지 받은 날보다 앞을 이어 붙인다. 아니면 처음부터 다시 읽는다.
  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(benefitsRepositoryProvider)
          .fetchPointsHistory(before: more ? _nextBefore : null);
      if (!mounted) return;
      setState(() {
        if (!more) _entries.clear();
        _entries.addAll(page.entries);
        _balance = page.balance;
        _nextBefore = page.nextBefore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final int? balance = _balance;
    return AppPage(
      key: const Key('pointsHistoryPage'),
      bottomInset: MediaQuery.paddingOf(context).bottom,
      header: AppTopBar(title: l.myPointsHistoryTitle),
      children: <Widget>[
        if (balance != null) ...<Widget>[
          Text(
            l.myPointsBalance(balance),
            key: const Key('pointsHistoryBalance'),
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: tokens.brand.primary),
          ),
          const SizedBox(height: OnCareSpacing.s16),
        ],
        ..._body(l),
      ],
    );
  }

  List<Widget> _body(AppLocalizations l) {
    if (_entries.isEmpty) {
      if (_loading) {
        return const <Widget>[
          AppCard(child: AppLoading(placement: AppStatePlacement.card)),
        ];
      }
      if (_failed) {
        return <Widget>[
          AppCard(
            child: AppErrorState(
              title: l.myPointsHistoryLoadFailed,
              retryLabel: l.actionRetry,
              onRetry: _load,
              placement: AppStatePlacement.card,
            ),
          ),
        ];
      }
      return <Widget>[
        AppCard(
          child: AppEmptyState(
            title: l.myPointsHistoryEmpty,
            message: l.myPointsHistoryEmptyMessage,
            icon: benefitIcon(''),
            placement: AppStatePlacement.card,
          ),
        ),
      ];
    }
    // 날짜로 묶는다 — 서버가 최신순으로 주므로 이어진 같은 날끼리 모인다.
    final List<List<PointsHistoryEntry>> days = <List<PointsHistoryEntry>>[];
    for (final PointsHistoryEntry e in _entries) {
      if (days.isEmpty || days.last.first.day != e.day) {
        days.add(<PointsHistoryEntry>[]);
      }
      days.last.add(e);
    }
    return <Widget>[
      for (int i = 0; i < days.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: OnCareSpacing.s24),
        AppSectionHeader(title: l.coachChatDateDivider(days[i].first.day)),
        const SizedBox(height: OnCareSpacing.s8),
        AppCard(
          child: Column(
            children: <Widget>[
              for (int j = 0; j < days[i].length; j++) ...<Widget>[
                if (j > 0) const AppDivider(),
                _EntryRow(entry: days[i][j]),
              ],
            ],
          ),
        ),
      ],
      if (_nextBefore != null) ...<Widget>[
        const SizedBox(height: OnCareSpacing.s16),
        AppButton(
          key: const Key('pointsHistoryMore'),
          label: l.myPointsHistoryMore,
          variant: AppButtonVariant.secondary,
          fullWidth: true,
          loading: _loading,
          onPressed: _loading ? null : () => _load(more: true),
        ),
      ],
    ];
  }
}

/// 내역 한 줄 — 무엇으로, 얼마.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final PointsHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool gain = entry.delta > 0;
    return Padding(
      key: ValueKey<String>('points-entry-${entry.id}'),
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s8),
      child: Row(
        children: <Widget>[
          BenefitIconTile(icon: pointsEntryIcon(entry)),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Text(
              pointsEntryLabel(l, entry),
              style: tokens
                  .text(OnCareTypography.body)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Text(
            pointsDelta(l, entry.delta),
            style:
                OnCareTypography.numeric(
                  tokens.text(OnCareTypography.strong(OnCareTypography.body)),
                ).copyWith(
                  color: gain ? tokens.brand.primary : OnCareColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
