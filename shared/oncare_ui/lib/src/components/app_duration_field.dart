import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oncare_ui/src/components/app_duration_wheel.dart';
import 'package:oncare_ui/src/components/app_inputs.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 걸린 시간을 **시 / 분 / 초** 세 칸으로 적는다 — 웹용. (#2221)
///
/// [AppDurationWheel] 과 같은 값(초 하나)·같은 라벨을 받는다. 휠은 손가락으로
/// 굴리는 모바일에 맞고, 마우스로는 한 칸에 1씩 움직여 45초를 맞추려면 45번을
/// 굴려야 한다 — 트레이너 웹은 이 칸을 쓴다.
///
/// 세 칸 모두 **직접 친다.** 칸에 들어가면 값이 전체 선택되고, 두 자리를 치면
/// 다음 칸으로 넘어간다. ↑↓ 는 그 칸의 단위로 1씩 옮기고, Enter·Esc 로 닫는다.
///
/// 칸을 누르면 **그 칸 바로 아래**에 그 단위의 목록이 뜬다. 고르면 다음 칸으로
/// 넘어가고 목록도 따라간다(초에서 고르면 닫힌다). 직접 치면 목록이 그 값으로
/// 따라온다. 목록이 칸을 덮으면 지금 값이 가려져, 칸 위가 아니라 아래에 둔다.
///
/// 분에 `90` 처럼 넘치는 값을 치면 세 칸을 **벗어날 때** `1시간 30분` 으로
/// 정리한다. 치는 동안 고쳐 쓰면 `9` 를 지나 `90` 으로 가는 길이 막힌다.
///
/// [maxSeconds] 를 넘는 조합은 목록에서 고를 수 없다 — 휠과 같은 규칙이다.
/// 직접 쳐서 넘긴 값은 상한으로 내려 보내고, 칸을 벗어날 때 칸도 그 값으로
/// 다시 채운다.
class AppDurationField extends StatefulWidget {
  const AppDurationField({
    super.key,
    required this.duration,
    required this.onChanged,
    required this.labels,
    this.label,
    this.maxSeconds = 86400,
    this.keyPrefix = 'duration',
  });

  /// 지금 적힌 시간. 음수는 0 으로 읽는다.
  final Duration duration;

  final ValueChanged<Duration> onChanged;

  /// 세 칸의 단위 이름 — 휠과 같은 규약이다.
  final AppDurationWheelLabels labels;

  /// 세 칸 위에 서는 이름(`운동 시간`). 없으면 칸만 그린다.
  final String? label;

  /// 적을 수 있는 가장 긴 시간(초). 기본값은 하루다.
  final int maxSeconds;

  /// 칸·목록 항목 키의 앞머리. 칸은 `<keyPrefix>-hours` · `-minutes` ·
  /// `-seconds`, 목록 항목은 `<keyPrefix>-minutes-option-30` 처럼 붙는다.
  final String keyPrefix;

  @override
  State<AppDurationField> createState() => _AppDurationFieldState();
}

/// 세 칸의 순서. 키 이름과 한 칸이 올라가는 초가 여기서 나온다.
enum _Part {
  hours('hours', 3600),
  minutes('minutes', 60),
  seconds('seconds', 1);

  const _Part(this.key, this.unitSeconds);

  final String key;
  final int unitSeconds;
}

class _AppDurationFieldState extends State<AppDurationField> {
  final Map<_Part, TextEditingController> _controllers =
      <_Part, TextEditingController>{
        for (final _Part part in _Part.values) part: TextEditingController(),
      };
  final Map<_Part, FocusNode> _focus = <_Part, FocusNode>{
    for (final _Part part in _Part.values) part: FocusNode(),
  };
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  /// 목록이 붙은 칸. 세 칸 어디에도 포커스가 없으면 비어 있다.
  _Part? _active;

  /// 세 칸이 선 줄의 폭 — 목록을 그 칸 폭에 맞춰 세운다.
  double _rowWidth = 0;

  bool get _anyFocused => _focus.values.any((FocusNode n) => n.hasFocus);

  int get _clamped =>
      widget.duration.inSeconds.clamp(0, widget.maxSeconds).toInt();

  @override
  void initState() {
    super.initState();
    _fill(_clamped);
    for (final _Part part in _Part.values) {
      _focus[part]!.addListener(() => _focusChanged(part));
    }
  }

  @override
  void didUpdateWidget(AppDurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 적는 동안에는 칸을 다시 채우지 않는다 — 우리가 올려보낸 값이 되돌아온
    // 것이고, 다시 채우면 치던 `9` 가 `9분` 으로 굳어 커서가 튄다.
    if (!_anyFocused && _typedTotal != _clamped) _fill(_clamped);
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    for (final FocusNode f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _focusChanged(_Part part) {
    if (_focus[part]!.hasFocus) {
      setState(() => _active = part);
      _portal.show();
      // 들어오면 전체 선택 — 오른쪽 정렬 칸은 누른 자리에 커서가 서서, 그대로
      // 치면 `0` 앞에 붙어 `450` 이 된다. 누름이 커서를 놓은 **뒤에** 고른다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final TextEditingController c = _controllers[part]!;
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      });
    }
    // 칸 사이를 옮겨 가는 동안에는 한 칸이 잃고 다음 칸이 얻는 사이가 있다.
    // 그 틈에 닫았다 열면 목록이 깜빡이고 넘치는 값이 너무 일찍 정리된다 —
    // 한 프레임 뒤에 셋 다 비었을 때만 닫는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anyFocused) return;
      _fill(_typedTotal);
      _portal.hide();
      setState(() => _active = null);
    });
  }

  int _read(_Part part) => int.tryParse(_controllers[part]!.text) ?? 0;

  /// 세 칸에 적힌 대로의 초. 분 `90` 처럼 넘치는 칸도 그대로 더하고, 상한으로
  /// 내린다.
  int get _typedTotal => (_Part.values.fold<int>(
    0,
    (int sum, _Part part) => sum + _read(part) * part.unitSeconds,
  )).clamp(0, widget.maxSeconds).toInt();

  void _fill(int total) {
    _controllers[_Part.hours]!.text = '${total ~/ 3600}';
    _controllers[_Part.minutes]!.text = '${total % 3600 ~/ 60}';
    _controllers[_Part.seconds]!.text = '${total % 60}';
  }

  void _emit() {
    setState(() {});
    widget.onChanged(Duration(seconds: _typedTotal));
  }

  void _next(_Part part) {
    if (part == _Part.seconds) {
      _focus[part]!.unfocus();
    } else {
      _focus[_Part.values[part.index + 1]]!.requestFocus();
    }
  }

  /// 두 자리를 치면 다음 칸으로. 초 칸은 마지막이라 그대로 둔다 — 치자마자
  /// 닫히면 방금 친 값을 목록에서 확인하거나 고칠 틈이 없다.
  void _typed(_Part part, String text) {
    _emit();
    if (text.length >= 2 && part != _Part.seconds) _next(part);
  }

  void _bump(_Part part, int delta) {
    final int next = (_typedTotal + delta * part.unitSeconds)
        .clamp(0, widget.maxSeconds)
        .toInt();
    _fill(next);
    final TextEditingController c = _controllers[part]!;
    c.selection = TextSelection.collapsed(offset: c.text.length);
    _emit();
  }

  void _pick(_Part part, int value) {
    _controllers[part]!.text = '$value';
    // 고른 값이 상한을 넘기면(10시간을 고른 뒤 30분) 칸째로 상한에 맞춘다 —
    // 목록이 넘는 값을 보여 주지 않으므로 여기 오는 일은 드물다.
    if (_typedTotal == widget.maxSeconds) _fill(widget.maxSeconds);
    _emit();
    _next(part);
  }

  /// 이 칸의 목록이 담을 값 수. 상한에 닿은 칸의 아래 칸은 그만큼 줄어든다
  /// ([AppDurationWheel] 과 같은 규칙).
  int _optionCount(_Part part) {
    final int maxHour = widget.maxSeconds ~/ 3600;
    final int maxMinuteAtMaxHour = widget.maxSeconds % 3600 ~/ 60;
    switch (part) {
      case _Part.hours:
        return maxHour + 1;
      case _Part.minutes:
        return _read(_Part.hours) >= maxHour ? maxMinuteAtMaxHour + 1 : 60;
      case _Part.seconds:
        return _read(_Part.hours) >= maxHour &&
                _read(_Part.minutes) >= maxMinuteAtMaxHour
            ? widget.maxSeconds % 60 + 1
            : 60;
    }
  }

  String _unit(_Part part) => switch (part) {
    _Part.hours => widget.labels.hours,
    _Part.minutes => widget.labels.minutes,
    _Part.seconds => widget.labels.seconds,
  };

  KeyEventResult _onKey(_Part part, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _bump(part, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _bump(part, -1);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.escape)) {
      _focus[part]!.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _box(BuildContext context, _Part part) {
    final OnCareTokens tokens = context.oncare;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (FocusNode _, KeyEvent event) => _onKey(part, event),
      child: AppTextField(
        key: ValueKey<String>('${widget.keyPrefix}-${part.key}'),
        controller: _controllers[part],
        focusNode: _focus[part],
        textAlign: TextAlign.end,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        onChanged: (String text) => _typed(part, text),
        suffix: Padding(
          padding: const EdgeInsetsDirectional.only(end: OnCareSpacing.s12),
          child: Center(
            widthFactor: 1,
            child: Text(
              _unit(part),
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final _Part? active = _active;
    if (active == null) return const SizedBox.shrink();
    final OnCareTokens tokens = context.oncare;
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, OnCareSpacing.s4),
      child: Align(
        alignment: Alignment.topLeft,
        // 목록을 눌러도 칸의 포커스가 빠지지 않게 칸과 같은 탭 영역으로 묶는다.
        // 빠지면 누르는 순간 목록이 닫혀 고른 값이 들어가지 않는다.
        child: TextFieldTapRegion(
          child: SizedBox(
            width: _rowWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final _Part part in _Part.values) ...<Widget>[
                  if (part != _Part.hours)
                    const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    child: part == active
                        ? _OptionList(
                            key: ValueKey<String>(
                              '${widget.keyPrefix}-${part.key}-options',
                            ),
                            keyPrefix: '${widget.keyPrefix}-${part.key}',
                            count: _optionCount(part),
                            unit: _unit(part),
                            selected: _read(part),
                            rowHeight: tokens.density.menuItem,
                            onPick: (int value) => _pick(part, value),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Widget row = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _rowWidth = constraints.maxWidth;
        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _overlay,
          child: CompositedTransformTarget(
            link: _link,
            child: Row(
              children: <Widget>[
                for (final _Part part in _Part.values) ...<Widget>[
                  if (part != _Part.hours)
                    const SizedBox(width: OnCareSpacing.s8),
                  Expanded(child: _box(context, part)),
                ],
              ],
            ),
          ),
        );
      },
    );
    final String? label = widget.label;
    if (label == null) return row;
    return Column(
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
        row,
      ],
    );
  }
}

/// 한 칸 아래에 뜨는 목록 — `0..count-1`.
///
/// 메뉴 규격(#1693)을 따른다: 흰 바탕·반경 12·`lineStrong` 테두리·떠 있는
/// 요소 그림자, 항목 높이는 밀도의 `menuItem`. 지금 값은 바로 위 칸에 이미
/// 보이므로 체크(정렬·필터 메뉴의 표시)는 두지 않고, 선택 칩처럼 옅은 브랜드
/// 바탕과 브랜드색 글자로 짚는다.
class _OptionList extends StatefulWidget {
  const _OptionList({
    super.key,
    required this.keyPrefix,
    required this.count,
    required this.unit,
    required this.selected,
    required this.rowHeight,
    required this.onPick,
  });

  final String keyPrefix;
  final int count;
  final String unit;
  final int selected;
  final double rowHeight;
  final ValueChanged<int> onPick;

  /// 한 번에 보이는 줄 수. 나머지는 스크롤한다.
  static const int visibleRows = 6;

  @override
  State<_OptionList> createState() => _OptionListState();
}

class _OptionListState extends State<_OptionList> {
  /// 지금 값이 위에서 셋째 줄에 오게 둔다 — 앞뒤 값이 함께 보인다.
  double _offsetFor(int value) =>
      ((value - 2) * widget.rowHeight).clamp(0, double.infinity).toDouble();

  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _offsetFor(widget.selected),
  );

  @override
  void didUpdateWidget(_OptionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 칸에 직접 친 값을 목록이 따라온다.
    if (oldWidget.selected != widget.selected && _scroll.hasClients) {
      _scroll.animateTo(
        _offsetFor(widget.selected)
            .clamp(0, _scroll.position.maxScrollExtent)
            .toDouble(),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      constraints: BoxConstraints(
        maxHeight:
            widget.rowHeight * _OptionList.visibleRows + OnCareSpacing.s8,
      ),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.fromBorderSide(
          BorderSide(color: OnCareColors.lineStrong),
        ),
        boxShadow: OnCareShadows.overlay,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: ListView.builder(
          controller: _scroll,
          shrinkWrap: true,
          itemExtent: widget.rowHeight,
          padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
          itemCount: widget.count,
          itemBuilder: (BuildContext context, int value) {
            final bool selected = value == widget.selected;
            return Semantics(
              selected: selected,
              button: true,
              child: Material(
                color: selected ? tokens.brand.surface : Colors.transparent,
                child: InkWell(
                  key: ValueKey<String>('${widget.keyPrefix}-option-$value'),
                  onTap: () => widget.onPick(value),
                  hoverColor: tokens.brand.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: OnCareSpacing.s12,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '$value${widget.unit}',
                        style:
                            OnCareTypography.numeric(
                              tokens.text(OnCareTypography.bodySmall),
                            ).copyWith(
                              color: selected
                                  ? tokens.brand.primary
                                  : OnCareColors.textPrimary,
                              fontWeight: selected ? FontWeight.w600 : null,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
