import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/data/repositories/chat_pdf_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/member_weekly_report.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_report_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_notice.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_image_attachment.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_card.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
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

  /// 마지막으로 그린 메시지 수. 길이가 바뀐 프레임에서만 스크롤한다.
  int _lastCount = -1;
  bool _sending = false;

  /// 대화 목록 전체 — 말풍선 스레드 뒤에 리포트 안내를 붙인다.
  ///
  /// 리포트 안내는 온 시각 자리에 끼우지 않고 **항상 맨 아래**에 둔다. 대화가
  /// 이어지면 안내가 위로 밀려 올라가 버리는데, 회원이 리포트를 여는 자리는
  /// 대화를 새로 열 때마다 같은 곳이어야 찾을 수 있다.
  List<Widget> _chatChildren(
    List<CoachMessage> messages, {
    required bool showDemoBanners,
  }) {
    final List<CoachMessage> thread = <CoachMessage>[];
    final List<CoachMessage> reports = <CoachMessage>[];
    for (final CoachMessage message in messages) {
      (message.reportWeekStart == null ? thread : reports).add(message);
    }
    return <Widget>[
      ...showDemoBanners
          ? _withDemoBanners(thread)
          : _withoutDemoBanners(thread),
      // 스레드의 마지막 요소는 아래 여백을 달지 않는다 — 원래 목록의 끝이라서다.
      // 그 뒤에 안내를 붙이면 `개인 추천운동을 받았어요` 배너와 맞붙으므로,
      // 스레드가 비어 있지 않을 때만 한 칸 띄운다.
      if (thread.isNotEmpty && reports.isNotEmpty)
        const SizedBox(height: OnCareSpacing.s16),
      for (final CoachMessage message in reports)
        _ReportNotice(
          key: ValueKey<String>('coach-message-bubble-${message.id}'),
          message: message,
          weekStart: message.reportWeekStart!,
        ),
    ];
  }

  /// 데모 안내 배너를 **하루 단위로** 끼워 넣은 목록을 만든다.
  ///
  /// 배너가 스레드 맨 앞·맨 뒤에 하나씩만 있으면, 사흘치 대화에서 "분석은 이
  /// 대화가 시작되기 전에 딱 한 번 있었다"로 읽힌다. 실제로는 매일 그날 데이터를
  /// 분석해 그 대화가 시작되고, 트레이너가 조정한 루틴을 보내며 끝난다 — 그래서
  /// 날이 바뀌는 자리마다 앞뒤로 붙인다. (#543)
  ///
  /// 날짜 판정은 `createdAt` 으로 한다. `timeLabel` 은 화면에 보일 문자열일
  /// 뿐이라 거기서 날짜를 파내면 표시 문구가 곧 로직이 된다.
  ///
  /// 시드 메시지에 대해서만 자른다. 데모 중에 내가 보낸 답장은 오늘 날짜라
  /// 그대로 두면 내 말풍선 앞에 "분석했어요" 가 끼어든다.
  List<Widget> _withDemoBanners(List<CoachMessage> messages) {
    final List<Widget> out = <Widget>[];
    final int lastSeeded = messages.lastIndexWhere(
      (message) => message.id.startsWith('seed-'),
    );
    for (int i = 0; i < messages.length; i++) {
      final CoachMessage m = messages[i];
      final bool seeded = m.id.startsWith('seed-');
      final bool newDay =
          i == 0 || !_sameDay(messages[i - 1].createdAt, m.createdAt);
      if (newDay) {
        if (seeded && i > 0) {
          out.add(
            _ReceivedBanner(key: ValueKey<String>('received-before-${m.id}')),
          );
          out.add(const SizedBox(height: OnCareSpacing.s8));
        }
        out.add(_dateDivider(m.createdAt));
        out.add(const SizedBox(height: OnCareSpacing.s8));
        if (seeded) {
          out.add(_AnalyzedBanner(trainerName: widget.trainerName));
          out.add(const SizedBox(height: OnCareSpacing.s16));
        }
      }
      out.add(_MessageRow(message: m, trainerName: widget.trainerName));
      if (i == lastSeeded) {
        out.add(const _ReceivedBanner());
        if (i != messages.length - 1) {
          out.add(const SizedBox(height: OnCareSpacing.s16));
        }
      }
    }
    return out;
  }

  List<Widget> _withoutDemoBanners(List<CoachMessage> messages) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (i == 0 || !_sameDay(messages[i - 1].createdAt, message.createdAt)) {
        out
          ..add(_dateDivider(message.createdAt))
          ..add(const SizedBox(height: OnCareSpacing.s8));
      }
      out.add(_MessageRow(message: message, trainerName: widget.trainerName));
    }
    return out;
  }

  /// 날짜 구분선. 요일까지 로케일 형식(`yMMMMEEEEd`)으로 적는다.
  ///
  /// 규격 구분선은 날짜 글자를 줄이지 않는다. 영어 전체 날짜에 글자 배율 1.3 이면
  /// 폰 폭보다 길어져 넘치므로, 그때만 줄 폭에 맞춰 통째로 줄인다 — 평소에는
  /// 가용 폭 그대로다. (패키지 구분선이 긴 날짜를 감당하게 되면 걷어낸다.)
  Widget _dateDivider(DateTime date) {
    final DateTime localDate = date.toLocal();
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

  static bool _sameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

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
    final bool showDemoBanners = ref.watch(appConfigProvider).useMockApi;
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
                // 재시도 동작은 원래 없었다 — 문구만 규격 빈 화면 틀에 담는다.
                error: (_, _) => AppEmptyState(
                  title: l.coachChatLoadFailed,
                  icon: AppIcons.error,
                ),
                data: (messages) {
                  // 길이가 바뀐 프레임에서만 — 매 빌드마다 부르면 사용자가
                  // 위로 올려 읽는 중에도 아래로 끌어내린다.
                  if (messages.length != _lastCount) {
                    _lastCount = messages.length;
                    _scrollToBottom();
                    // Mark newly polled trainer messages read while this
                    // full-screen route is visible, then refresh its badge.
                    Future<void>.microtask(_markRead);
                  }
                  return ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      OnCareSpacing.s16,
                      OnCareSpacing.s16,
                      OnCareSpacing.s16,
                      OnCareSpacing.s12,
                    ),
                    children: _chatChildren(
                      messages,
                      showDemoBanners: showDemoBanners,
                    ),
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
                sendTooltip: l.a11ySendMessage,
                enabled: !_sending,
                onSend: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 데모 전용 안내 배너 — 트레이너 앱의 같은 배너를 회원 시점으로 옮긴 것.
///
/// 트레이너 화면은 "AI가 김민수님의 … 분석했어요 / 루틴이 김민수님에게
/// 전송됐어요" 라고 말한다. 같은 사건을 받는 쪽에서 보면 "내 데이터를
/// 분석했어요 / 루틴을 받았어요" 가 된다 — 내용은 같고 시점만 다르다. (#543)
///
/// 실 모드에서는 그리지 않는다. 서버가 실제로 그 순간을 알려주는 것이 아니라
/// 데모 대화의 맥락을 설명하는 장치이기 때문이다.
class _AnalyzedBanner extends StatelessWidget {
  const _AnalyzedBanner({required this.trainerName});

  final String trainerName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return CoachChatNotice(
      icon: AppIcons.ai,
      title: l.coachChatDemoAnalyzed,
      subtitle: l.coachChatDemoReportSent(trainerName),
    );
  }
}

class _ReceivedBanner extends StatelessWidget {
  const _ReceivedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // #1239 이후로는 "완료" 배너를 두 앱이 함께 쓰는 완료 초록으로
    // 칠했는데, 이 배너는 상태 완료가 아니라 "개인 추천운동을 받았다"는
    // 안내다 — 위 [_AnalyzedBanner]와 같은 흐름의 다음 단계라, 초록이
    // 아니라 그 배너와 같은 안내(info) 톤으로 맞춘다(#1379).
    return CoachChatNotice(
      icon: AppIcons.checkCircle,
      title: l.coachChatDemoRoutineReceived,
      subtitle: l.coachChatDemoNotified,
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

  /// 말풍선 내용. 리포트 등록 안내는 여기로 오지 않는다 — 그것은 말풍선이
  /// 아니라 대화 가운데 안내라, 스레드를 세울 때 갈라진다(#1600).
  Widget _body(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(message.body),
        if (message.attachment case final attachment?) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          // 사진은 대화 안에서 그리고, 리포트 PDF 는 내려받는
          // 카드로 둔다. 사진을 카드로 두면 볼 때마다 파일을
          // 열어야 한다. (#921)
          if (attachment.isImage)
            CoachImageAttachment(attachment: attachment)
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
      await showPdfPreviewDialog(context, bytes, attachment.fileName);
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

/// PDF 한 부를 미리보기로 연다. 첨부 파일과 회원 기록으로 만든 문서가 같은
/// 화면으로 열려야, 회원이 무엇을 보고 있는지 헷갈리지 않는다. (#1600)
///
/// 모바일 전체 화면 시트다 — 위에 파일 이름과 닫기, 아래는 미리보기(#1702).
///
/// `build` 는 **부를 때마다 복사본**을 준다. 웹에서 미리보기는 pdf.js 로 그리는데,
/// pdf.js 는 받은 바이트의 버퍼를 워커로 넘기면서(transfer) 원본을 비워 버린다.
/// 같은 바이트를 그대로 다시 주면 두 번째 렌더가 `ArrayBuffer ... is already
/// detached` 로 죽고, 그리다 만 미리보기가 스피너만 도는 채로 남는다. 미리보기는
/// 화면 크기·용지 설정이 바뀔 때마다 다시 그리므로 두 번째 호출은 반드시 온다.
Future<void> showPdfPreviewDialog(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) {
  final AppLocalizations l = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) {
      final OnCareTokens tokens = sheetContext.oncare;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OnCareSpacing.sheetPadding,
              OnCareSpacing.s8,
              OnCareSpacing.s8,
              OnCareSpacing.s8,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.titleMedium)
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                ),
                const AppCloseButton(),
              ],
            ),
          ),
          const AppDivider(),
          Expanded(
            child: PdfPreview(
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
          ),
        ],
      );
    },
  );
}

/// 리포트 등록 안내 — 대화 가운데 안내 배너와 `PDF 미리보기`. (#1600, #1577)
///
/// 누르면 트레이너가 보낸 파일을 연다. 열 파일이 없으면(데모, 그리고 본문만
/// 보낸 리포트) 같은 주를 회원 기록으로 정리한 문서를 만들어 같은 미리보기로
/// 연다 — 리포트 화면이 보여 주는 통계를 회원도 그 자리에서 볼 수 있어야 한다.
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
      final CoachAttachment? attachment = widget.message.attachment;
      final Uint8List bytes;
      final String fileName;
      if (attachment != null) {
        bytes = await ref
            .read(chatPdfRepositoryProvider)
            .download(attachment.downloadPath);
        fileName = attachment.fileName;
      } else {
        final MemberWeeklyReport report = await ref.read(
          memberWeeklyReportProvider(widget.weekStart).future,
        );
        bytes = await ref
            .read(memberReportPdfGeneratorProvider)
            .generate(
              l: l,
              report: report,
              // 안내 상자가 본문을 감추므로, 트레이너가 리포트와 함께 보낸 글은
              // 문서 안에서 읽게 한다 — 트레이너 화면의 `트레이너 피드백` 자리다.
              trainerNote: widget.message.body,
            );
        fileName = l.coachReportPdfFileName(_ymd(widget.weekStart));
      }
      if (!mounted) return;
      await showPdfPreviewDialog(context, bytes, fileName);
    } catch (_) {
      toast.show(l.coachChatPdfOpenFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  static String _ymd(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
