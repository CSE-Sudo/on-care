import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// "AI 건강 도우미" bottom sheet — the daily coaching digest opened from the
/// floating Oni button and the Home coaching banner. Its CTA hands off to the
/// AI chat. Mirrors the Figma `CoachingSheet`.
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

/// 실제 제안을 받지 못했을 때 시트가 대신 그리는 기본 카드 수.
///
/// [_cardsOf] 의 길이와 같아야 한다 — 배지 숫자와 시트에 실제로 보이는 카드 수가
/// 어긋나면 배지가 다시 거짓말을 한다. 위젯 테스트가 두 값을 맞춰 둔다.
const int kCoachFallbackCardCount = 2;

/// 지금 코칭 시트가 보여 줄 카드 수. 배지와 시트가 같은 규칙을 읽는다.
final coachingSuggestionCountProvider = Provider<int>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) return kCoachFallbackCardCount;
  final List<AiSuggestion>? live = ref
      .watch(aiCoachStateProvider)
      .asData
      ?.value
      .suggestions;
  // 로딩·에러·빈 응답이면 시트가 기본 카드로 떨어지므로 수도 그것을 따른다.
  return (live == null || live.isEmpty) ? kCoachFallbackCardCount : live.length;
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

_CoachCard _cardFromSuggestion(AppLocalizations l, AiSuggestion s) => _CoachCard(
  tag: _suggestionTagLabel(l, s.tag),
  title: s.title,
  body: s.body,
);

class _CoachingSheet extends ConsumerWidget {
  const _CoachingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 데모/목 모드는 기존 하드코딩 카드를 유지(둘러보기 화면 동일). 실모드에서만
    // /ai-coach/feedback 의 실제 제안을 렌더하고, 로딩/에러/빈 응답은 기존 카드로 폴백.
    final List<_CoachCard> cards;
    if (ref.watch(appConfigProvider).useMockApi) {
      cards = _cardsOf(l);
    } else {
      final List<AiSuggestion>? live = ref
          .watch(aiCoachStateProvider)
          .asData
          ?.value
          .suggestions;
      cards = (live == null || live.isEmpty)
          ? _cardsOf(l)
          : live.map((AiSuggestion s) => _cardFromSuggestion(l, s)).toList();
    }

    // 폭 상한(콘텐츠 최대 폭)·높이 90%·핸들·닫기 X 는 [AppSheet] 와 테마가 정한다.
    return AppSheet(
      key: const Key('coachingSheet'),
      title: l.coachHeaderPill,
      subtitle: l.coachHeaderSubtitle,
      // 하단 여백·홈 인디케이터는 AppSheet 의 footer 가 맡는다 — 예전에는 여백
      // 0 이라 SafeArea 가 없는 기기에서 버튼이 시트 끝에 붙어 잘렸다(#1180).
      footer: KeyedSubtree(
        key: const Key('coachingSheetCta'),
        child: AppButton(
          label: l.coachCtaChat,
          leadingIcon: Icons.chat_bubble_outline_rounded,
          size: OnCareButtonSize.large,
          fullWidth: true,
          onPressed: () {
            Navigator.of(context).pop();
            context.push(AppRoutes.aiCoach);
          },
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: OniAvatar(),
          ),
          const SizedBox(height: OnCareSpacing.cardGap),
          for (final (int i, _CoachCard card) in cards.indexed) ...<Widget>[
            if (i > 0) const SizedBox(height: OnCareSpacing.cardGap),
            _CoachCardTile(card: card),
          ],
        ],
      ),
    );
  }
}

class _CoachCardTile extends StatelessWidget {
  const _CoachCardTile({required this.card});
  final _CoachCard card;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppTile(
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
