import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/wheel_column.dart';

/// 시·분·초 휠에 붙는 글자.
///
/// 패키지는 번역을 들고 있지 않다 — 앱이 자기 arb 문구를 넣는다
/// ([AppTimeRangePickerLabels] 와 같은 규약이다).
@immutable
class AppDurationWheelLabels {
  const AppDurationWheelLabels({
    required this.hours,
    required this.minutes,
    required this.seconds,
  });

  /// 세 칸의 단위 이름 — `시` · `분` · `초`.
  ///
  /// 읽어 주는 쪽에도 이 말이 간다. 휠은 숫자만 보이므로, 이 이름이 없으면
  /// `30` 이 30분인지 30초인지 화면 밖에서는 알 수 없다.
  final String hours;
  final String minutes;
  final String seconds;
}

/// 걸린 시간을 **시 / 분 / 초** 세 휠로 고른다. (#2071)
///
/// 아이폰 시계 앱의 타이머와 같은 모양이다 — 세 칸이 나란히 서고, 각 칸을
/// 굴려 값을 맞춘다. 분 단위 스테퍼로는 45초짜리 운동을 적을 수 없었고,
/// 한 시간이 넘는 운동은 `90분` 처럼 분으로 환산해 올려야 했다.
///
/// 값은 **초 하나**다([duration]). 시·분·초를 따로 들고 다니면 세 값이 서로
/// 어긋난 채 흘러가는 자리가 생긴다 — 쓰는 쪽은 초 하나만 알면 된다.
///
/// [maxSeconds] 를 넘는 조합은 **애초에 고를 수 없다.** 상한에 닿은 칸의 아래
/// 칸이 그만큼 줄어든다 — 상한이 열 시간이면 `10 시간` 을 고르는 순간 분 칸에는
/// `0 분` 만 남는다. iOS 날짜 피커가 최소·최대 날짜를 다루는 방식과 같다.
///
/// 넘는 조합을 받아 두었다가 전체를 상한으로 끌어내리면, 방금 적은 분·초가
/// 말없이 사라진다 — 왜 0 이 되었는지가 화면 어디에도 없다.
class AppDurationWheel extends StatefulWidget {
  const AppDurationWheel({
    super.key,
    required this.duration,
    required this.onChanged,
    required this.labels,
    this.maxSeconds = 86400,
    this.itemExtent = 40,
    this.visibleItems = 3,
  });

  /// 지금 고른 시간. 음수는 0 으로 읽는다.
  final Duration duration;

  final ValueChanged<Duration> onChanged;
  final AppDurationWheelLabels labels;

  /// 고를 수 있는 가장 긴 시간(초). 기본값은 하루다.
  final int maxSeconds;

  /// 휠 한 칸의 높이와 보이는 칸 수. 시트처럼 세로가 아쉬운 자리에서 낮춘다.
  final double itemExtent;
  final int visibleItems;

  @override
  State<AppDurationWheel> createState() => _AppDurationWheelState();
}

class _AppDurationWheelState extends State<AppDurationWheel> {
  late final FixedExtentScrollController _hours;
  late final FixedExtentScrollController _minutes;
  late final FixedExtentScrollController _seconds;

  /// 휠이 스스로 움직이는 중. 상한에 걸려 되돌릴 때 그 애니메이션이 다시
  /// [onChanged] 를 부르지 않게 막는다 — 부르면 값이 한 번 더 잘린다.
  bool _settling = false;

  int get _total => widget.duration.inSeconds.clamp(0, widget.maxSeconds);

  /// 세 칸이 지금 가리키는 초. 휠이 아직 붙기 전이면 0 이다.
  int get _controllerSeconds {
    if (!_hours.hasClients || !_minutes.hasClients || !_seconds.hasClients) {
      return -1;
    }
    return _hours.selectedItem * 3600 +
        _minutes.selectedItem * 60 +
        _seconds.selectedItem;
  }

  /// 이 상한에서 시 칸이 보여 줄 마지막 값. 열 시간이 상한이면 `10` 이다.
  int get _maxHour => widget.maxSeconds ~/ 3600;

  /// 시가 [_maxHour] 일 때 분 칸이 보여 줄 마지막 값. 상한이 시에 딱 떨어지면
  /// `0` 이라, 분 칸에 `0 분` 하나만 남는다.
  int get _maxMinuteAtMaxHour => widget.maxSeconds % 3600 ~/ 60;

  /// 시·분이 모두 상한일 때 초 칸이 보여 줄 마지막 값.
  int get _maxSecondAtMax => widget.maxSeconds % 60;

  /// 지금 고른 시에서 분 칸이 담을 칸 수.
  int get _minuteCount =>
      _selectedHour >= _maxHour ? _maxMinuteAtMaxHour + 1 : 60;

  /// 지금 고른 시·분에서 초 칸이 담을 칸 수.
  int get _secondCount =>
      _selectedHour >= _maxHour && _selectedMinute >= _maxMinuteAtMaxHour
      ? _maxSecondAtMax + 1
      : 60;

  /// 지금 고른 시·분. 컨트롤러가 아니라 여기서 읽는 이유는 **첫 빌드**다 —
  /// 그때는 휠이 아직 붙지 않아 `hasClients` 가 거짓이고, 컨트롤러에서 읽으면
  /// 0 시로 읽혀 분 칸이 60칸으로 그려진다(상한이 걸린 값으로 열었을 때 틀린
  /// 칸 수다).
  late int _selectedHour;
  late int _selectedMinute;

  @override
  void initState() {
    super.initState();
    final int total = _total;
    _selectedHour = total ~/ 3600;
    _selectedMinute = total % 3600 ~/ 60;
    _hours = FixedExtentScrollController(initialItem: _selectedHour);
    _minutes = FixedExtentScrollController(initialItem: _selectedMinute);
    _seconds = FixedExtentScrollController(initialItem: total % 60);
  }

  @override
  void didUpdateWidget(AppDurationWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // **밖에서** 값이 바뀐 경우만 휠을 옮긴다. 세 칸이 이미 그 값을 가리키고
    // 있으면 우리가 올려보낸 값이 되돌아온 것이다 — 그때 옮기면 튕기는 중인
    // 휠이 첫 칸에서 멎는다(`onSelectedItemChanged` 는 지나는 칸마다 울린다).
    if (_controllerSeconds == _total) return;
    _jumpTo(_total);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _jumpTo(int total) {
    _settling = true;
    _selectedHour = total ~/ 3600;
    _selectedMinute = total % 3600 ~/ 60;
    _hours.jumpToItem(_selectedHour);
    _minutes.jumpToItem(_selectedMinute);
    _seconds.jumpToItem(total % 60);
    _settling = false;
  }

  /// 세 칸이 지금 가리키는 초를 올려보낸다. 어느 칸을 굴렸든 셋을 함께 읽는다.
  void _emit() {
    if (_settling) return;
    final int raw = _controllerSeconds;
    if (raw < 0) return;
    // 시를 상한까지 올리면 아래 칸이 줄어든다. 줄어든 칸 밖에 서 있던 값은
    // 그 칸의 마지막 값으로 내려온다 — 줄어든 칸이 화면에 보이므로 왜
    // 내려왔는지가 읽힌다.
    final int clamped = raw > widget.maxSeconds ? widget.maxSeconds : raw;
    if (clamped != raw) {
      _jumpTo(clamped);
    } else {
      _selectedHour = _hours.selectedItem;
      _selectedMinute = _minutes.selectedItem;
    }
    // 칸 수가 시·분 선택을 따라가므로 여기서 다시 그린다.
    setState(() {});
    widget.onChanged(Duration(seconds: clamped));
  }

  @override
  Widget build(BuildContext context) {
    Widget column(
      FixedExtentScrollController controller,
      int count,
      String unit,
    ) => Expanded(
      child: WheelColumn(
        controller: controller,
        count: count,
        labelAt: (int index) => '$index',
        unit: unit,
        itemExtent: widget.itemExtent,
        onSelectedItemChanged: (int _) => _emit(),
      ),
    );
    return SizedBox(
      height: widget.itemExtent * widget.visibleItems,
      child: WheelBand(
        itemExtent: widget.itemExtent,
        child: Row(
          children: <Widget>[
            column(_hours, _maxHour + 1, widget.labels.hours),
            column(_minutes, _minuteCount, widget.labels.minutes),
            column(_seconds, _secondCount, widget.labels.seconds),
          ],
        ),
      ),
    );
  }
}

/// 걸린 시간을 사람이 읽는 말로 — **적은 만큼만** 보인다. (#2071)
///
/// `45초` · `30분` · `1시간 5분 30초`. 0 인 칸은 빼므로, 딱 떨어지는 30분은
/// 예전(`30분`)과 같은 모양으로 읽힌다 — 초를 적었을 때만 길어진다.
///
/// 0 이면 `0[secondsUnit]` 이다. 빈 문자열을 돌려주면 부르는 쪽마다 빈 칸을
/// 다르게 메운다.
String formatDurationParts(
  Duration duration, {
  required String hoursUnit,
  required String minutesUnit,
  required String secondsUnit,
}) {
  final int total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final List<String> parts = <String>[
    if (total ~/ 3600 > 0) '${total ~/ 3600}$hoursUnit',
    if (total % 3600 ~/ 60 > 0) '${total % 3600 ~/ 60}$minutesUnit',
    if (total % 60 > 0) '${total % 60}$secondsUnit',
  ];
  return parts.isEmpty ? '0$secondsUnit' : parts.join(' ');
}
