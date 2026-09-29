import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/wheel_column.dart';

/// 숫자 휠 한 칸의 규격 — 범위·걸음·단위와 지금 값. (#2545)
///
/// 칸마다 값을 따로 올려보낸다. 세트·횟수·중량은 서로 묶인 값이 아니라,
/// 시·분·초처럼 하나로 합칠 까닭이 없다.
@immutable
class AppNumberWheelColumn {
  const AppNumberWheelColumn({
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.step = 1,
    this.key,
  }) : assert(step > 0),
       assert(max >= min);

  final double value;
  final double min;
  final double max;

  /// 한 칸의 간격. 중량은 원판 단위인 0.5 다.
  final double step;

  /// 숫자 뒤에 붙는 단위(`세트` · `회` · `kg`). 읽어 주는 쪽에도 간다.
  final String unit;
  final ValueChanged<double> onChanged;

  /// 이 칸의 이름표. 같은 자리에서 칸이 **바뀌면**(횟수 ↔ 버티는 시간) 키도
  /// 달라야 한다 — 같은 키면 앞 칸의 휠 위치를 이어받는다.
  final Key? key;

  int get _count => ((max - min) / step).round() + 1;

  /// [v] 에 가장 가까운 칸. 범위 밖이면 끝 칸이다.
  int _indexOf(double v) => ((v.clamp(min, max) - min) / step).round();

  /// [index] 칸의 값. 걸음을 더해 가며 쌓인 부동소수 오차(0.1 + 0.2)를
  /// 걸음의 자릿수로 지운다.
  double _valueAt(int index) =>
      double.parse((min + index * step).toStringAsFixed(_decimals));

  /// 걸음이 정수면 0, 0.5 면 1.
  int get _decimals {
    final String text = step.toString();
    return text.endsWith('.0') || !text.contains('.')
        ? 0
        : text.split('.').last.length;
  }

  /// 칸에 적히는 숫자. 딱 떨어지면 소수점을 빼 `40` 과 `40.5` 로 읽힌다.
  String _labelAt(int index) {
    final double v = _valueAt(index);
    return v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(_decimals);
  }
}

/// 숫자 여러 칸을 **한 줄의 휠**로 고른다. (#2545)
///
/// [AppDurationWheel] 과 같은 띠·같은 칸 높이·같은 숫자 크기다. 근력의
/// 세트·횟수·중량을 스테퍼 세 줄로 받으면, 같은 시트에서 유산소(시간 휠)를
/// 근력으로 바꾸는 순간 폼이 길어지고 모양이 달라졌다.
///
/// 칸 수에 제한은 없지만 폰 폭에서 읽히는 것은 세 칸까지다.
class AppNumberWheel extends StatelessWidget {
  const AppNumberWheel({
    super.key,
    required this.columns,
    this.itemExtent = 40,
    this.visibleItems = 3,
  });

  final List<AppNumberWheelColumn> columns;

  /// 휠 한 칸의 높이와 보이는 칸 수 — [AppDurationWheel] 과 같은 기본값이다.
  final double itemExtent;
  final int visibleItems;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: itemExtent * visibleItems,
    child: WheelBand(
      itemExtent: itemExtent,
      child: Row(
        children: <Widget>[
          for (final AppNumberWheelColumn column in columns)
            Expanded(
              child: _NumberColumn(
                key: column.key ?? ValueKey<String>(column.unit),
                column: column,
                itemExtent: itemExtent,
              ),
            ),
        ],
      ),
    ),
  );
}

class _NumberColumn extends StatefulWidget {
  const _NumberColumn({
    super.key,
    required this.column,
    required this.itemExtent,
  });

  final AppNumberWheelColumn column;
  final double itemExtent;

  @override
  State<_NumberColumn> createState() => _NumberColumnState();
}

class _NumberColumnState extends State<_NumberColumn> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(
        initialItem: widget.column._indexOf(widget.column.value),
      );

  /// 휠을 밖의 값으로 옮기는 중. 그 이동이 다시 [AppNumberWheelColumn.onChanged]
  /// 를 부르지 않게 막는다 — 빌드 도중에 부모의 `setState` 가 불린다.
  bool _settling = false;

  @override
  void didUpdateWidget(_NumberColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // **밖에서** 값이 바뀐 경우만 휠을 옮긴다. 휠이 이미 그 칸에 서 있으면
    // 우리가 올려보낸 값이 되돌아온 것이다 — 그때 옮기면 굴러가는 중인 휠이
    // 멎는다(`onSelectedItemChanged` 는 지나는 칸마다 울린다).
    if (!_controller.hasClients) return;
    final int target = widget.column._indexOf(widget.column.value);
    if (_controller.selectedItem == target) return;
    _settling = true;
    _controller.jumpToItem(target);
    _settling = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppNumberWheelColumn column = widget.column;
    return WheelColumn(
      controller: _controller,
      count: column._count,
      labelAt: column._labelAt,
      unit: column.unit,
      itemExtent: widget.itemExtent,
      onSelectedItemChanged: (int index) {
        if (!_settling) column.onChanged(column._valueAt(index));
      },
    );
  }
}
