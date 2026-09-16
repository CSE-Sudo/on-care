import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 AI 챗봇 대화를 보관하는 기간(일). 서버 `HISTORY_RETENTION_DAYS` 와 같다(#1823).
const int kAiChatRetentionDays = 30;

/// The AI 코치 chat screen (#1702 규격). Opened from the coaching sheet's
/// "AI와 대화하기" CTA. Replies are served by [chatControllerProvider] (the
/// real coach repository, mock-RAG in demo mode), so questions get grounded
/// answers with source chips instead of a canned line.
class AICoachPage extends ConsumerStatefulWidget {
  const AICoachPage({super.key});

  @override
  ConsumerState<AICoachPage> createState() => _AICoachPageState();
}

List<String> _quickReplies(AppLocalizations l) => <String>[
  l.aicQuickReply1,
  l.aicQuickReply2,
  l.aicQuickReply3,
];

class _AICoachPageState extends ConsumerState<AICoachPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: OnCareMotion.normal,
          curve: OnCareMotion.curve,
        );
      }
    });
  }

  void _send([String? preset]) {
    final String text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatControllerProvider.notifier).send(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    // 담당 트레이너가 있는 회원은 AI 챗봇을 쓰지 않는다(#1823). 그 판단이 서기
    // 전에는 대화를 불러오지도 않는다 — 실서버는 이 회원의 대화 조회를 거절한다.
    // 조회에 실패하면 담당 여부를 모르므로 대화를 열어 두고, 판단은 서버에 맡긴다.
    final AsyncValue<MemberCoach?> coachAsync = ref.watch(memberCoachProvider);
    final MemberCoach? coach = coachAsync.valueOrNull;
    if (coach != null) {
      return _frame(
        context,
        showInsights: false,
        children: <Widget>[Expanded(child: _trainerConnected(context, coach))],
      );
    }
    if (!coachAsync.hasValue && !coachAsync.hasError) {
      return _frame(
        context,
        showInsights: false,
        children: const <Widget>[Expanded(child: AppLoading())],
      );
    }
    return _chat(context);
  }

  /// 머리·구분선 아래에 [children] 을 쌓는 화면 틀. 대화·트레이너 안내·로딩이
  /// 같은 틀을 쓴다.
  Widget _frame(
    BuildContext context, {
    required bool showInsights,
    required List<Widget> children,
  }) {
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: Column(
              children: <Widget>[
                _header(context, showInsights: showInsights),
                const AppDivider(),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 담당 트레이너가 있는 회원이 이 화면에 들어왔을 때 — 대화 대신 트레이너
  /// 채팅으로 안내한다(#1823).
  Widget _trainerConnected(BuildContext context, MemberCoach coach) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppEmptyState(
      key: const Key('aiCoachTrainerConnected'),
      icon: AppIcons.chat,
      title: l.aicTrainerConnectedTitle,
      message: l.aicTrainerConnectedBody(coach.name),
      actionLabel: l.coachChatWithTrainer,
      onAction: () => openTrainerChatPage(context, trainerName: coach.name),
    );
  }

  Widget _chat(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ChatState chat = ref.watch(chatControllerProvider);
    // Auto-scroll whenever the conversation grows / the typing bubble toggles.
    ref.listen<ChatState>(chatControllerProvider, (_, _) => _scrollToBottom());

    // The starter prompts only make sense before the user has said anything.
    final bool showQuickReplies =
        !chat.messages.any((ChatMessage m) => m.isUser) && !chat.sending;
    final TextStyle captionStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);

    return _frame(
      context,
      showInsights: true,
      children: <Widget>[
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(
              OnCareSpacing.s16,
              OnCareSpacing.s24,
              OnCareSpacing.s16,
              OnCareSpacing.s16,
            ),
            children: <Widget>[
              Center(child: AppTag(label: l.aicDatePillToday)),
              const SizedBox(height: OnCareSpacing.s12),
              // 의료 조언 면책 — 코치는 식단·운동 코칭이지 진료가 아니다.
              // 시스템 프롬프트에도 진단 금지 지시가 있지만, 사용자가
              // 그걸 볼 수는 없으므로 화면에도 한 줄 남긴다.
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OnCareSpacing.s24,
                  ),
                  child: Text(
                    l.aicMedicalDisclaimer,
                    textAlign: TextAlign.center,
                    style: captionStyle,
                  ),
                ),
              ),
              const SizedBox(height: OnCareSpacing.s4),
              // 대화는 한 달만 남는다(#1823). 지난 대화가 사라진 것을 고장으로
              // 읽지 않게 미리 말해 둔다.
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OnCareSpacing.s24,
                  ),
                  child: Text(
                    l.aicRetentionNotice(kAiChatRetentionDays),
                    key: const Key('aiCoachRetentionNotice'),
                    textAlign: TextAlign.center,
                    style: captionStyle,
                  ),
                ),
              ),
              const SizedBox(height: OnCareSpacing.s20),
              for (final ChatMessage m in chat.messages) ...<Widget>[
                _bubble(context, m),
                const SizedBox(height: OnCareSpacing.s16),
              ],
              if (showQuickReplies) _quickReplySection(),
            ],
          ),
        ),
        // 입력줄은 여러 줄 입력(줄바꿈)을 받으므로 키보드의 완료로는 보내지
        // 않는다 — 보내기는 전송 버튼 하나다.
        AppChatInputBar(
          controller: _controller,
          hint: l.aicInputHint,
          sendTooltip: l.a11ySendMessage,
          enabled: !chat.sending,
          onSend: () => _send(),
        ),
      ],
    );
  }

  /// [showInsights] 가 거짓이면 감지 기록 버튼을 숨기되 자리는 남겨, 제목이
  /// 가운데에서 밀리지 않게 한다.
  Widget _header(BuildContext context, {required bool showInsights}) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return ColoredBox(
      color: OnCareColors.surfaceCard,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s4,
          vertical: OnCareSpacing.s8,
        ),
        child: Row(
          children: <Widget>[
            AppBackButton(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go(AppRoutes.dashboard),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // 초록 `지금 연결됨` 점은 두지 않는다(#1823) — 트레이너 온라인
                  // 점과 같은 모양이라 AI 가 사람처럼 접속해 있다는 뜻으로 읽혔다.
                  const OniAvatar(),
                  const SizedBox(width: OnCareSpacing.s8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          l.pageAiCoachTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens
                              .text(OnCareTypography.titleSmall)
                              .copyWith(color: OnCareColors.textPrimary),
                        ),
                        Text(
                          l.aicHeaderSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens
                              .text(OnCareTypography.bodySmall)
                              .copyWith(color: tokens.brand.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 최근 30일 대화에서 감지한 통증·부정적 반응을 모아 보는 자리(#1824).
            // 트레이너 채팅의 감지와 같은 규칙이다.
            // 트레이너 안내·로딩 화면에서는 기록이 없으므로 자리만 남긴다(#1823).
            Visibility(
              visible: showInsights,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              // 아이콘만으로는 전할 수 없는 기능이라 글자를 함께 쓴다(#1900).
              // 예전의 심전도 모니터는 심박을 재는 자리로 읽혔다.
              child: AppButton(
                key: const Key('aiCoachInsightHistoryButton'),
                label: l.aicInsightHistoryAction,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
                leadingIcon: AppIcons.note,
                onPressed: () => _showInsightHistory(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m) {
    // 앱이 스스로 띄운 말풍선(인사·실패 안내)은 문구가 비어 있다. 로케일에 맞춰
    // 여기서 그린다 — 컨트롤러는 어떤 말풍선인지만 정한다(#847).
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String text = switch (m.notice) {
      ChatNotice.welcome => l.aiCoachWelcome,
      ChatNotice.failure => l.aiCoachFailure,
      null => m.content,
    };
    if (m.isUser) {
      final ChatInsight? insight = m.insight;
      if (insight == null) {
        return AppChatBubble(mine: true, child: Text(text));
      }
      // 트레이너 채팅처럼 감지한 신호를 말풍선 바로 아래 짧게 짚는다(#1824).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          AppChatBubble(mine: true, child: Text(text)),
          const SizedBox(height: OnCareSpacing.s4),
          AppTag(
            key: const Key('aiCoachInsightTag'),
            label: insightLabel(l, insight),
            tone: AppTagTone.caution,
            icon: AppIcons.healthCheck,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        const OniAvatar(size: OnCareSize.avatarMedium),
        const SizedBox(width: OnCareSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppChatBubble(
                mine: false,
                child: m.pending
                    // 점 세 개만 깜빡이면 무엇을 기다리는지 알 수 없다. 답이
                    // 그 사람의 기록을 읽고 만들어지는 중이라는 것을 한 줄로
                    // 말해 준다(#1180).
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const AppTypingIndicator(),
                          const SizedBox(width: OnCareSpacing.s8),
                          Flexible(
                            child: Text(
                              l.aicGeneratingReply,
                              style: tokens
                                  .text(OnCareTypography.bodySmall)
                                  .copyWith(color: OnCareColors.textSecondary),
                            ),
                          ),
                        ],
                      )
                    : Text(text),
              ),
              if (!m.pending && m.sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    top: OnCareSpacing.s8,
                    left: OnCareSpacing.s4,
                  ),
                  child: _sourceChips(m.sources),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceChips(List<String> sources) {
    return Wrap(
      spacing: OnCareSpacing.s4,
      runSpacing: OnCareSpacing.s4,
      children: <Widget>[
        for (final String s in sources)
          // 출처 제목이 줄 폭보다 길면 태그가 넘치지 않고 줄 폭에 맞춰 줄어든다.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AppTag(
              label: s,
              tone: AppTagTone.brand,
              icon: AppIcons.guide,
            ),
          ),
      ],
    );
  }

  Widget _quickReplySection() {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: OnCareSpacing.s4,
            bottom: OnCareSpacing.s12,
          ),
          child: Text(
            l.aicQuickRepliesLabel,
            style: context.oncare
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ),
        for (final String q in _quickReplies(l)) ...<Widget>[
          AppButton(
            label: q,
            onPressed: () => _send(q),
            variant: AppButtonVariant.secondary,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
        ],
      ],
    );
  }

  void _showInsightHistory(BuildContext context) {
    ref.invalidate(aiCoachInsightsProvider);
    showAppSheet<void>(
      context: context,
      builder: (BuildContext _) => const _InsightHistorySheet(),
    );
  }
}

/// 감지 한 줄의 이름 — `무릎 통증 감지` / `통증 감지` / `부정적 반응 감지`.
String insightLabel(AppLocalizations l, ChatInsight insight) =>
    switch (insight.kind) {
      ChatInsightKind.discomfort => switch (insight.bodyPart) {
        final String part => l.aicInsightDiscomfortPart(part),
        null => l.aicInsightDiscomfort,
      },
      ChatInsightKind.negativeFeedback => l.aicInsightNegative,
    };

/// 최근 30일 감지 기록 창(#1824).
class _InsightHistorySheet extends ConsumerWidget {
  const _InsightHistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AsyncValue<ChatInsightHistory> history = ref.watch(
      aiCoachInsightsProvider,
    );
    final int days = history.valueOrNull?.windowDays ?? kChatInsightWindowDays;
    return AppSheet(
      key: const Key('aiCoachInsightHistorySheet'),
      title: l.aicInsightHistoryTitle,
      subtitle: l.aicInsightHistorySubtitle(days),
      child: history.when(
        loading: () => const AppLoading(),
        error: (_, _) => Text(
          l.aicInsightHistoryFailed,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        data: (ChatInsightHistory value) => value.records.isEmpty
            ? Text(
                l.aicInsightHistoryEmpty(value.windowDays),
                key: const Key('aiCoachInsightHistoryEmpty'),
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (int i, ChatInsightRecord record)
                      in value.records.indexed) ...<Widget>[
                    if (i > 0) const AppDivider(),
                    _InsightRow(record: record),
                  ],
                ],
              ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.record});

  final ChatInsightRecord record;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String date = DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(record.createdAt);
    return Padding(
      key: ValueKey<String>('aiCoachInsightRow-${record.messageId}'),
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(
                label: insightLabel(l, record.insight),
                tone: AppTagTone.caution,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Text(
                date,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            record.text,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
