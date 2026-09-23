import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/consultations/data/dtos/consultation_dtos.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 카드 필드 라벨 열 폭 — `운동 목표`·`희망 일시` 가 한 줄에 들어가는 폭.
const double _fieldLabelWidth = 84;

String _hm(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// 회원이 고른 자리 문구 — `3월 5일 화 19:00–19:30 (30분)`. (#1873)
///
/// 길이는 트레이너가 그 자리를 열 때 정한 값이다. 예전에는 코드 상수 30분을
/// 더해 보여 줬는데, 승인이 만드는 일정과 카드가 서로 다른 길이를 말할 수 있었다.
///
/// 자리 선택 이전에 접수된 요청에는 자리가 없다 — 그때는 회원이 적어 보낸 희망
/// 시각을 [preferredTimeLabel] 그대로 보여 준다.
String _slotLabel(AppLocalizations l, ConsultationRequest request) {
  final DateTime? start = request.slotStartsAt;
  if (start == null) {
    return '${dateLabel(l, request.preferredDate)} '
        '${preferredTimeLabel(l, request.preferredTimeCode)}';
  }
  final int minutes = request.slotDurationMinutes ?? 60;
  final DateTime end = start.add(Duration(minutes: minutes));
  return '${dateLabel(l, start)} ${_hm(start)}–${_hm(end)} '
      '(${l.consultSlotDuration(minutes)})';
}

/// 상담 요청 — the inbox where a member becomes a client.
///
/// Accepting is the only path from "someone asked" to a real trainer↔member
/// link, so the card carries everything a trainer needs to decide without
/// opening anything else: who, what they want, and when they can come.
///
/// Two request sources land here — a member who picked this trainer by
/// name, and a member who asked the gym. The second kind is badged, since
/// any trainer at that gym can pick it up and the first to accept wins.
///
/// The demo build never reaches this page: its repository reports no inbox
/// and the sidebar row is not rendered (see [consultationInboxEnabledProvider]).
class ConsultationsPage extends ConsumerWidget {
  /// Creates the inbox page.
  const ConsultationsPage({super.key, this.returnTo, this.modal = false});

  /// Entry surface (`dashboard` or null/default schedule).
  final String? returnTo;

  /// Whether the inbox is being shown over its entry surface.
  ///
  /// 모달이면 페이지 틀 없이 [AppDialog] 안에 **목록만** 넣는다 — 창의
  /// 제목·닫기 X 가 페이지 헤더를 대신한다.
  final bool modal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);

    if (modal) {
      return KeyedSubtree(
        key: const ValueKey<String>('consultations-dialog'),
        child: AppDialog(
          title: l.consultTitle,
          size: AppDialogSize.large,
          child: const _Inbox(),
        ),
      );
    }

    final fromDashboard = returnTo == 'dashboard';
    return AppWebPage(
      title: l.consultTitle,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                key: const ValueKey<String>('consultations-back-to-schedule'),
                label: fromDashboard
                    ? l.consultBackToDashboard
                    : l.consultBackToSchedule,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
                leadingIcon: Icons.chevron_left_rounded,
                onPressed: () => context.go(
                  fromDashboard ? AppRoutes.dashboard : AppRoutes.schedule,
                ),
              ),
            ),
            const SizedBox(height: OnCareSpacing.s16),
            const _Inbox(),
          ],
        ),
      ),
    );
  }
}

/// Opens the shared consultation inbox without leaving the current workspace.
Future<void> showConsultationsDialog(BuildContext context) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => const ConsultationsPage(modal: true),
    );

/// 필터 칩 + 요청 목록. 페이지와 모달이 같은 것을 쓴다.
///
/// 스크롤은 감싸는 쪽(페이지의 스크롤 뷰, 창의 본문)이 맡는다.
class _Inbox extends ConsumerWidget {
  const _Inbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final filter = ref.watch(consultationFilterProvider);
    final inbox = ref.watch(consultationsProvider);
    final pending = ref.watch(consultationPendingCountProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 메시지 탭 고객 리스트 상단의 `전체 / 읽지 않음 N` 칩과 같은 언어다 —
        // 글자 토글(`전체 보기`/`대기 중만`) 대신 두 상태를 한눈에 본다.
        Row(
          children: <Widget>[
            AppChoiceChip(
              key: const ValueKey<String>('consultation-filter-all'),
              label: l.consultFilterAll,
              selected: filter == 'all',
              onSelected: (_) =>
                  ref.read(consultationFilterProvider.notifier).state = 'all',
            ),
            const SizedBox(width: OnCareSpacing.s8),
            AppChoiceChip(
              key: const ValueKey<String>('consultation-filter-pending'),
              label: l.consultFilterPendingCount(pending ?? 0),
              selected: filter == 'pending',
              onSelected: (_) =>
                  ref.read(consultationFilterProvider.notifier).state =
                      'pending',
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s16),
        inbox.requests.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (error, _) => AppErrorState(
            placement: AppStatePlacement.card,
            title: l.consultLoadFailed,
            message: serverDetailOr(
              l,
              error is AppError ? error.message : null,
              l.consultRetryLater,
            ),
            retryLabel: l.actionRetry,
            onRetry: () => ref.invalidate(consultationsProvider),
          ),
          data: (list) => list.isEmpty
              ? AppEmptyState(
                  placement: AppStatePlacement.card,
                  title: filter == 'pending'
                      ? l.consultEmptyPending
                      : l.consultEmptyHistory,
                  message: l.consultEmptyHint,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final request in list) ...<Widget>[
                      _RequestCard(
                        key: ValueKey<String>('consultation-${request.id}'),
                        request: request,
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                    ],
                    // 서버는 한 쪽만 준다(#980). 상한에 닿았을 때만 버튼을 띄운다 —
                    // 늘 보이면 더 없는데도 누를 것이 있는 것처럼 읽힌다.
                    if (inbox.hasMore)
                      Align(
                        child: AppButton(
                          key: const ValueKey<String>('consultation-load-more'),
                          label: l.consultLoadMore,
                          variant: AppButtonVariant.secondary,
                          leadingIcon: Icons.history_rounded,
                          onPressed: inbox.loadingMore
                              ? null
                              : () => ref
                                    .read(consultationsProvider.notifier)
                                    .loadMore(),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One request. Pending cards carry the 승인 / 거절 actions; decided ones
/// keep their place under the 전체 filter as a read-only record.
class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request, super.key});

  final ConsultationRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  /// Blocks both actions while one is in flight — a double-tapped 승인
  /// would otherwise race and the second call would 409.
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final AppLocalizations l = AppLocalizations.of(context);
    final String failureText = l.consultActionFailed;
    try {
      await action();
      if (!mounted) return;
      showAppToast(context, success, type: AppToastType.success);
    } on AppError catch (e) {
      // A failed decision usually means the request moved on without us —
      // another trainer at the same gym accepted it first. Refresh before
      // showing the reason, or the card stays actionable and the trainer
      // can keep pressing 승인 on something already decided (review).
      ref.invalidate(consultationsProvider);
      ref.invalidate(consultationPendingCountProvider);
      if (!mounted) return;
      // 409 carries the server's reason (이미 처리됨 / 다른 트레이너가 담당 중)
      // — that sentence is the whole point, so it is shown verbatim.
      showAppToast(
        context,
        serverDetailOr(l, e.message, failureText),
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 승인한다. 시각을 정하지 않는다 — 회원이 고른 자리가 날짜·시각·길이를 이미
  /// 들고 있고, 서버가 그 자리를 첫 일정으로 확정한다(#1873).
  ///
  /// 예전에는 여기서 희망 시각에 코드 상수 30분을 더해 일정을 보냈고, 겹치면
  /// 버튼 옆에 인라인 문구를 띄웠다. 자리를 연 사람이 트레이너 자신이고 한 자리는
  /// 한 사람 몫이라 겹침이 구조적으로 나지 않아 그 경로를 걷어냈다.
  Future<void> _accept() async {
    setState(() => _busy = true);
    final AppLocalizations l = AppLocalizations.of(context);
    final request = widget.request;
    try {
      final result = await acceptConsultation(ref, request.id);
      if (!mounted) return;
      showAppToast(
        context,
        result.scheduleCreated
            ? l.consultScheduleCreated(request.memberName)
            : l.consultApproved(request.memberName),
        type: AppToastType.success,
      );
    } on AppError catch (e) {
      ref.invalidate(consultationsProvider);
      ref.invalidate(consultationPendingCountProvider);
      if (!mounted) return;
      showAppToast(
        context,
        serverDetailOr(l, e.message, l.consultActionFailed),
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final note = await showAppDialog<String?>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (note == null) return;
    await _run(
      () => rejectConsultation(ref, widget.request.id, note: note),
      l.consultRejected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final tokens = context.oncare;
    final request = widget.request;
    // 이름이 비어 오는 경우의 대체 문구는 화면이 붙인다 — DTO 는
    // 로케일을 모른다. (#501)
    final String name = request.memberName.isEmpty
        ? l.unknownMember
        : request.memberName;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 아바타를 이름 옆(제목 자리)에 둔다 — 예전에는 아바타가 운동
          // 목표·희망 일시 줄과 한 Row에 있어 이름은 카드 제목으로, 아바타는
          // 그 아래 필드 줄 옆으로 떨어져 보였다(#1395).
          Row(
            children: <Widget>[
              AppAvatar(
                name: request.memberName.isEmpty
                    ? '?'
                    : request.memberName.characters.first,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              // 승인·거절 결과를 카드 우측 상단 태그로 바로 보여준다. 대기 중은
              // 태그를 달지 않는다 — 위 `대기 N` 필터가 이미 그 상태를 말하고
              // 있어, 카드마다 또 붙이면 같은 말을 반복하는 셈이다.
              if (!request.isPending) _StatusTag(status: request.status),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 건강관리 목적은 회원이 따로 고르지 않는다 — 운동 목표 하나에서
          // 서버 호환용으로 파생된 값이라, 여기서 또 보여주면 같은 정보를
          // 두 번 말하는 셈이다. `기타` 목표에서는 그 상세가 문의 내용과
          // 완전히 같은 문구라 아래 인용구와 겹치기까지 한다.
          _Field(
            label: l.consultExerciseGoal,
            value: label(exerciseGoalLabels(l), request.goalCode),
          ),
          _Field(
            // 회원이 고른 자리다 — 수락하면 이 자리가 그대로 첫 일정이 되므로,
            // 트레이너는 여기서 무엇을 수락하는지 본다(#1873).
            label: request.slotStartsAt == null
                ? l.consultPreferredTime
                : l.consultChosenSlot,
            value: _slotLabel(l, request),
          ),
          if (request.message != null)
            _Field(
              label: l.consultMessage,
              value: request.message!,
              bold: false,
            ),
          // 상태는 이제 위 태그가 말한다 — 거절 사유만 있으면 별도로
          // 덧붙인다(회원에게 보낸 알림 본문과 같은 문구).
          if (request.status == 'rejected' &&
              (request.decisionNote?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            _Field(label: l.consultDecisionNote, value: request.decisionNote!),
          ],
          if (request.isPending) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s16),
            Row(
              children: <Widget>[
                const Spacer(),
                // 거절은 사유를 받는 확인창을 연다. 빨간 글자만 있던 때에는 옆
                // `승인` 과 모양이 달라, 흰 카드 위 네이비 외곽선으로 짝을
                // 맞춘다(#2184). 위험 색은 확인창의 확정 버튼이 맡는다.
                AppButton(
                  key: ValueKey<String>('consultation-reject-${request.id}'),
                  label: l.consultReject,
                  variant: AppButtonVariant.strongOutline,
                  size: OnCareButtonSize.small,
                  onPressed: _busy ? null : _reject,
                ),
                const SizedBox(width: OnCareSpacing.buttonGap),
                AppButton(
                  key: ValueKey<String>('consultation-accept-${request.id}'),
                  label: l.consultApprove,
                  size: OnCareButtonSize.small,
                  onPressed: _busy ? null : _accept,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Rejection reason. Optional — a trainer who is simply full should not
/// have to compose a sentence, but the field is offered because the member
/// receives whatever is written here as their notification body.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppDialog(
      title: l.consultRejectTitle,
      size: AppDialogSize.medium,
      footer: AppButtonPair(
        cancelKey: const ValueKey<String>('consultation-reject-cancel'),
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('consultation-reject-confirm'),
        confirmLabel: l.consultReject,
        destructive: true,
        // Returns '' rather than null when left blank: null is the
        // cancel signal, and an empty note is a valid "no reason given".
        onConfirm: () => Navigator.of(context).pop(_controller.text.trim()),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l.consultRejectNotice),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('consultation-reject-reason'),
            controller: _controller,
            hint: l.consultRejectHint,
            maxLength: 500,
            minLines: 3,
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

/// 승인·거절 — 카드 우측 상단에 톤으로 구분해 붙인다.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  /// `pending` | `accepted` | `rejected`.
  final String status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final (String label, AppTagTone tone) = switch (status) {
      'accepted' => (l.consultStatusAccepted, AppTagTone.success),
      'rejected' => (l.consultStatusRejected, AppTagTone.danger),
      // 시간 안에 확인하지 못해 자리가 풀린 요청 — 거절(판단)과 구분한다(#1873).
      'expired' => (l.consultStatusExpired, AppTagTone.neutral),
      _ => (l.consultStatusPending, AppTagTone.caution),
    };
    return AppTag(label: label, tone: tone);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.bold = true});

  final String label;
  final String value;

  /// 문의 내용처럼 회원이 직접 쓴 글은 다른 항목과 굵기를 맞추지 않는다 —
  /// 원문 그대로라는 느낌을 남긴다.
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _fieldLabelWidth,
            child: Text(
              label,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: tokens
                  .text(
                    bold
                        ? OnCareTypography.strong(OnCareTypography.bodySmall)
                        : OnCareTypography.bodySmall,
                  )
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
