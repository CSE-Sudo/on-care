import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 한 줄에 들어가는 만큼만 [items] 를 앞에서부터 세우고, 넘치는 것은
/// `+N` 칩 하나로 묶는다(#2330).
///
/// [Wrap] 은 넘치면 줄을 늘리고, [Row] 는 넘치면 깨진다. 회원 상세 헤더의
/// 신호 배지는 몇 개가 걸리든 한 줄 높이를 지켜야 해서 둘 다 맞지 않는다.
///
/// [moreBuilder] 는 숨긴 개수(1…[items] 길이)마다 칩을 하나씩 만든다. 칩의
/// 폭이 개수에 따라 달라서(`+1` 과 `+12`), 몇 개를 숨길지는 레이아웃에서
/// 실제 폭을 재 본 뒤에야 정해진다. 칩은 모두 만들되 고른 하나만 그린다.
class OneLineOverflow extends StatelessWidget {
  /// Creates a single-line overflow row.
  const OneLineOverflow({
    super.key,
    required this.items,
    required this.moreBuilder,
    this.spacing = 0,
  });

  /// 앞에서부터 세울 것들 — 급한 순이어야 한다.
  final List<Widget> items;

  /// 숨긴 개수 `hidden` 을 말하는 칩.
  final Widget Function(int hidden) moreBuilder;

  /// 칩 사이 간격.
  final double spacing;

  @override
  Widget build(BuildContext context) => _OneLineOverflow(
    spacing: spacing,
    itemCount: items.length,
    children: <Widget>[
      ...items,
      for (int hidden = 1; hidden <= items.length; hidden++)
        moreBuilder(hidden),
    ],
  );
}

class _OneLineOverflow extends MultiChildRenderObjectWidget {
  const _OneLineOverflow({
    required this.spacing,
    required this.itemCount,
    required super.children,
  });

  final double spacing;
  final int itemCount;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOneLineOverflow(spacing, itemCount);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOneLineOverflow renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..itemCount = itemCount;
  }
}

class _OverflowParentData extends ContainerBoxParentData<RenderBox> {
  bool visible = false;
}

class _RenderOneLineOverflow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OverflowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _OverflowParentData> {
  _RenderOneLineOverflow(this._spacing, this._itemCount);

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  int _itemCount;
  set itemCount(int value) {
    if (value == _itemCount) return;
    _itemCount = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OverflowParentData) {
      child.parentData = _OverflowParentData();
    }
  }

  List<RenderBox> get _children {
    final List<RenderBox> out = <RenderBox>[];
    RenderBox? child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  /// 보일 자식의 번호들. [widths] 는 자식마다 잰 폭이다.
  List<int> _pick(List<double> widths, double maxWidth) {
    final int n = _itemCount;
    double run(int count) {
      double w = 0;
      for (int i = 0; i < count; i++) {
        w += widths[i] + (i > 0 ? _spacing : 0);
      }
      return w;
    }

    if (run(n) <= maxWidth) return <int>[for (int i = 0; i < n; i++) i];
    for (int shown = n - 1; shown >= 0; shown--) {
      final int more = n + (n - shown) - 1;
      final double w = run(shown) + (shown > 0 ? _spacing : 0) + widths[more];
      if (w <= maxWidth || shown == 0) {
        return <int>[for (int i = 0; i < shown; i++) i, more];
      }
    }
    return const <int>[];
  }

  @override
  void performLayout() {
    final List<RenderBox> children = _children;
    // 폭은 제약 없이 잰다 — 줄 폭으로 누르면 줄보다 넓은 칩이 제 안에서
    // 넘친다(그리지 않을 칩이어도 오류다). 줄에 들어가지 않는 칩은 아래에서
    // 숨긴다.
    const BoxConstraints loose = BoxConstraints();
    final List<double> widths = <double>[
      for (final RenderBox child in children)
        (child..layout(loose, parentUsesSize: true)).size.width,
    ];
    final Set<int> shown = _pick(widths, constraints.maxWidth).toSet();
    double height = 0;
    for (int i = 0; i < children.length; i++) {
      if (shown.contains(i)) {
        height = height > children[i].size.height
            ? height
            : children[i].size.height;
      }
    }
    double x = 0;
    for (int i = 0; i < children.length; i++) {
      final _OverflowParentData data =
          children[i].parentData! as _OverflowParentData;
      data.visible = shown.contains(i);
      if (!data.visible) {
        data.offset = Offset.zero;
        continue;
      }
      data.offset = Offset(x, (height - children[i].size.height) / 2);
      x += children[i].size.width + _spacing;
    }
    size = constraints.constrain(
      Size(constraints.hasBoundedWidth ? constraints.maxWidth : x, height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final RenderBox child in _children) {
      final _OverflowParentData data = child.parentData! as _OverflowParentData;
      if (data.visible) context.paintChild(child, data.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final RenderBox child in _children.reversed) {
      final _OverflowParentData data = child.parentData! as _OverflowParentData;
      if (!data.visible) continue;
      final bool hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final RenderBox child in _children) {
      if ((child.parentData! as _OverflowParentData).visible) visitor(child);
    }
  }
}
