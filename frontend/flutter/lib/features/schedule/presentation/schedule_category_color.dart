import 'package:flutter/painting.dart';

import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Single source of truth: schedule category → calendar color. Every event
/// of the same category renders in the same color, regardless of whatever
/// `color_hex` the row happens to carry.
///
/// 색은 #1690 토큰에서만 고른다(달력 점·범례·하루 목록 점이 같은 색이다). 회원앱
/// 전용 화면이라 브랜드 색은 회원 브랜드 값을 쓴다. 다섯 가지가 서로 구별되도록
/// 색상(hue)이 겹치지 않는 토큰을 골랐다 — 병원은 적십자 빨강, 운동은 성공 초록,
/// 식사는 주의 주황, 약 복용은 브랜드 파랑, 기타는 중립 회색.
Color scheduleCategoryColor(ScheduleCategory c) => switch (c) {
  ScheduleCategory.hospital => OnCareColors.danger,
  ScheduleCategory.exercise => OnCareColors.success,
  ScheduleCategory.meal => OnCareColors.cautionFill,
  ScheduleCategory.medication => OnCareBrand.member.primary,
  ScheduleCategory.other => OnCareColors.textTertiary,
};

/// Single source of truth: schedule category → 화면에 그릴 이름.
///
/// enum 값 자체는 서버로 나가는 계약이라 번역하지 않는다. 사람이 읽는 이름만
/// 여기서 로케일을 따른다(#847).
String scheduleCategoryLabel(AppLocalizations l, ScheduleCategory c) =>
    switch (c) {
      ScheduleCategory.hospital => l.scheduleCategoryHospital,
      ScheduleCategory.exercise => l.scheduleCategoryExercise,
      ScheduleCategory.meal => l.scheduleCategoryMeal,
      ScheduleCategory.medication => l.scheduleCategoryMedication,
      ScheduleCategory.other => l.scheduleCategoryOther,
    };
