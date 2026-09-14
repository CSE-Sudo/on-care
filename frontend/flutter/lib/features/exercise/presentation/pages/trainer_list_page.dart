import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

enum _TrainerSort { recommended, name }

/// 정렬 선택 필드 폭 — 결과 수 옆에 붙는 좁은 드롭다운.
const double _sortFieldWidth = 140;

class TrainerListPage extends ConsumerStatefulWidget {
  const TrainerListPage({super.key});

  @override
  ConsumerState<TrainerListPage> createState() => _TrainerListPageState();
}

class _TrainerListPageState extends ConsumerState<TrainerListPage> {
  String _query = '';
  _TrainerSort _sort = _TrainerSort.recommended;

  List<_TrainerListItem> _visibleTrainers(
    List<Trainer> trainers,
    List<Gym> gyms,
  ) {
    final String query = _query.trim().toLowerCase();
    final Map<String, String> gymNames = <String, String>{
      for (final Gym gym in gyms) gym.id: gym.name,
    };
    final List<_TrainerListItem> visible = trainers
        .map(
          (Trainer trainer) => _TrainerListItem(
            trainerId: trainer.id,
            name: trainer.name,
            role: trainer.role,
            gymName: gymNames[trainer.gymId] ?? '',
            reason: trainer.reason,
          ),
        )
        .where((_TrainerListItem trainer) {
          if (query.isEmpty) return true;
          return trainer.name.toLowerCase().contains(query) ||
              (trainer.role?.toLowerCase().contains(query) ?? false) ||
              trainer.gymName.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return switch (_sort) {
      _TrainerSort.recommended => visible,
      _TrainerSort.name =>
        visible.toList()..sort(
          (_TrainerListItem a, _TrainerListItem b) => a.name.compareTo(b.name),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double side = context.oncare.density.pagePadding;
    final AsyncValue<List<Trainer>> trainersAsync = ref.watch(
      allTrainersProvider,
    );
    // 헬스장 이름만 붙이면 되므로, 목록을 못 읽어도 트레이너는 그대로 보인다.
    final List<Gym> gyms =
        // 카카오 헬스장 소속 트레이너도 헬스장 이름이 나와야 한다(#329).
        ref.watch(gymFinderResultsProvider).valueOrNull ?? const <Gym>[];

    // 검색창은 위에 고정하고 결과만 스크롤한다 — ListView 틀(AppPage)이 맞지
    // 않아 Scaffold 로 둔다.
    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      appBar: AppTopBar(title: l.exFindTrainer),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                side,
                OnCareSpacing.s12,
                side,
                OnCareSpacing.s20,
              ),
              child: Column(
                children: <Widget>[
                  AppSearchField(
                    hint: l.exTrainerSearchPlaceholder,
                    clearTooltip: l.a11yClearSearch,
                    onChanged: (String value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: OnCareSpacing.s16),
                  Expanded(
                    child: trainersAsync.when(
                      loading: () => const AppLoading(),
                      error: (Object _, StackTrace _) => AppErrorState(
                        title: l.exTrainersLoadError,
                        retryLabel: l.actionRetry,
                        onRetry: () => ref.invalidate(allTrainersProvider),
                      ),
                      data: (List<Trainer> trainers) {
                        final List<_TrainerListItem> visible = _visibleTrainers(
                          trainers,
                          gyms,
                        );
                        return Column(
                          children: <Widget>[
                            _ResultControls(
                              countLabel: l.exResultCount(visible.length),
                              sort: _sort,
                              onSort: (_TrainerSort value) =>
                                  setState(() => _sort = value),
                            ),
                            const SizedBox(height: OnCareSpacing.s12),
                            Expanded(
                              child: visible.isEmpty
                                  ? AppEmptyState(
                                      title: l.exNoSearchResults,
                                      icon: Icons.search_off_rounded,
                                    )
                                  : ListView.separated(
                                      itemCount: visible.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(
                                            height: OnCareSpacing.cardGap,
                                          ),
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                            return _TrainerListCard(
                                              trainer: visible[index],
                                              onTap: () => context.push(
                                                AppRoutes.trainerDetailPath(
                                                  visible[index].trainerId,
                                                ),
                                              ),
                                            );
                                          },
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrainerListItem {
  const _TrainerListItem({
    required this.trainerId,
    required this.name,
    required this.role,
    required this.gymName,
    required this.reason,
  });

  final String trainerId;
  final String name;
  final String? role;
  final String gymName;
  final String? reason;
}

class _ResultControls extends StatelessWidget {
  const _ResultControls({
    required this.countLabel,
    required this.sort,
    required this.onSort,
  });

  final String countLabel;
  final _TrainerSort sort;
  final ValueChanged<_TrainerSort> onSort;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            countLabel,
            style: context.oncare
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ),
        SizedBox(
          width: _sortFieldWidth,
          child: AppSelectField<_TrainerSort>(
            value: sort,
            items: <DropdownMenuItem<_TrainerSort>>[
              DropdownMenuItem<_TrainerSort>(
                value: _TrainerSort.recommended,
                child: Text(l.exSortRecommended),
              ),
              DropdownMenuItem<_TrainerSort>(
                value: _TrainerSort.name,
                child: Text(l.exSortName),
              ),
            ],
            onChanged: (_TrainerSort? value) {
              if (value != null) onSort(value);
            },
          ),
        ),
      ],
    );
  }
}

class _TrainerListCard extends StatelessWidget {
  const _TrainerListCard({required this.trainer, required this.onTap});

  final _TrainerListItem trainer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppAvatar(name: trainer.name, size: AppAvatarSize.large),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  trainer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s2),
                // '전담 트레이너'가 있던 자리·스타일에 소속 헬스장을 표기.
                Text(
                  trainer.gymName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                Text(
                  trainer.reason ?? l.exTrainerRecommendationReason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: tokens.brand.primary),
                ),
              ],
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s8),
            const Icon(
              Icons.chevron_right_rounded,
              size: OnCareSize.iconMedium,
              color: OnCareColors.textTertiary,
            ),
          ],
        ],
      ),
    );
  }
}
