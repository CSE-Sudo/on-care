import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/not_found_page.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/admin/data/repositories/admin_trainer_repository.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_report.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
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

/// 신고·계정 관리 — 운영자가 회원의 트레이너 신고를 처리하고 계정을 정지·해제한다
/// (#3008).
///
/// 트레이너 승인 절차는 없다. 트레이너는 가입하고 소속을 고르면 바로 회원 앱에
/// 나오므로, 운영자는 사후에 들어온 신고를 보고 판단한다.
///
/// 상담 요청함과 같은 짜임이다: 머리의 갈래 토글(신고·트레이너), 상태 칩, 한 건씩
/// 카드, 카드 아래 동작 줄, 결정은 확인창을 거친다.
///
/// 운영자가 아니면 주소로 열어도 찾을 수 없음 안내만 보인다 — 메뉴도 없다.
class AdminReportsPage extends ConsumerWidget {
  /// Creates the admin page.
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(adminConsoleEnabledProvider)) {
      return const NotFoundBody();
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final AdminSection section = ref.watch(adminSectionProvider);
    final bool loading = section == AdminSection.reports
        ? ref.watch(adminReportsProvider).isLoading
        : ref.watch(adminTrainersProvider).isLoading;

    return AppWebPage(
      key: const ValueKey<String>('admin-reports-page'),
      title: l.adminReportsTitle,
      subtitle: l.adminReportsSubtitle,
      width: AppWebPageWidth.narrow,
      actions: <Widget>[
        AppButton(
          key: const ValueKey<String>('admin-refresh'),
          label: l.adminRefresh,
          leadingIcon: AppIcons.refresh,
          variant: AppButtonVariant.secondary,
          onPressed: loading
              ? null
              : () {
                  ref.invalidate(adminReportsProvider);
                  ref.invalidate(adminTrainersProvider);
                },
        ),
      ],
      body: PageScrollResetListener(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppSegmentedToggle<AdminSection>(
                key: const ValueKey<String>('admin-section'),
                expand: true,
                style: AppSegmentedToggleStyle.thumb,
                selected: section,
                onChanged: (AdminSection next) =>
                    ref.read(adminSectionProvider.notifier).state = next,
                segments: <AppSegment<AdminSection>>[
                  AppSegment<AdminSection>(
                    value: AdminSection.reports,
                    label: l.adminSectionReports,
                    icon: AppIcons.attention,
                  ),
                  AppSegment<AdminSection>(
                    value: AdminSection.trainers,
                    label: l.adminSectionTrainers,
                    icon: AppIcons.person,
                  ),
                ],
              ),
              const SizedBox(height: OnCareSpacing.s16),
              if (section == AdminSection.reports)
                const _ReportsSection()
              else
                const _TrainersSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 신고
// ---------------------------------------------------------------------------

class _ReportsSection extends ConsumerWidget {
  const _ReportsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AdminReportFilter filter = ref.watch(adminReportFilterProvider);
    final AsyncValue<List<AdminTrainerReport>> rows = ref.watch(
      adminReportsProvider,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ChipRow<AdminReportFilter>(
          keyPrefix: 'admin-report-filter',
          values: AdminReportFilter.values,
          selected: filter,
          label: (AdminReportFilter f) => adminReportFilterLabel(l, f),
          name: (AdminReportFilter f) => f.name,
          onSelected: (AdminReportFilter f) =>
              ref.read(adminReportFilterProvider.notifier).state = f,
        ),
        const SizedBox(height: OnCareSpacing.s16),
        rows.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (Object error, _) => AppErrorState(
            key: const ValueKey<String>('admin-reports-error'),
            placement: AppStatePlacement.card,
            title: l.adminReportsLoadFailed,
            message: serverDetailOr(
              l,
              error is AppError ? error.message : null,
              l.adminActionRetryLater,
            ),
            retryLabel: l.actionRetry,
            onRetry: () => ref.invalidate(adminReportsProvider),
          ),
          data: (List<AdminTrainerReport> list) => list.isEmpty
              ? AppEmptyState(
                  key: const ValueKey<String>('admin-reports-empty'),
                  placement: AppStatePlacement.card,
                  icon: AppIcons.attention,
                  title: filter == AdminReportFilter.open
                      ? l.adminReportsEmptyOpen
                      : l.adminReportsEmpty,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final AdminTrainerReport report in list) ...<Widget>[
                      AdminReportCard(
                        key: ValueKey<String>('admin-report-${report.id}'),
                        report: report,
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// 신고 칩 라벨.
String adminReportFilterLabel(AppLocalizations l, AdminReportFilter filter) =>
    switch (filter) {
      AdminReportFilter.open => l.adminReportFilterOpen,
      AdminReportFilter.closed => l.adminReportFilterClosed,
      AdminReportFilter.all => l.adminFilterAll,
    };

/// 신고 사유 라벨.
String adminReportReasonLabel(AppLocalizations l, AdminReportReason reason) =>
    switch (reason) {
      AdminReportReason.impersonation => l.adminReasonImpersonation,
      AdminReportReason.inappropriateMessage =>
        l.adminReasonInappropriateMessage,
      AdminReportReason.other => l.adminReasonOther,
    };

/// 신고 한 건. 대상·사유·내용과 처리(조치함·넘김)·계정 정지 동작을 한 카드에 둔다.
class AdminReportCard extends ConsumerStatefulWidget {
  /// Creates a card for [report].
  const AdminReportCard({required this.report, super.key});

  /// 보여 줄 신고.
  final AdminTrainerReport report;

  @override
  ConsumerState<AdminReportCard> createState() => _AdminReportCardState();
}

class _AdminReportCardState extends ConsumerState<AdminReportCard>
    with _AdminRunner<AdminReportCard> {
  @override
  String get trainerId => widget.report.trainerId;

  @override
  String trainerName(AppLocalizations l) => widget.report.trainerName.isEmpty
      ? l.adminTrainerUnnamed
      : widget.report.trainerName;

  Future<void> _close(AdminReportOutcome outcome) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = trainerName(l);
    final bool resolve = outcome == AdminReportOutcome.resolved;
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: resolve ? l.adminResolveTitle(name) : l.adminDismissTitle(name),
      message: resolve ? l.adminResolveBody : l.adminDismissBody,
      confirmLabel: resolve ? l.adminResolve : l.adminDismiss,
      cancelLabel: l.actionCancel,
    );
    if (!ok || !mounted) return;
    await run((AdminTrainerRepository repo) async {
      await repo.closeReport(widget.report.id, outcome);
      return resolve ? l.adminReportResolved : l.adminReportDismissed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AdminTrainerReport r = widget.report;
    final String name = trainerName(l);
    final DateTime? createdAt = r.createdAt;
    final DateTime? resolvedAt = r.resolvedAt;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardHeader(
            name: name,
            tags: <Widget>[
              if (!r.trainerIsActive)
                AppTag(
                  key: ValueKey<String>('admin-report-suspended-${r.id}'),
                  label: l.adminStatusSuspended,
                  tone: AppTagTone.danger,
                ),
              AdminReportStatusTag(status: r.status),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _Field(label: l.adminFieldTarget, value: r.trainerEmail),
          _Field(
            label: l.adminFieldReason,
            value: adminReportReasonLabel(l, r.reason),
          ),
          if (r.memo.isNotEmpty) _Field(label: l.adminFieldMemo, value: r.memo),
          if (createdAt != null)
            _Field(
              label: l.adminFieldReportedAt,
              value: dateLabel(l, createdAt),
            ),
          if (resolvedAt != null && !r.isOpen)
            _Field(
              label: l.adminFieldResolvedAt,
              value: dateLabel(l, resolvedAt),
            ),
          const SizedBox(height: OnCareSpacing.s16),
          AppActionRow(
            leading: suspendButton(
              l,
              keySuffix: 'report-${r.id}',
              isActive: r.trainerIsActive,
            ),
            actions: <Widget>[
              if (r.isOpen) ...<Widget>[
                AppButton(
                  key: ValueKey<String>('admin-report-dismiss-${r.id}'),
                  label: l.adminDismiss,
                  variant: AppButtonVariant.strongOutline,
                  size: OnCareButtonSize.small,
                  onPressed: busy
                      ? null
                      : () => _close(AdminReportOutcome.dismissed),
                ),
                AppButton(
                  key: ValueKey<String>('admin-report-resolve-${r.id}'),
                  label: l.adminResolve,
                  size: OnCareButtonSize.small,
                  onPressed: busy
                      ? null
                      : () => _close(AdminReportOutcome.resolved),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 신고 처리 상태 태그 — 카드 우측 상단.
class AdminReportStatusTag extends StatelessWidget {
  /// Creates the tag.
  const AdminReportStatusTag({required this.status, super.key});

  /// 처리 상태.
  final AdminReportStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final (String label, AppTagTone tone) = switch (status) {
      AdminReportStatus.open => (l.adminReportFilterOpen, AppTagTone.caution),
      AdminReportStatus.resolved => (
        l.adminReportStatusResolved,
        AppTagTone.success,
      ),
      AdminReportStatus.dismissed => (
        l.adminReportStatusDismissed,
        AppTagTone.neutral,
      ),
    };
    return AppTag(label: label, tone: tone);
  }
}

// ---------------------------------------------------------------------------
// 트레이너
// ---------------------------------------------------------------------------

class _TrainersSection extends ConsumerStatefulWidget {
  const _TrainersSection();

  @override
  ConsumerState<_TrainersSection> createState() => _TrainersSectionState();
}

class _TrainersSectionState extends ConsumerState<_TrainersSection> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(adminTrainerQueryProvider),
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit(String value) =>
      ref.read(adminTrainerQueryProvider.notifier).state = value.trim();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AdminTrainerState state = ref.watch(adminTrainerStateProvider);
    final AsyncValue<List<AdminTrainer>> rows = ref.watch(
      adminTrainersProvider,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSearchField(
          key: const ValueKey<String>('admin-trainer-search'),
          controller: _search,
          hint: l.adminTrainerSearchHint,
          clearTooltip: l.searchClear,
          onSubmitted: _submit,
          // 지우기 버튼은 바로 전체로 돌아간다. 글자를 칠 때마다 서버를 부르지는
          // 않는다.
          onChanged: (String value) {
            if (value.isEmpty) _submit('');
          },
        ),
        const SizedBox(height: OnCareSpacing.s12),
        _ChipRow<AdminTrainerState>(
          keyPrefix: 'admin-trainer-state',
          values: AdminTrainerState.values,
          selected: state,
          label: (AdminTrainerState s) => adminTrainerStateLabel(l, s),
          name: (AdminTrainerState s) => s.name,
          onSelected: (AdminTrainerState s) =>
              ref.read(adminTrainerStateProvider.notifier).state = s,
        ),
        const SizedBox(height: OnCareSpacing.s16),
        rows.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
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
                  icon: AppIcons.person,
                  title: l.adminTrainersEmpty,
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
    );
  }
}

/// 트레이너 상태 칩 라벨.
String adminTrainerStateLabel(AppLocalizations l, AdminTrainerState state) =>
    switch (state) {
      AdminTrainerState.all => l.adminFilterAll,
      AdminTrainerState.active => l.adminStateActive,
      AdminTrainerState.suspended => l.adminStatusSuspended,
    };

/// 트레이너 한 명. 소속·처리 전 신고 수와 계정 정지·해제를 한 카드에 둔다.
class AdminTrainerCard extends ConsumerStatefulWidget {
  /// Creates a card for [trainer].
  const AdminTrainerCard({required this.trainer, super.key});

  /// 보여 줄 트레이너.
  final AdminTrainer trainer;

  @override
  ConsumerState<AdminTrainerCard> createState() => _AdminTrainerCardState();
}

class _AdminTrainerCardState extends ConsumerState<AdminTrainerCard>
    with _AdminRunner<AdminTrainerCard> {
  @override
  String get trainerId => widget.trainer.trainerId;

  @override
  String trainerName(AppLocalizations l) =>
      widget.trainer.name.isEmpty ? l.adminTrainerUnnamed : widget.trainer.name;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AdminTrainer t = widget.trainer;
    final DateTime? createdAt = t.createdAt;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardHeader(
            name: trainerName(l),
            tags: <Widget>[
              if (t.openReports > 0)
                AppTag(
                  key: ValueKey<String>('admin-open-reports-${t.trainerId}'),
                  label: l.adminOpenReportsCount(t.openReports),
                  tone: AppTagTone.caution,
                ),
              AppTag(
                label: t.isActive ? l.adminStateActive : l.adminStatusSuspended,
                tone: t.isActive ? AppTagTone.success : AppTagTone.danger,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _Field(label: l.adminFieldEmail, value: t.email),
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
          _Field(
            label: l.adminFieldOpenReports,
            value: l.adminOpenReportsCount(t.openReports),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppActionRow(
            leading: suspendButton(
              l,
              keySuffix: t.trainerId,
              isActive: t.isActive,
            ),
            actions: const <Widget>[],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 공통
// ---------------------------------------------------------------------------

/// 두 카드가 함께 쓰는 처리 흐름 — 처리 중 버튼 막기, 결과 알림, 목록 다시 읽기,
/// 계정 정지·해제 확인창.
mixin _AdminRunner<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// 처리 중에는 모든 버튼을 막는다 — 두 번 눌러 같은 요청이 겹치지 않게.
  bool busy = false;

  /// 정지·해제할 트레이너 계정 id.
  String get trainerId;

  /// 확인창·알림에 쓰는 이름.
  String trainerName(AppLocalizations l);

  /// [action] 을 돌리고 성공 문구를 띄운 뒤 두 목록을 다시 읽는다.
  ///
  /// 실패해도 다시 읽는다 — 다른 운영자가 먼저 처리했으면 카드가 그 상태를
  /// 따라가야 같은 버튼을 계속 누르지 않는다. 정지는 신고 카드의 정지 표시와
  /// 트레이너 목록 양쪽에 걸리므로 둘 다 다시 읽는다.
  Future<void> run(
    Future<String> Function(AdminTrainerRepository repo) action,
  ) async {
    setState(() => busy = true);
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
      ref
        ..invalidate(adminReportsProvider)
        ..invalidate(adminTrainersProvider);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _suspend() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = trainerName(l);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.adminSuspendTitle(name),
      message: l.adminSuspendBody,
      confirmLabel: l.adminSuspend,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await run((AdminTrainerRepository repo) async {
      final AdminUserStatus result = await repo.suspend(trainerId);
      return result.releasedClients > 0
          ? l.adminSuspendedReleased(name, result.releasedClients)
          : l.adminSuspended(name);
    });
  }

  Future<void> _unsuspend() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = trainerName(l);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.adminUnsuspendTitle(name),
      message: l.adminUnsuspendBody,
      confirmLabel: l.adminUnsuspend,
      cancelLabel: l.actionCancel,
    );
    if (!ok || !mounted) return;
    await run((AdminTrainerRepository repo) async {
      await repo.unsuspend(trainerId);
      return l.adminUnsuspended(name);
    });
  }

  /// 카드 왼쪽 아래의 `계정 정지`·`정지 해제`.
  Widget suspendButton(
    AppLocalizations l, {
    required String keySuffix,
    required bool isActive,
  }) => isActive
      ? AppButton(
          key: ValueKey<String>('admin-suspend-$keySuffix'),
          label: l.adminSuspend,
          variant: AppButtonVariant.destructiveText,
          size: OnCareButtonSize.small,
          onPressed: busy ? null : _suspend,
        )
      : AppButton(
          key: ValueKey<String>('admin-unsuspend-$keySuffix'),
          label: l.adminUnsuspend,
          variant: AppButtonVariant.text,
          size: OnCareButtonSize.small,
          onPressed: busy ? null : _unsuspend,
        );
}

/// 상태 칩 줄 — 상담 요청함의 `전체 / 대기 N` 칩과 같은 부품이다.
class _ChipRow<V> extends StatelessWidget {
  const _ChipRow({
    required this.keyPrefix,
    required this.values,
    required this.selected,
    required this.label,
    required this.name,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<V> values;
  final V selected;
  final String Function(V) label;
  final String Function(V) name;
  final ValueChanged<V> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final V value in values)
            Padding(
              padding: const EdgeInsets.only(right: OnCareSpacing.s8),
              child: AppChoiceChip(
                key: ValueKey<String>('$keyPrefix-${name(value)}'),
                label: label(value),
                selected: value == selected,
                onSelected: (_) => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

/// 카드 머리 — 아바타·이름·오른쪽 태그.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.name, required this.tags});

  final String name;
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
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
        for (int i = 0; i < tags.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: OnCareSpacing.s4),
          tags[i],
        ],
      ],
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
