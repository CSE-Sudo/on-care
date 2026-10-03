import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/not_found_page.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/admin/data/repositories/admin_trainer_repository.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 카드 필드 라벨 열 폭 — 상담 요청 카드와 같은 폭이다.
const double _fieldLabelWidth = 84;

/// 이 세션이 운영 화면을 열 수 있는가 (#3008).
///
/// 실서버 로그인 세션이고 `GET /trainer/me` 의 `is_admin` 이 참일 때만이다. 데모
/// 프로필은 운영자가 아니다. 실제 권한은 서버가 `/admin/*` 에서 따로 확인한다.
final adminConsoleEnabledProvider = Provider<bool>((ref) {
  final SessionState session = ref.watch(sessionControllerProvider);
  return session.status == SessionStatus.authenticated &&
      (session.profile?.isAdmin ?? false);
}, name: 'adminConsoleEnabled');

/// 트레이너 승인 — 운영자가 가입한 트레이너를 승인·반려하고 계정을 정지한다
/// (#3008·#3009).
///
/// 상담 요청함과 같은 짜임이다: 머리의 상태 칩, 한 사람씩 카드, 카드 아래 동작
/// 줄, 결정은 확인창을 거친다. 반려는 사유를 받는 창이다 — 사유는 트레이너 웹
/// 배너와 알림 본문에 그대로 보인다.
///
/// 운영자가 아니면 주소로 열어도 찾을 수 없음 안내만 보인다 — 메뉴도 없다.
class AdminTrainersPage extends ConsumerWidget {
  /// Creates the admin review page.
  const AdminTrainersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(adminConsoleEnabledProvider)) {
      return const NotFoundBody();
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final AdminTrainerFilter filter = ref.watch(adminTrainerFilterProvider);
    final AsyncValue<List<AdminTrainer>> rows = ref.watch(
      adminTrainersProvider,
    );

    return AppWebPage(
      key: const ValueKey<String>('admin-trainers-page'),
      title: l.adminTrainersTitle,
      subtitle: l.adminTrainersSubtitle,
      width: AppWebPageWidth.narrow,
      actions: <Widget>[
        AppButton(
          key: const ValueKey<String>('admin-trainers-refresh'),
          label: l.adminRefresh,
          leadingIcon: AppIcons.refresh,
          variant: AppButtonVariant.secondary,
          onPressed: rows.isLoading
              ? null
              : () => ref.invalidate(adminTrainersProvider),
        ),
      ],
      body: PageScrollResetListener(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _FilterChips(selected: filter),
              const SizedBox(height: OnCareSpacing.s16),
              rows.when(
                loading: () =>
                    const AppLoading(placement: AppStatePlacement.card),
                error: (Object error, _) => AppErrorState(
                  key: const ValueKey<String>('admin-trainers-error'),
                  placement: AppStatePlacement.card,
                  title: l.adminTrainersLoadFailed,
                  message: serverDetailOr(
                    l,
                    error is AppError ? error.message : null,
                    l.adminActionRetryLater,
                  ),
                  retryLabel: l.actionRetry,
                  onRetry: () => ref.invalidate(adminTrainersProvider),
                ),
                data: (List<AdminTrainer> list) => list.isEmpty
                    ? AppEmptyState(
                        key: const ValueKey<String>('admin-trainers-empty'),
                        placement: AppStatePlacement.card,
                        icon: AppIcons.verified,
                        title: filter == AdminTrainerFilter.pending
                            ? l.adminTrainersEmptyPending
                            : l.adminTrainersEmpty,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final AdminTrainer trainer in list) ...<Widget>[
                            AdminTrainerCard(
                              key: ValueKey<String>(
                                'admin-trainer-${trainer.trainerId}',
                              ),
                              trainer: trainer,
                            ),
                            const SizedBox(height: OnCareSpacing.cardGap),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 승인 대기·승인·반려·전체 칩 — 상담 요청함의 `전체 / 대기 N` 칩과 같은 부품이다.
class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.selected});

  final AdminTrainerFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final AdminTrainerFilter filter in AdminTrainerFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: OnCareSpacing.s8),
              child: AppChoiceChip(
                key: ValueKey<String>('admin-filter-${filter.name}'),
                label: adminFilterLabel(l, filter),
                selected: filter == selected,
                onSelected: (_) =>
                    ref.read(adminTrainerFilterProvider.notifier).state =
                        filter,
              ),
            ),
        ],
      ),
    );
  }
}

/// 칩 라벨.
String adminFilterLabel(AppLocalizations l, AdminTrainerFilter filter) =>
    switch (filter) {
      AdminTrainerFilter.pending => l.adminStatusPending,
      AdminTrainerFilter.approved => l.adminStatusApproved,
      AdminTrainerFilter.rejected => l.adminStatusRejected,
      AdminTrainerFilter.all => l.adminFilterAll,
    };

/// 트레이너 한 명. 판단에 쓰는 값과 승인·반려·정지 동작을 한 카드에 둔다.
class AdminTrainerCard extends ConsumerStatefulWidget {
  /// Creates a card for [trainer].
  const AdminTrainerCard({required this.trainer, super.key});

  /// 보여 줄 트레이너.
  final AdminTrainer trainer;

  @override
  ConsumerState<AdminTrainerCard> createState() => _AdminTrainerCardState();
}

class _AdminTrainerCardState extends ConsumerState<AdminTrainerCard> {
  /// 처리 중에는 모든 버튼을 막는다 — 두 번 눌러 같은 요청이 겹치지 않게.
  bool _busy = false;

  String _name(AppLocalizations l) =>
      widget.trainer.name.isEmpty ? l.adminTrainerUnnamed : widget.trainer.name;

  /// [action] 을 돌리고 성공 문구 [success] 를 띄운 뒤 목록을 다시 읽는다.
  ///
  /// 실패해도 다시 읽는다 — 다른 운영자가 먼저 처리했으면 카드가 그 상태를
  /// 따라가야 같은 버튼을 계속 누르지 않는다.
  Future<void> _run(
    Future<String> Function(AdminTrainerRepository repo) action,
  ) async {
    setState(() => _busy = true);
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      final String success = await action(
        ref.read(adminTrainerRepositoryProvider),
      );
      if (!mounted) return;
      showAppToast(context, success, type: AppToastType.success);
    } on AppError catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        serverDetailOr(l, e.message, l.adminActionFailed),
        type: AppToastType.error,
      );
    } finally {
      ref.invalidate(adminTrainersProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = _name(l);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.adminApproveTitle(name),
      message: widget.trainer.hasGym && widget.trainer.gymIsFitness
          ? l.adminApproveBody
          : '${l.adminApproveBody}\n${l.adminGymNotListed}',
      confirmLabel: l.adminApprove,
      cancelLabel: l.actionCancel,
    );
    if (!ok || !mounted) return;
    await _run((AdminTrainerRepository repo) async {
      await repo.approve(widget.trainer.trainerId);
      return l.adminApproved(name);
    });
  }

  Future<void> _reject() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = _name(l);
    final String? reason = await showAppDialog<String?>(
      context: context,
      builder: (_) => AdminRejectDialog(trainerName: name),
    );
    if (reason == null || !mounted) return;
    await _run((AdminTrainerRepository repo) async {
      await repo.reject(widget.trainer.trainerId, reason: reason);
      return l.adminRejected(name);
    });
  }

  Future<void> _suspend() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = _name(l);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.adminSuspendTitle(name),
      message: l.adminSuspendBody,
      confirmLabel: l.adminSuspend,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run((AdminTrainerRepository repo) async {
      final AdminUserStatus result = await repo.suspend(
        widget.trainer.trainerId,
      );
      return result.releasedClients > 0
          ? l.adminSuspendedReleased(name, result.releasedClients)
          : l.adminSuspended(name);
    });
  }

  Future<void> _unsuspend() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = _name(l);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.adminUnsuspendTitle(name),
      message: l.adminUnsuspendBody,
      confirmLabel: l.adminUnsuspend,
      cancelLabel: l.actionCancel,
    );
    if (!ok || !mounted) return;
    await _run((AdminTrainerRepository repo) async {
      await repo.unsuspend(widget.trainer.trainerId);
      return l.adminUnsuspended(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AdminTrainer t = widget.trainer;
    final String name = _name(l);
    final String id = t.trainerId;
    final DateTime? createdAt = t.createdAt;
    final DateTime? decidedAt = t.decidedAt;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClientAvatar(name: name.characters.first),
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
              if (!t.isActive) ...<Widget>[
                AppTag(
                  key: ValueKey<String>('admin-suspended-$id'),
                  label: l.adminStatusSuspended,
                  tone: AppTagTone.danger,
                ),
                const SizedBox(width: OnCareSpacing.s4),
              ],
              AdminStatusTag(status: t.status),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _Field(label: l.adminFieldEmail, value: t.email),
          _Field(
            label: l.adminFieldSpecialty,
            value: t.specialty.isEmpty ? l.adminValueNone : t.specialty,
          ),
          _Field(
            label: l.adminFieldCareer,
            value: l.myCareerYears(t.careerYears),
          ),
          _Field(
            label: l.adminFieldCertifications,
            value: t.certifications.isEmpty
                ? l.adminValueNone
                : t.certifications.join(', '),
          ),
          _Field(
            label: l.adminFieldGym,
            value: t.hasGym
                ? (t.gymAddress.isEmpty
                      ? t.gymName
                      : '${t.gymName}\n${t.gymAddress}')
                : l.adminGymNone,
          ),
          if (createdAt != null)
            _Field(label: l.adminFieldSignedUp, value: dateLabel(l, createdAt)),
          if (decidedAt != null &&
              t.status != TrainerVerificationStatus.pending)
            _Field(label: l.adminFieldDecided, value: dateLabel(l, decidedAt)),
          if (t.status == TrainerVerificationStatus.rejected &&
              t.note.isNotEmpty)
            _Field(label: l.adminFieldNote, value: t.note),
          // 소속이 없거나 헬스장이 아니면 승인해도 회원 앱에 나오지 않는다 —
          // 승인하기 전에 그 사실을 본다.
          if (!t.hasGym || !t.gymIsFitness) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            AppBanner(
              key: ValueKey<String>('admin-gym-warning-$id'),
              title: t.hasGym ? l.adminGymNotFitness : l.adminGymNone,
              message: l.adminGymNotListed,
              icon: AppIcons.warning,
              tone: AppBannerTone.caution,
            ),
          ],
          const SizedBox(height: OnCareSpacing.s16),
          AppActionRow(
            leading: t.isActive
                ? AppButton(
                    key: ValueKey<String>('admin-suspend-$id'),
                    label: l.adminSuspend,
                    variant: AppButtonVariant.destructiveText,
                    size: OnCareButtonSize.small,
                    onPressed: _busy ? null : _suspend,
                  )
                : AppButton(
                    key: ValueKey<String>('admin-unsuspend-$id'),
                    label: l.adminUnsuspend,
                    variant: AppButtonVariant.text,
                    size: OnCareButtonSize.small,
                    onPressed: _busy ? null : _unsuspend,
                  ),
            actions: <Widget>[
              if (t.canReject)
                AppButton(
                  key: ValueKey<String>('admin-reject-$id'),
                  label: l.adminReject,
                  variant: AppButtonVariant.strongOutline,
                  size: OnCareButtonSize.small,
                  onPressed: _busy ? null : _reject,
                ),
              if (t.canApprove)
                AppButton(
                  key: ValueKey<String>('admin-approve-$id'),
                  label: l.adminApprove,
                  size: OnCareButtonSize.small,
                  onPressed: _busy ? null : _approve,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 승인 상태 태그 — 카드 우측 상단.
class AdminStatusTag extends StatelessWidget {
  /// Creates the tag.
  const AdminStatusTag({required this.status, super.key});

  /// 승인 상태.
  final TrainerVerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final (String label, AppTagTone tone) = switch (status) {
      TrainerVerificationStatus.pending => (
        l.adminStatusPending,
        AppTagTone.caution,
      ),
      TrainerVerificationStatus.approved => (
        l.adminStatusApproved,
        AppTagTone.success,
      ),
      TrainerVerificationStatus.rejected => (
        l.adminStatusRejected,
        AppTagTone.danger,
      ),
    };
    return AppTag(label: label, tone: tone);
  }
}

/// 반려 사유 창. 사유는 비워도 된다 — 비우면 트레이너 알림이 MY 확인을 안내한다.
///
/// 확정하면 다듬은 사유(빈 문자열 가능)를, 취소하면 `null` 을 돌려준다.
class AdminRejectDialog extends StatefulWidget {
  /// Creates the dialog for [trainerName].
  const AdminRejectDialog({required this.trainerName, super.key});

  /// 제목에 쓰는 트레이너 이름.
  final String trainerName;

  @override
  State<AdminRejectDialog> createState() => _AdminRejectDialogState();
}

class _AdminRejectDialogState extends State<AdminRejectDialog> {
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
      title: l.adminRejectTitle(widget.trainerName),
      size: AppDialogSize.medium,
      footer: AppButtonPair(
        cancelKey: const ValueKey<String>('admin-reject-cancel'),
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('admin-reject-confirm'),
        confirmLabel: l.adminReject,
        destructive: true,
        onConfirm: () => Navigator.of(context).pop(_controller.text.trim()),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l.adminRejectBody),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('admin-reject-reason'),
            controller: _controller,
            hint: l.adminRejectHint,
            maxLength: kTrainerRejectReasonMaxLength,
            showCounter: true,
            minLines: 3,
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
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
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
