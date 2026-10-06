import 'package:flutter/widgets.dart';

/// 창 하나의 "요청 중" 을 모아, 요청이 도는 동안에만 창이 닫히지 않게 한다.
///
/// 열람형 창(회원 신체·목표, 메모, 상담 요청함)은 평소에는 바깥을 눌러도,
/// 뒤로 가기·X 를 눌러도 바로 닫혀야 한다 — 보러 들어온 창이다. 그런데 저장·
/// 승인 같은 요청이 도는 사이 닫히면 결과 토스트가 사라진 화면에 남지 않고,
/// 트레이너는 저장됐는지 모른 채 창을 다시 연다. 그래서 공용 `showAppDialog`
/// 의 기본값(바깥 닫힘 허용)은 그대로 두고, 요청 중일 때만 이 범위가 닫힘을
/// 막는다.
///
/// 요청을 보내는 위젯은 창 안 어디에 있든 [DialogBusyScope.guard] 나
/// [DialogBusyScope.hold] 로 알린다. 범위는 요청 수를 세고, 하나라도 돌고 있으면
/// [PopScope] 로 닫힘을 막는다. 바깥 누름·뒤로 가기·X(`Navigator.maybePop`)가
/// 모두 이 하나를 거친다. 범위 밖(창이 아닌 페이지)에서는 아무 일도 하지 않는다.
class DialogBusyScope extends StatefulWidget {
  /// Wraps a dialog's content.
  const DialogBusyScope({super.key, required this.child});

  /// 창 내용.
  final Widget child;

  /// [context] 위의 창에 요청 하나가 시작됐음을 알린다. 돌려받은 함수를 부르면
  /// 끝난다(여러 번 불러도 한 번만 센다). 범위가 없으면 아무 일도 하지 않는다.
  ///
  /// `await` 앞에서 불러야 한다 — 요청이 끝날 즈음엔 부른 위젯이 사라졌을 수 있다.
  static VoidCallback hold(BuildContext context) {
    final _DialogBusyScopeState? scope = context
        .findAncestorStateOfType<_DialogBusyScopeState>();
    if (scope == null) return () {};
    scope._begin();
    bool released = false;
    return () {
      if (released) return;
      released = true;
      scope._end();
    };
  }

  /// [task] 가 도는 동안 [context] 위의 창을 닫히지 않게 한다.
  static Future<T> guard<T>(
    BuildContext context,
    Future<T> Function() task,
  ) async {
    final VoidCallback release = hold(context);
    try {
      return await task();
    } finally {
      release();
    }
  }

  /// 지금 [context] 위의 창에 도는 요청이 있는가.
  static bool isBusy(BuildContext context) =>
      (context.findAncestorStateOfType<_DialogBusyScopeState>()?._pending ??
          0) >
      0;

  @override
  State<DialogBusyScope> createState() => _DialogBusyScopeState();
}

class _DialogBusyScopeState extends State<DialogBusyScope> {
  int _pending = 0;

  void _begin() {
    if (!mounted) return;
    setState(() => _pending++);
  }

  void _end() {
    if (!mounted) return;
    setState(() => _pending = _pending > 0 ? _pending - 1 : 0);
  }

  @override
  Widget build(BuildContext context) =>
      PopScope<Object?>(canPop: _pending == 0, child: widget.child);
}
