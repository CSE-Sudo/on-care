import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oncare_core/clock.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/presentation/diet_analysis_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `식단 분석` — 기간마다 파란 카드 하나. (#2379)
///
/// 예전 이름은 `AI 분석` 이었지만 문장은 서버 규칙이 만든다(AI 호출 없음). 그래서
/// 제목은 세 기간 모두 `식단 분석` 이고, 무엇을 두고 한 말인지는 문장이 밝힌다
/// ("이번 주 …", "최근 4주 동안 …").
///
/// `오늘` 은 같은 카드 안에 [recommendation] 이 이어진다 — 분석 한 문단 바로 아래에서
/// 그 이유로 고른 메뉴를 회원에게 추천할지 묻는다. 소제목·구분선을 두지 않는다:
/// 분석이 추천의 이유라 한 흐름으로 읽혀야 한다.
class ClientDietAnalysisCard extends StatelessWidget {
  const ClientDietAnalysisCard({
    super.key,
    required this.analysis,
    this.recommendation,
  });

  final ClientDietAnalysis analysis;

  /// 분석 아래 이어지는 추천(오늘만). 그릴 것이 없으면 스스로 비운다.
  final Widget? recommendation;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String text = clientDietAnalysisText(l, analysis);
    // 빈 문장으로 카드를 세우지 않는다 — 제목만 있으면 분석이 사라진 것인지 아직
    // 안 온 것인지 알 수 없다.
    if (text.isEmpty) return const SizedBox.shrink();
    // 대시보드 활동 피드백·리포트 요약과 같은 카드형 배너다(#2468).
    return AppBanner(
      key: const ValueKey<String>('diet-analysis'),
      placement: AppBannerPlacement.card,
      icon: AppIcons.insights,
      title: l.clientDietAnalysisTitle,
      message: text,
      child: recommendation,
    );
  }
}

/// 한 번에 보여 주는 AI 후보 수 — 다 넘기면 처음부터 다시 보거나 다음 묶음을 본다.
const int kDietRecPageSize = 3;

/// `오늘` 식단 분석 아래 이어지는 `AI 식단 추천`. (#2379)
///
/// AI 가 회원의 4주 추천 메뉴 리스트에서 고른 후보를 하나씩 묻는다 —
/// `아니요` 는 다음 후보, 세 개를 다 넘기면 `처음부터 다시 보기`/`다른 메뉴 보기`.
/// `예` 로 확정하면 회원 앱 홈 `추천 식단` 첫 장이 된다. 확정한 뒤에는 추천 중인
/// 메뉴와 `바꾸기`, 회원이 그 메뉴를 먹었으면 그 사실과 `다음 추천 보기` 를 보인다.
/// 채울 점이 없으면(후보 없음) 아무것도 그리지 않는다 — 분석만 남는다.
///
/// **트레이너가 메뉴를 직접 적는 칸은 두지 않는다.** PT 트레이너의 일은 운동 지도가
/// 중심이고, 끼니마다 무엇을 먹으라고 정해 주는 식단 추천은 거의 하지 않는다. 그래서
/// 메뉴를 짓는 일은 회원의 4주 기록을 읽은 AI 가 맡고, 트레이너는 그 후보를 보고
/// 회원에게 권할지만 `예`/`아니요` 로 정한다 — 식단 코칭이 트레이너의 짐이 되지
/// 않으면서, 회원에게는 트레이너가 확인한 추천으로 닿는다. 서버도 지금 후보 리스트에
/// 없는 메뉴는 확정하지 않는다(`diet_trainer_pick.confirm`).
class ClientDietRecommendationSection extends ConsumerStatefulWidget {
  const ClientDietRecommendationSection({
    super.key,
    required this.clientId,
    this.nextSlot,
  });

  final String clientId;

  /// 오늘 아직 기록하지 않은 다음 끼니(`breakfast`·`lunch`·`dinner`). 다 기록했으면
  /// null — 그때는 "다음 식사로" 묻는다. 그 끼니의 후보를 같은 급함 안에서 앞으로.
  final String? nextSlot;

  @override
  ConsumerState<ClientDietRecommendationSection> createState() =>
      _ClientDietRecommendationSectionState();
}

class _ClientDietRecommendationSectionState
    extends ConsumerState<ClientDietRecommendationSection> {
  int _index = 0;
  bool _exhausted = false;

  /// 확정했거나 먹은 추천 대신 후보를 다시 고르는 중인가.
  bool _choosing = false;
  bool _saving = false;
  bool _failed = false;

  List<ClientDietCandidate> _ordered(List<ClientDietCandidate> all) {
    final String? next = widget.nextSlot;
    if (next == null) return all;
    // 같은 급함 안에서만 다음 끼니를 앞으로 — 급한 이유가 끼니보다 먼저다.
    int rank(ClientDietCandidate c) =>
        (c.urgent ? 0 : 2) + (c.slot == next ? 0 : 1);
    final List<int> order = List<int>.generate(all.length, (int i) => i)
      ..sort((int a, int b) {
        final int by = rank(all[a]).compareTo(rank(all[b]));
        return by != 0 ? by : a.compareTo(b);
      });
    return <ClientDietCandidate>[for (final int i in order) all[i]];
  }

  void _no(int total) {
    setState(() {
      final int pageEnd = (_index ~/ kDietRecPageSize + 1) * kDietRecPageSize;
      if (_index + 1 >= pageEnd || _index + 1 >= total) {
        _exhausted = true;
      } else {
        _index++;
      }
    });
  }

  /// 카운터 옆 꺾쇠 — 같은 묶음 안에서만 오간다. 비교하려고 앞 후보로 돌아가는
  /// 길이며, `아니요` 와 달리 끝에 닿아도 `모두 넘겼어요` 로 가지 않는다.
  void _step(int delta) => setState(() {
    _index += delta;
    _failed = false;
  });

  void _restart() => setState(() {
    _index = _index ~/ kDietRecPageSize * kDietRecPageSize;
    _exhausted = false;
  });

  void _more(int total) => setState(() {
    final int next = (_index ~/ kDietRecPageSize + 1) * kDietRecPageSize;
    _index = next >= total ? 0 : next;
    _exhausted = false;
  });

  Future<void> _yes(ClientDietCandidate c) async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await confirmClientDietRecommendation(ref, widget.clientId, c);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _choosing = false;
        _index = 0;
        _exhausted = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ClientDietRecommendations? r = ref
        .watch(
          clientDietRecommendationsProvider(
            clientDietRecommendationsKey(widget.clientId),
          ),
        )
        .valueOrNull;
    if (r == null) return const SizedBox.shrink();
    final ClientDietPick? pick = r.pick;
    final List<ClientDietCandidate> candidates = _ordered(r.candidates);

    final Widget? body;
    if (pick != null && !pick.resolved && !_choosing) {
      body = _Active(
        pick: pick,
        onChange: () => setState(() => _choosing = true),
      );
    } else if (pick != null && pick.resolved && !_choosing) {
      body = _Resolved(
        pick: pick,
        onNext: candidates.isEmpty
            ? null
            : () => setState(() => _choosing = true),
      );
    } else if (candidates.isEmpty) {
      body = null;
    } else if (_exhausted) {
      body = _Exhausted(
        count:
            (candidates.length - _index ~/ kDietRecPageSize * kDietRecPageSize)
                .clamp(1, kDietRecPageSize),
        onRestart: _restart,
        onMore: () => _more(candidates.length),
      );
    } else {
      final int index = _index.clamp(0, candidates.length - 1);
      final int pageStart = index ~/ kDietRecPageSize * kDietRecPageSize;
      body = _Question(
        candidate: candidates[index],
        nextSlot: widget.nextSlot,
        position: index - pageStart + 1,
        pageSize: (candidates.length - pageStart).clamp(1, kDietRecPageSize),
        saving: _saving,
        failed: _failed,
        onPrev: index > pageStart ? () => _step(-1) : null,
        onForward:
            index + 1 < pageStart + kDietRecPageSize &&
                index + 1 < candidates.length
            ? () => _step(1)
            : null,
        onNo: () => _no(candidates.length),
        onYes: () => _yes(candidates[index]),
      );
    }
    if (body == null) return const SizedBox.shrink();
    // 배너가 본문과 이 구획 사이에 8 을 두어, 분석 문단과 합쳐 16 이 된다.
    return Padding(
      key: const ValueKey<String>('diet-recommendation'),
      padding: const EdgeInsets.only(top: OnCareSpacing.s8),
      child: body,
    );
  }
}

TextStyle _line(BuildContext context) => context.oncare
    .text(OnCareTypography.body)
    .copyWith(color: OnCareColors.textPrimary);

/// 'N월 N일' — KST 날짜로 읽는다(#2893). 서버 시각은 UTC 순간이라 그대로
/// 찍으면 브라우저 시간대의 날짜가 된다.
String _day(BuildContext context, DateTime d) => DateFormat.MMMd(
  Localizations.localeOf(context).toLanguageTag(),
).format(kstDateOf(d));

/// 끼니 · 메뉴 이름 · 이유 키워드 · 1인분 추정치.
class _Menu extends StatelessWidget {
  const _Menu({
    required this.slot,
    required this.name,
    required this.keyword,
    this.candidate,
  });

  final String slot;
  final String name;
  final String keyword;
  final ClientDietCandidate? candidate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ClientDietCandidate? c = candidate;
    return Wrap(
      spacing: OnCareSpacing.s8,
      runSpacing: OnCareSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AppTag(label: l.clientDietRecSlot(slot)),
        Text(
          name,
          key: const ValueKey<String>('diet-recommendation-menu'),
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.bodyLarge))
              .copyWith(color: OnCareColors.textPrimary),
        ),
        if (keyword.isNotEmpty) AppTag(label: keyword, tone: AppTagTone.brand),
        // 데모 리스트처럼 추정치가 없으면 적지 않는다 — `0kcal` 은 거짓말이다.
        if (c != null && c.kcal > 0)
          Text(
            l.clientDietRecNutrition(
              formatDietAmount(c.kcal, 'calorie').replaceAll('kcal', ''),
              '${c.proteinG}',
              formatDietAmount(c.sodiumMg, 'sodium').replaceAll('mg', ''),
            ),
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.candidate,
    required this.nextSlot,
    required this.position,
    required this.pageSize,
    required this.saving,
    required this.failed,
    required this.onPrev,
    required this.onForward,
    required this.onNo,
    required this.onYes,
  });

  final ClientDietCandidate candidate;
  final String? nextSlot;
  final int position;
  final int pageSize;
  final bool saving;
  final bool failed;

  /// 묶음의 첫·끝에서는 null — 꺾쇠를 흐리게 둔다(숨기면 카운터가 흔들린다).
  final VoidCallback? onPrev;
  final VoidCallback? onForward;
  final VoidCallback onNo;
  final VoidCallback onYes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                nextSlot == null
                    ? l.clientDietRecQuestionNext
                    : l.clientDietRecQuestion(candidate.slot),
                style: _line(context),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            // 질문이 두 줄로 접혀도 꺾쇠·카운터는 첫 줄에 한 덩어리로 가운데 맞춘다.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Step(
                  key: const ValueKey<String>('diet-recommendation-prev'),
                  icon: AppIcons.chevronLeft,
                  tooltip: l.clientDietRecPrev,
                  onPressed: saving ? null : onPrev,
                ),
                Text(
                  l.clientDietRecCounter(position, pageSize),
                  key: const ValueKey<String>('diet-recommendation-counter'),
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
                _Step(
                  key: const ValueKey<String>('diet-recommendation-forward'),
                  icon: AppIcons.chevronRight,
                  tooltip: l.clientDietRecForward,
                  onPressed: saving ? null : onForward,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        _WithActions(
          content: _Menu(
            slot: candidate.slot,
            name: candidate.name,
            keyword: candidate.keyword,
            candidate: candidate,
          ),
          actions: <Widget>[
            AppButton(
              key: const ValueKey<String>('diet-recommendation-no'),
              label: l.clientDietRecNo,
              onPressed: saving ? null : onNo,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
            ),
            AppButton(
              key: const ValueKey<String>('diet-recommendation-yes'),
              label: l.clientDietRecYes,
              onPressed: saving ? null : onYes,
              loading: saving,
              size: OnCareButtonSize.small,
            ),
          ],
        ),
        if (failed) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            l.clientDietRecConfirmFailed,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.danger),
          ),
        ],
      ],
    );
  }
}

/// 카운터 옆 꺾쇠. 묶음 끝에서는 흐리게 남긴다 — 숨기면 카운터 자리가 흔들린다.
class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.3 : 1,
    child: AppIconButton(
      icon: icon,
      tooltip: tooltip,
      size: AppIconButtonSize.small,
      color: OnCareColors.textSecondary,
      onPressed: onPressed,
    ),
  );
}

class _Exhausted extends StatelessWidget {
  const _Exhausted({
    required this.count,
    required this.onRestart,
    required this.onMore,
  });

  final int count;
  final VoidCallback onRestart;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _WithActions(
      content: Text(l.clientDietRecExhausted(count), style: _line(context)),
      actions: <Widget>[
        AppButton(
          key: const ValueKey<String>('diet-recommendation-restart'),
          label: l.clientDietRecRestart,
          onPressed: onRestart,
          variant: AppButtonVariant.secondary,
          size: OnCareButtonSize.small,
        ),
        AppButton(
          key: const ValueKey<String>('diet-recommendation-more'),
          label: l.clientDietRecMore,
          onPressed: onMore,
          size: OnCareButtonSize.small,
        ),
      ],
    );
  }
}

/// 내용 오른쪽 끝에 버튼을 한 줄로 — 좁으면 버튼을 아래 줄 오른쪽으로 내린다.
///
/// 버튼만 따로 한 줄을 차지하면 카드가 그만큼 길어지고, 무엇에 대한 `예`·`아니요`
/// 인지가 한 줄 떨어져 읽힌다.
class _WithActions extends StatelessWidget {
  const _WithActions({required this.content, required this.actions});

  final Widget content;
  final List<Widget> actions;

  /// 이보다 좁으면 버튼을 아래 줄로 — 메뉴 이름·키워드가 버튼에 밀려 여러 줄로
  /// 쪼개지지 않을 폭이다.
  static const double _oneLineMinWidth = 480;

  @override
  Widget build(BuildContext context) {
    final Widget buttons = AppActionRow(actions: actions);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        if (c.maxWidth < _oneLineMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              content,
              const SizedBox(height: OnCareSpacing.s12),
              buttons,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: content),
            const SizedBox(width: OnCareSpacing.s12),
            buttons,
          ],
        );
      },
    );
  }
}

class _Active extends StatelessWidget {
  const _Active({required this.pick, required this.onChange});

  final ClientDietPick pick;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.clientDietRecActive(_day(context, pick.confirmedAt)),
          style: _line(context),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Row(
          children: <Widget>[
            Expanded(
              child: _Menu(
                slot: pick.slot,
                name: pick.name,
                keyword: pick.keyword,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            AppButton(
              key: const ValueKey<String>('diet-recommendation-change'),
              label: l.clientDietRecChange,
              onPressed: onChange,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
            ),
          ],
        ),
      ],
    );
  }
}

class _Resolved extends StatelessWidget {
  const _Resolved({required this.pick, required this.onNext});

  final ClientDietPick pick;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime? when = pick.resolvedAt;
    final String text = when == null
        ? l.clientDietRecResolvedNoSlot(
            pick.name,
            _day(context, pick.confirmedAt),
          )
        : l.clientDietRecResolved(pick.name, _day(context, when), pick.slot);
    return Row(
      children: <Widget>[
        const AppIcon(
          AppIcons.checkCircle,
          size: OnCareSize.iconMedium,
          color: OnCareColors.success,
        ),
        const SizedBox(width: OnCareSpacing.s8),
        Expanded(
          child: Text(
            text,
            key: const ValueKey<String>('diet-recommendation-resolved'),
            style: _line(context),
          ),
        ),
        if (onNext != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          AppButton(
            key: const ValueKey<String>('diet-recommendation-next'),
            label: l.clientDietRecNext,
            onPressed: onNext,
            size: OnCareButtonSize.small,
          ),
        ],
      ],
    );
  }
}
