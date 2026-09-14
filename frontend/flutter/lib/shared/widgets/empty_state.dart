import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// "Nothing to show yet" placeholder, intended for list / detail pages
/// before the user has any data.
///
/// 그림은 공용 [AppEmptyState] 가 그린다(#1699). 이 이름은 정리 이슈(#1707)에서
/// 사라지니 새 코드는 [AppEmptyState] 를 바로 쓴다.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.title, this.message, this.icon, super.key});

  final String title;
  final String? message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title,
      message: message,
      icon: icon ?? Icons.inbox_rounded,
    );
  }
}
