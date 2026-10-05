import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/app_error_state_for.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// "AI 건강 도우미" bottom sheet — the daily coaching digest opened from the
/// floating Oni button and the Home coaching banner. Its CTA hands off to the
/// AI chat — or, for a member with a trainer, to that trainer's chat (#1823).
/// Mirrors the Figma `CoachingSheet`.
Future<void> showCoachingSheet(BuildContext context, {WidgetRef? ref}) {
  // 열어서 봤으면 배지를 내린다. 읽을 것이 없는데도 남는 숫자는 알림 벨의
  // 미읽음 점과 같은 종류의 거짓말이다(#788).
  ref?.read(coachingSeenCountProvider.notifier).state = ref.read(
    coachingSuggestionCountProvider,
  );
  return showAppSheet<void>(
    // 탭 페이지마다 Navigator 가 따로 있어 가까운 Navigator 로 열면 시트가 그
    // 안에 뜬다. MainShell 의 하단 바와 + 버튼은 그 바깥이라 시트 **위에**
    // 그려지고, 스크림도 걸리지 않은 채 눌린다 — 시트를 열어 둔 채 탭이
    // 바뀐다(#791). 루트 Navigator 의 context 로 띄워 맨 위에 올린다.
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (BuildContext ctx) => const _CoachingSheet(),
  );
}

/// 데모 모드에서 시트가 그리는 데모 카드 수.
///
/// [_cardsOf] 의 길이와 같아야 한다 — 배지 숫자와 시트에 실제로 보이는 카드 수가
/// 어긋나면 배지가 다시 거짓말을 한다. 위젯 테스트가 두 값을 맞춰 둔다.
///
/// 이 카드는 **데모 회원의 하루를 묘사한 고정 문구**다. 실서버에서는 쓰지 않는다
/// — 기록이 없는 회원에게도 "점심으로 드신 짬뽕" 이 실제 분석처럼 보였다(#2813).
const int kCoachFallbackCardCount = 2;

/// 지금 코칭 시트가 보여 줄 카드 수. 배지와 시트가 같은 규칙을 읽는다.
///
/// 실서버에서는 **실제로 받은 제안 수만** 센다. 로딩·에러·빈 응답이면 시트에
/// 볼 카드가 없으므로 0 이다 — 볼 것이 없는데 `새 제안 2` 가 뜨지 않게(#2813).
final coachingSuggestionCountProvider = Provider<int>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) return kCoachFallbackCardCount;
  final List<AiSuggestion>? live = ref
      .watch(aiCoachStateProvider)
      .asData
      ?.value
      .suggestions;
  return live?.length ?? 0;
}, name: 'coachingSuggestionCount');

/// 마지막으로 시트를 열어 확인한 카드 수.
///
/// 배지는 이 값을 넘는 만큼만 뜬다. 새 제안이 늘면 다시 뜨고, 다 본 뒤에는
/// 사라진다. 앱을 다시 켜면 초기화된다 — 코칭 카드는 하루 단위 요약이라
/// 영구 저장까지 할 만한 상태가 아니다.
final coachingSeenCountProvider = StateProvider<int>(
  (ref) => 0,
  name: 'coachingSeenCount',
);

/// 플로팅 버튼에 띄울 배지 숫자. 볼 것이 없으면 0.
final coachingBadgeCountProvider = Provider<int>((ref) {
  final int count = ref.watch(coachingSuggestionCountProvider);
  final int seen = ref.watch(coachingSeenCountProvider);
  return count > seen ? count - seen : 0;
}, name: 'coachingBadgeCount');

class _CoachCard {
  const _CoachCard({
    required this.tag,
    required this.title,
    required this.body,
  });
  final String tag;
  final String title;
  final String body;
}

List<_CoachCard> _cardsOf(AppLocalizations l) => <_CoachCard>[
  _CoachCard(
    tag: l.coachCardDietTag,
    title: l.coachCardDietTitle,
    body: l.coachCardDietBody,
  ),
  _CoachCard(
    tag: l.coachCardExerciseTag,
    title: l.coachCardExerciseTitle,
    body: l.coachCardExerciseBody,
  ),
];

/// 제안 태그 → 화면에 그릴 이름. 태그 자체는 서버가 주는 계약값이라 그대로
/// 두고, 사람이 읽는 이름만 로케일을 따른다(#847).
String _suggestionTagLabel(AppLocalizations l, AiSuggestionTag tag) =>
    switch (tag) {
      AiSuggestionTag.diet => l.coachCardDietTag,
      AiSuggestionTag.exercise => l.coachCardExerciseTag,
      AiSuggestionTag.sleep => l.coachCardSleepTag,
      AiSuggestionTag.hydration => l.coachCardWaterTag,
    };

_CoachCard _cardFromSuggestion(AppLocalizations l, AiSuggestion s) =>
    _CoachCard(
      tag: _suggestionTagLabel(l, s.tag),
      title: s.title,
      body: s.body,
    );

class _CoachingSheet extends ConsumerStatefulWidget {
  const _CoachingSheet();

  @override
  ConsumerState<_CoachingSheet> createState() => _CoachingSheetState();
}

class _CoachingSheetState extends ConsumerState<_CoachingSheet> {
  @override
  void initState() {
    super.initState();
    // 조언 상태는 세션 내내 살아 있다. 한 번 실패하면 그 세션 내내 오류에
    // 머물렀으므로, 시트를 열 때 오류 상태면 다시 받는다(#2813). 빌드 중에
    // provider 를 건드리지 않도록 첫 프레임 뒤에 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(aiCoachStateProvider).hasError) {
        ref.invalidate(aiCoachStateProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 데모/목 모드는 기존 데모 카드를 유지(둘러보기 화면 동일). 실서버에서는
    // /ai-coach/feedback 의 실제 제안만 그리고, 로딩·오류·빈 응답은 각자의 상태로
    // 보여 준다 — 데모 고정 문구로 채우지 않는다(#2813).
    final Widget body;
    if (ref.watch(appConfigProvider).useMockApi) {
      body = _CoachCardList(cards: _cardsOf(l));
    } else {
      final AsyncValue<AiCoachState> state = ref.watch(aiCoachStateProvider);
      final List<AiSuggestion>? live = state.asData?.value.suggestions;
      if (live != null && live.isNotEmpty) {
        body = _CoachCardList(
          cards: <_CoachCard>[
            for (final AiSuggestion s in live) _cardFromSuggestion(l, s),
          ],
        );
      } else if (state.hasError && !state.isLoading) {
        body = appErrorStateFor(
          context,
          key: const Key('coachingSheetError'),
          error: state.error,
          title: l.coachSheetErrorTitle,
          message: l.coachSheetErrorBody,
          retryKey: const Key('coachingSheetRetry'),
          onRetry: () => ref.invalidate(aiCoachStateProvider),
          placement: AppStatePlacement.card,
        );
      } else if (state.isLoading) {
        body = const AppLoading(
          key: Key('coachingSheetLoading'),
          placement: AppStatePlacement.card,
        );
      } else {
        body = AppEmptyState(
          key: const Key('coachingSheetEmpty'),
          title: l.coachSheetEmptyTitle,
          message: l.coachSheetEmptyBody,
          placement: AppStatePlacement.card,
        );
      }
    }

    // 담당 트레이너가 있는 회원은 AI 챗봇을 쓰지 않는다(#1823). 같은 버튼이 그
    // 트레이너 채팅으로 이어진다.
    final MemberCoach? coach = ref.watch(memberCoachProvider).valueOrNull;

    // 이전 디자인으로 되돌린다(#1831) — 시트 제목 줄 대신 **도우미가 조언을 건네는**
    // 머리: 왼쪽 Oni 아바타, 옆에 파란 `AI 건강 도우미` 와 굵은 한 줄. 회원 앱의
    // 부분 창에는 닫기 X 를 두지 않는다 — 끌어내리기·바깥 누르기·뒤로가기로
    // 닫는다(#2170). 핸들·높이·하단 여백은 [AppSheet] 가 그대로 맡는다.
    return AppSheet(
      key: const Key('coachingSheet'),
      showClose: false,
      // 하단 여백·홈 인디케이터는 AppSheet 의 footer 가 맡는다 — 예전에는 여백
      // 0 이라 SafeArea 가 없는 기기에서 버튼이 시트 끝에 붙어 잘렸다(#1180).
      footer: KeyedSubtree(
        key: const Key('coachingSheetCta'),
        child: AppButton(
          label: coach != null ? l.coachChatWithTrainer : l.coachCtaChat,
          // 담당이 없으면 이 버튼이 여는 곳은 AI 챗봇이다 — 머리의 입구와 같은
          // 마크를 써서 같은 곳으로 간다는 것을 보인다(#1918). 채운 버튼이라
          // 말풍선이 흰색이고 별은 버튼 색으로 뚫린다.
          leadingIcon: AppIcons.chat,
          leadingGlyph: coach != null
              ? null
              : AppAiChatGlyph(
                  bubble: AppIcons.chat,
                  color: OnCareColors.textOnFill,
                  holeColor: context.oncare.brand.primary,
                ),
          size: OnCareButtonSize.large,
          fullWidth: true,
          onPressed: () {
            Navigator.of(context).pop();
            if (coach != null) {
              openTrainerChatPage(context, trainerName: coach.name);
            } else {
              context.push(AppRoutes.aiCoach);
            }
          },
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _CoachingSheetHeader(),
          const SizedBox(height: OnCareSpacing.s16),
          body,
        ],
      ),
    );
  }
}

/// 코칭 카드 목록 — 카드 사이에 같은 간격을 둔다.
class _CoachCardList extends StatelessWidget {
  const _CoachCardList({required this.cards});

  final List<_CoachCard> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (int i, _CoachCard card) in cards.indexed) ...<Widget>[
          if (i > 0) const SizedBox(height: OnCareSpacing.cardGap),
          _CoachCardTile(card: card),
        ],
      ],
    );
  }
}

/// 도우미 창 머리 — Oni 아바타 · `AI 건강 도우미` · 오늘의 한 줄. (#1831)
class _CoachingSheetHeader extends StatelessWidget {
  const _CoachingSheetHeader();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Row(
      key: const Key('coachingSheetHeader'),
      children: <Widget>[
        const OniAvatar(size: OnCareSize.avatarXLarge),
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l.coachHeaderPill,
                style: tokens
                    .text(OnCareTypography.strong(OnCareTypography.label))
                    .copyWith(color: tokens.brand.primary),
              ),
              const SizedBox(height: OnCareSpacing.s2),
              Text(
                l.coachHeaderSubtitle,
                style: tokens
                    .text(OnCareTypography.titleSmall)
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoachCardTile extends StatelessWidget {
  const _CoachCardTile({required this.card});
  final _CoachCard card;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // 흰 둥근 카드 + 옅은 테두리·그림자, 왼쪽 옅은 파랑 알약 태그(#1831).
    return Container(
      padding: const EdgeInsets.all(OnCareSpacing.s16),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.xlAll,
        border: Border.fromBorderSide(
          BorderSide(color: OnCareColors.lineSubtle),
        ),
        boxShadow: OnCareShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 태그는 종류를 알려 줄 뿐 상태가 아니라, 카드마다 색을 달리
          // 하지 않고 시트의 다른 요소와 같은 메인 컬러로 둔다(#1375).
          AppTag(label: card.tag, tone: AppTagTone.brand),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  card.title,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  card.body,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
