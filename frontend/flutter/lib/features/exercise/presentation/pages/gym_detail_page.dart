import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/connection_disconnect.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' hide showAppToast, AppToastType;

/// 상세 머리의 헬스장 아이콘 상자 한 변.
const double _heroIconBox = 80;

/// 트레이너 행 사이 구분선의 들여쓰기 — 행 여백 + 아바타 + 간격만큼.
const double _trainerDividerIndent =
    OnCareSpacing.s16 + OnCareSize.avatarLarge + OnCareSpacing.s12;

class GymDetailPage extends ConsumerWidget {
  const GymDetailPage({required this.gymId, super.key});

  final String gymId;

  Gym? _findGym(List<Gym> gyms) {
    for (final Gym gym in gyms) {
      if (gym.id == gymId) return gym;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 목록(헬스장 찾기)이 제휴 + 카카오를 합쳐 보여주므로 상세도 같은 소스를 봐야
    // 카카오에서 온 헬스장을 눌렀을 때 "찾을 수 없음"이 되지 않는다(#329).
    final AsyncValue<List<Gym>> nearbyAsync = ref.watch(
      gymFinderResultsProvider,
    );
    final AsyncValue<Gym?> myGymAsync = ref.watch(myGymProvider);

    final Gym? nearbyGym = switch (nearbyAsync) {
      AsyncData<List<Gym>>(:final value) => _findGym(value),
      _ => null,
    };
    final Gym? myGym = switch (myGymAsync) {
      AsyncData<Gym?>(:final value) when value?.id == gymId => value,
      _ => null,
    };
    final Gym? gym = nearbyGym ?? myGym;
    final Widget body;
    if (gym != null) {
      body = _GymDetails(gym: gym, isMyGym: myGym != null);
    } else if (nearbyAsync.isLoading || myGymAsync.isLoading) {
      body = const AppLoading();
    } else if (nearbyAsync.hasError || myGymAsync.hasError) {
      body = AppErrorState(
        title: l.exGymsLoadError,
        retryLabel: l.actionRetry,
        onRetry: () {
          ref.invalidate(gymFinderResultsProvider);
          ref.invalidate(myGymProvider);
        },
      );
    } else {
      body = AppEmptyState(title: l.exGymNotFound, icon: Icons.info_rounded);
    }

    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      appBar: AppTopBar(title: l.exGymDetailTitle),
      body: SafeArea(top: false, child: body),
    );
  }
}

class _GymDetails extends ConsumerWidget {
  const _GymDetails({required this.gym, required this.isMyGym});

  final Gym gym;
  final bool isMyGym;

  /// 연결을 끊고, 끊었으면 이 화면을 닫는다 — 지운 대상의 상세에 그대로
  /// 남아 있으면 방금 무엇을 했는지 화면이 말해 주지 못한다. (#1057)
  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l = AppLocalizations.of(context);
    // 아직 읽는 중이면 `valueOrNull` 은 null 이다 — 담당이 있는데도 없다고
    // 보고 "트레이너도 함께 해제됩니다" 를 빠뜨린다.
    final Trainer? trainer = await ref.read(myTrainerProvider.future);
    if (!context.mounted) return;
    final bool removed = await confirmDisconnect(
      context,
      ref,
      // 담당 트레이너가 있으면 함께 사라진다는 것을 알린다.
      message: trainer == null
          ? l.myGymDisconnectConfirm(gym.name)
          : l.myGymDisconnectWithTrainerConfirm(gym.name, trainer.name),
      disconnect: (GymRepository repo) => repo.disconnectMyGym(),
    );
    // go_router 의 pop 을 쓴다 — 상세는 라우터가 쌓은 화면이라, 그 안의
    // Navigator 로는 돌아갈 곳이 없다고 나온다.
    if (removed && context.mounted && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle bodyStyle = tokens
        .text(OnCareTypography.body)
        .copyWith(color: OnCareColors.textPrimary);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: OnCareLayout.mobileContentMaxWidth,
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            tokens.density.pagePadding,
            OnCareSpacing.s16,
            tokens.density.pagePadding,
            OnCareSpacing.s32,
          ),
          children: <Widget>[
            Center(
              child: Container(
                width: _heroIconBox,
                height: _heroIconBox,
                decoration: BoxDecoration(
                  color: tokens.brand.surface,
                  borderRadius: OnCareRadius.xlAll,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.fitness_center_rounded,
                  size: OnCareSize.iconEmptyState,
                  color: tokens.brand.primary,
                ),
              ),
            ),
            const SizedBox(height: OnCareSpacing.s16),
            Text(
              gym.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.titleLarge)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MetricCard(
                    icon: Icons.place_rounded,
                    label: l.exDistance,
                    value: '${gym.distanceKm.toStringAsFixed(1)}km',
                  ),
                ),
                const SizedBox(width: OnCareSpacing.cardGap),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.star_rounded,
                    label: l.exRating,
                    value: gym.rating.toStringAsFixed(1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s20),
            _DetailSection(
              icon: Icons.place_rounded,
              title: l.exAddress,
              child: Text(gym.address, style: bodyStyle),
            ),
            if (gym.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: OnCareSpacing.cardGap),
              _DetailSection(
                icon: Icons.fitness_center_rounded,
                title: l.exSpecialty,
                child: Wrap(
                  spacing: OnCareSpacing.s8,
                  runSpacing: OnCareSpacing.s8,
                  children: <Widget>[
                    for (final String tag in gym.tags)
                      AppTag(label: tag, tone: AppTagTone.brand),
                  ],
                ),
              ),
            ],
            if (gym.weekdayHours != null ||
                gym.weekendHours != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.cardGap),
              _DetailSection(
                icon: Icons.schedule_rounded,
                title: l.exHours,
                child: Column(
                  children: <Widget>[
                    if (gym.weekdayHours != null)
                      _InfoLine(text: l.exGymWeekdayHours(gym.weekdayHours!)),
                    if (gym.weekendHours != null)
                      _InfoLine(text: l.exGymWeekendHours(gym.weekendHours!)),
                  ],
                ),
              ),
            ],
            if (gym.phone != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.cardGap),
              _DetailSection(
                icon: Icons.call_rounded,
                title: l.exPhone,
                child: Text(
                  gym.phone!,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.body))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
            ],
            const SizedBox(height: OnCareSpacing.cardGap),
            _AffiliatedTrainers(gymId: gym.id),
            if (isMyGym) ...<Widget>[
              const SizedBox(height: OnCareSpacing.sectionGap),
              // 목록 카드에서 삭제를 여기로 옮겼다 (#1057). 상세에 지울 자리가
              // 없으면 연결을 끊을 방법이 화면에서 사라진다.
              DisconnectButton(
                label: l.myGymDisconnectTooltip,
                onTap: () => _disconnect(context, ref),
              ),
            ],
            if (!isMyGym) ...<Widget>[
              const SizedBox(height: OnCareSpacing.sectionGap),
              AppButton(
                key: const Key('gym-consult-start'),
                label: l.exGymConsultRequest,
                // 상담은 트레이너 한 사람에게만 간다 — 헬스장에서 시작해도 소속
                // 트레이너 중 누구에게 보낼지 먼저 고른다.
                onPressed: () => _pickTrainerForConsultation(context, gym),
                size: OnCareButtonSize.large,
                fullWidth: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 소속 트레이너 중 상담을 보낼 한 명을 고르는 시트.
///
/// 헬스장 상세의 목록으로 올려보내지 않고 시트로 띄우는 이유: 목록 행을 누르면
/// 트레이너 상세로 가야 하고(정보를 보고 고르는 동선), 여기서는 "상담을 건다"는
/// 의도가 이미 정해져 있어 한 번 더 상세를 거치게 하면 단계만 늘어난다.
Future<void> _pickTrainerForConsultation(BuildContext context, Gym gym) {
  // 상세는 루트 내비게이터에 쌓인 화면이라, 시트도 하단 바·+ 버튼 위에
  // 뜬다(#791).
  return showAppSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => _TrainerPickerSheet(gym: gym),
  );
}

class _TrainerPickerSheet extends ConsumerWidget {
  const _TrainerPickerSheet({required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<Trainer> trainers =
        ref.watch(gymTrainersProvider(gym.id)).valueOrNull ?? const <Trainer>[];
    final List<ConsultationRequest> requests = ref.watch(
      consultationRequestControllerProvider,
    );

    return AppSheet(
      title: l.exGymConsultPickTrainer,
      subtitle: l.exGymConsultPickTrainerHint,
      child: trainers.isEmpty
          ? AppEmptyState(
              title: l.exGymConsultNoTrainers,
              icon: Icons.person_off_rounded,
              placement: AppStatePlacement.card,
            )
          : Column(
              key: const Key('gym-consult-trainer-picker'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (
                  int index = 0;
                  index < trainers.length;
                  index++
                ) ...<Widget>[
                  if (index > 0)
                    const Padding(
                      padding: EdgeInsets.only(left: _trainerDividerIndent),
                      child: AppDivider(),
                    ),
                  _pickerRow(context, trainers[index], requests, l),
                ],
              ],
            ),
    );
  }

  Widget _pickerRow(
    BuildContext context,
    Trainer trainer,
    List<ConsultationRequest> requests,
    AppLocalizations l,
  ) {
    // 이미 대기 중인 트레이너를 다시 누르면 서버가 409 를 준다.
    // 누르기 전에 상태를 보여 주고 막는다.
    final bool pending = requests.any(
      (ConsultationRequest request) =>
          request.trainerId == trainer.id &&
          request.status == ConsultationStatus.pending,
    );
    return _AffiliatedTrainerRow(
      key: Key('gym-consult-trainer-${trainer.id}'),
      trainer: trainer,
      trailingLabel: pending ? l.exConsultPendingCta : null,
      onTap: pending
          ? null
          : () {
              Navigator.of(context).pop();
              context.push(
                AppRoutes.consultationRequestPath(
                  gymId: gym.id,
                  trainerId: trainer.id,
                ),
              );
            },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      child: Row(
        children: <Widget>[
          Icon(icon, size: OnCareSize.iconMedium, color: tokens.brand.primary),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OnCareTypography.numeric(
                    tokens
                        .text(OnCareTypography.titleSmall)
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 이 헬스장에 소속된 트레이너 전원. 헬스장당 여러 명일 수 있으므로 목록으로
/// 그리고, 한 명도 없으면 섹션 자체를 숨긴다.
class _AffiliatedTrainers extends ConsumerWidget {
  const _AffiliatedTrainers({required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<Trainer> trainers =
        ref.watch(gymTrainersProvider(gymId)).valueOrNull ?? const <Trainer>[];
    if (trainers.isEmpty) return const SizedBox.shrink();

    return _DetailSection(
      icon: Icons.person_rounded,
      title: l.exAffiliatedTrainer,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < trainers.length; i++) ...<Widget>[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(left: _trainerDividerIndent),
                child: AppDivider(),
              ),
            _AffiliatedTrainerRow(trainer: trainers[i]),
          ],
        ],
      ),
    );
  }
}

class _AffiliatedTrainerRow extends StatelessWidget {
  const _AffiliatedTrainerRow({
    required this.trainer,
    this.onTap,
    this.trailingLabel,
    super.key,
  });

  final Trainer trainer;

  /// 기본 동작은 트레이너 상세로 가기다. 상담 트레이너 선택 시트는 여기에 자기
  /// 동작을 넣고, 이미 대기 중이면 null 을 줘 행을 잠근다.
  final VoidCallback? onTap;

  /// 오른쪽 화살표 대신 보여 줄 상태 문구(예: "상담 요청 대기 중").
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool locked = onTap == null && trailingLabel != null;
    return AppListRow(
      title: trainer.name,
      subtitle: trainer.role,
      onTap: locked
          ? null
          : (onTap ??
                () => context.push(AppRoutes.trainerDetailPath(trainer.id))),
      leading: Container(
        width: OnCareSize.avatarLarge,
        height: OnCareSize.avatarLarge,
        decoration: BoxDecoration(
          color: tokens.brand.surface,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.person_rounded,
          size: OnCareSize.iconMedium,
          color: tokens.brand.primary,
        ),
      ),
      trailing: trailingLabel != null
          ? Text(
              trailingLabel!,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.textSecondary),
            )
          : const Icon(
              Icons.chevron_right_rounded,
              size: OnCareSize.iconMedium,
              color: OnCareColors.textTertiary,
            ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.icon,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(OnCareSpacing.cardPadding),
  });

  final IconData icon;
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OnCareSpacing.cardPadding,
              OnCareSpacing.s12,
              OnCareSpacing.cardPadding,
              OnCareSpacing.s12,
            ),
            child: AppSectionHeader(icon: icon, title: title),
          ),
          const AppDivider(),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
        child: Text(
          text,
          style: context.oncare
              .text(OnCareTypography.body)
              .copyWith(color: OnCareColors.textPrimary),
        ),
      ),
    );
  }
}
