import 'package:flutter/widgets.dart';

/// 웹이 아닌 빌드 — 구글 버튼은 앱 버튼 그대로 둔다.
Widget buildGoogleWebButton({
  required Future<void> ready,
  required Widget placeholder,
  required double size,
}) => placeholder;
