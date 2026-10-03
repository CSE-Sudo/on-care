import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_report/oncare_report.dart' show PdfPagesView;
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/data/repositories/chat_pdf_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/features/clients/presentation/controllers/chat_scroll.dart';
import 'package:oncare_trainer/features/clients/presentation/controllers/chat_thread_history.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_image_attachment.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/trainer_emote_sheet.dart';
import 'package:oncare_trainer/features/messages/domain/chat_context_insight.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// PDF 미리보기 창에서 문서가 차지하는 높이. 한 쪽을 줄이지 않고 읽을 수 있는
/// 크기다 — 창이 화면보다 낮으면 창 본문이 스크롤된다.
const double _pdfPreviewHeight = 640;

/// The 채팅 sub-tab: an AI-received system banner, the message thread
/// (trainer right / client left), and an input bar that appends a
/// trainer message to the local DB.
class ChatView extends ConsumerStatefulWidget {
  /// Creates the chat view for [clientId].
  const ChatView({
    super.key,
    required this.clientId,
    required this.clientAvatar,
    required this.clientName,
  });

  /// Client whose thread is shown.
  final String clientId;

  /// Single-char avatar label for client bubbles.
  final String clientAvatar;

  /// Client display name (used in the system banner).
  final String clientName;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Mirrors the backend's `ChatSendRequest.text` cap (`TEXT_LONG_MAX`)
  /// so an over-long message is rejected here, with a clear message,
  /// instead of round-tripping to the server for a 422 (review).
  static const int _maxMessageLength = AppTextLimits.long;

  /// A send is in flight — blocks re-entry (button mash / IME send)
  /// from inserting the same message twice.
  bool _sending = false;

  /// Insight ids whose memo save is in flight. A memo write is a network
  /// round trip in API mode, so a second tap before it lands would fire a
  /// duplicate request.
  final Set<String> _savingInsights = <String>{};

  /// 마지막으로 스크롤을 맞춘 대화의 양 끝. 끝이 바뀐 프레임에서만
  /// 스크롤한다 — 뒤가 바뀌면 맨 아래로, 앞만 바뀌면(이전 쪽이 붙으면) 보던
  /// 자리를 지킨다(#2749).
  ChatEdges? _lastEdges;

  /// 메시지 id → 자리 표시. 지금 가장 오래된 메시지 하나와, 이전 쪽이 붙은 뒤
  /// 되돌리는 중인 메시지 하나만 들고 있다.
  final Map<String, GlobalKey> _anchorKeys = <String, GlobalKey>{};

  /// 되돌리는 중인 메시지 id — 끝나면 null.
  String? _restoringAnchorId;

  /// 지금 그린 대화의 가장 오래된 메시지 — 이전 쪽을 받을 커서다.
  ClientChatMessage? _oldestShown;

  /// 지금 그린 대화에 받을 이전 쪽이 남아 있는가.
  bool _canLoadOlder = false;

  /// 맨 위에서 이만큼 안쪽에 닿으면 이전 쪽을 받는다. 화면 크기가 아니라
  /// "거의 끝까지 올렸다" 를 가르는 기준이다.
  static const double _loadOlderEdge = 80;

  static const ChatContextInsightDetector _insightDetector =
      ChatContextInsightDetector();

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _input.dispose();
    super.dispose();
  }

  set _anchorKeyId(String? oldestId) {
    _anchorKeys.removeWhere(
      (String id, GlobalKey _) => id != oldestId && id != _restoringAnchorId,
    );
    if (oldestId != null) {
      _anchorKeys.putIfAbsent(
        oldestId,
        () => GlobalKey(debugLabel: 'trainer-chat-anchor'),
      );
    }
  }

  /// 위로 끝까지 올리면 이전 쪽을 받는다. (#2749)
  ///
  /// 사용자가 올리는 중일 때만 본다 — 대화를 열며 맨 아래로 내리는 애니메이션도
  /// 맨 위에서 출발하므로, 방향을 보지 않으면 열자마자 이전 쪽을 받는다.
  void _onScroll() {
    if (!_canLoadOlder || !_scroll.hasClients) return;
    // 방금 붙은 쪽의 자리를 되돌리는 중이다. 그 사이 남은 관성 스크롤이 맨 위에
    // 머물러 있어도 다음 쪽을 연달아 받지 않는다.
    if (_restoringAnchorId != null) return;
    final ScrollPosition position = _scroll.position;
    if (position.userScrollDirection != ScrollDirection.forward) return;
    if (position.pixels > position.minScrollExtent + _loadOlderEdge) return;
    _loadOlder();
  }

  /// 지금 가장 오래된 메시지 앞의 한 쪽을 받는다. 받는 중이거나 처음 메시지까지
  /// 받았으면 [ChatThreadHistory.loadOlder] 가 아무것도 하지 않는다.
  void _loadOlder() {
    final ClientChatMessage? oldest = _oldestShown;
    if (oldest == null) return;
    ref
        .read(chatThreadHistoryProvider(widget.clientId).notifier)
        .loadOlder(oldest);
  }

  /// 이모티콘 창을 열고, 고른 것을 그 자리에서 보낸다. (#2020)
  ///
  /// 고르면 바로 보낸다 — 이모티콘은 한 번의 반응이라, 고른 뒤 전송을 다시 누르게
  /// 하면 글보다 느려진다. 회원 앱의 고르는 창과 같은 흐름이다.
  Future<void> _sendEmote() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String? picked = await showTrainerEmoteSheet(context);
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendTrainerMessage(
            clientId: widget.clientId,
            text: '',
            emoteId: picked,
          );
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, l.chatSendFailed, type: AppToastType.error);
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    // 데모(drift)는 쓰기에 스트림이 다시 흐른다. 실서버는 한 번 읽어 오는 경로라
    // 보낸 뒤 다시 받아야 방금 보낸 것이 보인다 — 글 전송과 같다.
    if (!ref.read(appConfigProvider).useMockApi) {
      ref.invalidate(chatThreadProvider(widget.clientId));
      ref.invalidate(unreadCountsProvider);
      _refreshRosterAfterSend();
    }
  }

  /// 보낸 뒤 로스터를 한 번 다시 읽는다 — 메시지 탭 목록은 로스터의
  /// `last_message_at` 으로 최신순을 정하므로, 다음 폴링(30초)까지 기다리면
  /// 방금 대화한 회원이 제자리에 남는다(#3011).
  void _refreshRosterAfterSend() {
    final ClientRepository repository = ref.read(clientRepositoryProvider);
    if (repository case final ClientDataRefresher refresher) {
      refresher.refreshClientData(widget.clientId);
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final AppLocalizations l = AppLocalizations.of(context);
    if (text.trim().length > _maxMessageLength) {
      showAppToast(context, l.chatTooLong);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendTrainerMessage(clientId: widget.clientId, text: text);
    } catch (_) {
      // Guard the failure path too: a slow send that fails after the
      // user left would otherwise touch a disposed context.
      if (!mounted) return;
      // Keep the draft in the input and tell the user it didn't go out.
      showAppToast(context, l.chatSendFailed, type: AppToastType.error);
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    // The insert may outlive this widget (user navigated away while
    // awaiting) — don't touch disposed controllers.
    if (!mounted) return;
    // Clear only after the insert succeeds so the text isn't lost on error.
    _input.clear();
    // Drift streams re-emit on write; the Dio source is a single fetch, so
    // refetch the thread + unread badges after a real-API send. NOTE: don't
    // scroll here — `ref.invalidate` only *starts* an async refetch, so the
    // list the user is looking at right now is still the pre-send one; the
    // `data:` branch below already scrolls to bottom once the new message
    // actually renders (it fires on every list-length change, which covers
    // both the reactive Drift path and this refetch) (review).
    if (!ref.read(appConfigProvider).useMockApi) {
      ref.invalidate(chatThreadProvider(widget.clientId));
      ref.invalidate(unreadCountsProvider);
      _refreshRosterAfterSend();
    }
  }

  /// 사진 한 장을 고르고 그대로 보낸다. (#921)
  ///
  /// 고른 뒤 미리보기를 한 번 더 거치지 않는 이유는, 자세 사진은 대화 흐름
  /// 안에서 즉시 오가는 것이라서다 — 확인 단계를 넣으면 말 한마디 붙이는 것보다
  /// 사진 한 장 보내는 쪽이 번거로워진다. 잘못 보낸 사진은 대화에서 바로 보인다.
  ///
  /// 데모에서는 서버 대신 로컬 대화에 바이트째 붙는다 — 회원앱 데모에서 사진을
  /// 보낼 수 있는데 트레이너만 못 보내면, 두 앱을 나란히 볼 때 한쪽만 되는
  /// 기능으로 읽힌다. (#2493)
  Future<void> _sendImage() async {
    if (_sending) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      // 원본 그대로는 상한(6MiB)에 쉽게 닿는다. 자세를 보는 데 필요한 해상도는
      // 남기면서 전송이 실패하지 않을 정도로 줄인다.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    // 함께 붙이는 한마디도 본문과 같은 상한을 지킨다 — 서버가 422 로 거절하면
    // 사진까지 다시 골라야 한다.
    final caption = _input.text.trim();
    if (caption.length > _maxMessageLength) {
      if (!mounted) return;
      showAppToast(context, l.chatTooLong);
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(trainerChatImageRepositoryProvider)
          .send(
            clientId: widget.clientId,
            bytes: bytes,
            fileName: picked.name,
            message: caption,
          );
    } on AppError catch (error) {
      if (!mounted) return;
      // 용량·형식 거절은 서버가 이유를 문장으로 준다. 그 문장이 트레이너가
      // 다음에 할 일(줄여서 다시 보낼지)을 정한다.
      showAppToast(
        context,
        serverDetailOr(l, error.message, l.chatImageSendFailed),
        type: AppToastType.error,
      );
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    _input.clear();
    ref.invalidate(chatThreadProvider(widget.clientId));
    ref.invalidate(unreadCountsProvider);
  }

  /// 스레드를 날짜 구분선과 함께 그린다.
  ///
  /// 데모에만 날이 바뀔 때마다 `AI 가 분석했어요`·`루틴 전송됨` 배너를 끼우던
  /// 것은 지웠다(#2672) — 실제로 일어난 일과 상관없이 대화가 있는 날마다 붙어,
  /// 루틴을 보내지 않은 날에도 보냈다고 말했다. 이제 운동을 **실제로 보낸**
  /// 자리에 서버(데모는 로컬)가 남긴 전송 안내 카드가 선다.
  List<Widget> _threadChildren(
    List<ClientChatMessage> list, {
    required Set<String> savedInsightIds,
  }) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      final ClientChatMessage m = list[i];
      final bool newDay =
          i == 0 || !_sameDay(list[i - 1].createdAt, m.createdAt);
      if (newDay) {
        // 구분선은 위아래 여백을 스스로 갖는다.
        //
        // 날짜는 KST 로 정한다(#2751). 말풍선 시각은 서버가 KST 로 적어 준
        // 라벨이라, 구분선만 `toLocal()`(브라우저 시간대)로 정하면 UTC 브라우저에서
        // KST 아침 메시지가 전날 구분선 아래 "08:10" 으로 놓인다.
        final DateTime day = kstDateOf(m.createdAt);
        out.add(
          AppChatDateDivider(
            AppLocalizations.of(context).chatDateDivider(day),
            key: ValueKey<String>(
              'trainer-chat-date-${day.year}-${day.month}-${day.day}',
            ),
          ),
        );
      }
      // 리포트 전송은 말풍선이 아니라 **가운데 안내**다. 누가 무슨 말을 했는가가
      // 아니라 스레드에 무슨 일이 있었는가를 적는 자리라, 같은 흐름의 다른
      // 안내("개인 추천운동이 …")와 같은 모양으로 가운데에 둔다(#1600).
      final DateTime? reportWeek = m.reportWeekStart;
      final RoutineDeliveryNotice? delivery = m.routineDelivery;
      final Widget item = delivery != null
          // 운동을 보낸 일도 같은 가운데 안내다(#2672).
          ? RoutineDeliveryCard(
              key: ValueKey<String>('trainer-routine-delivery-${m.id}'),
              notice: delivery,
            )
          : reportWeek == null
          ? _Bubble(message: m, avatar: widget.clientAvatar)
          : ReportRegisteredCard(
              key: ValueKey<String>('trainer-message-bubble-${m.id}'),
              weekStart: reportWeek,
              onOpen: () => context.go(
                AppRoutes.reportFor(widget.clientId, weekStart: reportWeek),
              ),
            );
      // 가장 오래된 메시지에는 자리 표시를 단다 — 이전 쪽이 그 앞에 붙은 뒤 이
      // 메시지를 같은 자리로 되돌리는 기준이다(#2749).
      final GlobalKey? anchor = _anchorKeys[m.id];
      out
        ..add(anchor == null ? item : KeyedSubtree(key: anchor, child: item))
        ..add(const SizedBox(height: OnCareSpacing.s12));
      final insight = _insightDetector.detect(m);
      if (insight != null) {
        out
          ..add(
            _ChatInsightBanner(
              key: ValueKey<String>('chat-insight-${insight.id}'),
              insight: insight,
              saved: savedInsightIds.contains(insight.id),
              onAddMemo: () => _addInsightMemo(insight),
            ),
          )
          ..add(const SizedBox(height: OnCareSpacing.s12));
      }
    }
    return out;
  }

  /// Saves a detected signal as a trainer memo on this client.
  ///
  /// The memo lands in the same list the client detail screen shows, and the
  /// insight id makes the write idempotent — a double tap or a retry after a
  /// dropped response does not add a second memo.
  Future<void> _addInsightMemo(ChatContextInsight insight) async {
    if (!_savingInsights.add(insight.id)) return;
    // 원문이 아니라 감지 요약을 남긴다 — 프로그램 탭이 이 메모를 그대로
    // 읽으므로([chatInsightMemoSummary]), 그날의 말투가 아니라 조치할 내용이
    // 남아야 한다 (#1655).
    final String body = chatInsightMemoSummary(
      AppLocalizations.of(context),
      insight,
    );
    try {
      await ref
          .read(trainerMemoRepositoryProvider)
          .create(
            widget.clientId,
            body: body,
            source: TrainerMemoSource.chatInsight,
            insightId: insight.id,
            insightKind: insight.kind.name,
          );
      ref.invalidate(trainerMemosProvider(widget.clientId));
      if (!mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(context).chatInsightMemoSaved,
        type: AppToastType.success,
      );
    } on Object {
      // The button stays in its unsaved state so the trainer can try again —
      // the list is only invalidated on a write that actually landed.
      if (!mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(context).chatInsightMemoSaveFailed,
        type: AppToastType.error,
      );
    } finally {
      _savingInsights.remove(insight.id);
    }
  }

  /// 같은 날인가 — KST 기준(#2751). 브라우저 시간대로 가르면 구분선이 말풍선
  /// 시각(서버 KST 라벨)과 다른 날을 가리킨다.
  static bool _sameDay(DateTime a, DateTime b) => isSameKstDay(a, b);

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: OnCareMotion.normal,
        curve: OnCareMotion.curve,
      );
    });
  }

  /// 이전 쪽이 [anchorId] 앞에 붙은 뒤에도 그 메시지를 **보던 자리에** 둔다.
  /// (#2749)
  ///
  /// 붙이기 전 그 메시지의 화면 위치를 잡아 두고, 붙인 뒤 같은 위치로 스크롤을
  /// 옮긴다. 이전 쪽이 길면 붙인 직후 그 메시지가 아직 만들어지지 않았을 수
  /// 있다(ListView 는 보이는 근처만 만든다). 그때는 먼저 목록 끝에서의 거리로
  /// 가까이 옮기고, 다음 프레임에 만들어진 메시지로 정확히 맞춘다.
  void _keepPositionAfterPrepend(String anchorId) {
    final double? anchorTop = _globalTopOf(anchorId);
    final double? fromBottom = _scroll.hasClients
        ? _scroll.position.maxScrollExtent - _scroll.position.pixels
        : null;
    if (anchorTop == null && fromBottom == null) return;
    _restoringAnchorId = anchorId;
    _anchorKeys.putIfAbsent(
      anchorId,
      () => GlobalKey(debugLabel: 'trainer-chat-anchor'),
    );
    void settle(int attemptsLeft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final ScrollPosition position = _scroll.position;
        final double? top = _globalTopOf(anchorId);
        final double target;
        if (top != null && anchorTop != null) {
          target = position.pixels + (top - anchorTop);
        } else if (fromBottom != null) {
          target = position.maxScrollExtent - fromBottom;
        } else {
          _restoringAnchorId = null;
          return;
        }
        final double clamped = target.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        final bool done =
            (clamped - position.pixels).abs() < 0.5 &&
            (top != null || anchorTop == null);
        if (done || attemptsLeft <= 1) {
          if (!done) position.jumpTo(clamped);
          _restoringAnchorId = null;
          return;
        }
        position.jumpTo(clamped);
        WidgetsBinding.instance.scheduleFrame();
        settle(attemptsLeft - 1);
      });
    }

    settle(12);
  }

  /// [id] 메시지의 화면 위 끝(전역 좌표). 아직 만들어지지 않았으면 null.
  double? _globalTopOf(String id) {
    final RenderObject? box = _anchorKeys[id]?.currentContext
        ?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy;
  }

  /// 대화 맨 위의 이전 쪽 자리 — 더 보기 버튼, 받는 중이면 같은 버튼의 스피너,
  /// 실패했으면 다시 시도. 위로 끝까지 올려도 같은 일이 일어나지만, 대화가
  /// 화면보다 짧아 올릴 수 없을 때도 받을 수 있게 버튼을 둔다(#2749).
  ///
  /// 받는 동안에도 같은 버튼을 둔다 — 스피너로 바꿔 끼우면 그 높이 차이만큼
  /// 아래 메시지가 들썩인다.
  Widget _olderSlot(AppLocalizations l, ChatThreadHistoryState history) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s12),
      child: Center(
        child: AppButton(
          key: ValueKey<String>(
            history.failed
                ? 'trainer-chat-older-retry'
                : 'trainer-chat-load-older',
          ),
          label: history.failed ? l.chatLoadOlderFailed : l.chatLoadOlder,
          variant: AppButtonVariant.text,
          size: OnCareButtonSize.small,
          loading: history.loading,
          onPressed: _loadOlder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final messages = ref.watch(chatThreadProvider(widget.clientId));
    final ChatThreadHistoryState history = ref.watch(
      chatThreadHistoryProvider(widget.clientId),
    );
    final savedInsightIds =
        ref
            .watch(trainerMemosProvider(widget.clientId))
            .valueOrNull
            ?.map((memo) => memo.insightId)
            .whereType<String>()
            .toSet() ??
        const <String>{};

    return Column(
      children: <Widget>[
        Expanded(
          child: messages.when(
            loading: () => const AppLoading(),
            error: (e, _) => AppErrorState(
              // 다시 시도 버튼은 이 상태 안의 [AppButton] 이다.
              key: ValueKey<String>('chat-retry-${widget.clientId}'),
              title: l.chatLoadFailed,
              retryLabel: l.actionRetry,
              onRetry: messages.isLoading
                  ? null
                  : () => ref.invalidate(chatThreadProvider(widget.clientId)),
            ),
            data: (latest) {
              // 폴링한 최신 쪽에 위로 올려 받은 이전 쪽을 합친다(#2749). 같은
              // 메시지가 양쪽에 있으면 id 로 하나만 남는다.
              final List<ClientChatMessage> list = visibleChatThread(
                history,
                latest,
              );
              _oldestShown = list.firstOrNull;
              _canLoadOlder =
                  list.isNotEmpty && canLoadOlderChat(history, latest);
              final ChatEdges edges = ChatEdges(
                oldestId: list.firstOrNull?.id,
                newestId: list.lastOrNull?.id,
                count: list.length,
              );
              // 무엇이 바뀐 프레임인지 보고 스크롤한다 — 매 빌드마다 부르면
              // 위로 올려 읽는 중에도 아래로 끌어내린다. 이전 쪽이 앞에 붙은
              // 때는 보던 자리를 지킨다.
              final ChatEdges? previous = _lastEdges;
              final ChatScrollAction action = chatScrollAction(previous, edges);
              if (action != ChatScrollAction.none) _lastEdges = edges;
              if (action == ChatScrollAction.keepPosition &&
                  previous?.oldestId != null) {
                _keepPositionAfterPrepend(previous!.oldestId!);
              }
              _anchorKeyId = edges.oldestId;
              // Auto-scroll only when a message arrived, not every build.
              if (action == ChatScrollAction.toBottom) {
                _scrollToBottom();
                // Viewing the thread clears its unread badge — also for
                // messages that arrive while it stays open. Deferred so
                // the write never runs inside build.
                final repo = ref.read(chatRepositoryProvider);
                final realApi = !ref.read(appConfigProvider).useMockApi;
                Future<void>.microtask(() async {
                  try {
                    await repo.markThreadRead(widget.clientId);
                    // Drift updates unread via its stream; the Dio source
                    // needs an explicit refetch of the badge counts. The
                    // server also marks this member's message notifications
                    // read (#2291), so the inbox and its badge refetch too.
                    if (realApi && mounted) {
                      ref
                        ..invalidate(unreadCountsProvider)
                        ..invalidate(trainerNotificationsProvider)
                        ..invalidate(trainerUnreadNotificationsProvider);
                    }
                  } catch (_) {
                    // Reading the thread still succeeded. A transient read
                    // receipt failure may leave the badge visible, but must
                    // not escape as an unhandled async error.
                  }
                });
              }
              return ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(OnCareSpacing.s16),
                children: <Widget>[
                  if (_canLoadOlder) _olderSlot(l, history),
                  ..._threadChildren(list, savedInsightIds: savedInsightIds),
                ],
              );
            },
          ),
        ),
        _InputBar(
          controller: _input,
          sending: _sending,
          onSend: _send,
          onAttachImage: _sendImage,
          onEmote: _sendEmote,
        ),
      ],
    );
  }
}

/// 대화에서 감지한 불편·부정 신호. (#1655)
///
/// 대화 폭을 다 쓰는 흰 카드에 옅은 빨간 테두리 — 가운데 안내(분석했어요·
/// 전송됐어요)와 달리 트레이너가 **읽고 조치할** 자리라 폭을 다 쓴다.
///
/// 메모로 남긴 뒤에도 카드의 빨간색은 그대로다 — 무슨 일이 있었는지(부정적
/// 피드백)는 바뀌지 않았고, 그 사실까지 지우면 나중에 훑을 때 이 자리가
/// 무엇이었는지 알아볼 수 없다. 처리 여부는 오른쪽 알약의 아이콘(＋ → ✓)과
/// 문구(메모 추가 → 메모 추가됨)가 말한다.
class _ChatInsightBanner extends StatelessWidget {
  const _ChatInsightBanner({
    required this.insight,
    required this.saved,
    required this.onAddMemo,
    super.key,
  });

  final ChatContextInsight insight;
  final bool saved;
  final Future<void> Function() onAddMemo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isDiscomfort = insight.kind == ChatInsightKind.discomfort;
    final title = isDiscomfort
        ? l.chatInsightDiscomfortTitle(chatInsightBodyPartLabel(l, insight))
        : l.chatInsightNegativeTitle;
    final description = isDiscomfort
        ? l.chatInsightDiscomfortDescription
        : l.chatInsightNegativeDescription;

    // AI 루틴의 감지 메모 칸과 같은 감지 경고 모양이다(#2468) — 같은 신호가
    // 두 화면에서 같은 것으로 읽힌다.
    return SizedBox(
      width: double.infinity,
      child: AppBanner(
        key: ValueKey<String>('chat-insight-banner-${insight.messageId}'),
        tone: AppBannerTone.danger,
        density: AppBannerDensity.compact,
        icon: AppIcons.warning,
        title: title,
        message: description,
        // 메모로 옮겨 적으면 바탕만 하얗게 비우고 붉은 테두리는 남긴다 —
        // 무슨 일이 있었는지는 그대로이고, 처리 여부만 바탕색이 가른다.
        resolved: saved,
        // 알약은 저장 뒤에도 빨간색이다. 초록으로 뒤집으면 빨간 카드
        // 한가운데서 가장 밝은 것이 "메모 추가됨" 이 되어, 정작 읽어야 할
        // 감지 내용보다 눈에 먼저 들어온다. 배너 채움(8%) 위에서 알약이
        // 보이도록 한 단계 진하게(16%) 칠한다.
        trailing: AppTag(
          key: ValueKey<String>('chat-insight-add-${insight.id}'),
          label: saved ? l.chatInsightMemoAdded : l.chatInsightAddMemo,
          tone: AppTagTone.danger,
          icon: saved ? AppIcons.check : AppIcons.add,
          onTint: true,
          onTap: saved ? null : onAddMemo,
        ),
      ),
    );
  }
}

/// 스레드 가운데에 서는 작은 안내 상자 — 아이콘 + 굵은 제목, 그 아래 흐린 한 줄.
///
/// 누가 무슨 말을 했는가가 아니라 스레드에 무슨 일이 있었는가를 적는
/// 자리라, 대화 폭을 채우지 않고 글자만큼만 가운데에 선다. 폭을 다 쓰면
/// 말풍선보다 무거워져 대화를 가로막는다.
class _ThreadNotice extends StatelessWidget {
  const _ThreadNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.fill,
    required this.border,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color fill;
  final Color border;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.oncare;
    final Color accent = tokens.brand.primary;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s12,
          vertical: OnCareSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: OnCareRadius.mdAll,
          border: Border.all(color: border),
        ),
        // 글자 배율을 키우면 제목·설명·다음 행동이 차례로 길어진다. 한 줄에
        // 이어 붙이지 않고 세로로 쌓아 두면, 잘리는 대신 상자가 아래로 자란다.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppIcon(icon, size: OnCareSize.iconSmall, color: accent),
                const SizedBox(width: OnCareSpacing.s4),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// 시스템 안내(분석·전송)의 옅은 브랜드 채움과 옅은 테두리.
Color _noticeFill(BuildContext context) =>
    OnCareColors.onWhite(context.oncare.brand.primary, OnCareAlpha.subtle);
Color _noticeBorder(BuildContext context) =>
    OnCareColors.onWhite(context.oncare.brand.primary, OnCareAlpha.medium);

/// 운동을 보낸 일을 적는 대화 가운데 안내. (#2672)
///
/// 리포트 안내([ReportRegisteredCard])와 같은 자리·같은 상자다. 누를 것은
/// 없다 — 무엇을 보냈는지는 이 카드가 다 말하고, 자세한 구성은 프로그램 탭의
/// 전송 이력에 있다. 옅은 브랜드 채움이라 누를 것이 있는 리포트 안내(흰 바탕)와
/// 갈린다.
class RoutineDeliveryCard extends StatelessWidget {
  /// Creates the card.
  const RoutineDeliveryCard({required this.notice, super.key});

  /// 무엇을 보냈나.
  final RoutineDeliveryNotice notice;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _ThreadNotice(
      icon: AppIcons.personalRoutine,
      title: routineDeliveryTitle(l, notice.kind),
      message: routineDeliveryNames(l, <String>[
        ...notice.programNames,
        ...notice.routineNames,
      ]),
      fill: _noticeFill(context),
      border: _noticeBorder(context),
    );
  }
}

/// 전송 종류 → 안내 제목. 모르는 종류는 일반 문구다.
String routineDeliveryTitle(AppLocalizations l, String kind) => switch (kind) {
  'pt_with_routine' => l.chatRoutineDeliveredPt,
  'routine_only' => l.chatRoutineDeliveredPersonal,
  'cancelled_routine_only' => l.chatRoutineDeliveredAfterCancel,
  'program' => l.chatRoutineDeliveredProgram,
  _ => l.chatRoutineDelivered,
};

/// 운동 이름 셋까지 적고 나머지는 개수로 접는다 — 서버 본문과 같은 규칙이다.
String routineDeliveryNames(AppLocalizations l, List<String> names) {
  const int shown = 3;
  final String head = names.take(shown).join(' · ');
  final int rest = names.length - shown;
  return rest > 0 ? l.chatRoutineDeliveredMore(head, rest) : head;
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message, required this.avatar});

  final ClientChatMessage message;
  final String avatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final fromTrainer = message.fromTrainer;
    // 말풍선 폭 상한(대화 폭의 72%)과 시간 위치는 [AppChatBubble] 이 정한다.
    // 누가 한 말인지는 색과 **어느 쪽으로 붙어 있는가**가 말한다.
    final Widget bubble = AppChatBubble(
      mine: fromTrainer,
      time: _clockOnly(message.timeLabel),
      // 이모티콘은 말풍선 없이 그림만 둔다 — 회원 앱과 같다(#2020).
      bare: message.emoteId != null,
      child: Column(
        key: ValueKey<String>('trainer-message-bubble-${message.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 회원이 보낸 이모티콘은 그림만 둔다 — 본문은 이모티콘을 그리지 못하는
          // 자리(로스터의 마지막 메시지)가 읽는 글이다(#2020).
          if (message.emoteId case final String emote?)
            AppEmote(id: emote, semanticLabel: l.chatEmoteLabel)
          else
            Text(message.body),
          if (message.attachment case final attachment?) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            // 사진은 대화 안에서 그리고, PDF 는 내려받는 카드로 둔다. 사진을
            // 카드로 두면 자세를 확인하려고 매번 파일을 열어야 하고, 그건
            // 채팅에 사진을 붙이는 이유 자체를 없앤다. (#921)
            if (attachment.isImage)
              ChatImageAttachment(attachment: attachment)
            else
              AppChatFileCard(
                key: ValueKey<String>('trainer-chat-pdf-${attachment.fileId}'),
                name: attachment.fileName,
                detail: _fileSize(attachment.fileSize),
                onTap: () => _openPdf(context, ref, attachment),
              ),
          ],
        ],
      ),
    );

    if (fromTrainer) return bubble;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        ClientAvatar(name: avatar, size: AppAvatarSize.small),
        const SizedBox(width: OnCareSpacing.s8),
        Expanded(child: bubble),
      ],
    );
  }

  static String _clockOnly(String label) =>
      RegExp(r'\d{1,2}:\d{2}').firstMatch(label)?.group(0) ?? label;

  static String _fileSize(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';

  /// 채팅에 붙은 PDF 한 부를 미리보기로 연다.
  ///
  /// 쪽을 굽는 일은 공용 [PdfPagesView] 가 한다 — 웹에서 `printing` 의
  /// `PdfPreview` 는 CSP 에 막혀 스피너만 돌았다(#2828).
  Future<void> _openPdf(
    BuildContext context,
    WidgetRef ref,
    ChatAttachment attachment,
  ) async {
    final l = AppLocalizations.of(context);
    try {
      // 데모 대화의 파일은 받아 올 서버가 없어 바이트를 들고 온다(#2669).
      final bytes =
          attachment.localBytes ??
          await ref
              .read(trainerChatPdfRepositoryProvider)
              .download(attachment.downloadPath);
      if (!context.mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AppDialog(
          title: attachment.fileName,
          size: AppDialogSize.large,
          bodyPadding: EdgeInsets.zero,
          child: SizedBox(
            height: _pdfPreviewHeight,
            child: PdfPagesView(pdf: bytes, failedText: l.chatPdfOpenFailed),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(context, l.chatPdfOpenFailed, type: AppToastType.error);
    }
  }
}

/// 리포트 등록 안내. (#1378, #1421, #1600)
///
/// 회원 앱과 **같은 정보 구조**로 그린다 — 아이콘, `리포트가 등록되었어요`,
/// 대상 주, 그리고 다음 행동 한 줄. 같은 사건을 두 앱이 다른 모양으로 보여
/// 주면 회원과 트레이너가 같은 화면을 두고 이야기할 수 없다.
///
/// 자리는 말풍선이 아니라 **대화 가운데**다. 누가 무슨 말을 했는가가 아니라
/// 스레드에 무슨 일이 있었는가를 적는 자리라, 같은 흐름의 다른 안내(분석했어요·
/// 개인 추천운동이 전송됐어요)와 같은 가운데 안내 상자를 쓴다.
///
/// 다음 행동은 역할마다 다르다. 트레이너 쪽에는 열 PDF 가 없다 — 데모·드리프트
/// 는 파일을 저장하지 못하므로(#1378), 있지도 않은 파일을 여는 시늉 대신 그
/// 리포트가 있는 화면으로 보낸다.
class ReportRegisteredCard extends StatelessWidget {
  /// Creates the card. [onOpen] 은 리포트 탭으로 보내는 동작이다.
  const ReportRegisteredCard({
    required this.weekStart,
    required this.onOpen,
    super.key,
  });

  /// 카드가 가리키는 주의 월요일.
  final DateTime weekStart;

  /// 리포트 탭으로 가기 를 눌렀을 때.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final range = l.dateRange(
      l.dateMonthDay(weekStart.month, weekStart.day),
      l.dateMonthDay(weekEnd.month, weekEnd.day),
    );
    // 바탕은 흰색이고 테두리만 앱의 메인 색이다. 구조가 같으면 같은 안내로
    // 읽히고, 흰 바탕은 이 안내에만 **누를 것**이 있다는 것을 말해 준다.
    return _ThreadNotice(
      icon: AppIcons.document,
      title: l.chatReportRegistered,
      message: range,
      fill: OnCareColors.surfaceCard,
      border: context.oncare.brand.primary,
      // 흰 글씨 + 메인 파랑 채움 알약(#1828). 글자 버튼일 때는 제목·날짜와
      // 구분이 약해 누를 것으로 읽히지 않았다. 회원앱 `PDF 미리보기` 와 같은 모양.
      action: Padding(
        padding: const EdgeInsets.only(top: OnCareSpacing.s8),
        child: ChatPillButton(
          label: l.chatReportOpenInReports,
          onPressed: onOpen,
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onAttachImage,
    this.onEmote,
  });

  final TextEditingController controller;

  /// Disables the field and the send button while an insert is in flight.
  final bool sending;

  final Future<void> Function() onSend;

  /// 사진 첨부. null 이면 버튼 자체가 그려지지 않는다 — 눌러도 아무 데도 닿지
  /// 않는 버튼을 두지 않는다. (#921) 데모도 로컬 대화로 받으므로 지금은 늘
  /// 값이 있다(#2493).
  final Future<void> Function()? onAttachImage;

  /// 이모티콘 창 열기(#2020). 트레이너는 이용권 없이 보낸다.
  final Future<void> Function()? onEmote;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Future<void> Function()? attach = onAttachImage;
    // 웹에서 Enter 는 이전처럼 바로 보낸다(Shift+Enter 는 줄바꿈). 입력줄은
    // 여러 줄을 받으므로 Enter 를 여기서 가로채지 않으면 줄바꿈이 된다.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!sending) onSend();
        },
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
          if (!sending) onSend();
        },
      },
      child: AppChatInputBar(
        key: const ValueKey<String>('client-chat-input'),
        controller: controller,
        hint: l.chatInputHint,
        maxLength: _ChatViewState._maxMessageLength,
        sendTooltip: l.a11ySendMessage,
        onSend: onSend,
        attachTooltip: l.chatAttachImage,
        onAttach: attach == null ? null : () => attach(),
        emoteTooltip: l.chatEmoteLabel,
        onEmote: onEmote == null ? null : () => onEmote!(),
        enabled: !sending,
      ),
    );
  }
}

/// 채팅 안내 상자 안의 행동 버튼 — 흰 글씨, 메인 파랑 채움, 양 끝이 둥근 알약. (#1828)
///
/// 회원앱 채팅의 `PDF 미리보기` 와 같은 모양이다. 공용 버튼은 반경이 12 로
/// 고정이라, 알약 모양은 이 자리에서 그린다.
class ChatPillButton extends StatelessWidget {
  /// Creates the pill.
  const ChatPillButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// 버튼 글자.
  final String label;

  /// 눌렀을 때.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Semantics(
      button: true,
      child: Material(
        key: const Key('chatPillButton'),
        color: tokens.brand.primary,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tokens.density.buttonSmall),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s16,
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: tokens
                      .text(OnCareTypography.buttonSmall)
                      .copyWith(color: OnCareColors.textOnFill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
