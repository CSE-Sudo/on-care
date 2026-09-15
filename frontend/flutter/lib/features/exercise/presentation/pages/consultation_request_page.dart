import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/consult_time_range_picker.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

enum _ExerciseGoal { weightLoss, strength, fitness, posture, health, other }

// 화면 선택지 → 서버 계약 enum. 순서가 같으므로 index 로 잇되, 길이가 어긋나면
// 조용히 틀린 값이 나가므로 아래 assert 로 막는다.
extension on _ExerciseGoal {
  ExerciseGoal get wire => ExerciseGoal.values[index];
}

/// 필드 위 제목 — 섹션 제목 역할 글자.
TextStyle _fieldTitleStyle(BuildContext context) => context.oncare
    .text(OnCareTypography.titleSmall)
    .copyWith(color: OnCareColors.textPrimary);

class ConsultationRequestPage extends ConsumerStatefulWidget {
  const ConsultationRequestPage({
    required this.gymId,
    required this.trainerId,
    super.key,
  });

  final String gymId;

  /// 상담을 받을 트레이너. 폐지된 헬스장 대상 링크로 들어오면 비어 있고, 그때는
  /// 폼 대신 "대상을 찾을 수 없음"을 띄운다.
  final String? trainerId;

  @override
  ConsumerState<ConsultationRequestPage> createState() =>
      _ConsultationRequestPageState();
}

class _ConsultationRequestPageState
    extends ConsumerState<ConsultationRequestPage> {
  final TextEditingController _messageController = TextEditingController();

  _ExerciseGoal? _exerciseGoal;
  DateTime? _preferredDate;

  /// 희망 시각은 시작·종료가 모두 있어야 한다 — "시간 협의"는 없앴다(#1587).
  /// 시각이 비어 있으면 트레이너가 승인해도 잡을 시간이 없어, 승인만 되고
  /// 상담 일정은 만들어지지 않는 반쪽 상태가 남았다.
  TimeOfDay? _preferredTimeOfDay;
  TimeOfDay? _preferredEndTimeOfDay;
  bool _attempted = false;
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Gym? _findGym(List<Gym> gyms) {
    for (final Gym gym in gyms) {
      if (gym.id == widget.gymId) return gym;
    }
    return null;
  }

  Future<void> _selectDate() async {
    final DateTime today = DateUtils.dateOnly(nowKst());
    final DateTime? selected = await showAppDatePicker(
      context: context,
      initialDate: _preferredDate ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 100),
    );
    if (selected != null && mounted) {
      setState(() => _preferredDate = selected);
    }
  }

  /// 시작과 종료 시각을 차례로 고른다. 두 앱이 같은 공용 시간 선택기로
  /// 정확한 범위를 입력한다.
  Future<void> _selectTime() async {
    final TimeRangeValue? picked = await showConsultTimeRangePicker(
      context: context,
      start: _preferredTimeOfDay ?? const TimeOfDay(hour: 10, minute: 0),
      end:
          _preferredEndTimeOfDay ??
          TimeOfDay(
            hour: (_preferredTimeOfDay?.hour ?? 10) + 1,
            minute: _preferredTimeOfDay?.minute ?? 0,
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preferredTimeOfDay = picked.start;
      _preferredEndTimeOfDay = picked.end;
    });
  }

  /// 운동 목표가 "기타"면 문의 내용에 구체적으로 적어야 한다 — 그 내용이
  /// 서버로는 `health_purpose_detail`도 겸해서 나간다(#1112). 목표 선택
  /// 하나로 줄었으니 상세를 받을 자리도 문의 내용 하나여야 한다.
  bool get _otherGoalDetailMissing =>
      _exerciseGoal == _ExerciseGoal.other &&
      _messageController.text.trim().isEmpty;

  /// 데이터 공유에 동의했는가. 신청은 회원이 하고 연결은 나중에 트레이너가
  /// 수락하며 만들어진다 — 회원이 그 자리에 없으므로 동의는 여기서 받는다.
  /// (#1022)
  bool _dataSharingConsent = false;

  bool get _isValid =>
      _exerciseGoal != null &&
      !_otherGoalDetailMissing &&
      _preferredDate != null &&
      _preferredTimeOfDay != null &&
      _preferredEndTimeOfDay != null &&
      _dataSharingConsent;

  Future<void> _submit({
    required Gym gym,
    required Trainer trainer,
    required Map<_ExerciseGoal, String> goalLabels,
  }) async {
    if (_submitting) return;
    setState(() => _attempted = true);
    if (!_isValid) return;

    final controller = ref.read(consultationRequestControllerProvider.notifier);
    if (controller.hasPending(trainerId: trainer.id)) {
      return;
    }

    setState(() => _submitting = true);
    final DateTime now = nowKst();
    final String message = _messageController.text.trim();
    final ExerciseGoal exerciseGoal = _exerciseGoal!.wire;
    final HealthPurposeType healthPurposeType = healthPurposeFromExerciseGoal(
      exerciseGoal,
    );
    // "기타"만 상세가 필요하다(서버 422 회피) — 그 상세는 문의 내용
    // 그대로다. 나머지 목표는 매핑된 종류만으로 뜻이 충분하다.
    final String? healthPurposeDetail =
        healthPurposeType == HealthPurposeType.other ? message : null;
    final PreferredTime preferredTime = PreferredTime.range(
      _preferredTimeOfDay!,
      _preferredEndTimeOfDay!,
    );
    final ConsultationRequest request = ConsultationRequest(
      id: 'consult-${now.microsecondsSinceEpoch}',
      trainerId: trainer.id,
      trainerName: trainer.name,
      trainerRole: trainer.role,
      trainerGymName: gym.name,
      // 라벨이 아니라 계약 enum 을 담는다 — 라벨을 저장하면 서버에서 복원할 때
      // 문구를 만들 수 없다(#327).
      exerciseGoal: exerciseGoal,
      healthPurposeType: healthPurposeType,
      healthPurposeDetail: healthPurposeDetail,
      preferredDate: _preferredDate!,
      preferredTimeSlot: preferredTime,
      message: message.isEmpty ? null : message,
      status: ConsultationStatus.pending,
      createdAt: now,
    );
    final ConsultationDraft draft = ConsultationDraft(
      trainerId: trainer.id,
      exerciseGoal: exerciseGoal,
      healthPurposeType: healthPurposeType,
      healthPurposeDetail: healthPurposeDetail,
      preferredDate: _preferredDate!,
      preferredTimeSlot: preferredTime,
      message: message.isEmpty ? null : message,
      dataSharingConsent: _dataSharingConsent,
    );

    final ConsultationRequest? saved;
    try {
      saved = await controller.submit(draft: draft, display: request);
    } on Object {
      // 409 외의 실패(네트워크 등)를 잡지 않으면 _submitting 이 true 로 남아
      // 제출 버튼이 영영 눌리지 않는다(리뷰 지적).
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(
        context,
        AppLocalizations.of(context).errorUnknown,
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    if (saved == null) {
      setState(() => _submitting = false);
      return;
    }
    context.replace(AppRoutes.consultationComplete, extra: saved);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<Gym>> nearbyAsync = ref.watch(nearbyGymsProvider);
    final AsyncValue<Gym?> myGymAsync = ref.watch(myGymProvider);
    final List<ConsultationRequest> requests = ref.watch(
      consultationRequestControllerProvider,
    );

    final Gym? nearbyGym = switch (nearbyAsync) {
      AsyncData<List<Gym>>(:final value) => _findGym(value),
      _ => null,
    };
    final Gym? myGym = switch (myGymAsync) {
      AsyncData<Gym?>(:final value) when value?.id == widget.gymId => value,
      _ => null,
    };
    final Gym? gym = nearbyGym ?? myGym;
    final bool hasTrainerId = (widget.trainerId ?? '').isNotEmpty;
    // 대상 트레이너를 id 로 직접 읽는다.
    final AsyncValue<Trainer?> trainerAsync = hasTrainerId
        ? ref.watch(trainerProvider(widget.trainerId!))
        : const AsyncValue<Trainer?>.data(null);
    final Trainer? trainer = trainerAsync.valueOrNull;
    final bool targetIsValid = gym != null && trainer != null;

    final Widget body;
    if (targetIsValid) {
      final bool hasPending = requests.any(
        (ConsultationRequest request) =>
            request.trainerId == trainer.id &&
            request.status == ConsultationStatus.pending,
      );
      body = _buildForm(gym: gym, trainer: trainer, hasPending: hasPending);
    } else if (hasTrainerId && trainerAsync.isLoading) {
      body = const AppLoading();
    } else if (!hasTrainerId || widget.gymId.isEmpty || gym != null) {
      body = AppEmptyState(
        title: l.exConsultTargetNotFound,
        icon: Icons.info_rounded,
      );
    } else if (nearbyAsync.isLoading || myGymAsync.isLoading) {
      body = const AppLoading();
    } else if (nearbyAsync.hasError || myGymAsync.hasError) {
      body = AppErrorState(
        title: l.exGymsLoadError,
        retryLabel: l.actionRetry,
        onRetry: () {
          ref.invalidate(nearbyGymsProvider);
          ref.invalidate(myGymProvider);
        },
      );
    } else {
      body = AppEmptyState(
        title: l.exConsultTargetNotFound,
        icon: Icons.info_rounded,
      );
    }

    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: l.exConsultRequestTitle),
      body: SafeArea(top: false, child: body),
    );
  }

  Widget _buildForm({
    required Gym gym,
    required Trainer trainer,
    required bool hasPending,
  }) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final Map<_ExerciseGoal, String> goalLabels = <_ExerciseGoal, String>{
      _ExerciseGoal.weightLoss: l.exGoalWeightLoss,
      _ExerciseGoal.strength: l.exGoalStrength,
      _ExerciseGoal.fitness: l.exGoalFitness,
      _ExerciseGoal.posture: l.exGoalPosture,
      _ExerciseGoal.health: l.exGoalHealth,
      _ExerciseGoal.other: l.exOptionOther,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: OnCareLayout.mobileContentMaxWidth,
        ),
        child: ListView(
          // 폼이 한 화면보다 길다. 아래쪽 항목은 화면에 들어오기 전까지 만들어지지
          // 않으므로, E2E 가 이 목록을 잡고 스크롤할 수 있어야 한다. (#640)
          key: const Key('consult-form'),
          padding: const EdgeInsets.fromLTRB(
            OnCareSpacing.s20,
            OnCareSpacing.s16,
            OnCareSpacing.s20,
            OnCareSpacing.s32,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: <Widget>[
            _TargetCard(gym: gym, trainer: trainer),
            const SizedBox(height: OnCareSpacing.s12),
            _DataSharingNotice(
              consented: _dataSharingConsent,
              onChanged: (bool next) =>
                  setState(() => _dataSharingConsent = next),
              showRequired: _attempted && !_dataSharingConsent,
            ),
            const SizedBox(height: OnCareSpacing.s20),
            _ChoiceField<_ExerciseGoal>(
              chipKeyPrefix: 'consult-goal',
              title: l.exExerciseGoal,
              values: _ExerciseGoal.values,
              labels: goalLabels,
              selected: _exerciseGoal,
              onSelected: (_ExerciseGoal value) =>
                  setState(() => _exerciseGoal = value),
              errorText: _attempted && _exerciseGoal == null
                  ? l.exGoalRequired
                  : null,
            ),
            if (_exerciseGoal == _ExerciseGoal.other) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Text(
                l.exOtherGoalHint,
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ],
            const SizedBox(height: OnCareSpacing.s20),
            Text(l.exPreferredDate, style: _fieldTitleStyle(context)),
            const SizedBox(height: OnCareSpacing.s8),
            _PickerField(
              key: const Key('consult-date'),
              icon: Icons.calendar_today_rounded,
              text: _preferredDate == null
                  ? l.exSelectDate
                  : MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(_preferredDate!),
              filled: _preferredDate != null,
              onTap: _selectDate,
            ),
            if (_attempted && _preferredDate == null)
              _ErrorText(l.exDateRequired),
            const SizedBox(height: OnCareSpacing.s20),
            Text(l.exPreferredTime, style: _fieldTitleStyle(context)),
            const SizedBox(height: OnCareSpacing.s8),
            // 날짜 필드와 같은 자리·스타일이다 — 눌렀을 때 뜨는 게 날짜 대신
            // [showConsultTimeRangePicker]일 뿐이다(#1256). 옆에 나란히 서던
            // "시간 협의" 토글은 없앴다(#1587) — 값은 반드시 채워야 한다.
            _PickerField(
              key: const Key('consult-time'),
              icon: Icons.access_time_rounded,
              text: _timeText(context),
              filled: _preferredTimeOfDay != null,
              onTap: _selectTime,
            ),
            if (_attempted &&
                (_preferredTimeOfDay == null || _preferredEndTimeOfDay == null))
              _ErrorText(l.exTimeRequired),
            const SizedBox(height: OnCareSpacing.s20),
            Text(l.exConsultMessage, style: _fieldTitleStyle(context)),
            const SizedBox(height: OnCareSpacing.s8),
            AppTextField(
              key: const Key('consult-message'),
              controller: _messageController,
              onChanged: (_) => setState(() {}),
              minLines: 4,
              maxLines: 7,
              hint: l.exConsultMessageHint,
              errorText: _attempted && _otherGoalDetailMissing
                  ? l.exOtherGoalDetailRequired
                  : null,
            ),
            if (hasPending) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s16),
              AppBanner(title: l.exConsultPendingExists),
            ],
            const SizedBox(height: OnCareSpacing.s24),
            AppButton(
              key: const Key('consult-submit'),
              label: hasPending
                  ? l.exConsultPendingCta
                  : l.exSendConsultRequest,
              // 보내는 중에는 스피너를 띄우고 탭을 막는다(loading).
              onPressed: hasPending
                  ? null
                  : () => unawaited(
                      _submit(
                        gym: gym,
                        trainer: trainer,
                        goalLabels: goalLabels,
                      ),
                    ),
              loading: _submitting,
              size: OnCareButtonSize.large,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }

  String _timeText(BuildContext context) {
    final TimeOfDay? start = _preferredTimeOfDay;
    final TimeOfDay? end = _preferredEndTimeOfDay;
    if (start == null || end == null) {
      return AppLocalizations.of(context).exSelectTime;
    }
    final MaterialLocalizations m = MaterialLocalizations.of(context);
    return '${m.formatTimeOfDay(start, alwaysUse24HourFormat: true)}'
        '–${m.formatTimeOfDay(end, alwaysUse24HourFormat: true)}';
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.gym, required this.trainer});

  final Gym gym;
  final Trainer trainer;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.exConsultTarget,
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: tokens.brand.primary),
                ),
              ),
              AppTag(label: l.exTrainerConsultType, tone: AppTagTone.brand),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            trainer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens
                .text(OnCareTypography.titleSmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            trainer.role ?? l.exTrainerDedicated,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            '${l.exTrainerAffiliation} · ${gym.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// 이 요청이 수락되면 트레이너가 조회할 수 있게 되는 정보 범위 안내(#935).
///
/// 상담 요청 → 승인으로 `TrainerClient` 링크가 생기면(#467) 트레이너 웹은 담당
/// 회원의 식단·운동 기록과 신체 정보·목표를 그 즉시 조회할 수 있다(#316, #646,
/// #914). 지금까지는 이 화면 어디에도 그 사실이 적혀 있지 않아, 회원이 무엇에
/// 동의하는지 모른 채 요청을 보냈다. 문구는 실제 조회 범위와 일치시킨다 —
/// 여기 없는 항목(예: 혈압·혈당)은 애초에 수집하지 않으므로 트레이너도 볼 수
/// 없다.
class _DataSharingNotice extends StatelessWidget {
  const _DataSharingNotice({
    required this.consented,
    required this.onChanged,
    required this.showRequired,
  });

  /// 동의했는가. 이 값은 화면 상태(`_dataSharingConsent`)가 들고 있다 — 제출
  /// 가능 여부를 함께 판단해야 해서다. (#1022)
  final bool consented;
  final ValueChanged<bool> onChanged;

  /// 제출을 눌렀는데 아직 동의하지 않았는가 — 그때만 빨간 안내를 붙인다.
  final bool showRequired;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Container(
      key: const Key('consult-data-sharing-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(OnCareSpacing.s12),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.info_rounded,
                size: OnCareSize.iconSmall,
                color: OnCareColors.textSecondary,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  l.exConsultDataSharingNotice,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
            ],
          ),
          // 안내로 지나가지 않고 **동의를 받는다** — 수락되는 순간 넘어가는
          // 것은 회원의 건강 기록이다. (#1022)
          const SizedBox(height: OnCareSpacing.s4),
          InkWell(
            key: const Key('consultDataSharingConsent'),
            onTap: () => onChanged(!consented),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Checkbox(
                  value: consented,
                  onChanged: (bool? next) => onChanged(next ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: OnCareSpacing.s2),
                    child: Text(
                      l.exConsultDataSharingAgree,
                      style: tokens
                          .text(
                            OnCareTypography.strong(OnCareTypography.bodySmall),
                          )
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showRequired) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              l.exConsultDataSharingRequired,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceField<T> extends StatelessWidget {
  const _ChoiceField({
    required this.title,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.errorText,
    this.chipKeyPrefix,
    super.key,
  });

  final String title;
  final List<T> values;
  final Map<T, String> labels;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String? errorText;

  /// 칩마다 붙일 키의 앞자리. E2E 가 화면에 보이는 **문구 대신 자리**로 칩을 고를
  /// 수 있게 한다 — 문구는 번역이 바뀌면 흔들리고, 이 화면은 선택지가 많다. (#640)
  final String? chipKeyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: _fieldTitleStyle(context)),
        const SizedBox(height: OnCareSpacing.s8),
        Wrap(
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s8,
          children: <Widget>[
            for (final (int i, T value) in values.indexed)
              AppChoiceChip(
                key: chipKeyPrefix == null
                    ? null
                    : ValueKey<String>('$chipKeyPrefix-$i'),
                label: labels[value]!,
                selected: selected == value,
                onSelected: (_) => onSelected(value),
              ),
          ],
        ),
        if (errorText != null) _ErrorText(errorText!),
      ],
    );
  }
}

/// 눌러서 선택기를 여는 한 칸(희망 날짜·희망 시각). 입력창과 같은 채움·테두리다.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.text,
    required this.filled,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String text;

  /// 값이 골라졌는가 — 아니면 안내 문구를 옅게 쓴다.
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Material(
      color: OnCareColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: OnCareRadius.mdAll,
        side: BorderSide(color: OnCareColors.lineStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tokens.density.inputMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: OnCareSize.iconMedium,
                  color: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Text(
                    text,
                    style: filled
                        ? tokens
                              .text(
                                OnCareTypography.strong(OnCareTypography.body),
                              )
                              .copyWith(color: OnCareColors.textPrimary)
                        : tokens
                              .text(OnCareTypography.body)
                              .copyWith(color: OnCareColors.textTertiary),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: OnCareSize.iconMedium,
                  color: OnCareColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: OnCareSpacing.s8,
        left: OnCareSpacing.s4,
      ),
      child: Text(
        text,
        style: context.oncare
            .text(OnCareTypography.caption)
            .copyWith(color: OnCareColors.danger),
      ),
    );
  }
}
