import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/exercise/presentation/utils/slot_label.dart';
import 'package:oncare/features/exercise/presentation/widgets/connected_gym_card.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

class GymTab extends ConsumerWidget {
  const GymTab({
    required this.selectedSlot,
    required this.onSlot,
    this.gymAnchorKey,
    super.key,
  });

  final String? selectedSlot;
  final ValueChanged<String> onSlot;

  /// 사용 가이드가 `내 헬스장` 카드의 자리를 재는 열쇠(#1857). 운동 탭은 이
  /// 값을 주지 않는다 — 가이드 화면만 자기 사본에 달아 쓴다.
  final GlobalKey? gymAnchorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<Gym?> myGymAsync = ref.watch(myGymProvider);
    final MemberCoach? assignedCoach = ref
        .watch(memberCoachProvider)
        .valueOrNull;
    final List<ConsultationRequest> requests = ref.watch(
      consultationRequestControllerProvider,
    );
    ConsultationRequest? pendingRequest;
    for (final ConsultationRequest request in requests) {
      if (request.status == ConsultationStatus.pending) {
        pendingRequest = request;
        break;
      }
    }
    final bool showTrainerChat =
        assignedCoach != null && pendingRequest == null;
    // 연결된 헬스장이 없으면 이 탭에서 할 일은 헬스장을 찾는 것뿐이다 —
    // 지도만 든 빈 카드와 `헬스장 찾기` 버튼 대신 찾기 화면을 그대로 보여
    // 준다 (#1133). 추천 헬스장·추천 트레이너 섹션도 그 화면의 목록과 같은
    // 말을 하므로 함께 내린다. 트레이너와 채팅 버튼도 여기서는 없다 (#1132) —
    // 담당이 있으면 헤더의 채팅 버튼이 그 자리를 맡는다.
    //
    // 조회 중에는 찾기 화면을 미리 보여 주지 않는다. 잠깐 떴다 사라지면 연결이
    // 풀린 것처럼 읽힌다.
    if (myGymAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: OnCareSpacing.s20),
        child: Align(
          alignment: Alignment.topCenter,
          child: AppLoading(placement: AppStatePlacement.card),
        ),
      );
    }
    if (!myGymAsync.hasError && myGymAsync.valueOrNull == null) {
      // 상담 요청 내역은 검색창 옆 아이콘이 맡는다. 요청 직후 요약 카드를 여기
      // 끼우면 검색창이 아래로 밀려 화면 구조가 바뀐다(#1287).
      return const GymFinderView();
    }

    // 이 탭은 높이를 받아 놓인다 (#1274) — 연결된 헬스장 화면은 섹션이 여럿인
    // 긴 화면이라 제 스크롤을 갖는다. 찾기 화면은 스스로 시트를 굴리므로 이
    // 스크롤을 타지 않는다.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 이미 연결된 헬스장이 있어도 다른 헬스장을 둘러볼 수 있어야 한다 —
          // 마이페이지의 `헬스장 찾기`와 같은 목적지다(#1257).
          AppSectionHeader(
            title: l.exMyGymSection,
            actionLabel: l.exFindGym,
            onAction: () => context.push(AppRoutes.gyms),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          KeyedSubtree(
            key: gymAnchorKey,
            child: _MyGymSection(
              gymAsync: myGymAsync,
              trainer: ref.watch(myTrainerProvider).valueOrNull,
              selectedSlot: selectedSlot,
              onSlot: onSlot,
              onRetry: () => ref.invalidate(myGymProvider),
              onTrainerChatTap: showTrainerChat
                  ? () => openTrainerChatPage(
                      context,
                      trainerName: assignedCoach.name,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyGymSection extends StatelessWidget {
  const _MyGymSection({
    required this.gymAsync,
    required this.trainer,
    required this.selectedSlot,
    required this.onSlot,
    required this.onRetry,
    required this.onTrainerChatTap,
  });

  final AsyncValue<Gym?> gymAsync;

  /// 담당 트레이너. 헬스장과 별개로 해제될 수 있어 null 이면 트레이너 행이 빠진다.
  final Trainer? trainer;
  final String? selectedSlot;
  final ValueChanged<String> onSlot;
  final VoidCallback onRetry;
  final VoidCallback? onTrainerChatTap;

  Widget _error(AppLocalizations l) => AppCard(
    child: AppErrorState(
      title: l.exGymsLoadError,
      retryLabel: l.actionRetry,
      onRetry: onRetry,
      placement: AppStatePlacement.card,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return gymAsync.when(
      loading: () => const AppLoading(placement: AppStatePlacement.card),
      error: (Object _, StackTrace _) => _error(l),
      // 연결된 헬스장이 없는 경우는 이 위젯에 오지 않는다 — 탭이 찾기 화면을
      // 대신 그린다 (#1133). 그래도 방어적으로 빈 상태를 오류처럼 다루지 않고
      // 재시도 자리를 남긴다.
      data: (Gym? gym) => gym == null
          ? _error(l)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ConnectedGymCard(
                  gym: gym,
                  trainer: trainer,
                  onGymTap: () => context.push(AppRoutes.gymDetailPath(gym.id)),
                  onTrainerDetail: trainer == null
                      ? null
                      : () => context.push(
                          AppRoutes.trainerDetailPath(trainer!.id),
                        ),
                  footer: onTrainerChatTap == null
                      ? null
                      : _TrainerChatButton(onTap: onTrainerChatTap!),
                ),
                if (trainer != null) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s12),
                  _ReservationPanel(
                    key: const Key('my-gym-reservation-panel'),
                    gym: gym,
                    trainer: trainer!,
                    selectedSlot: selectedSlot,
                    onSlot: onSlot,
                  ),
                ],
              ],
            ),
    );
  }
}

/// 담당 트레이너와의 대화로 들어가는 버튼.
///
/// **읽지 않음 배지를 달지 않는다.** 같은 숫자를 헤더의 채팅 아이콘이 이미
/// 말하고 있고, 그쪽은 어느 탭에 있든 보이는 자리라 알림의 몫을 거기서 한다.
/// 이 버튼은 같은 대화로 들어가는 두 번째 입구일 뿐이어서, 배지를 함께 달면
/// 한 화면이 같은 말을 두 번 한다.
class _TrainerChatButton extends StatelessWidget {
  const _TrainerChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppButton(
      key: const Key('gymTrainerChatButton'),
      label: l.coachChatWithTrainer,
      onPressed: onTap,
      // variant 를 적지 않아 기본값(브랜드 채움)을 쓴다 — 헤더의 채팅
      // 아이콘과 같은 대화로 들어가는 자리라 헤더가 쓰는 `brand.primary`
      // 와 같은 색이어야 한다 (#1849). 흰 바탕 보조 버튼으로 두었을 때는
      // 같은 채팅인데도 둘이 다른 동작처럼 읽혔다. 색은 테스트가 고정한다.
      leadingIcon: AppIcons.chat,
      fullWidth: true,
    );
  }
}

/// 이 화면이 내주는 단 하나의 자리 종류. [TrainerSlot.sessionType] 의 계약값을
/// 그대로 쓴다 — 도메인·저장소는 상담 자리까지 그대로 들고 있고, 회원에게 무엇을
/// 열어 줄지 좁히는 일은 화면 몫이다 (#1849).
const String _kPersonalTrainingSessionType = '1:1 PT';

/// 담당 트레이너의 실제 예약 가능 시간.
///
/// 슬롯은 트레이너에 귀속되므로 여기서 [trainerSlotsProvider] 를 직접 읽는다.
/// 마감된 자리도 숨기지 않고 비활성으로 남겨, 그 트레이너의 하루가 "비어 있음"
/// 이 아니라 "찼음" 으로 읽히게 한다.
class _ReservationPanel extends ConsumerStatefulWidget {
  const _ReservationPanel({
    super.key,
    required this.gym,
    required this.trainer,
    required this.selectedSlot,
    required this.onSlot,
  });

  final Gym gym;
  final Trainer trainer;

  /// 선택된 슬롯 id. 부모(운동 탭)가 들고 있다.
  final String? selectedSlot;
  final ValueChanged<String> onSlot;

  @override
  ConsumerState<_ReservationPanel> createState() => _ReservationPanelState();
}

class _ReservationPanelState extends ConsumerState<_ReservationPanel> {
  /// 요청이 오가는 동안 잡고 있는 슬롯 id. 예약은 멱등이 아니라서, 확정 버튼을
  /// 두 번 누르면 좌석이 두 번 빠진다 — 그래서 진행 중에는 버튼을 잠근다.
  String? _reserving;

  /// 취소 요청이 오가는 동안 잡고 있는 예약 id. 예약과 같은 이유로 잠근다.
  String? _cancelling;

  /// 24시간(HH:mm) 표기로 고정한다 — 로케일 기본(오전/오후 12시간제)을 쓰던
  /// `MaterialLocalizations.formatTimeOfDay` 대신이다. 빈 예약 시간을
  /// 트레이너 쪽 스케줄·모달과 같은 표기로 보여준다.
  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// "8월 8일 19:00" 형태. 고정 문자열이 아니라 실제 시각을 쓰므로 날이
  /// 바뀌어도 어긋나지 않는다.
  String _when(BuildContext context, AppLocalizations l, DateTime at) {
    final MaterialLocalizations m = MaterialLocalizations.of(context);
    return l.exSlotWhen(
      m.formatMediumDate(at),
      _hhmm(TimeOfDay.fromDateTime(at)),
    );
  }

  Future<void> _reserve(AppLocalizations l, TrainerSlot slot) async {
    if (_reserving != null) return;
    final AppToastHost toast = AppToastHost.of(context);
    final String label = _when(context, l, slot.startsAt);
    setState(() => _reserving = slot.id);
    try {
      await ref.read(gymRepositoryProvider).reserve(slot.id);
    } catch (_) {
      if (mounted) setState(() => _reserving = null);
      toast.show(l.exReserveFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() => _reserving = null);
    // 잔여 자리를 다시 읽어, 방금 잡은 자리가 목록에도 반영되게 한다.
    ref.invalidate(trainerSlotsProvider(widget.trainer.id));
    // 방금 잡은 예약이 '내 예약'에도 나타나야 취소가 걸린다. (#502)
    ref.invalidate(myReservationsProvider);
    toast.show(
      l.exReserveConfirmedSlotGym(label, widget.gym.name),
      type: AppToastType.success,
    );
  }

  /// 예약 취소. 확인을 받고, 성공하면 잔여 자리와 내 예약을 함께 다시 읽는다.
  ///
  /// 되돌릴 수 없는 동작이라 확인을 한 번 받는다 — 취소하면 그 자리는 곧바로
  /// 다른 회원이 잡을 수 있다. (#502)
  Future<void> _cancel(AppLocalizations l, MyReservation reservation) async {
    if (_reserving != null || _cancelling != null) return;
    final AppToastHost toast = AppToastHost.of(context);
    final String label = _when(context, l, reservation.startsAt);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.exCancelConfirmTitle,
      message: l.exCancelConfirmBody(label),
      confirmLabel: l.exCancelReservation,
      cancelLabel: l.exCancelKeep,
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _cancelling = reservation.id);
    try {
      await ref.read(gymRepositoryProvider).cancelReservation(reservation.id);
    } catch (_) {
      if (mounted) setState(() => _cancelling = null);
      toast.show(l.exCancelFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() => _cancelling = null);
    // 좌석이 돌아왔으므로 슬롯도 함께 다시 읽는다.
    ref.invalidate(trainerSlotsProvider(widget.trainer.id));
    ref.invalidate(myReservationsProvider);
    toast.show(l.exCancelDone(label), type: AppToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AsyncValue<List<TrainerSlot>> slotsAsync = ref.watch(
      trainerSlotsProvider(widget.trainer.id),
    );
    // 이 트레이너에 대한 내 예약만 추린다 — 패널이 한 트레이너의 자리를 다룬다.
    final List<MyReservation> mine =
        (ref.watch(myReservationsProvider).valueOrNull ??
                const <MyReservation>[])
            .where((MyReservation r) => r.trainerId == widget.trainer.id)
            .toList()
          // 서버는 늦은 예약부터 준다(#980) — 쪽을 나누려면 그 순서여야 한다. 화면은
          // 다르다: **곧 다가오는 자리가 맨 위**여야 하고, 지난 예약은 최근 것부터
          // 아래에 남는다. 취소 가능 여부(`cancellable`)가 곧 예정/지난 판단이다.
          ..sort((MyReservation a, MyReservation b) {
            if (a.cancellable != b.cancellable) return a.cancellable ? -1 : 1;
            return a.cancellable
                ? a.startsAt.compareTo(b.startsAt)
                : b.startsAt.compareTo(a.startsAt);
          });
    // 다가오는 예약이 이미 있으면 빈 자리를 더 고르게 하지 않는다 — 1:1 PT 라
    // 다음 일정은 하나면 충분하고, 자리를 옮기려면 먼저 취소하는 흐름이다(#1072).
    // 취소 가능 여부(`cancellable`)가 곧 '다음 일정' 판단이다.
    final bool hasUpcoming = mine.any((MyReservation r) => r.cancellable);
    final bool busy = _reserving != null || _cancelling != null;
    return AppTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (mine.isNotEmpty) ...<Widget>[
            _MyReservations(
              reservations: mine,
              label: (DateTime at) => _when(context, l, at),
              cancelling: _cancelling,
              disabled: busy,
              onCancel: (MyReservation r) => _cancel(l, r),
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          if (!hasUpcoming) ...<Widget>[
            Row(
              children: <Widget>[
                AppIcon(
                  AppIcons.eventAvailable,
                  size: OnCareSize.iconSmall,
                  color: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s4),
                Expanded(
                  child: Text(
                    l.exTrainerAvailability(widget.trainer.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.label)
                        .copyWith(color: tokens.brand.primary),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                // 종류는 칩마다 적지 않고 한 번만 적는다. 내 헬스장에는 1:1 PT
                // 자리만 남으므로(#1136) 칩마다 늘 같은 값이었다.
                AppTag(
                  label: l.exSlotTypePersonalTraining,
                  tone: AppTagTone.brand,
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s8),
            slotsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
                child: Center(child: AppLoading.inline()),
              ),
              error: (Object _, StackTrace _) => _SlotNotice(
                message: l.exSlotsLoadError,
                onRetry: () =>
                    ref.invalidate(trainerSlotsProvider(widget.trainer.id)),
              ),
              data: (List<TrainerSlot> all) {
                // 이미 연결된 헬스장이라 상담은 지난 걸음이다 — 상담으로 열린
                // 자리는 여기서 보여 주지 않는다 (#1136). 제목 줄이 종류를
                // `1:1 PT` 로 한 번만 못 박으므로(#1701), 거르는 기준도 상담을
                // 빼는 쪽이 아니라 **1:1 PT 만 남기는 쪽**이어야 한다 — 상담
                // 아닌 다른 종류가 섞여 들어오면 제목과 칩이 어긋난다 (#1849).
                final List<TrainerSlot> slots = all
                    .where(
                      (TrainerSlot slot) =>
                          slot.sessionType == _kPersonalTrainingSessionType,
                    )
                    .toList(growable: false);
                if (slots.isEmpty) {
                  return _SlotNotice(message: l.exSlotsEmpty);
                }
                final bool allBooked = slots.every(
                  (TrainerSlot slot) => slot.booked,
                );
                final TrainerSlot? picked = slots
                    .where(
                      (TrainerSlot slot) =>
                          slot.id == widget.selectedSlot && !slot.booked,
                    )
                    .firstOrNull;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (allBooked) ...<Widget>[
                      _SlotNotice(message: l.exSlotsAllBooked),
                      const SizedBox(height: OnCareSpacing.s8),
                    ],
                    LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final double itemWidth =
                                (constraints.maxWidth - OnCareSpacing.s8) / 2;
                            return Wrap(
                              spacing: OnCareSpacing.s8,
                              runSpacing: OnCareSpacing.s8,
                              children: <Widget>[
                                for (final TrainerSlot slot in slots)
                                  SizedBox(
                                    width: itemWidth,
                                    child: AppChoiceChip(
                                      key: ValueKey<String>(
                                        'slot-chip-${slot.id}',
                                      ),
                                      label: trainerSlotChipLabel(slot),
                                      selected: picked?.id == slot.id,
                                      // 마감된 자리는 고를 수 없고, 예약이 오가는 중에는
                                      // 선택도 잠근다.
                                      onSelected: slot.booked || busy
                                          ? null
                                          : (bool _) => widget.onSlot(slot.id),
                                    ),
                                  ),
                              ],
                            );
                          },
                    ),
                    if (picked != null) ...<Widget>[
                      const SizedBox(height: OnCareSpacing.s12),
                      AppButton(
                        key: const ValueKey<String>('reserve-confirm'),
                        label: l.exReserveConfirm(
                          _when(context, l, picked.startsAt),
                        ),
                        onPressed: busy ? null : () => _reserve(l, picked),
                        // size 를 적지 않아 기본값(medium)을 쓴다 — 같은 탭의
                        // `트레이너와 채팅` 과 같은 높이다. 36 짜리 자리 칩들
                        // 사이에서 large(52)는 혼자 너무 크게 서 있었고, 폭이
                        // 이미 전체라 크기로 더 강조하지 않아도 다음 걸음인
                        // 것이 읽힌다. 높이는 테스트가 고정한다.
                        fullWidth: true,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 슬롯이 없거나 전부 찼거나 조회에 실패했을 때의 한 줄 안내.
class _SlotNotice extends StatelessWidget {
  const _SlotNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        const AppIcon(
          AppIcons.eventBusy,
          size: OnCareSize.iconSmall,
          color: OnCareColors.textTertiary,
        ),
        const SizedBox(width: OnCareSpacing.s8),
        Expanded(
          child: Text(
            message,
            style: context.oncare
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ),
        if (onRetry != null)
          AppButton(
            label: l.actionRetry,
            onPressed: onRetry,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
      ],
    );
  }
}

/// 이 트레이너에 대한 **내 예약** 목록과 취소 버튼. (#502)
///
/// 예약 패널 안에 두는 이유: 자리를 잡은 곳과 무르는 곳이 같아야 회원이 찾는다.
/// 별도 '예약 내역' 화면을 만들면 한 번 보고 다시 안 여는 자리가 하나 더 생긴다.
class _MyReservations extends StatelessWidget {
  const _MyReservations({
    required this.reservations,
    required this.label,
    required this.cancelling,
    required this.disabled,
    required this.onCancel,
  });

  final List<MyReservation> reservations;
  final String Function(DateTime) label;

  /// 취소 요청이 오가는 예약 id(있다면).
  final String? cancelling;
  final bool disabled;
  final ValueChanged<MyReservation> onCancel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OnCareSpacing.s12),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: tokens.brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.exMyReservations,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: tokens.brand.primary),
          ),
          for (final MyReservation r in reservations) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label(r.startsAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                        )
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                ),
                // 취소 가능 여부는 서버 판단(`cancellable`)을 따른다. 지난 예약은
                // 버튼 대신 그 사실을 적어 둔다 — 눌러도 실패할 버튼을 남기면
                // 회원은 앱이 고장 난 것으로 읽는다.
                if (!r.cancellable)
                  Text(
                    l.exReservationPast,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textSecondary),
                  )
                else if (cancelling == r.id)
                  const AppLoading.inline()
                else
                  AppButton(
                    key: ValueKey<String>('cancel-reservation-${r.id}'),
                    label: l.exCancelReservation,
                    onPressed: disabled ? null : () => onCancel(r),
                    variant: AppButtonVariant.destructiveText,
                    size: OnCareButtonSize.small,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
