import 'package:flutter/material.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Generic error placeholder for any page that needs to show an
/// [AppError]. Pages should prefer this over re-implementing their
/// own.
///
/// 그림은 공용 [AppErrorState] 가 그린다(#1699). 이 위젯이 하는 일은 오류 종류를
/// 문구로 옮기는 것뿐이다.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, this.onRetry, super.key});

  final AppError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = switch (error) {
      NetworkError() => l.errorNetwork,
      UnauthorizedError() => l.errorUnauthorized,
      NotFoundError() => l.errorNotFound,
      ServerError() => l.errorServer,
      CancelledError() => l.errorCancelled,
      UnknownError() => l.errorUnknown,
    };
    // 다시 시도할 길이 없으면 버튼 없는 같은 틀로 그린다.
    if (onRetry == null) {
      return AppEmptyState(
        title: title,
        message: error.message,
        icon: Icons.cloud_off_rounded,
      );
    }
    return AppErrorState(
      title: title,
      message: error.message,
      retryLabel: l.actionRetry,
      onRetry: onRetry,
    );
  }
}
