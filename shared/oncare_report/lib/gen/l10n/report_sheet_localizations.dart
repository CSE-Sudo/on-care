import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'report_sheet_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ReportSheetLocalizations
/// returned by `ReportSheetLocalizations.of(context)`.
///
/// Applications need to include `ReportSheetLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/report_sheet_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ReportSheetLocalizations.localizationsDelegates,
///   supportedLocales: ReportSheetLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the ReportSheetLocalizations.supportedLocales
/// property.
abstract class ReportSheetLocalizations {
  ReportSheetLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ReportSheetLocalizations of(BuildContext context) {
    return Localizations.of<ReportSheetLocalizations>(
      context,
      ReportSheetLocalizations,
    )!;
  }

  static const LocalizationsDelegate<ReportSheetLocalizations> delegate =
      _ReportSheetLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ko')];

  /// No description provided for @chartNoRecord.
  ///
  /// In ko, this message translates to:
  /// **'기록 없음'**
  String get chartNoRecord;

  /// No description provided for @dateMonthDay.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {day}일'**
  String dateMonthDay(int month, int day);

  /// No description provided for @metricCalories.
  ///
  /// In ko, this message translates to:
  /// **'칼로리'**
  String get metricCalories;

  /// No description provided for @metricCarbs.
  ///
  /// In ko, this message translates to:
  /// **'탄수화물'**
  String get metricCarbs;

  /// No description provided for @metricFat.
  ///
  /// In ko, this message translates to:
  /// **'지방'**
  String get metricFat;

  /// No description provided for @metricProtein.
  ///
  /// In ko, this message translates to:
  /// **'단백질'**
  String get metricProtein;

  /// No description provided for @metricSodium.
  ///
  /// In ko, this message translates to:
  /// **'나트륨'**
  String get metricSodium;

  /// No description provided for @metricSugar.
  ///
  /// In ko, this message translates to:
  /// **'당류'**
  String get metricSugar;

  /// No description provided for @reportsFeedbackTitle.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 피드백'**
  String get reportsFeedbackTitle;

  /// No description provided for @reportsMemberFeedbackConditionLabel.
  ///
  /// In ko, this message translates to:
  /// **'컨디션'**
  String get reportsMemberFeedbackConditionLabel;

  /// No description provided for @reportsMemberFeedbackIntensityLabel.
  ///
  /// In ko, this message translates to:
  /// **'운동 강도'**
  String get reportsMemberFeedbackIntensityLabel;

  /// No description provided for @reportsMemberFeedbackNoteLabel.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 피드백'**
  String get reportsMemberFeedbackNoteLabel;

  /// No description provided for @reportsMemberFeedbackNoteNone.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 피드백 없음'**
  String get reportsMemberFeedbackNoteNone;

  /// No description provided for @reportsMemberFeedbackPainLabel.
  ///
  /// In ko, this message translates to:
  /// **'통증'**
  String get reportsMemberFeedbackPainLabel;

  /// No description provided for @reportsMemberFeedbackPainNone.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get reportsMemberFeedbackPainNone;

  /// No description provided for @reportsMemberFeedbackPainOn.
  ///
  /// In ko, this message translates to:
  /// **'{area} ({date})'**
  String reportsMemberFeedbackPainOn(String area, String date);

  /// No description provided for @reportsMemberFeedbackTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 주간 피드백'**
  String get reportsMemberFeedbackTitle;

  /// No description provided for @reportsMemberFeedbackUnanswered.
  ///
  /// In ko, this message translates to:
  /// **'미응답'**
  String get reportsMemberFeedbackUnanswered;

  /// No description provided for @reportsPdfAttendance.
  ///
  /// In ko, this message translates to:
  /// **'{done}/{booked}회 ({rate}%)'**
  String reportsPdfAttendance(String done, String booked, String rate);

  /// No description provided for @reportsPdfDocTitle.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get reportsPdfDocTitle;

  /// No description provided for @reportsPdfLabelCompletion.
  ///
  /// In ko, this message translates to:
  /// **'운동 완료율'**
  String get reportsPdfLabelCompletion;

  /// No description provided for @reportsPdfLabelSessions.
  ///
  /// In ko, this message translates to:
  /// **'완료 PT'**
  String get reportsPdfLabelSessions;

  /// No description provided for @reportsPdfNoData.
  ///
  /// In ko, this message translates to:
  /// **'미집계'**
  String get reportsPdfNoData;

  /// No description provided for @reportsPdfNoFeedback.
  ///
  /// In ko, this message translates to:
  /// **'피드백 없음'**
  String get reportsPdfNoFeedback;

  /// No description provided for @reportsPdfValueDays.
  ///
  /// In ko, this message translates to:
  /// **'{value}일'**
  String reportsPdfValueDays(String value);

  /// No description provided for @reportsPdfValueGram.
  ///
  /// In ko, this message translates to:
  /// **'{value}g'**
  String reportsPdfValueGram(String value);

  /// No description provided for @reportsPdfValueKcal.
  ///
  /// In ko, this message translates to:
  /// **'{value}kcal'**
  String reportsPdfValueKcal(String value);

  /// No description provided for @reportsPdfValueMg.
  ///
  /// In ko, this message translates to:
  /// **'{value}mg'**
  String reportsPdfValueMg(String value);

  /// No description provided for @reportsPdfValuePercent.
  ///
  /// In ko, this message translates to:
  /// **'{value}%'**
  String reportsPdfValuePercent(String value);

  /// No description provided for @reportsPdfValueSessions.
  ///
  /// In ko, this message translates to:
  /// **'{value}회'**
  String reportsPdfValueSessions(String value);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'완료 PT'**
  String get reportsSheetAttendance;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'4주 평균'**
  String get reportsSheetAverageBase;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'변화'**
  String get reportsSheetAverageChange;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get reportsSheetAverageNow;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'4주 평균 대비'**
  String get reportsSheetAverageTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'적정'**
  String get reportsSheetBandNormal;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'초과'**
  String get reportsSheetBandOver;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'부족'**
  String get reportsSheetBandUnder;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'칼로리 적정일'**
  String get reportsSheetCalorieDays;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'칼로리'**
  String get reportsSheetDailyCalories;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'완료율'**
  String get reportsSheetDailyCompletion;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'끼니'**
  String get reportsSheetDailyMeals;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'요일별 기록'**
  String get reportsSheetDailyTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get reportsSheetDailyWorkouts;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'{days}/{due}일'**
  String reportsSheetDaysOf(String days, String due);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'하루 평균 · 목표 대비'**
  String get reportsSheetDietHint;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'식단 분석'**
  String get reportsSheetDietTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'항목별 평가'**
  String get reportsSheetEvalTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'이번 주 · 목표 대비'**
  String get reportsSheetExerciseHint;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'운동 분석'**
  String get reportsSheetExerciseTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'범위는 이번 주 기록을 회원의 목표와 견줘요. 기록이 없는 항목은 미집계로 표시해요.'**
  String get reportsSheetFootnote;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'목표 {value}'**
  String reportsSheetGoal(String value);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'식단 기록'**
  String get reportsSheetInfoMealDays;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'회원'**
  String get reportsSheetInfoMember;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'기간'**
  String get reportsSheetInfoPeriod;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'식단 기록일'**
  String get reportsSheetMealDaysLabel;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'{start} ~ {end}'**
  String reportsSheetPeriodValue(String start, String end);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'운동 완료율·완료 PT·식단 기록·칼로리 적정일 비율의 평균이에요. 기록이 없는 항목은 빠져요.'**
  String get reportsSheetScoreFormula;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'점수를 낼 기록이 없어요'**
  String get reportsSheetScoreNone;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'주간 관리 점수'**
  String get reportsSheetScoreTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'/100점'**
  String get reportsSheetScoreUnit;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'요일별 섭취 칼로리 · 목표선'**
  String get reportsSheetTrendDaily;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'추이'**
  String get reportsSheetTrendTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In ko, this message translates to:
  /// **'주별 운동 달성률 (8주)'**
  String get reportsSheetTrendWeekly;

  /// No description provided for @reportsTrendUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'이 주의 운동 기록을 불러오지 못했어요'**
  String get reportsTrendUnavailable;

  /// No description provided for @weekdayMon.
  ///
  /// In ko, this message translates to:
  /// **'월'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In ko, this message translates to:
  /// **'화'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In ko, this message translates to:
  /// **'수'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In ko, this message translates to:
  /// **'목'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In ko, this message translates to:
  /// **'금'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In ko, this message translates to:
  /// **'토'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In ko, this message translates to:
  /// **'일'**
  String get weekdaySun;

  /// No description provided for @routineTypeCardio.
  ///
  /// In ko, this message translates to:
  /// **'유산소'**
  String get routineTypeCardio;

  /// No description provided for @routineTypeStrength.
  ///
  /// In ko, this message translates to:
  /// **'근력'**
  String get routineTypeStrength;

  /// No description provided for @routineTypeStretching.
  ///
  /// In ko, this message translates to:
  /// **'스트레칭'**
  String get routineTypeStretching;

  /// No description provided for @minutesShort.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분'**
  String minutesShort(int minutes);

  /// No description provided for @progSetsValue.
  ///
  /// In ko, this message translates to:
  /// **'{sets}세트'**
  String progSetsValue(int sets);

  /// No description provided for @reportsMemberFeedbackConditionGreat.
  ///
  /// In ko, this message translates to:
  /// **'아주 좋았어요'**
  String get reportsMemberFeedbackConditionGreat;

  /// No description provided for @reportsMemberFeedbackConditionGood.
  ///
  /// In ko, this message translates to:
  /// **'좋았어요'**
  String get reportsMemberFeedbackConditionGood;

  /// No description provided for @reportsMemberFeedbackConditionOk.
  ///
  /// In ko, this message translates to:
  /// **'보통이었어요'**
  String get reportsMemberFeedbackConditionOk;

  /// No description provided for @reportsMemberFeedbackConditionTired.
  ///
  /// In ko, this message translates to:
  /// **'지쳤어요'**
  String get reportsMemberFeedbackConditionTired;

  /// No description provided for @reportsMemberFeedbackConditionBad.
  ///
  /// In ko, this message translates to:
  /// **'많이 안 좋았어요'**
  String get reportsMemberFeedbackConditionBad;

  /// No description provided for @reportsMemberFeedbackIntensityTooEasy.
  ///
  /// In ko, this message translates to:
  /// **'너무 쉬웠어요'**
  String get reportsMemberFeedbackIntensityTooEasy;

  /// No description provided for @reportsMemberFeedbackIntensityRight.
  ///
  /// In ko, this message translates to:
  /// **'딱 맞았어요'**
  String get reportsMemberFeedbackIntensityRight;

  /// No description provided for @reportsMemberFeedbackIntensityHard.
  ///
  /// In ko, this message translates to:
  /// **'조금 힘들었어요'**
  String get reportsMemberFeedbackIntensityHard;

  /// No description provided for @reportsMemberFeedbackIntensityTooHard.
  ///
  /// In ko, this message translates to:
  /// **'너무 힘들었어요'**
  String get reportsMemberFeedbackIntensityTooHard;
}

class _ReportSheetLocalizationsDelegate
    extends LocalizationsDelegate<ReportSheetLocalizations> {
  const _ReportSheetLocalizationsDelegate();

  @override
  Future<ReportSheetLocalizations> load(Locale locale) {
    return SynchronousFuture<ReportSheetLocalizations>(
      lookupReportSheetLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_ReportSheetLocalizationsDelegate old) => false;
}

ReportSheetLocalizations lookupReportSheetLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ko':
      return ReportSheetLocalizationsKo();
  }

  throw FlutterError(
    'ReportSheetLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
