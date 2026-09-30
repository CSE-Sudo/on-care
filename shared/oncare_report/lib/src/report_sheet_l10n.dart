/// 결과지의 문구와 수치 표기. (#2652)
///
/// 결과지는 두 앱 어디서 그려도 같은 말을 해야 한다. 그래서 문구를 앱의 ARB 가
/// 아니라 이 패키지의 ARB 에 두고, 그리는 쪽이 따로 대리자를 등록하지 않아도
/// 앱의 로케일만 보고 찾아 쓴다.
library;

import 'package:flutter/widgets.dart';
import 'package:oncare_report/gen/l10n/report_sheet_localizations.dart';

/// 결과지가 쓰는 문구 묶음 — 둘러싼 로케일을 따르고, 결과지가 모르는 언어면
/// 한국어로 그린다.
ReportSheetLocalizations reportSheetLocalizationsOf(BuildContext context) =>
    reportSheetLocalizationsFor(
      Localizations.maybeLocaleOf(context) ?? const Locale('ko'),
    );

/// [locale] 의 결과지 문구. 결과지가 모르는 언어면 한국어.
ReportSheetLocalizations reportSheetLocalizationsFor(Locale locale) {
  final bool known = ReportSheetLocalizations.supportedLocales.any(
    (Locale l) => l.languageCode == locale.languageCode,
  );
  return lookupReportSheetLocalizations(
    known ? Locale(locale.languageCode) : const Locale('ko'),
  );
}

/// 화면에 적는 수치의 표기 — 정수 부분에 천 단위 쉼표, 정수가 아니면 소수 한
/// 자리. 두 앱의 `formatNumber` 와 같은 규칙이다.
String reportFormatNumber(num value) {
  final String text = value != value.roundToDouble()
      ? value.toStringAsFixed(1)
      : value.toInt().toString();
  return text.replaceAllMapped(
    RegExp(r'^-?\d+'),
    (Match m) => m[0]!.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (Match _) => ',',
    ),
  );
}
