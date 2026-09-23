import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/utils/gym_phone.dart';
import 'package:oncare/features/exercise/presentation/widgets/connection_disconnect.dart';
import 'package:oncare/features/exercise/presentation/widgets/trainer_reason_badges.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

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
      body = AppEmptyState(title: l.exGymNotFound, icon: AppIcons.info);
    }

    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
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
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.gym,
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
            if (gym.rating > 0) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Semantics(
                label: '${l.exRating} ${gym.rating.toStringAsFixed(1)}',
                excludeSemantics: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const AppIcon(
                      AppIcons.star,
                      size: OnCareSize.iconSmall,
                      color: OnCareColors.cautionFill,
                    ),
                    const SizedBox(width: OnCareSpacing.s4),
                    Text(
                      gym.rating.toStringAsFixed(1),
                      style: OnCareTypography.numeric(
                        tokens
                            .text(OnCareTypography.bodySmall)
                            .copyWith(color: OnCareColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: OnCareSpacing.s20),
            _DetailSection(
              icon: AppIcons.location,
              title: l.exAddress,
              child: Text(gym.address, style: bodyStyle),
            ),
            if (gym.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: OnCareSpacing.cardGap),
              _DetailSection(
                icon: AppIcons.exercise,
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
                icon: AppIcons.clock,
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
              // 번호 한 줄뿐이라 머리·구분선을 따로 두지 않고 한 줄 카드로 둔다.
              // 누르면 전화·복사 시트를 띄운다(#1873) — 상담 자리가 없을 때 회원이
              // 나갈 곳이 이 번호라 걸 수 있어야 한다.
              Semantics(
                button: true,
                label: '${l.exGymCall} ${gym.phone!}',
                excludeSemantics: true,
                child: AppCard(
                  key: const Key('gym-detail-phone'),
                  onTap: () => showGymPhoneSheet(context, gym.name, gym.phone!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: OnCareSpacing.cardPadding,
                    vertical: OnCareSpacing.s12,
                  ),
                  child: Row(
                    children: <Widget>[
                      AppIcon(
                        AppIcons.phone,
                        size: OnCareSize.iconMedium,
                        color: tokens.brand.primary,
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      Text(
                        l.exPhone,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      const SizedBox(width: OnCareSpacing.s12),
                      Expanded(
                        child: Text(
                          gym.phone!,
                          overflow: TextOverflow.ellipsis,
                          style: tokens
                              .text(OnCareTypography.body)
                              .copyWith(color: OnCareColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
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
      showClose: false,
      title: l.exGymConsultPickTrainer,
      subtitle: l.exGymConsultPickTrainerHint,
      child: trainers.isEmpty
          ? AppEmptyState(
              title: l.exGymConsultNoTrainers,
              icon: AppIcons.personOff,
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
      reasonKeyPrefix: 'gym-consult-trainer-${trainer.id}',
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
      icon: AppIcons.person,
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
            _AffiliatedTrainerRow(
              trainer: trainers[i],
              reasonKeyPrefix: 'gym-detail-trainer-${trainers[i].id}',
            ),
          ],
        ],
      ),
    );
  }
}

class _AffiliatedTrainerRow extends StatelessWidget {
  const _AffiliatedTrainerRow({
    required this.trainer,
    required this.reasonKeyPrefix,
    this.onTap,
    this.trailingLabel,
    super.key,
  });

  final Trainer trainer;

  /// 추천 이유 태그의 키 접두어. 소속 트레이너 섹션과 상담 트레이너 시트가 한
  /// 트리에 함께 서므로(시트는 상세 위에 뜬다) 부르는 쪽이 제 이름을 준다.
  final String reasonKeyPrefix;

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
      // 이름과 직함은 한 줄에 읽힌다 — 헬스장 찾기·내 헬스장 카드의 트레이너
      // 줄과 같은 규칙이다(#2038 · #2082). 폭이 모자라면 직함이 먼저 준다.
      title: trainer.name,
      titleMeta: trainer.role,
      onTap: locked
          ? null
          : (onTap ??
                () => context.push(AppRoutes.trainerDetailPath(trainer.id))),
      // 트레이너 상세·채팅과 같은 성씨 프로필로 선다 (#2154) — 고르는 자리와
      // 눌러 들어간 자리에서 같은 사람이 다른 얼굴이 되지 않게.
      leading: AppAvatar(name: trainer.name, size: AppAvatarSize.large),
      // 여기가 상담할 트레이너를 고르는 자리다 — 헬스장 찾기에서 봤던 근거를
      // 정작 고르는 화면에서 다시 찾게 두지 않는다 (#1881).
      below: trainer.reasons.isEmpty
          ? null
          : TrainerReasonBadges(
              reasons: trainer.reasons,
              keyPrefix: reasonKeyPrefix,
            ),
      trailing: trailingLabel != null
          ? Text(
              trailingLabel!,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.textSecondary),
            )
          : const AppIcon(
              AppIcons.chevronRight,
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
