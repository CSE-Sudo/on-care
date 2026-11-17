import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;
import 'package:oncare_social_login/src/google_button_scale.dart';
import 'package:web/web.dart' as web;

/// 구글이 그리는 로그인 버튼(GIS, #330).
///
/// 웹 플러그인은 초기화가 끝나기 전 버튼을 그리면 '준비 중' 상태로 남으므로,
/// [ready] 가 끝날 때까지 [placeholder](꺼진 앱 버튼)를 보인다. 초기화가 실패해도
/// 꺼진 버튼이 그대로 남는다.
///
/// GIS 아이콘 버튼은 [kGoogleIconButtonExtent] 고정 크기라 [size] 자리에서 작아
/// 보인다. 구글이 그린 버튼을 다시 그리거나 덮지 않고 비율 그대로 확대해 옆의
/// 카카오 버튼과 크기를 맞춘다(#3445). 웹은 플랫폼 뷰에 변환을 CSS transform 으로
/// 적용하므로 확대된 영역 전체가 눌린다.
///
/// 버튼을 누르면 구글 iframe 이 포커스를 가져가 구글이 그린 포커스 외곽선이 눌린 뒤에도
/// 남는다. iframe 안은 우리 CSS 가 닿지 않으므로 [_GoogleFocusRelease] 가 포인터로
/// 눌렀을 때만 포커스를 놓는다.
Widget buildGoogleWebButton({
  required Future<void> ready,
  required Widget placeholder,
  required double size,
}) => FutureBuilder<void>(
  future: ready,
  builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done || snapshot.hasError) {
      return placeholder;
    }
    return _GoogleFocusRelease(
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Transform.scale(
            scale: googleIconButtonScale(size),
            child: SizedBox.square(
              dimension: kGoogleIconButtonExtent,
              child: gsi.renderButton(
                configuration: gsi.GSIButtonConfiguration(
                  type: gsi.GSIButtonType.icon,
                  shape: gsi.GSIButtonShape.pill,
                  size: gsi.GSIButtonSize.large,
                  theme: gsi.GSIButtonTheme.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);

/// 구글 버튼 iframe 의 출처. 이 iframe 이 포커스를 가졌을 때만 다룬다.
const String _gsiButtonOrigin = 'https://accounts.google.com/gsi/';

/// Tab 키로 포커스가 들어온 것으로 볼 시간. 이 안에 들어온 포커스는 놓지 않는다.
const Duration _keyboardWindow = Duration(milliseconds: 300);

/// 포인터로 누른 직후 포커스를 놓기까지의 지연. 누름·뗌 사이에 끼어들지 않으려는 값이다.
const Duration _releaseDelay = Duration(milliseconds: 150);

/// 구글 버튼을 누른 뒤 iframe 에 남는 포커스 외곽선을 없앤다.
///
/// iframe 안을 누르면 부모 창에 `blur` 가 오고 `document.activeElement` 가 그 iframe
/// 이 된다. 이때 iframe 의 `blur()` 로 포커스를 놓으면 구글이 그린 외곽선이 사라진다.
/// 클릭 자체는 이미 처리되므로 로그인 흐름에는 영향이 없다.
///
/// 키보드 사용자는 외곽선이 보여야 하므로, 직전에 Tab 을 눌러 들어온 포커스는 그대로 둔다.
class _GoogleFocusRelease extends StatefulWidget {
  const _GoogleFocusRelease({required this.child});

  final Widget child;

  @override
  State<_GoogleFocusRelease> createState() => _GoogleFocusReleaseState();
}

class _GoogleFocusReleaseState extends State<_GoogleFocusRelease> {
  late final JSFunction _onKeyDown = _handleKeyDown.toJS;
  late final JSFunction _onBlur = _handleBlur.toJS;
  Timer? _timer;
  DateTime? _lastTab;

  @override
  void initState() {
    super.initState();
    // 캡처 단계로 받아 Flutter 가 키를 먼저 삼켜도 Tab 을 놓치지 않는다.
    web.window.addEventListener('keydown', _onKeyDown, true.toJS);
    web.window.addEventListener('blur', _onBlur);
  }

  @override
  void dispose() {
    _timer?.cancel();
    web.window.removeEventListener('keydown', _onKeyDown, true.toJS);
    web.window.removeEventListener('blur', _onBlur);
    super.dispose();
  }

  void _handleKeyDown(web.KeyboardEvent event) {
    if (event.key == 'Tab') {
      _lastTab = DateTime.now();
    }
  }

  void _handleBlur(web.Event event) {
    _timer?.cancel();
    _timer = Timer(_releaseDelay, _release);
  }

  void _release() {
    final web.Element? active = web.document.activeElement;
    if (active == null || !active.isA<web.HTMLIFrameElement>()) {
      return;
    }
    final web.HTMLIFrameElement frame = active as web.HTMLIFrameElement;
    if (!frame.src.startsWith(_gsiButtonOrigin)) {
      return;
    }
    final DateTime? tabbed = _lastTab;
    if (tabbed != null && DateTime.now().difference(tabbed) < _keyboardWindow) {
      return;
    }
    frame.blur();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
