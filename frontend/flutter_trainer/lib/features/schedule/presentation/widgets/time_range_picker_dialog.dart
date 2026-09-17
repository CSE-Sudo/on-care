import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

typedef TimeRangeValue = ({TimeOfDay start, TimeOfDay end});

/// 시 → 분 → 종료 시 → 종료 분을 한 시계에서 고르는 범위 선택기.
Future<TimeRangeValue?> showScheduleTimeRangePicker({
  required BuildContext context,
  required TimeOfDay start,
  required TimeOfDay end,
}) => showAppDialog<TimeRangeValue>(
  context: context,
  builder: (_) => _ScheduleTimePickerDialog(start: start, end: end),
);

/// 시각 **하나**를 같은 시계로 고르는 선택기 (#1425).
///
/// 프로그램 직접 만들기의 PT 등록 시각처럼 시작 시각만 필요한 자리가 쓴다.
/// 범위 선택기와 같은 대화상자를 단일 모드로 연다 — 단계만 시 → 분 둘이다.
Future<TimeOfDay?> showScheduleTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) => showAppDialog<TimeOfDay>(
  context: context,
  builder: (_) => _ScheduleTimePickerDialog(start: initialTime),
);

/// 모드마다 테스트·호출부가 찾는 키 이름. 두 모드의 키는 예전 그대로다.
@immutable
class _PickerKeys {
  const _PickerKeys.single()
    : startInput = 'session-time-input',
      endInput = null,
      back = 'session-time-back',
      next = 'session-time-next',
      periodPrefix = 'session-time-period',
      cancel = 'session-time-cancel',
      confirm = 'session-time-confirm',
      stepPrefix = 'session-time-step';

  const _PickerKeys.range()
    : startInput = 'session-time-range-start-input',
      endInput = 'session-time-range-end-input',
      back = 'time-range-back',
      next = 'time-range-next',
      periodPrefix = 'time-period',
      cancel = null,
      confirm = 'session-time-range-confirm',
      stepPrefix = 'time-range-step';

  final String startInput;
  final String? endInput;
  final String back;
  final String next;
  final String periodPrefix;
  final String? cancel;
  final String confirm;
  final String stepPrefix;
}

Key? _keyOf(String? value) => value == null ? null : ValueKey<String>(value);

/// 단일·범위 두 모드를 한 클래스로 그리는 시각 선택 대화상자.
///
/// [end] 가 없으면 단일 모드(시 → 분), 있으면 범위 모드(시 → 분 → 종료 시 →
/// 종료 분)다.
class _ScheduleTimePickerDialog extends StatefulWidget {
  const _ScheduleTimePickerDialog({required this.start, this.end});

  final TimeOfDay start;
  final TimeOfDay? end;

  @override
  State<_ScheduleTimePickerDialog> createState() =>
      _ScheduleTimePickerDialogState();
}

class _ScheduleTimePickerDialogState extends State<_ScheduleTimePickerDialog> {
  late TimeOfDay _start = widget.start;
  late TimeOfDay _end = widget.end ?? widget.start;
  late final TextEditingController _startController = TextEditingController(
    text: _clock(_start),
  );
  late final TextEditingController _endController = TextEditingController(
    text: _clock(_end),
  );
  final FocusNode _startFocus = FocusNode();
  final FocusNode _endFocus = FocusNode();
  int _step = 0;

  bool get _range => widget.end != null;
  _PickerKeys get _keys =>
      _range ? const _PickerKeys.range() : const _PickerKeys.single();
  int get _lastStep => _range ? 3 : 1;
  bool get _isStart => _step < 2;
  bool get _isHour => _step.isEven;
  TimeOfDay get _active => _isStart ? _start : _end;

  static String _clock(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _startFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  void _syncFields() {
    _startController.text = _clock(_start);
    _endController.text = _clock(_end);
  }

  void _readField(String text, {required bool start}) {
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(text.trim());
    if (match == null) return;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return;
    setState(() {
      final value = TimeOfDay(hour: hour, minute: minute);
      if (start) {
        _start = value;
        _step = 0;
      } else {
        _end = value;
        _step = 2;
      }
    });
  }

  void _setActiveValue(int value, {required bool advance}) {
    final current = _active;
    final next = _isHour
        ? TimeOfDay(hour: value, minute: current.minute)
        : TimeOfDay(hour: current.hour, minute: value);
    setState(() {
      if (_isStart) {
        _start = next;
      } else {
        _end = next;
      }
      if (advance && _step < _lastStep) _step++;
      _syncFields();
    });
  }

  void _setPeriod(bool pm) {
    final current = _active;
    final hour = current.hour % 12 + (pm ? 12 : 0);
    setState(() {
      final next = TimeOfDay(hour: hour, minute: current.minute);
      if (_isStart) {
        _start = next;
      } else {
        _end = next;
      }
      _syncFields();
    });
  }

  String _stepLabel(AppLocalizations l) {
    if (!_range) {
      return _isHour ? l.schedTimePickerHour : l.schedTimePickerMinute;
    }
    return switch (_step) {
      0 => l.schedTimePickerStartHour,
      1 => l.schedTimePickerStartMinute,
      2 => l.schedTimePickerEndHour,
      _ => l.schedTimePickerEndMinute,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final _PickerKeys keys = _keys;
    final endMinutes = _end.hour * 60 + _end.minute;
    final startMinutes = _start.hour * 60 + _start.minute;
    final bool invalidEnd = _range && endMinutes <= startMinutes;

    return AppDialog(
      // 작은 창(400) — 시계 지름 280 이 안쪽 여백 안에 들어간다.
      title: l.schedTimeRangeTitle,
      footer: AppButtonPair(
        cancelKey: _keyOf(keys.cancel),
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.pop(context),
        confirmKey: _keyOf(keys.confirm),
        confirmLabel: l.schedTimeRangeConfirm,
        onConfirm: invalidEnd
            ? null
            : () => _range
                  ? Navigator.pop(context, (start: _start, end: _end))
                  : Navigator.pop(context, _start),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_range)
            Row(
              children: <Widget>[
                Expanded(
                  child: _TimeValueBox(
                    fieldKey: keys.startInput,
                    label: l.slotStartTime,
                    controller: _startController,
                    focusNode: _startFocus,
                    active: _isStart,
                    onTap: () => setState(() => _step = 0),
                    onChanged: (value) => _readField(value, start: true),
                  ),
                ),
                SizedBox(
                  width: OnCareSpacing.s24,
                  child: Center(
                    child: Text(
                      '–',
                      style: tokens
                          .text(OnCareTypography.titleMedium)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ),
                ),
                Expanded(
                  child: _TimeValueBox(
                    fieldKey: keys.endInput!,
                    label: l.schedTimePickerEndTime,
                    controller: _endController,
                    focusNode: _endFocus,
                    active: !_isStart,
                    onTap: () => setState(() => _step = 2),
                    onChanged: (value) => _readField(value, start: false),
                  ),
                ),
              ],
            )
          else
            _TimeValueBox(
              fieldKey: keys.startInput,
              label: l.schedTimePickerTimeLabel,
              controller: _startController,
              focusNode: _startFocus,
              active: true,
              onTap: () => setState(() => _step = 0),
              onChanged: (value) => _readField(value, start: true),
            ),
          const SizedBox(height: OnCareSpacing.s16),
          SizedBox(
            height: OnCareSpacing.s48,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _stepLabel(l),
                    style: tokens
                        .text(OnCareTypography.label)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ),
                // 단일 모드는 두 화살표를 늘 두고, 범위 모드는 첫 단계를
                // 지난 뒤에만 보인다 — 예전 두 선택기의 동작 그대로다.
                if (!_range || _step > 0) ...<Widget>[
                  AppIconButton(
                    key: ValueKey<String>(keys.back),
                    icon: Icons.chevron_left_rounded,
                    tooltip: l.schedTimePickerPrevStep,
                    onPressed: _step > 0
                        ? () => setState(() => _step--)
                        : null,
                  ),
                  AppIconButton(
                    key: ValueKey<String>(keys.next),
                    icon: Icons.chevron_right_rounded,
                    tooltip: l.schedTimePickerNextStep,
                    onPressed: _step < _lastStep
                        ? () => setState(() => _step++)
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          SizedBox(
            height: OnCareSpacing.s48,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Visibility(
                  visible: _isHour,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainState: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      AppChoiceChip(
                        key: ValueKey<String>('${keys.periodPrefix}-am'),
                        label: l.slotAm,
                        selected: _active.hour < 12,
                        onSelected: (_) => _setPeriod(false),
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      AppChoiceChip(
                        key: ValueKey<String>('${keys.periodPrefix}-pm'),
                        label: l.slotPm,
                        selected: _active.hour >= 12,
                        onSelected: (_) => _setPeriod(true),
                      ),
                    ],
                  ),
                ),
                if (_step == 3 && invalidEnd)
                  Text(
                    l.schedTimePickerEndBeforeStart,
                    key: const ValueKey<String>('time-range-invalid-end'),
                    textAlign: TextAlign.center,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                        .copyWith(color: OnCareColors.danger),
                  ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          ScheduleClockDial(
            key: ValueKey<String>('${keys.stepPrefix}-$_step'),
            mode: _isHour ? ScheduleClockDialMode.hour : ScheduleClockDialMode.minute,
            selected: _isHour ? _active.hour : _active.minute,
            onChanged: (value) => _setActiveValue(value, advance: false),
            onSelected: (value) => _setActiveValue(value, advance: true),
          ),
        ],
      ),
    );
  }
}

/// 값 상자 — 라벨 + 가운데 큰 `HH:mm`. 활성 상자만 옅은 브랜드로 채운다.
///
/// 입력창 모양이 상자 안에 들어가야 해서 [AppTextField] 대신 [EditableText]
/// 를 직접 둔다. 상자 어디를 눌러도 이 값의 단계로 옮기고 입력에 초점을 준다.
class _TimeValueBox extends StatelessWidget {
  const _TimeValueBox({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.active,
    required this.onTap,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        key: ValueKey<String>(fieldKey),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          focusNode.requestFocus();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: OnCareSpacing.s12,
            vertical: OnCareSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: active ? tokens.brand.surface : OnCareColors.surfaceInput,
            borderRadius: OnCareRadius.mdAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                label,
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
              EditableText(
                controller: controller,
                focusNode: focusNode,
                // 탭은 바깥 상자가 받는다 — 글자 위를 눌러도 단계가 바뀐다.
                rendererIgnoresPointer: true,
                keyboardType: TextInputType.datetime,
                textAlign: TextAlign.center,
                onChanged: onChanged,
                onSubmitted: onChanged,
                onEditingComplete: () => onChanged(controller.text),
                style: OnCareTypography.numeric(
                  tokens.text(OnCareTypography.titleLarge),
                ).copyWith(
                  color: active
                      ? tokens.brand.primary
                      : OnCareColors.textPrimary,
                ),
                cursorColor: tokens.brand.primary,
                backgroundCursorColor: OnCareColors.lineStrong,
                selectionColor: tokens.brand.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 시계 다이얼이 고르는 값.
enum ScheduleClockDialMode {
  /// 0..23 시. 숫자는 1..12 로 보이고 오전·오후는 [ScheduleClockDial.selected]
  /// 의 값을 따른다.
  hour,

  /// 1..12 시. 오전·오후는 다이얼 밖에서 정한다.
  hour12,

  /// 0..55 분(5분 단위).
  minute,
}

/// 시계 다이얼 크기.
enum ScheduleClockDialSize {
  /// 선택기 한가운데 한 개.
  regular,

  /// 한 대화상자에 두 개를 위아래로 둘 때.
  compact,
}

/// 12칸이 원형으로 둘러선 스케줄 시계 다이얼(#1706).
///
/// 시각 선택기(시·분)와 시작·종료 대화상자(시만)가 함께 쓴다. 숫자 키는
/// `'$keyPrefix-$값'` 이다. [onChanged] 를 주면 끌어서 미리 보고 손을 떼면
/// [onSelected] 로 확정한다.
class ScheduleClockDial extends StatelessWidget {
  const ScheduleClockDial({
    super.key,
    required this.mode,
    required this.selected,
    required this.onSelected,
    this.onChanged,
    this.keyPrefix = 'clock-value',
    this.size = ScheduleClockDialSize.regular,
  });

  /// 숫자 칸 44 열두 개가 겹치지 않고 둘러서는 지름.
  static const double regularDiameter = 280;

  /// 다이얼 두 개를 한 대화상자에 쌓아도 넘치지 않는 지름.
  static const double compactDiameter = 220;

  /// 숫자 한 칸(원형 터치 영역) 지름.
  static const double _regularCell = 44;
  static const double _compactCell = 36;

  /// 테두리에서 숫자 중심까지 거리.
  static const double _regularInset = 32;
  static const double _compactInset = 22;

  /// 시곗바늘 굵기.
  static const double _handStrokeWidth = 3;

  final ScheduleClockDialMode mode;

  /// [mode] 의 값. hour = 0..23, hour12 = 1..12, minute = 0..59.
  final int selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onChanged;
  final String keyPrefix;
  final ScheduleClockDialSize size;

  bool get _compact => size == ScheduleClockDialSize.compact;
  double get _diameter => _compact ? compactDiameter : regularDiameter;
  double get _cell => _compact ? _compactCell : _regularCell;
  double get _numberRadius =>
      _diameter / 2 - (_compact ? _compactInset : _regularInset);

  int get _handIndex => mode == ScheduleClockDialMode.minute
      ? (selected / 5).round() % 12
      : selected % 12;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle numberStyle = OnCareTypography.numeric(
      tokens.text(OnCareTypography.label),
    );

    Widget face = Stack(
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _ClockHandPainter(
              index: _handIndex,
              length: _numberRadius,
              color: tokens.brand.primary,
            ),
          ),
        ),
        for (var index = 0; index < 12; index++)
          _number(context, l, tokens, numberStyle, index),
      ],
    );
    final ValueChanged<int>? preview = onChanged;
    if (preview != null) {
      face = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => preview(_valueAt(details.localPosition)),
        onPanEnd: (_) => onSelected(selected),
        child: face,
      );
    }

    return Center(
      child: SizedBox.square(
        dimension: _diameter,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: OnCareColors.surfaceInput,
            shape: BoxShape.circle,
          ),
          child: face,
        ),
      ),
    );
  }

  int _valueAt(Offset position) {
    final center = Offset(_diameter / 2, _diameter / 2);
    final delta = position - center;
    final raw =
        (math.atan2(delta.dy, delta.dx) + math.pi / 2) / (2 * math.pi) * 12;
    final index = raw.round() % 12;
    return switch (mode) {
      ScheduleClockDialMode.minute => index * 5,
      ScheduleClockDialMode.hour12 => index == 0 ? 12 : index,
      ScheduleClockDialMode.hour =>
        ((index == 0 ? 12 : index) % 12) + (selected >= 12 ? 12 : 0),
    };
  }

  Widget _number(
    BuildContext context,
    AppLocalizations l,
    OnCareTokens tokens,
    TextStyle numberStyle,
    int index,
  ) {
    final bool isMinute = mode == ScheduleClockDialMode.minute;
    final value = isMinute ? index * 5 : (index == 0 ? 12 : index);
    // 12시가 정각 위, 시계 방향으로 한 칸마다 30도.
    final angle = index * math.pi / 6 - math.pi / 2;
    final center = _diameter / 2;
    final bool active = isMinute
        ? selected == value
        : selected % 12 == value % 12;
    return Positioned(
      left: center + math.cos(angle) * _numberRadius - _cell / 2,
      top: center + math.sin(angle) * _numberRadius - _cell / 2,
      child: Semantics(
        button: true,
        selected: active,
        label: isMinute ? null : l.schedClockHourSemantics('$value'),
        excludeSemantics: !isMinute,
        child: InkWell(
          key: ValueKey<String>('$keyPrefix-$value'),
          customBorder: const CircleBorder(),
          onTap: () => onSelected(switch (mode) {
            ScheduleClockDialMode.hour =>
              (value % 12) + (selected >= 12 ? 12 : 0),
            _ => value,
          }),
          child: Container(
            width: _cell,
            height: _cell,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? tokens.brand.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              isMinute ? value.toString().padLeft(2, '0') : '$value',
              style: numberStyle.copyWith(
                color: active
                    ? OnCareColors.textOnFill
                    : OnCareColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockHandPainter extends CustomPainter {
  const _ClockHandPainter({
    required this.index,
    required this.length,
    required this.color,
  });

  final int index;
  final double length;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final angle = index * math.pi / 6 - math.pi / 2;
    final end = center + Offset(math.cos(angle), math.sin(angle)) * length;
    final paint = Paint()
      ..color = color
      ..strokeWidth = ScheduleClockDial._handStrokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, end, paint);
    canvas.drawCircle(center, OnCareSize.dot / 2, paint);
  }

  @override
  bool shouldRepaint(_ClockHandPainter oldDelegate) =>
      oldDelegate.index != index ||
      oldDelegate.length != length ||
      oldDelegate.color != color;
}
