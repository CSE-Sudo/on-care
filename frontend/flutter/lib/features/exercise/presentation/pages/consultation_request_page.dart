import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/utils/exercise_goal_label.dart';
import 'package:oncare/features/exercise/presentation/utils/gym_phone.dart';
import 'package:oncare/features/exercise/presentation/utils/slot_label.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 화면에 그릴 운동 목표 선택지. 온보딩·MY 의 건강 목표 8종을 `kHealthFocusOptions`
/// 에서 **그대로 읽고**, 그 뒤에 `기타` 를 붙인다 — 목록을 여기서 따로 들면 두
/// 화면이 다시 갈라진다(#1992).
///
/// 여덟 목표는 [ExerciseGoal.other] 와 달리 건강 목표로 1:1 로 이어져, 상담이
/// 수락되면 회원의 건강 목표가 빠짐없이 채워진다.
final List<ExerciseGoal> _kGoalChoices = <ExerciseGoal>[
  for (final String focus in kHealthFocusOptions)
    kHealthFocusExerciseGoals[focus]!,
  ExerciseGoal.other,
];

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

  ExerciseGoal? _exerciseGoal;

  /// 회원이 고른 트레이너의 빈 자리. 희망 시각을 적어 보내던 방식을 버렸다
  /// (#1873) — 회원이 적은 시각은 트레이너의 실제 달력과 아무 관계가 없어,
  /// 길이를 아무도 정하지 못하고 겹치면 승인 자체가 막혔다.
  String? _slotId;
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

  /// 운동 목표가 "기타"면 문의 내용에 구체적으로 적어야 한다 — 그 내용이
  /// 서버로는 `health_purpose_detail`도 겸해서 나간다(#1112). 목표 선택
  /// 하나로 줄었으니 상세를 받을 자리도 문의 내용 하나여야 한다.
  bool get _otherGoalDetailMissing =>
      _exerciseGoal == ExerciseGoal.other &&
      _messageController.text.trim().isEmpty;

  /// 데이터 공유에 동의했는가. 신청은 회원이 하고 연결은 나중에 트레이너가
  /// 수락하며 만들어진다 — 회원이 그 자리에 없으므로 동의는 여기서 받는다.
  /// (#1022)
  bool _dataSharingConsent = false;

  bool get _isValid =>
      _exerciseGoal != null &&
      !_otherGoalDetailMissing &&
      _slotId != null &&
      _dataSharingConsent;

  Future<void> _submit({
    required Gym gym,
    required Trainer trainer,
    required List<TrainerSlot> slots,
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
    final ExerciseGoal exerciseGoal = _exerciseGoal!;
    final HealthPurposeType healthPurposeType = healthPurposeFromExerciseGoal(
      exerciseGoal,
    );
    // "기타"만 상세가 필요하다(서버 422 회피) — 그 상세는 문의 내용
    // 그대로다. 나머지 목표는 매핑된 종류만으로 뜻이 충분하다.
    final String? healthPurposeDetail =
        healthPurposeType == HealthPurposeType.other ? message : null;
    final TrainerSlot slot = slots.firstWhere(
      (TrainerSlot s) => s.id == _slotId,
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
      // 고른 자리의 시각을 그대로 옮겨 적는다 — 서버도 같은 값을 돌려준다.
      preferredDate: slot.startsAt,
      preferredTimeSlot: PreferredTime.at(
        TimeOfDay.fromDateTime(slot.startsAt),
      ),
      slotStartsAt: slot.startsAt,
      slotDurationMinutes: slot.durationMinutes,
      message: message.isEmpty ? null : message,
      status: ConsultationStatus.pending,
      createdAt: now,
    );
    final ConsultationDraft draft = ConsultationDraft(
      trainerId: trainer.id,
      exerciseGoal: exerciseGoal,
      healthPurposeType: healthPurposeType,
      healthPurposeDetail: healthPurposeDetail,
      slotId: slot.id,
      message: message.isEmpty ? null : message,
      dataSharingConsent: _dataSharingConsent,
    );

    final ConsultationRequest? saved;
    try {
      saved = await controller.submit(draft: draft, display: request);
    } on ConsultationSlotTaken {
      // 다른 회원이 먼저 그 자리를 골랐다. 대기 중으로 표시하지 않고, 목록을 다시
      // 읽어 남은 자리 중에서 고르게 한다(#1873).
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _slotId = null;
      });
      ref.invalidate(consultationSlotsProvider(trainer.id));
      showAppToast(
        context,
        AppLocalizations.of(context).exConsultSlotTaken,
        type: AppToastType.error,
      );
      return;
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
        icon: AppIcons.info,
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
        icon: AppIcons.info,
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
    final Map<ExerciseGoal, String> goalLabels = <ExerciseGoal, String>{
      for (final ExerciseGoal goal in _kGoalChoices)
        goal: exerciseGoalLabel(l, goal),
    };
    final AsyncValue<List<TrainerSlot>> slotsAsync = ref.watch(
      consultationSlotsProvider(trainer.id),
    );
    final List<TrainerSlot> slots =
        slotsAsync.valueOrNull ?? const <TrainerSlot>[];
    // 자리가 하나도 없으면 신청할 수 없다 — 앱은 없는 시간을 만들어 내지 않고
    // 헬스장 전화로 내보낸다(#1873).
    final bool canSubmit = !hasPending && slots.isNotEmpty;

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
            _ChoiceField<ExerciseGoal>(
              chipKeyPrefix: 'consult-goal',
              title: l.exExerciseGoal,
              values: _kGoalChoices,
              labels: goalLabels,
              selected: _exerciseGoal,
              onSelected: (ExerciseGoal value) =>
                  setState(() => _exerciseGoal = value),
              errorText: _attempted && _exerciseGoal == null
                  ? l.exGoalRequired
                  : null,
            ),
            if (_exerciseGoal == ExerciseGoal.other) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Text(
                l.exOtherGoalHint,
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ],
            const SizedBox(height: OnCareSpacing.s20),
            // 회원이 희망 시각을 적어 보내던 두 칸(날짜·시각)을 걷어내고, 트레이너가
            // 열어 둔 자리를 고르게 한다(#1873). 시각을 정하는 사람이 하나가 되면서
            // 길이도 겹침도 자리가 이미 정해 둔 값이 된다.
            Text(l.exConsultSlotTitle, style: _fieldTitleStyle(context)),
            const SizedBox(height: OnCareSpacing.s8),
            _SlotField(
              slots: slotsAsync,
              selectedId: _slotId,
              onSelected: (String id) => setState(() => _slotId = id),
              onRetry: () =>
                  ref.invalidate(consultationSlotsProvider(trainer.id)),
              gym: gym,
            ),
            if (_attempted && slots.isNotEmpty && _slotId == null)
              _ErrorText(l.exConsultSlotRequired),
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
              onPressed: canSubmit
                  ? () => unawaited(
                      _submit(gym: gym, trainer: trainer, slots: slots),
                    )
                  : null,
              loading: _submitting,
              size: OnCareButtonSize.large,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// 트레이너가 열어 둔 빈 자리 목록. 회원은 여기서 하나를 고른다. (#1873)
///
/// 자리가 하나도 없으면 **없는 시간을 만들어 내지 않는다** — 헬스장 전화로
/// 내보내고 신청 버튼은 잠긴다. 트레이너가 자리를 열지 않으면 그것이 사실이다.
class _SlotField extends StatelessWidget {
  const _SlotField({
    required this.slots,
    required this.selectedId,
    required this.onSelected,
    required this.onRetry,
    required this.gym,
  });

  final AsyncValue<List<TrainerSlot>> slots;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onRetry;
  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return switch (slots) {
      AsyncLoading<List<TrainerSlot>>() => const Padding(
        padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
        child: AppLoading(),
      ),
      AsyncError<List<TrainerSlot>>() => AppErrorState(
        key: const Key('consult-slots-error'),
        title: l.exConsultSlotsError,
        retryLabel: l.actionRetry,
        onRetry: onRetry,
      ),
      AsyncValue<List<TrainerSlot>>(:final value)
          when (value ?? const []).isEmpty =>
        _NoSlotsNotice(gym: gym),
      // 헬스장 탭의 빈 예약 시간과 **같은 모양**이다 — 같은 자리를 같은 방식으로
      // 고르는데 화면마다 모양이 다르면 같은 것인지 알아보기 어렵다. 같은 폼의 운동
      // 목표도 칩이라 줄도 맞는다. 두 열로 두어 자리가 많아도 폼이 길어지지 않는다.
      AsyncValue<List<TrainerSlot>>(:final value) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double itemWidth =
              (constraints.maxWidth - OnCareSpacing.s8) / 2;
          return Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final TrainerSlot slot in value ?? const <TrainerSlot>[])
                SizedBox(
                  width: itemWidth,
                  child: AppChoiceChip(
                    // 자리 id 로 짚는다 — 헬스장 탭의 `slot-chip-<id>` 와 같다.
                    // 순번으로 짚으면 다른 자리가 앞에 끼는 순간 엉뚱한 자리를
                    // 고른다(실 API E2E 는 시드·다른 스위트의 자리와 함께 본다).
                    key: ValueKey<String>('consult-slot-${slot.id}'),
                    label: trainerSlotChipLabel(slot),
                    selected: slot.id == selectedId,
                    onSelected: (bool _) => onSelected(slot.id),
                  ),
                ),
            ],
          );
        },
      ),
    };
  }
}

/// 열린 자리가 없을 때. 헬스장 전화로 내보낸다. (#1873)
class _NoSlotsNotice extends StatelessWidget {
  const _NoSlotsNotice({required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String? phone = gym.phone;
    return Container(
      key: const Key('consult-slots-empty'),
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
          Text(
            l.exConsultSlotsEmptyTitle,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.body))
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            // 번호가 없는 헬스장(`Gym.phone` 은 nullable)이면 주소·영업시간이 있는
            // 헬스장 상세로 보낸다.
            phone == null
                ? l.exConsultSlotsEmptyNoPhone(gym.name)
                : l.exConsultSlotsEmptyBody(gym.name, phone),
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppButton(
            key: const Key('consult-slots-empty-cta'),
            label: phone == null ? l.exGymDetail : l.exGymCall,
            onPressed: () {
              if (phone == null) {
                unawaited(context.push(AppRoutes.gymDetailPath(gym.id)));
              } else {
                unawaited(callGym(context, phone));
              }
            },
            fullWidth: true,
          ),
        ],
      ),
    );
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
              const AppIcon(
                AppIcons.info,
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
                // 넘어가는 것이 회원의 건강 기록이라, 무엇에 동의하는지 이름
                // 없이 `checkbox, not checked` 만 들려서는 안 된다(#1942).
                Semantics(
                  checked: consented,
                  label: l.exConsultDataSharingAgree,
                  child: Checkbox(
                    value: consented,
                    onChanged: (bool? next) => onChanged(next ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: tokens.brand.primary,
                  ),
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
