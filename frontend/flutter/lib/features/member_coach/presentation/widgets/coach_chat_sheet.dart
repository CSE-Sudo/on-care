import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/member_coach/data/repositories/chat_pdf_repository.dart';
import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/coach_photo_send_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_notice.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_scroll.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_image_attachment.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_photo_picker.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_card.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_opener.dart';
import 'package:oncare/features/member_coach/presentation/widgets/emote_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:printing/printing.dart';

/// 루트 화면 위에 채팅 페이지를 열어 하단 내비게이션과 플로팅 버튼을 가린다.
Future<void> openTrainerChatPage(
  BuildContext context, {
  required String trainerName,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TrainerChatPage(trainerName: trainerName),
    ),
  );
}

/// 담당 트레이너와의 대화 목록과 메시지 입력창을 보여주는 전체 화면이다.
class TrainerChatPage extends ConsumerStatefulWidget {
  const TrainerChatPage({required this.trainerName, super.key});

  final String trainerName;

  @override
  ConsumerState<TrainerChatPage> createState() => _TrainerChatPageState();
}

class _TrainerChatPageState extends ConsumerState<TrainerChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 마지막으로 스크롤을 맞춘 대화의 양 끝. 끝이 바뀐 프레임에서만
  /// 스크롤한다(#2640).
  ChatEdges? _lastEdges;

  /// 메시지 id → 자리 표시. 지금 가장 오래된 메시지 하나와, 옛 쪽이 붙은 뒤
  /// 되돌리는 중인 메시지 하나만 들고 있다.
  final Map<String, GlobalKey> _anchorKeys = <String, GlobalKey>{};

  /// 되돌리는 중인 메시지 id — 끝나면 null.
  String? _restoringAnchorId;

  set _anchorKeyId(String? oldestId) {
    _anchorKeys.removeWhere(
      (String id, GlobalKey _) => id != oldestId && id != _restoringAnchorId,
    );
    if (oldestId != null) {
      _anchorKeys.putIfAbsent(
        oldestId,
        () => GlobalKey(debugLabel: 'coach-chat-anchor'),
      );
    }
  }

  bool _sending = false;

  /// OS 사진 선택기가 떠 있는 동안 다시 열지 않는다 — image_picker 는 겹친
  /// 요청을 `multiple_request` 로 거절한다.
  bool _picking = false;

  /// 대화 목록 전체 — 일반 말풍선과 리포트 안내를 한 타임라인에 둔다.
  ///
  /// 서버 응답 순서에 기대지 않고 발생 시각으로 정렬한다. 같은 시각에는 id를
  /// 보조 기준으로 써 새로고침할 때마다 순서가 바뀌지 않게 한다(#2127).
  List<Widget> _chatChildren(List<CoachMessage> messages) {
    final List<CoachMessage> timeline = List<CoachMessage>.of(messages)
      ..sort((CoachMessage first, CoachMessage second) {
        final int byTime = first.createdAt.compareTo(second.createdAt);
        return byTime != 0 ? byTime : first.id.compareTo(second.id);
      });
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < timeline.length; i++) {
      final CoachMessage message = timeline[i];
      if (i == 0 || !_sameDay(timeline[i - 1].createdAt, message.createdAt)) {
        out
          ..add(_dateDivider(message.createdAt))
          ..add(const SizedBox(height: OnCareSpacing.s8));
      }
      out.add(_chatItem(message));
    }
    return out;
  }

  Widget _chatItem(CoachMessage message) {
    final Widget item = _chatItemBody(message);
    // 가장 오래된 메시지에는 자리 표시를 단다 — 옛 쪽이 그 앞에 붙은 뒤 이
    // 메시지를 같은 자리로 되돌리는 기준이다(#2640).
    final GlobalKey? anchor = _anchorKeys[message.id];
    return anchor == null ? item : KeyedSubtree(key: anchor, child: item);
  }

  Widget _chatItemBody(CoachMessage message) {
    final DateTime? weekStart = message.reportWeekStart;
    if (weekStart != null) {
      return _ReportNotice(
        key: ValueKey<String>('coach-message-bubble-${message.id}'),
        message: message,
        weekStart: weekStart,
      );
    }
    final CoachRoutineDelivery? delivery = message.routineDelivery;
    if (delivery != null) {
      return Padding(
        key: ValueKey<String>('coach-routine-delivery-${message.id}'),
        padding: const EdgeInsets.only(bottom: OnCareSpacing.s16),
        child: CoachRoutineDeliveryNotice(delivery: delivery),
      );
    }
    return _MessageRow(message: message, trainerName: widget.trainerName);
  }

  /// 날짜 구분선. 요일까지 로케일 형식(`yMMMMEEEEd`)으로 적는다.
  ///
  /// 규격 구분선은 날짜 글자를 줄이지 않는다. 영어 전체 날짜에 글자 배율 1.3 이면
  /// 폰 폭보다 길어져 넘치므로, 그때만 줄 폭에 맞춰 통째로 줄인다 — 평소에는
  /// 가용 폭 그대로다. (패키지 구분선이 긴 날짜를 감당하게 되면 걷어낸다.)
  Widget _dateDivider(DateTime date) {
    // 서버 시각(UTC 순간)을 KST 날짜로 — 기기 시간대가 달라도 KST 오전 0~9시
    // 메시지가 전날 구분선 아래로 가지 않는다(#2876).
    final DateTime localDate = kstDateOf(date);
    final Widget divider = AppChatDateDivider(
      AppLocalizations.of(context).coachChatDateDivider(localDate),
      key: ValueKey<String>(
        'coach-chat-date-${localDate.year}-${localDate.month}-${localDate.day}',
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => FittedBox(
        fit: BoxFit.scaleDown,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: divider,
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => isSameKstDay(a, b);

  /// 대화를 열거나 메시지가 늘면 맨 아래를 보여 준다.
  ///
  /// 없을 때는 스레드가 가장 오래된 메시지부터 보였다. 한 개짜리 데모에서는
  /// 티가 안 났지만 기록이 3일치로 늘자, 채팅을 열면 며칠 전 첫 인사가 뜨고
  /// 최근 대화는 직접 내려야 보였다. 트레이너 앱은 이미 같은 동작을 한다.
  void _scrollToBottom({double? previousMax, int attemptsLeft = 12}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final double max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(max);

      // ListView는 긴 목록의 아직 만들지 않은 자식 높이를 추정한다. 첫 jump로
      // 새 자식이 만들어지면 maxScrollExtent가 다음 프레임에 다시 늘 수 있다.
      // 그 상태에서 멈추면 서버에서 최신 메시지를 받았어도 화면에는 이전 끝이
      // 남는다. 범위가 한 프레임 동안 안정될 때까지 다시 끝을 맞춘다.
      final bool stable =
          previousMax != null && (max - previousMax).abs() < 0.5;
      if (!stable && attemptsLeft > 1) {
        _scrollToBottom(previousMax: max, attemptsLeft: attemptsLeft - 1);
      }
    });
  }

  /// 옛 쪽이 [anchorId] 앞에 붙은 뒤에도 그 메시지를 **보던 자리에** 둔다.
  /// (#2640)
  ///
  /// 붙이기 전 그 메시지의 화면 위치를 잡아 두고, 붙인 뒤 같은 위치로 스크롤을
  /// 옮긴다. 옛 쪽이 길면 붙인 직후 그 메시지가 아직 만들어지지 않았을 수
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
      () => GlobalKey(debugLabel: 'coach-chat-anchor'),
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

  Future<void> _markRead() async {
    try {
      await ref.read(memberCoachRepositoryProvider).markRead();
    } catch (_) {
      // 읽음 처리 실패는 이미 불러오는 대화 표시를 막지 않는다.
      return;
    }
    if (mounted) ref.invalidate(coachUnreadProvider);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 이모티콘 창을 열고, 고른 것을 그 자리에서 보낸다. (#2020)
  ///
  /// 고르면 바로 보낸다 — 이모티콘은 한 번의 반응이라, 고른 뒤 전송을 다시 누르게
  /// 하면 글보다 느려진다. 이용권은 창이 맡는다(없으면 고를 수 없다).
  Future<void> _pickEmote() async {
    final AppToastHost toast = AppToastHost.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final String? picked = await showEmoteSheet(context);
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(memberCoachRepositoryProvider)
          .sendMessage('', emoteId: picked);
    } catch (_) {
      if (!mounted) return;
      toast.show(l.emoteSendFailed, type: AppToastType.error);
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    ref.invalidate(coachChatProvider);
  }

  /// 트레이너에게 보낼 사진을 골라 보낸다. (#1665)
  ///
  /// 보내는 동안과 실패는 대화 끝의 내 말풍선이 보여 준다 — 알림 한 줄로 끝내면
  /// 무엇을 다시 보내야 하는지 남지 않는다.
  Future<void> _attachPhoto() async {
    if (_picking) return;
    setState(() => _picking = true);
    final MealPhoto? photo;
    try {
      photo = await pickCoachPhoto(context, ref);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (photo == null || !mounted) return;
    await ref.read(coachPhotoSendProvider.notifier).send(photo);
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // 문구와 같이 await 전에 잡아 둔다.
    final AppToastHost toast = AppToastHost.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(memberCoachRepositoryProvider).sendMessage(text);
    } catch (_) {
      if (!mounted) return;
      toast.show(l.coachChatSendFailed, type: AppToastType.error);
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    _input.clear();
    ref.invalidate(coachChatProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final chat = ref.watch(coachChatProvider);
    // 서버가 대화를 404 로 답하면 담당이 해제된 것이다(#2843). 빈 대화로 그리지
    // 않고 안내를 띄우며 입력을 막는다.
    final bool unassigned = chat.error is CoachUnassignedException;
    // 폴링으로 새 리포트 안내가 오면 받은 리포트 목록도 다시 읽는다(#2643) —
    // 예전에는 앱을 다시 켜기 전까지 목록에 나타나지 않았다.
    ref.listen<AsyncValue<List<CoachMessage>>>(coachChatProvider, (
      AsyncValue<List<CoachMessage>>? previous,
      AsyncValue<List<CoachMessage>> next,
    ) {
      // 해제를 처음 알게 된 순간 담당 코치도 다시 읽는다 — 대화방을 나가면
      // 헤더가 AI 챗봇 입구로, 홈 트레이너 카드가 사라진 모습으로 바뀐다.
      if (next.error is CoachUnassignedException &&
          previous?.error is! CoachUnassignedException) {
        unawaited(
          recheckMemberCoach(ProviderScope.containerOf(context, listen: false)),
        );
      }
      final List<CoachMessage>? before = previous?.valueOrNull;
      final List<CoachMessage>? after = next.valueOrNull;
      // 보낸 사진이 대화에 들어왔으면 대기 목록에서 뺀다 — 원본 바이트가
      // 화면을 오래 열어 둔 만큼 쌓이지 않게(#2880).
      if (after != null) {
        ref.read(coachPhotoSendProvider.notifier).settle(after);
      }
      if (before == null || after == null) return;
      if (hasNewReportNotice(before, after)) {
        ref.invalidate(sentReportNoticesProvider);
      }
    });
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            ColoredBox(
              color: OnCareColors.surfaceCard,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OnCareSpacing.s4,
                  vertical: OnCareSpacing.s8,
                ),
                // 서브 페이지 머리처럼 [뒤로][가운데 제목][같은 폭 빈 자리] —
                // AI 코치 채팅 머리와 같은 배치다.
                child: Row(
                  children: <Widget>[
                    AppBackButton(onPressed: () => Navigator.of(context).pop()),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          AppAvatar(
                            name: widget.trainerName,
                            size: AppAvatarSize.large,
                          ),
                          const SizedBox(width: OnCareSpacing.s8),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  widget.trainerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tokens
                                      .text(OnCareTypography.titleSmall)
                                      .copyWith(
                                        color: OnCareColors.textPrimary,
                                      ),
                                ),
                                // 관계만 적는다 — 트레이너가 지금 답할 수
                                // 있는지는 앱이 모른다. `상담 가능` 처럼
                                // 지킬 수 없는 약속은 하지 않는다(#2089).
                                // #1235 가 초록 상태 점을 걷어낸 것과 같은
                                // 까닭이다.
                                Text(
                                  l.coachChatSubtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tokens
                                      .text(OnCareTypography.caption)
                                      .copyWith(
                                        color: OnCareColors.textTertiary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: OnCareSize.backCloseTouch),
                  ],
                ),
              ),
            ),
            const AppDivider(),
            Expanded(
              child: chat.when(
                loading: () => const AppLoading(),
                // 해제는 다시 받아도 같으니 안내만, 그 밖의 실패는 다음 폴링까지
                // 기다리지 않고 다시 받을 수 있게 한다(#2880).
                error: (Object error, _) => error is CoachUnassignedException
                    ? AppEmptyState(
                        key: const ValueKey<String>('coach-chat-unassigned'),
                        title: l.coachChatUnassigned,
                        icon: AppIcons.disconnect,
                      )
                    : AppErrorState(
                        key: const ValueKey<String>('coach-chat-error'),
                        title: l.coachChatLoadFailed,
                        retryLabel: l.actionRetry,
                        retryKey: const ValueKey<String>('coach-chat-retry'),
                        onRetry: () => ref.invalidate(coachChatProvider),
                      ),
                data: (latest) {
                  // 폴링이 주는 최신 쪽 앞에, 손으로 더 받아 온 옛 쪽을 붙여
                  // 그린다(#1943). 둘을 한 provider 에 두면 15초마다 새로 받는
                  // 최신 쪽이 받아 둔 옛 쪽을 지운다.
                  final CoachChatHistoryState history = ref.watch(
                    coachChatHistoryProvider,
                  );
                  // 같은 메시지가 양쪽에 있으면 id 로 하나만 남긴다(#2640) —
                  // 옛 쪽을 받은 뒤로는 history 가 폴링한 최신 쪽도 모아 둔다.
                  final List<CoachMessage> thread = mergeCoachThread(
                    history.messages,
                    latest,
                  );
                  // 내가 보낸 사진(#1665). 서버가 받은 것은 대화를 다시 받아
                  // 올 때까지 그 메시지로 끼워 두고(id 로 겹침을 거른다),
                  // 아직 못 받은 것은 대화 끝에 상태와 함께 둔다.
                  final List<PendingCoachPhoto> photos = ref.watch(
                    coachPhotoSendProvider,
                  );
                  final List<CoachMessage> messages = mergeCoachThread(
                    <CoachMessage>[
                      for (final PendingCoachPhoto p in photos) ?p.message,
                    ],
                    thread,
                  );
                  final List<PendingCoachPhoto> unsent = <PendingCoachPhoto>[
                    for (final PendingCoachPhoto p in photos)
                      if (p.status != CoachPhotoSendStatus.sent) p,
                  ];
                  // 연결만 되고 아직 주고받은 것이 없으면 입력줄 위가 통째로
                  // 비었다. 무엇을 보내면 되는지 안내한다(#2880).
                  if (messages.isEmpty && unsent.isEmpty) {
                    return AppEmptyState(
                      key: const ValueKey<String>('coach-chat-empty'),
                      title: l.coachChatEmptyTitle(widget.trainerName),
                      message: l.coachChatEmptyBody,
                      icon: AppIcons.chat,
                    );
                  }
                  final ChatEdges edges = ChatEdges(
                    oldestId: messages.firstOrNull?.id,
                    newestId: unsent.isNotEmpty
                        ? 'pending-${unsent.last.requestId}'
                        : messages.lastOrNull?.id,
                    count: messages.length + unsent.length,
                  );
                  // 무엇이 바뀐 프레임인지 보고 스크롤한다 — 매 빌드마다 부르면
                  // 사용자가 위로 올려 읽는 중에도 아래로 끌어내린다. 옛 쪽이
                  // 앞에 붙은 때는 보던 자리를 지킨다(#2640).
                  final ChatScrollAction action = chatScrollAction(
                    _lastEdges,
                    edges,
                  );
                  if (action != ChatScrollAction.none) {
                    final ChatEdges? previous = _lastEdges;
                    _lastEdges = edges;
                    if (action == ChatScrollAction.keepPosition &&
                        previous?.oldestId != null) {
                      _keepPositionAfterPrepend(previous!.oldestId!);
                    } else {
                      _scrollToBottom();
                    }
                    // Mark newly polled trainer messages read while this
                    // full-screen route is visible, then refresh its badge.
                    Future<void>.microtask(_markRead);
                  }
                  _anchorKeyId = edges.oldestId;
                  return ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      OnCareSpacing.s16,
                      OnCareSpacing.s16,
                      OnCareSpacing.s16,
                      OnCareSpacing.s12,
                    ),
                    children: <Widget>[
                      // 서버는 한 번에 최신 50건만 준다 — 그 앞을 받을 자리가
                      // 없어 51번째 이전 메시지는 위로 올려도 나오지 않았다.
                      // 한 쪽이 다 찼을 때만 보여 준다: 덜 찼다면 그 앞에 없다.
                      if (!history.exhausted &&
                          latest.length >= chatPageSize &&
                          messages.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: OnCareSpacing.s12,
                          ),
                          child: Center(
                            child: history.loading
                                ? const AppLoading.inline()
                                : AppButton(
                                    key: const ValueKey<String>(
                                      'coach-chat-load-older',
                                    ),
                                    label: l.coachChatLoadOlder,
                                    variant: AppButtonVariant.text,
                                    size: OnCareButtonSize.small,
                                    onPressed: () => ref
                                        .read(coachChatHistoryProvider.notifier)
                                        .loadOlder(messages.first),
                                  ),
                          ),
                        ),
                      ..._chatChildren(messages),
                      for (final PendingCoachPhoto photo in unsent)
                        _PendingPhotoRow(
                          key: ValueKey<String>(
                            'coach-pending-photo-${photo.requestId}',
                          ),
                          photo: photo,
                        ),
                    ],
                  );
                },
              ),
            ),
            // 입력줄은 여러 줄 입력(줄바꿈)을 받으므로 보내기는 전송 버튼으로 한다.
            KeyedSubtree(
              key: const ValueKey<String>('member-chat-input'),
              child: AppChatInputBar(
                controller: _input,
                hint: l.coachChatInputHint,
                // 서버 `ChatSendRequest.text` 와 같은 긴 글 상한(#2618).
                maxLength: AppTextLimits.long,
                sendTooltip: l.a11ySendMessage,
                emoteTooltip: l.a11yOpenEmotes,
                onEmote: _pickEmote,
                attachTooltip: l.coachPhotoAttach,
                onAttach: _picking ? null : _attachPhoto,
                enabled: !_sending && !unassigned,
                onSend: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 루틴 전송 안내 — 트레이너가 운동을 보낸 자리에 대화 가운데 안내로 선다. (#2672)
///
/// 알림과 함께 대화에도 남아, "어제 받은 루틴" 에 대한 이야기가 그 전송 바로
/// 아래에 이어진다. 트레이너 웹의 같은 안내와 같은 제목·같은 이름 줄이다.
class CoachRoutineDeliveryNotice extends StatelessWidget {
  const CoachRoutineDeliveryNotice({required this.delivery, super.key});

  final CoachRoutineDelivery delivery;

  /// 이름으로 적는 운동 수. 나머지는 개수로 접는다 — 서버 본문과 같다.
  static const int _shownNames = 3;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<String> names = <String>[
      ...delivery.programNames,
      ...delivery.routineNames,
    ];
    final String shown = names.take(_shownNames).join(' · ');
    final int more = names.length - _shownNames;
    return CoachChatNotice(
      icon: AppIcons.routine,
      title: switch (delivery.kind) {
        'pt_with_routine' => l.coachChatRoutineReceivedPt,
        'routine_only' => l.coachChatRoutineReceivedPersonal,
        'cancelled_routine_only' => l.coachChatRoutineReceivedAfterCancel,
        'program' => l.coachChatRoutineReceivedProgram,
        _ => l.coachChatRoutineReceived,
      },
      subtitle: more > 0 ? l.coachChatRoutineReceivedMore(shown, more) : shown,
    );
  }
}

/// 메시지 한 줄 — 받은 메시지는 트레이너 아바타, 말풍선, 시간 순서다.
class _MessageRow extends ConsumerWidget {
  const _MessageRow({required this.message, required this.trainerName});

  final CoachMessage message;
  final String trainerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool fromMe = message.fromMe;
    final Widget bubble = AppChatBubble(
      mine: fromMe,
      time: _clockOnly(message.timeLabel),
      // 이모티콘은 그림 하나가 곧 말이다 — 말풍선에 담으면 그림 뒤로 파란 상자가
      // 비친다(#2020).
      bare: message.emoteId != null,
      child: KeyedSubtree(
        key: ValueKey<String>('coach-message-bubble-${message.id}'),
        child: _body(context, ref),
      ),
    );
    return Padding(
      key: ValueKey<String>('coach-message-${message.id}'),
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s16),
      child: fromMe
          ? bubble
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                AppAvatar(
                  key: ValueKey<String>('coach-message-avatar-${message.id}'),
                  name: trainerName,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(child: bubble),
              ],
            ),
    );
  }

  /// 본문 글줄을 그릴지. 글 없이 보낸 사진은 본문이 빈 문자열이라, 그대로
  /// 그리면 사진 위에 빈 글줄과 간격만큼 여백이 생겼다(#2880). 첨부가 없으면
  /// 빈 본문이어도 말풍선 높이를 지키려고 그린다.
  bool get _hasText =>
      message.body.trim().isNotEmpty || message.attachment == null;

  /// 말풍선 내용. 리포트 등록 안내는 여기로 오지 않는다 — 그것은 말풍선이
  /// 아니라 대화 가운데 안내라, 스레드를 세울 때 갈라진다(#1600).
  Widget _body(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 이모티콘 메시지는 그림만 둔다 — 본문은 이모티콘을 그리지 못하는
        // 자리(알림·목록의 마지막 메시지)가 읽는 글이라 여기서 또 보이면
        // `(이모티콘)` 이 말풍선에 그대로 남는다(#2020).
        if (message.emoteId case final String emote?)
          AppEmote(
            id: emote,
            semanticLabel: AppLocalizations.of(context).a11yEmote,
          )
        else if (_hasText)
          Text(message.body),
        if (message.attachment case final attachment?) ...<Widget>[
          if (message.emoteId != null || _hasText)
            const SizedBox(height: OnCareSpacing.s8),
          // 사진은 대화 안에서 그리고, 리포트 PDF 는 내려받는
          // 카드로 둔다. 사진을 카드로 두면 볼 때마다 파일을
          // 열어야 한다. (#921)
          if (attachment.isImage)
            CoachImageAttachment(attachment: attachment, mine: message.fromMe)
          else
            AppChatFileCard(
              key: ValueKey<String>('coach-pdf-${attachment.fileId}'),
              name: attachment.fileName,
              detail: _fileSize(attachment.fileSize),
              onTap: () => _openPdf(context, ref, attachment),
            ),
        ],
      ],
    );
  }

  Future<void> _openPdf(
    BuildContext context,
    WidgetRef ref,
    CoachAttachment attachment,
  ) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    try {
      final bytes = await ref
          .read(chatPdfRepositoryProvider)
          .download(attachment.downloadPath);
      if (!context.mounted) return;
      await openPdfPreviewPage(context, bytes, attachment.fileName);
    } catch (_) {
      toast.show(l.coachChatPdfOpenFailed, type: AppToastType.error);
    }
  }

  static String _clockOnly(String label) =>
      RegExp(r'\d{1,2}:\d{2}').firstMatch(label)?.group(0) ?? label;

  static String _fileSize(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';
}

/// 아직 대화에 들어가지 않은 내 사진 — 말풍선 아래에 보내는 중·실패를 적는다.
/// (#1665)
///
/// 실패하면 그 자리에서 다시 보내거나 지운다. 다시 보내기는 같은 멱등키를 써서,
/// 서버는 받았는데 응답만 끊긴 경우에도 사진이 두 장 쌓이지 않는다.
class _PendingPhotoRow extends ConsumerWidget {
  const _PendingPhotoRow({required this.photo, super.key});

  final PendingCoachPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool failed = photo.status == CoachPhotoSendStatus.failed;
    final CoachPhotoSendController controller = ref.read(
      coachPhotoSendProvider.notifier,
    );
    final TextStyle caption = tokens
        .text(OnCareTypography.caption)
        .copyWith(
          color: failed ? OnCareColors.danger : OnCareColors.textTertiary,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          AppChatBubble(
            mine: true,
            child: CoachImageAttachment(
              attachment: photo.attachment,
              mine: true,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          if (failed)
            Wrap(
              key: const ValueKey<String>('coach-pending-photo-failed'),
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: OnCareSpacing.s4,
              children: <Widget>[
                Text(l.coachPhotoSendFailed, style: caption),
                AppButton(
                  key: const ValueKey<String>('coach-pending-photo-retry'),
                  label: l.coachPhotoRetry,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                  onPressed: () => controller.retry(photo.requestId),
                ),
                AppButton(
                  key: const ValueKey<String>('coach-pending-photo-discard'),
                  label: l.coachPhotoDiscard,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                  onPressed: () => controller.discard(photo.requestId),
                ),
              ],
            )
          else
            Row(
              key: const ValueKey<String>('coach-pending-photo-sending'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const AppLoading.inline(),
                const SizedBox(width: OnCareSpacing.s4),
                Text(l.coachPhotoSending, style: caption),
              ],
            ),
        ],
      ),
    );
  }
}

/// PDF 한 부를 미리보기로 연다. 첨부 파일과 회원 기록으로 만든 문서가 같은
/// 화면으로 열려야, 회원이 무엇을 보고 있는지 헷갈리지 않는다. (#1600)
///
/// 부분 창이 아니라 전체 화면 페이지다(#2170) — 회원 앱의 부분 창에는 닫기 X 를
/// 두지 않는데, 여기는 A4 리포트를 확대·스크롤하며 오래 읽는 화면이라 시트로
/// 두면 문서를 밀다가 창이 닫힌다. 다른 상세 화면과 같은 `<` 로 나간다. 채팅
/// 페이지처럼 루트에 쌓아 하단 내비와 + 버튼을 가린다(#791).
Future<void> openPdfPreviewPage(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => PdfPreviewPage(bytes: bytes, fileName: fileName),
    ),
  );
}

/// [openPdfPreviewPage] 가 여는 화면 — 머리에 파일 이름과 `<`, 아래는 미리보기.
///
/// `build` 는 **부를 때마다 복사본**을 준다. 웹에서 미리보기는 pdf.js 로 그리는데,
/// pdf.js 는 받은 바이트의 버퍼를 워커로 넘기면서(transfer) 원본을 비워 버린다.
/// 같은 바이트를 그대로 다시 주면 두 번째 렌더가 `ArrayBuffer ... is already
/// detached` 로 죽고, 그리다 만 미리보기가 스피너만 도는 채로 남는다. 미리보기는
/// 화면 크기·용지 설정이 바뀔 때마다 다시 그리므로 두 번째 호출은 반드시 온다.
class PdfPreviewPage extends StatelessWidget {
  const PdfPreviewPage({
    required this.bytes,
    required this.fileName,
    super.key,
  });

  static const Key pageKey = Key('pdfPreviewPage');

  final Uint8List bytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Scaffold(
      key: pageKey,
      appBar: AppTopBar(title: fileName),
      body: PdfPreview(
        build: (_) async => Uint8List.fromList(bytes),
        pdfFileName: fileName,
        allowSharing: false,
        // 미리보기가 실패했을 때 스피너를 계속 돌리면 회원은 느린 것과
        // 안 되는 것을 구별할 수 없다.
        onError: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s24),
            child: Text(
              l.coachChatPdfOpenFailed,
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// 리포트 등록 안내 — 대화 가운데 안내 배너와 `PDF 미리보기`. (#1600, #1577)
///
/// 누르면 트레이너가 보낸 파일을 연다. 열 파일이 없으면(데모, 그리고 본문만
/// 보낸 리포트) 트레이너 웹과 같은 결과지를 세워 같은 미리보기로 연다(#2652) —
/// 트레이너가 보는 한 장을 회원도 그 자리에서 볼 수 있어야 한다.
class _ReportNotice extends ConsumerStatefulWidget {
  const _ReportNotice({
    required this.message,
    required this.weekStart,
    super.key,
  });

  final CoachMessage message;
  final DateTime weekStart;

  @override
  ConsumerState<_ReportNotice> createState() => _ReportNoticeState();
}

class _ReportNoticeState extends ConsumerState<_ReportNotice> {
  /// 문서를 만드는 동안 다시 누르지 못하게 한다 — 같은 문서를 두 번 그리면
  /// 미리보기가 두 겹으로 열린다.
  bool _opening = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: OnCareSpacing.s16),
    child: CoachReportCard(
      weekStart: widget.weekStart,
      onOpenPdf: _opening ? () {} : _open,
    ),
  );

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    try {
      // 여는 규칙은 MY 탭 목록과 한곳에서 나눠 쓴다 — 두 화면이 서로 다른
      // 문서를 열면 회원은 같은 주 리포트를 두 벌 가진 셈이 된다(#2232).
      await openCoachReport(
        context,
        ref,
        message: widget.message,
        weekStart: widget.weekStart,
      );
    } catch (_) {
      toast.show(l.coachChatPdfOpenFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
