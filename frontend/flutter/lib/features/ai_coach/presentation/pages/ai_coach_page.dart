import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';
import 'package:oncare/features/ai_coach/presentation/widgets/insight_history_sheet.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
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

  Future<void> _send([String? preset]) async {
    final String text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    _controller.clear();
    _scrollToBottom();
    final ChatController chat = ref.read(chatControllerProvider.notifier);
    ChatSendResult result = await chat.send(text);
    if (!mounted) return;
    if (result.outcome == ChatSendOutcome.needsConsent) {
      // 포인트가 나가는 일은 보낼 때마다 묻는다(#2217) — 하루 한 번 동의로
      // 묶어 두면 그 뒤로는 무엇이 언제 나갔는지 모르고 쌓인다.
      if (!await _confirmPaidChat()) {
        _restoreInput(text);
        return;
      }
      result = await chat.send(text, payWithPoints: true);
      if (!mounted) return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    switch (result.outcome) {
      case ChatSendOutcome.sent:
        // 포인트로 보냈으면 MY 의 잔액도 바뀌었다.
        if (ref.read(chatControllerProvider).messages.lastOrNull?.pointsSpent
            case final int spent when spent > 0) {
          ref.invalidate(myHealthStateProvider);
        }
      case ChatSendOutcome.ignored:
        break;
      case ChatSendOutcome.needsConsent:
        _restoreInput(text);
      case ChatSendOutcome.dailyLimit:
        _restoreInput(text);
        showAppToast(context, l.aicQuotaExhausted);
      case ChatSendOutcome.insufficientPoints:
        _restoreInput(text);
        showAppToast(
          context,
          l.aicPaidInsufficient(l.myPointsCost(result.shortfall)),
          type: AppToastType.error,
        );
    }
  }

  /// 보내지 못한 글을 입력칸에 돌려놓는다 — 다시 쓰게 하지 않는다.
  void _restoreInput(String text) {
    if (_controller.text.isEmpty) _controller.text = text;
  }

  Future<bool> _confirmPaidChat() {
    final AppLocalizations l = AppLocalizations.of(context);
    final AiChatQuota? quota = ref.read(chatControllerProvider).quota;
    return showAppConfirmDialog(
      context: context,
      title: l.aicPaidConfirmTitle,
      // 얼마가 나가는지와 **지금 가진 것**을 함께 보여 준다(#2217).
      message: l.aicPaidConfirmMessage(
        l.myPointsCost(quota?.cost ?? 0),
        quota?.paidLimit ?? 0,
        l.myPointsCost(quota?.balance ?? 0),
      ),
      confirmLabel: l.aicPaidConfirmAction,
      cancelLabel: l.myCancel,
    );
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

    // 빠른 질문은 **마지막 말 아래**에 붙는다. 내 차례일 때만 띄워, 답을 기다리는
    // 동안 끼어들지 않는다(#1918).
    // 오늘 대화를 다 썼으면 눌러도 보낼 수 없으므로 띄우지 않는다(#2145).
    final bool showQuickReplies =
        !chat.sending &&
        chat.quota?.next != AiChatNext.exhausted &&
        chat.messages.isNotEmpty &&
        !chat.messages.last.isUser;
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
              ..._thread(context, chat.messages),
              if (showQuickReplies) _quickReplySection(),
            ],
          ),
        ),
        // 오늘 남은 대화(#2145) — 보내기 전에 얼마가 나갈지 먼저 보인다.
        if (chat.quota case final AiChatQuota quota) _QuotaLine(quota: quota),
        // 입력줄은 여러 줄 입력(줄바꿈)을 받으므로 키보드의 완료로는 보내지
        // 않는다 — 보내기는 전송 버튼 하나다.
        AppChatInputBar(
          controller: _controller,
          hint: l.aicInputHint,
          sendTooltip: l.a11ySendMessage,
          enabled:
              !chat.sending && chat.quota?.next != AiChatNext.exhausted,
          onSend: () => _send(),
        ),
      ],
    );
  }

  /// [showInsights] 가 거짓이면 참고 기록 버튼을 숨기되 자리는 남겨, 제목이
  /// 가운데에서 밀리지 않게 한다.
  ///
  /// **양쪽 폭을 맞춰 제목을 화면 가운데에 세운다**(#1975). 왼쪽 뒤로 버튼은
  /// 고정 폭이고 오른쪽 `참고 기록` 은 글자 길이만큼이라, 그대로 두면 가운데
  /// 정렬한 묶음이 왼쪽으로 밀린다 — 영어처럼 버튼이 길어지는 로케일에서 더
  /// 밀린다.
  ///
  /// 그래서 뒤로 버튼을 `기록` 과 같은 폭의 빈 자리 **위에 겹쳐** 둔다. 두 자리를
  /// 나란히 두면 좌우는 맞지만 제목이 쓸 폭이 그만큼 줄어 부제가 말줄임된다.
  /// 폭을 숫자로 적지 않고 같은 위젯을 숨겨 두는 것은, 로케일이 바뀌어도
  /// 저절로 따라가게 하기 위해서다.
  Widget _header(BuildContext context, {required bool showInsights}) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 오른쪽에 그릴 버튼과 왼쪽에 자리만 잡을 복제본. 키는 진짜 하나에만 둔다 —
    // 둘 다 달면 테스트가 어느 쪽을 누를지 가릴 수 없다.
    AppButton insightButton({Key? key}) => AppButton(
      key: key,
      label: l.aicInsightHistoryAction,
      size: OnCareButtonSize.small,
      leadingIcon: AppIcons.note,
      // 채움이던 동안에는 머리에서 대화보다 먼저 눈에 들었다(#1975).
      variant: AppButtonVariant.brandOutline,
      onPressed: () => _showInsightHistory(context),
    );
    return ColoredBox(
      color: OnCareColors.surfaceCard,
      child: Padding(
        // 다른 페이지 머리(`AppTopBar`)와 같은 가장자리 여백. s4 로는 오른쪽
        // 버튼이 화면 끝에 붙었다(#2216). 좌우가 같아야 아래 겹쳐 둔 복제본이
        // 제목을 가운데에 세운다(#1975).
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s8,
          vertical: OnCareSpacing.s8,
        ),
        child: Row(
          children: <Widget>[
            // 뒤로 버튼을 `참고 기록` 과 같은 폭의 자리 **위에** 겹쳐 둔다. 두
            // 자리를 나란히 두면 그만큼 제목이 쓸 폭이 줄어 부제가 말줄임된다.
            Stack(
              alignment: AlignmentDirectional.centerStart,
              children: <Widget>[
                Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IgnorePointer(
                    child: ExcludeSemantics(child: insightButton()),
                  ),
                ),
                AppBackButton(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.dashboard),
                ),
              ],
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
              child: insightButton(
                key: const Key('aiCoachInsightHistoryButton'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 대화 한 줄씩 — 날짜가 바뀌는 자리에 구분선을 끼운다. (#1918)
  ///
  /// 감지 기록 창에는 날짜가 있는데 대화에는 없어, 같은 일을 두 화면이 다르게
  /// 말하고 있었다. 트레이너 채팅과 같은 구분선을 쓴다.
  List<Widget> _thread(BuildContext context, List<ChatMessage> messages) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<Widget> out = <Widget>[];
    DateTime? shown;
    for (final ChatMessage m in messages) {
      final DateTime? at = m.at?.toLocal();
      if (at != null && (shown == null || !_sameDay(shown, at))) {
        shown = at;
        out
          ..add(
            AppChatDateDivider(
              l.coachChatDateDivider(at),
              key: ValueKey<String>(
                'aiCoachDate-${at.year}-${at.month}-${at.day}',
              ),
            ),
          )
          ..add(const SizedBox(height: OnCareSpacing.s8));
      }
      out
        ..add(_bubble(context, m))
        ..add(const SizedBox(height: OnCareSpacing.s16));
    }
    return out;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 말풍선 옆 시각(`18:13`). 주고받은 때를 모르는 말풍선(인사·실패 안내·기다리는
  /// 중)에는 붙이지 않는다.
  static String? _clock(ChatMessage m) {
    final DateTime? at = m.at?.toLocal();
    if (at == null || m.pending) return null;
    return '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
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
    final String? time = _clock(m);
    if (m.isUser) {
      final ChatInsight? insight = m.insight;
      if (insight == null) {
        return AppChatBubble(mine: true, time: time, child: Text(text));
      }
      // 트레이너 채팅처럼 감지한 신호를 말풍선 바로 아래 짧게 짚는다(#1824).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          AppChatBubble(mine: true, time: time, child: Text(text)),
          const SizedBox(height: OnCareSpacing.s4),
          AppTag(
            key: const Key('aiCoachInsightTag'),
            label: insightLabel(l, insight),
            // 통증·부정적 반응은 주의가 아니라 짚고 넘어갈 신호다(#1975).
            tone: AppTagTone.danger,
            // 머리의 `기록` 버튼과 같은 아이콘이다 — 그 버튼이 모아 보여 주는
            // 것이 바로 이 표시라는 것을 아이콘이 잇는다(#1918).
            icon: AppIcons.note,
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
                time: time,
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
              // 포인트로 산 답변이면 얼마가 나갔는지 바로 아래에 적는다(#2145).
              if (!m.pending && m.pointsSpent > 0)
                Padding(
                  padding: const EdgeInsets.only(
                    top: OnCareSpacing.s4,
                    left: OnCareSpacing.s4,
                  ),
                  child: Text(
                    // 남은 포인트는 여기 적지 않는다 — MY 에서 보는 값이고,
                    // 답변마다 따라다니면 대화보다 잔액이 먼저 읽힌다(#2217).
                    l.aicPointsSpent(l.myPointsCost(m.pointsSpent)),
                    key: const Key('aiCoachPointsSpent'),
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.caption),
                    ).copyWith(color: OnCareColors.textTertiary),
                  ),
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

  void _showInsightHistory(BuildContext context) =>
      showInsightHistorySheet(context, ref);
}

/// 입력칸 위의 오늘 남은 대화 한 줄. (#2145)
///
/// 무료가 남았으면 남은 횟수, 다 썼으면 다음 대화의 값과 오늘 산 수·잔액, 오늘 다
/// 썼으면 내일 다시 열린다는 안내와 트레이너 찾기다. 담당 트레이너와 연결하면 AI
/// 챗봇 대신 트레이너와 대화한다 — 한도가 곧 그 길의 입구다.
class _QuotaLine extends StatelessWidget {
  const _QuotaLine({required this.quota});

  final AiChatQuota quota;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle style = OnCareTypography.numeric(
      tokens.text(OnCareTypography.caption),
    ).copyWith(
      color: quota.short ? OnCareColors.danger : OnCareColors.textSecondary,
    );
    final String text = switch (quota.next) {
      AiChatNext.free => l.aicQuotaFreeLeft(quota.freeLeft),
      AiChatNext.paid => l.aicQuotaPaidNext(
        l.myPointsCost(quota.cost),
        quota.paidUsed,
        quota.paidLimit,
      ),
      AiChatNext.exhausted => l.aicQuotaExhausted,
    };
    return Padding(
      key: const Key('aiCoachQuotaLine'),
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s16,
        OnCareSpacing.s8,
        OnCareSpacing.s16,
        0,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: style)),
          if (quota.next == AiChatNext.exhausted)
            AppButton(
              key: const Key('aiCoachFindTrainer'),
              label: l.aicQuotaFindTrainer,
              size: OnCareButtonSize.small,
              variant: AppButtonVariant.brandOutline,
              onPressed: () => context.go(AppRoutes.exerciseGym),
            ),
        ],
      ),
    );
  }
}
