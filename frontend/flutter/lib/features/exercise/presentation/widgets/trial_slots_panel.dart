/// 트레이너 빈 시간대 포인트 체험 예약. (#1790)
///
/// 트레이너가 `포인트 체험 허용` 으로 연 빈 시간에만, **담당 트레이너가 없는 회원**이
/// 500P 로 20분 자세 점검을 예약한다. 담당이 있는 회원에게는 그리지 않는다 — 다른
/// 트레이너가 기존 회원을 데려가는 통로가 되지 않게 한다(서버도 체험 자리를 내주지
/// 않는다).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 상세에 붙는 포인트 체험 상자. 보일 체험 자리도, 내 체험 예약도 없으면
/// 자리를 차지하지 않는다.
class TrialSlotsPanel extends ConsumerStatefulWidget {
  const TrialSlotsPanel({required this.trainer, super.key});

  final Trainer trainer;

  @override
  ConsumerState<TrialSlotsPanel> createState() => _TrialSlotsPanelState();
}

class _TrialSlotsPanelState extends ConsumerState<TrialSlotsPanel> {
  /// 고른 체험 자리 id.
  String? _selected;

  /// 예약·취소 요청이 오가는 중. 체험 예약은 포인트를 쓰므로 두 번 눌러도 한 번만
  /// 나가게 잠근다.
  bool _busy = false;

  static String _hhmm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// "9월 16일 10:00" — 헬스장 탭 예약 패널과 같은 표기.
  String _when(AppLocalizations l, DateTime at) => l.exSlotWhen(
    MaterialLocalizations.of(context).formatMediumDate(at),
    _hhmm(at),
  );

  /// 칩 한 줄 "9/16 10:00–10:20".
  static String _chipLabel(TrainerSlot slot) {
    final DateTime end = slot.startsAt.add(
      Duration(minutes: slot.durationMinutes),
    );
    return '${slot.startsAt.month}/${slot.startsAt.day} '
        '${_hhmm(slot.startsAt)}–${_hhmm(end)}';
  }

  /// 잔액·체험 가능 여부·내 예약이 함께 바뀌었다 — 모두 다시 읽는다.
  void _refresh() {
    ref
      ..invalidate(trainerSlotsProvider(widget.trainer.id))
      ..invalidate(myReservationsProvider)
      ..invalidate(myHealthStateProvider)
      ..invalidate(pointsShopProvider);
  }

  Future<void> _book(AppLocalizations l, TrainerSlot slot) async {
    if (_busy) return;
    final String when = _when(l, slot.startsAt);
    final String points = l.myPointsCost(slot.pointsCost);
    // 포인트를 쓰는 동작이라 파란 2열 확인창으로 한 번 묻는다.
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.exTrialConfirmTitle,
      message: l.exTrialConfirmBody(when, points),
      confirmLabel: l.exTrialConfirmAction,
      cancelLabel: l.myCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).reserve(slot.id);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      // 그사이 잔액·1회 조건이 바뀌었을 수 있다 — 다시 읽어 막힌 이유를 보여 준다.
      ref.invalidate(trainerSlotsProvider(widget.trainer.id));
      showAppToast(context, l.exTrialFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected = null;
    });
    _refresh();
    showAppToast(context, l.exTrialBooked(when), type: AppToastType.success);
  }

  Future<void> _cancel(AppLocalizations l, MyReservation reservation) async {
    if (_busy) return;
    final String when = _when(l, reservation.startsAt);
    final String points = l.myPointsCost(reservation.pointsCost);
    // 반환·소멸은 서버 판단(`points_refundable`)을 그대로 따른다.
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.exCancelConfirmTitle,
      message: reservation.pointsRefundable
          ? l.exTrialCancelRefundBody(when, points)
          : l.exTrialCancelForfeitBody(points),
      confirmLabel: l.exCancelReservation,
      cancelLabel: l.exCancelKeep,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).cancelReservation(reservation.id);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, l.exCancelFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _refresh();
    showAppToast(context, l.exCancelDone(when), type: AppToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trainer?> myTrainer = ref.watch(myTrainerProvider);
    // 담당이 있는 것으로 확인된 회원은 체험 자리를 읽지도 않는다. 담당을 읽는
    // 동안에는 체험 자리와 내 예약을 함께 읽어 둔다 — 담당이 없는 회원이 상자를
    // 한 박자 늦게 보지 않게 한다.
    if (myTrainer.valueOrNull != null) return const SizedBox.shrink();
    final List<TrainerSlot> trials =
        (ref.watch(trainerSlotsProvider(widget.trainer.id)).valueOrNull ??
                const <TrainerSlot>[])
            .where((TrainerSlot slot) => slot.isPointsTrial)
            .toList(growable: false);
    final List<MyReservation> mine =
        (ref.watch(myReservationsProvider).valueOrNull ??
                const <MyReservation>[])
            .where(
              (MyReservation r) =>
                  r.trainerId == widget.trainer.id &&
                  r.isPointsTrial &&
                  r.cancellable,
            )
            .toList(growable: false);
    // 담당 조회가 끝나 담당이 없을 때만 그린다. 읽는 중에 잠깐 떴다 사라지면
    // 담당 회원에게도 체험이 열린 것처럼 보인다.
    if (myTrainer is! AsyncData<Trainer?>) return const SizedBox.shrink();
    if (trials.isEmpty && mine.isEmpty) return const SizedBox.shrink();

    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<TrainerSlot> open = trials
        .where((TrainerSlot slot) => !slot.booked)
        .toList(growable: false);
    // 막힌 이유는 회원·트레이너 단위라 체험 자리마다 같다.
    final String? blocked = trials
        .map((TrainerSlot slot) => slot.trialBlockedReason)
        .whereType<String>()
        .firstOrNull;
    final TrainerSlot? picked = open
        .where((TrainerSlot slot) => slot.id == _selected)
        .firstOrNull;
    final String cost = l.myPointsCost(kPointsTrialCost);

    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.cardGap),
      child: AppCard(
        key: const Key('trainer-trial-panel'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                AppTag(label: l.exTrialTag, tone: AppTagTone.brand),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Text(
                    l.exTrialTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.titleSmall)
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              l.exTrialIntro(cost),
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            if (mine.isNotEmpty)
              _MyTrialBookings(
                reservations: mine,
                label: (DateTime at) => _when(l, at),
                disabled: _busy,
                onCancel: (MyReservation r) => _cancel(l, r),
              )
            else if (open.isEmpty)
              _Notice(message: l.exSlotsAllBooked)
            else ...<Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double itemWidth =
                      (constraints.maxWidth - OnCareSpacing.s8) / 2;
                  return Wrap(
                    spacing: OnCareSpacing.s8,
                    runSpacing: OnCareSpacing.s8,
                    children: <Widget>[
                      for (final TrainerSlot slot in open)
                        SizedBox(
                          width: itemWidth,
                          child: AppChoiceChip(
                            key: ValueKey<String>('trial-slot-chip-${slot.id}'),
                            label: _chipLabel(slot),
                            selected: picked?.id == slot.id,
                            onSelected: blocked != null || _busy
                                ? null
                                : (bool _) =>
                                      setState(() => _selected = slot.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (blocked != null) ...<Widget>[
                const SizedBox(height: OnCareSpacing.s8),
                _Notice(
                  key: const Key('trainer-trial-blocked'),
                  message: switch (blocked) {
                    TrialBlockedReason.trialUsed => l.exTrialUsed,
                    TrialBlockedReason.insufficientPoints =>
                      l.exTrialInsufficient(cost),
                    _ => l.exTrialFailed,
                  },
                ),
              ],
              const SizedBox(height: OnCareSpacing.s12),
              AppButton(
                key: const Key('trainer-trial-book'),
                label: l.exTrialBook(cost),
                onPressed: picked == null || blocked != null || _busy
                    ? null
                    : () => _book(l, picked),
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

/// 이 트레이너에 잡아 둔 체험 예약과 취소 버튼.
class _MyTrialBookings extends StatelessWidget {
  const _MyTrialBookings({
    required this.reservations,
    required this.label,
    required this.disabled,
    required this.onCancel,
  });

  final List<MyReservation> reservations;
  final String Function(DateTime) label;
  final bool disabled;
  final ValueChanged<MyReservation> onCancel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.exTrialMyBooking,
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: tokens.brand.primary),
        ),
        for (final MyReservation r in reservations)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label(r.startsAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              AppButton(
                key: ValueKey<String>('cancel-trial-${r.id}'),
                label: l.exCancelReservation,
                onPressed: disabled ? null : () => onCancel(r),
                variant: AppButtonVariant.destructiveText,
                size: OnCareButtonSize.small,
              ),
            ],
          ),
      ],
    );
  }
}

/// 한 줄 안내.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(
          Icons.info_rounded,
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
      ],
    );
  }
}
