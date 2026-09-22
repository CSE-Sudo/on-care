import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/time_range_picker_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 예약 슬롯 관리 내용. `showAppDialog` + `AppDialog(title: l.slotManageTitle,
/// size: medium)` 본문에 들어간다 — 제목·닫기(X)·스크롤은 다이얼로그 틀이
/// 맡고, 이 위젯은 틀 없이 내용만 세로로 쌓는다.
class ReservationSlotsSheet extends ConsumerStatefulWidget {
  const ReservationSlotsSheet({super.key, required this.selectedDay});

  final DateTime selectedDay;

  @override
  ConsumerState<ReservationSlotsSheet> createState() =>
      _ReservationSlotsSheetState();
}

class _ReservationSlotsSheetState extends ConsumerState<ReservationSlotsSheet> {
  late DateTime _date = widget.selectedDay;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  bool _saving = false;

  /// 정원 대신 종류를 고른다 — 슬롯은 늘 한 사람 몫이다(#1012). 회원 예약이
  /// 만드는 일정이 이 종류를 그대로 물려받는다(#1083).
  String _type = SessionType.personalTraining;

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  /// 24시간 표기로 고정한다 — `TimeOfDay.format(context)` 는 로케일 기본값
  /// (오전/오후 12시간제)을 따라가 이 시트만 다른 곳(스케줄 시간표 등)과
  /// 다른 표기로 보였다.
  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  DateTime _startsAt(TimeOfDay time) =>
      DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);

  int _duration(TimeOfDay start, TimeOfDay end) =>
      end.hour * 60 + end.minute - start.hour * 60 - start.minute;

  Future<void> _pickRange() async {
    final picked = await showScheduleTimeRangePicker(
      context: context,
      start: _time,
      end: _endTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _time = picked.start;
      _endTime = picked.end;
    });
  }

  /// 시트를 연 날짜만 볼 수 있던 것을 고친다 — 다른 날짜에 슬롯을 열려면
  /// 시트를 닫고 캘린더에서 날짜를 옮긴 뒤 다시 열어야 했다(#1090).
  Future<void> _pickDate() async {
    final today = nowKst();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _create() async {
    // await 전에 한 번만 잡아 둔다 — 뒤에서 context 를 다시 만지면 async gap 을
    // 건너 쓰게 된다.
    final AppLocalizations l = AppLocalizations.of(context);
    final startsAt = _startsAt(_time);
    if (!startsAt.isAfter(nowKst())) {
      _showMessage(l.slotPastTime);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(reservationSlotRepositoryProvider)
          .create(
            startsAt: startsAt,
            durationMinutes: _duration(_time, _endTime),
            sessionType: _type,
          );
      // 목록을 직접 무효화하지 않는다 — 리포지토리가 변경을 알리면 스트림이
      // 이어서 새 목록을 낸다(#1590). 무효화하면 구독이 처음부터 다시 서서
      // 방금 만든 자리 대신 로딩 표시가 한 번 스쳐 지나간다.
      _showMessage(l.slotOpened, type: AppToastType.success);
    } catch (error) {
      _showMessage(_errorMessage(l, error), type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close(ReservationSlot slot) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool confirmed = await showAppConfirmDialog(
      context: context,
      title: l.slotCloseTitle,
      message: l.slotCloseBody,
      confirmLabel: l.actionClose,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(reservationSlotRepositoryProvider).close(slot.id);
      _showMessage(l.slotClosed, type: AppToastType.success);
    } catch (error) {
      _showMessage(_errorMessage(l, error), type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorMessage(AppLocalizations l, Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] is String) {
        // 서버가 보낸 사유는 한국어 화면에서만 그대로 쓴다. (#501)
        return serverDetailOr(l, data['detail'] as String, l.slotActionFailed);
      }
    }
    if (error is StateError) {
      // 목 리포지토리는 코드를 던진다 — 문구는 여기서 붙인다. (#501)
      return switch (error.message.toString()) {
        SlotErrorCodes.futureOnly => l.slotFutureOnly,
        SlotErrorCodes.notFound => l.slotNotFound,
        SlotErrorCodes.typeLockedByBooking => l.slotTypeLockedByBooking,
        _ => l.slotActionFailed,
      };
    }
    return l.slotActionFailed;
  }

  void _showMessage(String message, {AppToastType type = AppToastType.info}) {
    if (!mounted) return;
    showAppToast(context, message, type: type);
  }

  /// 종류·날짜·시간 세 필드가 같은 모양으로 보이도록 쓰는 라벨 + 입력창 모양
  /// 상자 — `AppTextField`/`AppSelectField` 와 같은 틀(위 라벨, 채움 + 테두리
  /// 상자)이다. 눌러서 메뉴·선택창을 여는 자리라 글자 입력은 받지 않는다.
  Widget _fieldColumn({
    required String label,
    required IconData icon,
    required String value,
    required VoidCallback? onTap,
    Key? key,
  }) {
    final OnCareTokens tokens = context.oncare;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          InputDecorator(
            decoration: InputDecoration(
              enabled: onTap != null,
              prefixIcon: Icon(
                icon,
                size: OnCareSize.iconSmall,
                color: tokens.brand.primary,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: OnCareSpacing.s32,
              ),
              suffixIcon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: OnCareSize.iconMedium,
              ),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens
                  .text(OnCareTypography.body)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final slots = ref.watch(reservationSlotsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.slotIntro(l.dateMonthDay(_date.month, _date.day)),
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s16),
        // 종류·날짜·시간·추가 버튼은 "언제·누구 자리를 열까"를 정하고 실행하는
        // 같은 흐름이라 한 덩어리로 둔다(#1090). 넷을 한 줄에 세우던 때에는
        // 560 창에서 칸마다 글자 폭이 모자라 `9월 ...`·`10:0...` 처럼 잘렸다
        // (#2181). 두 줄로 나누어 종류·날짜 → 시간·열기 순서로 읽히게 한다 —
        // 실행 버튼은 여전히 흐름의 끝(오른쪽 아래)이다.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: AppMenu(
                items: <AppMenuItem>[
                  for (final t in SessionType.all)
                    AppMenuItem(
                      label: sessionTypeLabel(l, t),
                      selected: t == _type,
                      onSelected: () => setState(() => _type = t),
                    ),
                ],
                triggerBuilder: (context, toggle) => _fieldColumn(
                  key: const ValueKey<String>('slot-session-type'),
                  label: l.schedFieldType,
                  icon: Icons.badge_rounded,
                  value: sessionTypeLabel(l, _type),
                  onTap: _saving ? null : toggle,
                ),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(
              child: _fieldColumn(
                key: const ValueKey<String>('slot-date'),
                label: l.schedFieldDate,
                icon: Icons.calendar_today_rounded,
                value: l.dateMonthDay(_date.month, _date.day),
                onTap: _saving ? null : _pickDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: _fieldColumn(
                key: const ValueKey<String>('slot-time-range'),
                label: l.schedFieldTime,
                icon: Icons.schedule_rounded,
                value: '${_hhmm(_time)} – ${_hhmm(_endTime)}',
                onTap: _saving ? null : _pickRange,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            AppButton(
              key: const ValueKey<String>('slot-create'),
              label: l.slotOpenAction,
              leadingIcon: Icons.add_rounded,
              onPressed: _saving ? null : _create,
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s24),
        const AppDivider(),
        const SizedBox(height: OnCareSpacing.s12),
        slots.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (_, _) => Center(
            child: AppButton(
              label: l.slotReload,
              leadingIcon: Icons.refresh_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () => ref.invalidate(reservationSlotsProvider),
            ),
          ),
          data: (allSlots) {
            final daySlots = allSlots
                .where((slot) => _sameDay(slot.startsAt, _date))
                .toList();
            if (daySlots.isEmpty) {
              return AppEmptyState(
                title: l.slotEmpty,
                icon: Icons.event_available_rounded,
                placement: AppStatePlacement.card,
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < daySlots.length; i++) ...<Widget>[
                  if (i != 0) const SizedBox(height: OnCareSpacing.s8),
                  _slotRow(l, tokens, daySlots[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _slotRow(
    AppLocalizations l,
    OnCareTokens tokens,
    ReservationSlot slot,
  ) {
    // 닫혔거나 이미 예약된 자리는 "골라 쓸 수 없는 자리"라 같은 회색으로
    // 눌러 둔다 — 비어 있는 자리(흰 카드)와 구분된다.
    final taken = slot.isClosed || slot.booked;
    final TimeOfDay start = TimeOfDay.fromDateTime(slot.startsAt);
    final TimeOfDay end = TimeOfDay.fromDateTime(
      slot.startsAt.add(Duration(minutes: slot.durationMinutes)),
    );
    return Container(
      key: ValueKey<String>('slot-row-${slot.id}'),
      constraints: BoxConstraints(minHeight: tokens.density.listRowMin),
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.tilePadding,
        vertical: OnCareSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: taken ? OnCareColors.surfaceInput : OnCareColors.surfaceCard,
        border: Border.all(color: OnCareColors.lineStrong),
        borderRadius: OnCareRadius.mdAll,
      ),
      child: Row(
        children: <Widget>[
          // 종류 → 시간 순서다 — 새 일정 모달과 위 열기 폼(종류 → 날짜 →
          // 시간)이 같은 순서로 읽힌다.
          AppTag(
            label: sessionTypeLabel(l, slot.sessionType),
            tone: AppTagTone.brand,
          ),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Text(
              '${_hhmm(start)} – ${_hhmm(end)}',
              style: OnCareTypography.numeric(
                tokens.text(OnCareTypography.strong(OnCareTypography.body)),
              ).copyWith(color: OnCareColors.textPrimary),
            ),
          ),
          if (slot.isClosed)
            Text(
              l.slotClosedSummary,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            )
          else if (slot.booked)
            // 예약자 이름을 보여 준다(#1394) — 예전 수정·닫기 아이콘
            // 자리다. 이름이 아직 없으면(오래된 데이터 등) 상태 문구로
            // 대신한다.
            Text(
              slot.bookedByName ?? l.slotBookedSummary,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.body))
                  .copyWith(color: OnCareColors.textPrimary),
            )
          else
            // 아직 아무도 잡지 않은 자리만 지울 수 있다 — 수정 대신
            // 삭제다(#1394).
            AppIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: l.slotCloseAction,
              color: OnCareColors.danger,
              onPressed: _saving ? null : () => _close(slot),
            ),
        ],
      ),
    );
  }
}
