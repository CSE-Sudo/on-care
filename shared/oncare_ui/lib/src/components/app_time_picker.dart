import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
import 'package:oncare_ui/src/components/app_dialog.dart';
import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 시간 선택창에서 두 모드(시각 하나·시작~종료)가 함께 쓰는 글자.
///
/// 패키지는 번역을 들고 있지 않다 — 앱이 자기 arb 문구를 넣는다.
@immutable
class AppTimePickerLabels {
  const AppTimePickerLabels({
    required this.title,
    required this.am,
    required this.pm,
    required this.previousStep,
    required this.nextStep,
    required this.cancel,
    required this.confirm,
  });

  /// 창 제목(예: `시간 선택`).
  final String title;

  /// 오전·오후 알약.
  final String am;
  final String pm;

  /// 단계 화살표(이전·다음)의 접근성 이름.
  final String previousStep;
  final String nextStep;

  /// 하단 두 버튼.
  final String cancel;
  final String confirm;
}

/// 시각 **하나**를 고르는 시간 선택창(#1779).
///
/// 상담 신청 시간 선택창과 같은 모양에 시간 칸이 하나다 — 시 → 분 두 단계를
/// 시계판으로 고르고, 칸에 `HH:mm`(24시간)을 직접 칠 수도 있다. Material 기본
/// 시간 선택기와 달리 키보드 전환 버튼은 없다. 닫거나 취소하면 `null` 이다.
///
/// 테스트·호출부가 찾는 키는 `'$keyPrefix-…'` 다: `input`, `back`, `next`,
/// `period-am`·`period-pm`, `step-<단계>`, `clock-value-<값>`, `actions`.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  required AppTimePickerLabels labels,
  required String timeLabel,
  required String hourStepLabel,
  required String minuteStepLabel,
  String keyPrefix = 'app-time-picker',
}) {
  return showAppDialog<TimeOfDay>(
    context: context,
    builder: (_) => AppTimePickerDialog._(
      initialStart: initialTime,
      labels: labels,
      startLabel: timeLabel,
      startHourStepLabel: hourStepLabel,
      startMinuteStepLabel: minuteStepLabel,
      keyPrefix: keyPrefix,
    ),
  );
}

/// 시작·종료 시각을 **한 창에서** 차례로 고르는 시간 선택창(#1779).
///
/// `2db5b04` 시점 회원앱 상담 신청의 전용 시간 선택창을 규격 토큰으로 옮긴
/// 것이다. 위에 시작·종료 칸(누르면 그 값을 고르는 단계로 옮기고, `HH:mm` 을
/// 직접 칠 수 있다), 지금 고르는 단계 라벨과 화살표, 오전/오후 알약, 시계판
/// 순서다. 시작 시 → 시작 분 → 종료 시 → 종료 분 네 단계로 넘어간다.
///
/// 종료가 시작보다 이르거나 같으면 확인이 막히고, 종료 분 단계에서
/// [invalidEndMessage] 를 보인다. 닫거나 취소하면 `null` 이다.
///
/// 키는 [showAppTimePicker] 와 같고, 칸만 `start-input`·`end-input` 둘이며
/// 안내 문구는 `invalid-end` 다.
Future<({TimeOfDay start, TimeOfDay end})?> showAppTimeRangePicker({
  required BuildContext context,
  required TimeOfDay initialStart,
  required TimeOfDay initialEnd,
  required AppTimePickerLabels labels,
  required String startLabel,
  required String endLabel,
  required String startHourStepLabel,
  required String startMinuteStepLabel,
  required String endHourStepLabel,
  required String endMinuteStepLabel,
  required String invalidEndMessage,
  String keyPrefix = 'app-time-range-picker',
}) {
  return showAppDialog<({TimeOfDay start, TimeOfDay end})>(
    context: context,
    builder: (_) => AppTimePickerDialog._(
      initialStart: initialStart,
      labels: labels,
      startLabel: startLabel,
      startHourStepLabel: startHourStepLabel,
      startMinuteStepLabel: startMinuteStepLabel,
      keyPrefix: keyPrefix,
      end: _RangeEnd(
        initial: initialEnd,
        label: endLabel,
        hourStepLabel: endHourStepLabel,
        minuteStepLabel: endMinuteStepLabel,
        invalidMessage: invalidEndMessage,
      ),
    ),
  );
}

/// 범위 모드에만 있는 종료 시각 쪽 값·글자.
@immutable
class _RangeEnd {
  const _RangeEnd({
    required this.initial,
    required this.label,
    required this.hourStepLabel,
    required this.minuteStepLabel,
    required this.invalidMessage,
  });

  final TimeOfDay initial;
  final String label;
  final String hourStepLabel;
  final String minuteStepLabel;
  final String invalidMessage;
}

/// 시간 선택창 본체. [showAppTimePicker]·[showAppTimeRangePicker] 로만 연다.
///
/// 떠 있는 창을 테스트가 `find.byType` 으로 찾을 수 있게 타입만 공개한다.
class AppTimePickerDialog extends StatefulWidget {
  const AppTimePickerDialog._({
    required this.initialStart,
    required this.labels,
    required this.startLabel,
    required this.startHourStepLabel,
    required this.startMinuteStepLabel,
    required this.keyPrefix,
    _RangeEnd? end,
  }) : _end = end;

  final TimeOfDay initialStart;
  final AppTimePickerLabels labels;
  final String startLabel;
  final String startHourStepLabel;
  final String startMinuteStepLabel;
  final String keyPrefix;

  /// 없으면 시각 하나 모드(시 → 분), 있으면 범위 모드(네 단계)다.
  final _RangeEnd? _end;

  @override
  State<AppTimePickerDialog> createState() => _AppTimePickerDialogState();
}

class _AppTimePickerDialogState extends State<AppTimePickerDialog> {
  late TimeOfDay _start = widget.initialStart;
  late TimeOfDay _end = widget._end?.initial ?? widget.initialStart;
  late final TextEditingController _startController = TextEditingController(
    text: _clock(_start),
  );
  late final TextEditingController _endController = TextEditingController(
    text: _clock(_end),
  );

  /// 0 시작 시 · 1 시작 분 · 2 종료 시 · 3 종료 분. 시각 하나 모드는 0·1 뿐이다.
  int _step = 0;

  bool get _range => widget._end != null;
  int get _lastStep => _range ? 3 : 1;
  bool get _isStart => _step < 2;
  bool get _isHour => _step.isEven;
  TimeOfDay get _active => _isStart ? _start : _end;

  /// 범위로 쓸 수 없는 값 — 종료가 시작보다 이르거나 같다.
  bool get _endNotAfterStart => _range && _minutes(_end) <= _minutes(_start);

  static int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

  static String _clock(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  ValueKey<String> _key(String suffix) =>
      ValueKey<String>('${widget.keyPrefix}-$suffix');

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _syncFields() {
    _startController.text = _clock(_start);
    _endController.text = _clock(_end);
  }

  /// `HH:mm` 을 24시간 기준으로 읽는다 — 시계판이 12시간+오전/오후로만 고를 수
  /// 있는 것과 달리, 칸에는 `23:30` 처럼 바로 칠 수 있다. 치는 중인 글자는
  /// 덮어쓰지 않도록 칸은 다시 채우지 않는다.
  void _readField(String text, {required bool start}) {
    final RegExpMatch? match = RegExp(
      r'^(\d{1,2}):(\d{1,2})$',
    ).firstMatch(text.trim());
    if (match == null) return;
    final int? hour = int.tryParse(match.group(1)!);
    final int? minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return;
    setState(() {
      final TimeOfDay value = TimeOfDay(hour: hour, minute: minute);
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
    final TimeOfDay current = _active;
    final TimeOfDay next = _isHour
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
    final TimeOfDay current = _active;
    final TimeOfDay next = TimeOfDay(
      hour: current.hour % 12 + (pm ? 12 : 0),
      minute: current.minute,
    );
    setState(() {
      if (_isStart) {
        _start = next;
      } else {
        _end = next;
      }
      _syncFields();
    });
  }

  void _confirm() {
    if (_range) {
      Navigator.pop<({TimeOfDay start, TimeOfDay end})>(context, (
        start: _start,
        end: _end,
      ));
    } else {
      Navigator.pop<TimeOfDay>(context, _start);
    }
  }

  String get _stepLabel {
    final _RangeEnd? end = widget._end;
    if (_isStart || end == null) {
      return _isHour ? widget.startHourStepLabel : widget.startMinuteStepLabel;
    }
    return _isHour ? end.hourStepLabel : end.minuteStepLabel;
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppTimePickerLabels labels = widget.labels;
    final _RangeEnd? end = widget._end;

    return AppDialog(
      title: labels.title,
      // 두 버튼 규칙 — 취소 왼쪽, 확인 오른쪽, 폭 반반.
      footer: AppButtonPair(
        key: _key('actions'),
        cancelLabel: labels.cancel,
        onCancel: () => Navigator.pop(context),
        confirmLabel: labels.confirm,
        onConfirm: _endNotAfterStart ? null : _confirm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (end == null)
            _TimeValueBox(
              fieldKey: _key('input'),
              label: widget.startLabel,
              controller: _startController,
              active: true,
              onTap: () => setState(() => _step = 0),
              onChanged: (String value) => _readField(value, start: true),
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: _TimeValueBox(
                    fieldKey: _key('start-input'),
                    label: widget.startLabel,
                    controller: _startController,
                    active: _isStart,
                    onTap: () => setState(() => _step = 0),
                    onChanged: (String value) => _readField(value, start: true),
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
                    fieldKey: _key('end-input'),
                    label: end.label,
                    controller: _endController,
                    active: !_isStart,
                    onTap: () => setState(() => _step = 2),
                    onChanged: (String value) =>
                        _readField(value, start: false),
                  ),
                ),
              ],
            ),
          const SizedBox(height: OnCareSpacing.s16),
          SizedBox(
            height: OnCareSpacing.s48,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _stepLabel,
                    style: tokens
                        .text(OnCareTypography.label)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ),
                // 첫 단계에서는 화살표를 두지 않는다 — 옛 상담 선택창 그대로다.
                if (_step > 0) ...<Widget>[
                  AppIconButton(
                    key: _key('back'),
                    icon: Icons.chevron_left_rounded,
                    tooltip: labels.previousStep,
                    onPressed: () => setState(() => _step--),
                  ),
                  AppIconButton(
                    key: _key('next'),
                    icon: Icons.chevron_right_rounded,
                    tooltip: labels.nextStep,
                    onPressed: _step < _lastStep
                        ? () => setState(() => _step++)
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 오전/오후는 시 단계에만 보인다. 분 단계에서도 자리는 남겨 두어
          // 시계판이 오르내리지 않고, 비는 자리에 종료 시각 안내가 선다.
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
                      _PeriodPill(
                        tapKey: _key('period-am'),
                        label: labels.am,
                        selected: _active.hour < 12,
                        onTap: () => _setPeriod(false),
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      _PeriodPill(
                        tapKey: _key('period-pm'),
                        label: labels.pm,
                        selected: _active.hour >= 12,
                        onTap: () => _setPeriod(true),
                      ),
                    ],
                  ),
                ),
                if (end != null && _step == 3 && _endNotAfterStart)
                  Text(
                    end.invalidMessage,
                    key: _key('invalid-end'),
                    textAlign: TextAlign.center,
                    style: tokens
                        .text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                        )
                        .copyWith(color: OnCareColors.danger),
                  ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          AppClockDial(
            key: _key('step-$_step'),
            mode: _isHour ? AppClockDialMode.hour : AppClockDialMode.minute,
            selected: _isHour ? _active.hour : _active.minute,
            keyPrefix: '${widget.keyPrefix}-clock-value',
            onChanged: (int value) => _setActiveValue(value, advance: false),
            onSelected: (int value) => _setActiveValue(value, advance: true),
          ),
        ],
      ),
    );
  }
}

/// 값 칸 — 위 라벨 + 가운데 큰 `HH:mm`. 지금 고르는 칸만 옅은 브랜드로 채운다.
///
/// 칸 어디를 눌러도 그 값을 고르는 단계로 옮긴다. 글자는 입력창이라 직접 고칠
/// 수 있지만, 칸 모양은 입력창 테마(채움·테두리)를 따르지 않는다.
class _TimeValueBox extends StatelessWidget {
  const _TimeValueBox({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.active,
    required this.onTap,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            TextField(
              key: fieldKey,
              controller: controller,
              onTap: onTap,
              onChanged: onChanged,
              onSubmitted: onChanged,
              onEditingComplete: () => onChanged(controller.text),
              keyboardType: TextInputType.datetime,
              textAlign: TextAlign.center,
              // 테마의 입력 채움·테두리·최소 높이를 모두 끈다 — 칸 모양은
              // 바깥 상자가 그린다.
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              style:
                  OnCareTypography.numeric(
                    tokens.text(OnCareTypography.titleLarge),
                  ).copyWith(
                    color: active
                        ? tokens.brand.primary
                        : OnCareColors.textPrimary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오전·오후 알약. 선택은 옅은 브랜드 채움 + 브랜드 글자, 아니면 회색 채움이다.
class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.tapKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key tapKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? tokens.brand.surface : OnCareColors.surfaceInput,
        borderRadius: OnCareRadius.mdAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: tapKey,
          onTap: onTap,
          child: Container(
            height: tokens.density.chip,
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s24),
            alignment: Alignment.center,
            child: Text(
              label,
              style: tokens
                  .text(OnCareTypography.label)
                  .copyWith(
                    color: selected
                        ? tokens.brand.primary
                        : OnCareColors.textSecondary,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 시계판이 고르는 값.
enum AppClockDialMode {
  /// 0..23 시. 숫자는 1..12 로 보이고 오전·오후는 [AppClockDial.selected] 를
  /// 따른다.
  hour,

  /// 0..55 분(5분 단위).
  minute,
}

/// 12칸이 원형으로 둘러선 시계판(#1779) — 회색 판에 브랜드 바늘·선택 숫자.
///
/// 숫자를 누르면 [onSelected] 로 확정한다. [onChanged] 를 주면 판을 끌어 미리
/// 보고, 손을 떼면 [onSelected] 로 확정한다. 숫자 키는 `'$keyPrefix-$값'` 이다.
///
/// 지름은 [diameter] 지만 창이 그보다 좁으면(360 폭 폰의 모바일 창 등) 들어가는
/// 만큼 줄인다.
class AppClockDial extends StatelessWidget {
  const AppClockDial({
    super.key,
    required this.mode,
    required this.selected,
    required this.onSelected,
    this.onChanged,
    this.keyPrefix = 'app-clock-value',
  });

  /// 시계판 지름. 숫자 칸 열두 개가 겹치지 않고 둘러서는 크기다.
  static const double diameter = 280;

  /// 숫자 한 칸(원형 터치 영역) 지름 — 모바일 최소 터치 영역과 같다.
  static const double cellDiameter = 44;

  /// 판 가장자리에서 숫자 중심까지 거리.
  static const double numberInset = 32;

  /// 시곗바늘 굵기.
  static const double handStrokeWidth = 3;

  /// 바늘 가운데 점 지름.
  static const double hubDiameter = 10;

  final AppClockDialMode mode;

  /// [mode] 의 값. hour = 0..23, minute = 0..59.
  final int selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onChanged;
  final String keyPrefix;

  bool get _isMinute => mode == AppClockDialMode.minute;

  int get _handIndex => _isMinute ? (selected / 5).round() % 12 : selected % 12;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double size = math.min(diameter, constraints.maxWidth);
        final double numberRadius = size / 2 - numberInset;

        Widget face = Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _ClockHandPainter(
                  index: _handIndex,
                  length: numberRadius,
                  color: tokens.brand.primary,
                ),
              ),
            ),
            for (int index = 0; index < 12; index++)
              _number(tokens, index, size, numberRadius),
          ],
        );
        final ValueChanged<int>? preview = onChanged;
        if (preview != null) {
          face = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (DragUpdateDetails details) =>
                preview(_valueAt(details.localPosition, size)),
            onPanEnd: (_) => onSelected(selected),
            child: face,
          );
        }

        return Center(
          child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: OnCareColors.surfaceInput,
                shape: BoxShape.circle,
              ),
              child: face,
            ),
          ),
        );
      },
    );
  }

  int _valueAt(Offset position, double size) {
    final Offset delta = position - Offset(size / 2, size / 2);
    final double raw =
        (math.atan2(delta.dy, delta.dx) + math.pi / 2) / (2 * math.pi) * 12;
    final int index = raw.round() % 12;
    if (_isMinute) return index * 5;
    return index + (selected >= 12 ? 12 : 0);
  }

  Widget _number(
    OnCareTokens tokens,
    int index,
    double size,
    double numberRadius,
  ) {
    final int value = _isMinute ? index * 5 : (index == 0 ? 12 : index);
    // 12시가 정각 위, 시계 방향으로 한 칸마다 30도.
    final double angle = index * math.pi / 6 - math.pi / 2;
    final double center = size / 2;
    final bool active = _isMinute
        ? selected == value
        : selected % 12 == value % 12;
    return Positioned(
      left: center + math.cos(angle) * numberRadius - cellDiameter / 2,
      top: center + math.sin(angle) * numberRadius - cellDiameter / 2,
      child: Semantics(
        button: true,
        selected: active,
        child: InkWell(
          key: ValueKey<String>('$keyPrefix-$value'),
          customBorder: const CircleBorder(),
          onTap: () => onSelected(
            _isMinute ? value : (value % 12) + (selected >= 12 ? 12 : 0),
          ),
          child: Container(
            width: cellDiameter,
            height: cellDiameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? tokens.brand.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              _isMinute ? value.toString().padLeft(2, '0') : '$value',
              style:
                  OnCareTypography.numeric(
                    tokens.text(OnCareTypography.label),
                  ).copyWith(
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
    final Offset center = size.center(Offset.zero);
    final double angle = index * math.pi / 6 - math.pi / 2;
    final Offset end =
        center + Offset(math.cos(angle), math.sin(angle)) * length;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = AppClockDial.handStrokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, end, paint);
    canvas.drawCircle(center, AppClockDial.hubDiameter / 2, paint);
  }

  @override
  bool shouldRepaint(_ClockHandPainter oldDelegate) =>
      oldDelegate.index != index ||
      oldDelegate.length != length ||
      oldDelegate.color != color;
}
