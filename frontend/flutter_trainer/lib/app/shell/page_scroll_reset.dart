import 'package:flutter/widgets.dart';

/// Delivers page-navigation events to the active top-level page.
///
/// The indexed navigation shell deliberately keeps every branch alive. That
/// preserves useful page state, but it must not preserve the viewport when a
/// trainer explicitly navigates to a page: the destination should open at its
/// beginning.
class PageScrollResetScope extends InheritedNotifier<ValueNotifier<int>> {
  /// Creates a reset scope around the trainer navigation shell.
  const PageScrollResetScope({
    super.key,
    required ValueNotifier<int> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Returns the navigation reset notifier for the surrounding shell.
  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PageScrollResetScope>()
      ?.notifier;
}

/// 셸이 보내는 이동 신호를 받아 [child] 안의 최상위 세로 스크롤을 맨 위로 돌린다.
///
/// 옛 `PageScaffold` 가 하던 일을 페이지 틀(`AppWebPage`)과 떼어 둔 것이다(#1703).
/// 페이지는 `AppWebPage` 의 body 를 이 위젯으로 감싼다.
class PageScrollResetListener extends StatefulWidget {
  const PageScrollResetListener({super.key, required this.child});

  final Widget child;

  @override
  State<PageScrollResetListener> createState() =>
      _PageScrollResetListenerState();
}

class _PageScrollResetListenerState extends State<PageScrollResetListener> {
  final Set<ScrollableState> _topLevelScrollables = <ScrollableState>{};
  ValueNotifier<int>? _resetNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = PageScrollResetScope.maybeOf(context);
    if (identical(next, _resetNotifier)) return;
    _resetNotifier?.removeListener(_resetScroll);
    _resetNotifier = next;
    _resetNotifier?.addListener(_resetScroll);
  }

  @override
  void dispose() {
    _resetNotifier?.removeListener(_resetScroll);
    super.dispose();
  }

  void _resetScroll() {
    if (!TickerMode.valuesOf(context).enabled) return;
    _topLevelScrollables.removeWhere((scrollable) => !scrollable.mounted);
    for (final scrollable in _topLevelScrollables) {
      final position = scrollable.position;
      if (position.hasPixels && position.pixels != position.minScrollExtent) {
        position.jumpTo(position.minScrollExtent);
      }
    }
  }

  bool _rememberScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final notificationContext = notification.context;
    if (notificationContext != null) {
      final scrollable = Scrollable.maybeOf(notificationContext);
      if (scrollable != null) _topLevelScrollables.add(scrollable);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _rememberScroll,
      child: widget.child,
    );
  }
}
