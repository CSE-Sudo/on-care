/// 트레이너가 보낸 리포트 한 건을 연다 — 대화에서도, MY 탭 목록에서도. (#2232)
///
/// 여는 규칙이 두 화면에 따로 있으면 한쪽만 고쳐지는 날이 온다. 실제로 이
/// 규칙에는 조용히 갈리는 갈림길이 하나 있다 — **첨부가 있으면 트레이너가
/// 보낸 그 파일**을, 없으면(데모, 그리고 본문만 보낸 리포트) 같은 주를 트레이너
/// 웹과 같은 자료·같은 결과지로 세운 문서를 연다(#2652). 두 화면이 서로 다른
/// 문서를 열면, 회원은 같은 주 리포트를 두 벌 가진 셈이 된다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/member_coach/data/repositories/chat_pdf_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_report_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_report/oncare_report.dart' show ReportSheetInputs;
import 'package:oncare_ui/oncare_ui.dart';

/// [message] 가 실어 온 [weekStart] 주 리포트를 미리보기로 연다.
///
/// 열지 못하면 던진다 — 부르는 쪽이 자기 자리에 맞는 안내를 띄운다.
Future<void> openCoachReport(
  BuildContext context,
  WidgetRef ref, {
  required CoachMessage message,
  required DateTime weekStart,
}) async {
  final CoachReportPdf pdf = await loadCoachReportPdf(
    ref.read,
    l: AppLocalizations.of(context),
    message: message,
    weekStart: weekStart,
  );
  if (!context.mounted) return;
  await openPdfPreviewPage(context, pdf.bytes, pdf.fileName);
}

/// 미리보기에 띄울 파일 한 부.
typedef CoachReportPdf = ({Uint8List bytes, String fileName});

/// [openCoachReport] 가 여는 파일을 만든다 — 화면을 띄우지 않고 파일만.
///
/// 첨부가 있으면 트레이너가 보낸 그 파일이다. 없으면 트레이너 웹과 같은 결과지를
/// 세워 굽고, 트레이너가 함께 보낸 글을 `트레이너 피드백` 칸에 싣는다.
Future<CoachReportPdf> loadCoachReportPdf(
  ProviderRead read, {
  required AppLocalizations l,
  required CoachMessage message,
  required DateTime weekStart,
}) async {
  final CoachAttachment? attachment = message.attachment;
  if (attachment != null) {
    return (
      bytes: await read(
        chatPdfRepositoryProvider,
      ).download(attachment.downloadPath),
      fileName: attachment.fileName,
    );
  }
  final ReportSheetInputs inputs = await loadMemberReportSheet(
    read,
    weekStart: weekStart,
    languageCode: l.localeName,
  );
  return (
    bytes: await read(memberReportPdfGeneratorProvider).generate(
      l: l,
      inputs: inputs,
      // 안내 상자가 본문을 감추므로, 트레이너가 리포트와 함께 보낸 글은
      // 문서 안에서 읽게 한다 — 트레이너 결과지의 `트레이너 피드백` 자리다.
      feedback: trainerReportFeedback(message.body),
    ),
    fileName: l.coachReportPdfFileName(wireDate(weekStart)),
  );
}
