import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// 구글이 그리는 로그인 버튼(GIS, #330).
///
/// 웹 플러그인은 초기화가 끝나기 전 버튼을 그리면 '준비 중' 상태로 남으므로,
/// [ready] 가 끝날 때까지 [placeholder](꺼진 앱 버튼)를 보인다. 초기화가 실패해도
/// 꺼진 버튼이 그대로 남는다.
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
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: gsi.renderButton(
          configuration: gsi.GSIButtonConfiguration(
            type: gsi.GSIButtonType.icon,
            shape: gsi.GSIButtonShape.pill,
            size: gsi.GSIButtonSize.large,
            theme: gsi.GSIButtonTheme.outline,
          ),
        ),
      ),
    );
  },
);
