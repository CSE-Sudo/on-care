import 'package:flutter/material.dart';

import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// [PreferredTime] → 현지화 문구. "시간 협의"거나 로케일에 맞는 "오후 7:00" 형태.
///
/// 엔티티는 라벨이 아니라 값(계약)을 들고 있으므로 화면이 렌더 시점에 만든다 — 그래야
/// 서버에서 복원한 신청도 같은 문구로 보인다(#327 의 연장, #1256).
String preferredTimeLabel(
  BuildContext context,
  AppLocalizations l,
  PreferredTime time,
) {
  final TimeOfDay? start = time.start;
  if (start == null) return l.exTimeFlexible;
  final MaterialLocalizations m = MaterialLocalizations.of(context);
  final TimeOfDay end = time.end ?? start;
  final String startLabel = m.formatTimeOfDay(
    start,
    alwaysUse24HourFormat: true,
  );
  if (start == end) return startLabel;
  return '$startLabel–${m.formatTimeOfDay(end, alwaysUse24HourFormat: true)}';
}

/// 상담 요청의 시각 한 줄 — `2026. 3. 5. 19:00–19:30`. (#1873)
///
/// 고른 자리가 있으면 그 자리의 시작–종료를 그린다. 길이는 트레이너가 자리를 열 때
/// 정한 값이다. 자리 선택 이전 요청(과 자리가 지워진 요청)은 회원이 적어 보낸 희망
/// 날짜·시각을 예전 그대로 보여 준다 — 조회가 깨지면 안 된다.
String consultationTimeLabel(
  BuildContext context,
  AppLocalizations l,
  ConsultationRequest request,
) {
  final MaterialLocalizations m = MaterialLocalizations.of(context);
  final DateTime? start = request.slotStartsAt;
  if (start == null) {
    return '${m.formatMediumDate(request.preferredDate)} · '
        '${preferredTimeLabel(context, l, request.preferredTimeSlot)}';
  }
  final DateTime end = start.add(
    Duration(minutes: request.slotDurationMinutes ?? 60),
  );
  String hm(DateTime value) => m.formatTimeOfDay(
    TimeOfDay.fromDateTime(value),
    alwaysUse24HourFormat: true,
  );
  return '${m.formatMediumDate(start)} ${hm(start)}–${hm(end)}';
}
