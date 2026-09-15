/// 로그인·회원가입·온보딩 화면의 현지화 — #642.
///
/// 세 화면만 한국어가 하드코딩돼 있어, 영어 로케일로 켜면 앱에서 처음 보는 세 화면이
/// 로케일을 따르지 않았다.
///
/// 여기서 고정하는 것은 둘이다.
///
///  * en 로케일에서 한국어가 남지 않는다.
///  * **ko 로케일 문구는 옮기기 전과 같다.** 로그인 화면은 "데모 둘러보기" 직전 화면이라
///    문구가 바뀌면 시연 첫 장면이 달라진다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';

/// 옮기기 전 화면에 있던 한국어 문구. 값이 바뀌면 시연 화면이 달라진다.
const Map<String, String> _koBefore = <String, String>{
  'authTagline': '식단·운동 관리 앱',
  'authEmailHint': '이메일',
  'authPasswordHint': '비밀번호',
  'authSignInAction': '로그인',
  'authNoAccountQuestion': '계정이 없으신가요?',
  'authSignUpAction': '회원가입',
  'authDemoAction': '로그인 없이 데모 둘러보기',
  'authOrDivider': '또는',
  'authKakaoAction': '카카오로 시작하기',
  'authGoogleAction': '구글로 시작하기',
  'authMissingCredentials': '이메일과 비밀번호를 입력해 주세요',
  'authSignInFailed': '로그인에 실패했어요. 이메일·비밀번호를 확인해 주세요',
  'authSocialSignInFailed': '소셜 로그인에 실패했어요. 잠시 후 다시 시도해 주세요',
  'signUpTitle': '회원가입',
  'signUpSubtitle': 'On-Care 계정을 만들어 건강 관리를 시작하세요',
  'signUpNameHint': '이름',
  'signUpPasswordHint': '비밀번호 (8자 이상)',
  'signUpPasswordConfirmHint': '비밀번호 확인',
  'signUpAction': '가입하고 시작하기',
  'signUpHaveAccountQuestion': '이미 계정이 있으신가요?',
  'signUpPasswordTooShort': '비밀번호는 8자 이상이어야 해요',
  'signUpPasswordMismatch': '비밀번호가 일치하지 않아요',
  'signUpEmailTaken': '이미 가입된 이메일이에요. 로그인해 주세요.',
  'signUpFailed': '회원가입에 실패했어요. 잠시 후 다시 시도해 주세요.',
  'onboardSkip': '나중에 하기',
  'onboardPrevious': '이전',
  'onboardNext': '다음',
  'onboardDone': '완료',
  'onboardSaveFailed': '저장에 실패했어요. 잠시 후 다시 시도해 주세요',
  'onboardBasicTitle': '기본 정보',
  'onboardBasicSubtitle': '맞춤 건강 관리를 위해 기본 정보를 알려주세요.',
  'onboardHeightHint': '키 (cm)',
  // 2단계는 진단받은 질환이 아니라 **어디에 초점을 둘지**를 묻는다(#1471).
  'onboardHealthTitle': '건강 목표',
  'onboardHealthSubtitle': '건강 관리에서 더 집중하고 싶은 항목을 선택해 주세요. (복수 선택 가능)',
  'onboardGoalTitle': '운동 목표',
  'onboardGoalSubtitle': '달성하고 싶은 목표를 입력해 주세요. 나중에 바꿀 수 있어요.',
  'onboardGenderMale': '남성',
  'onboardGenderFemale': '여성',
  'onboardGenderOther': '기타',
};

/// 온보딩 개편에서 새로 생긴 문구. [_koBefore] 는 #642 에서 *옮기기 전* 화면을
/// 못 박아 둔 표라 여기에 섞지 않고 따로 둔다 — 아래 en/차이 검사는 두 표를
/// 함께 돈다.
const Map<String, String> _koAdded = <String, String>{
  'onboardOptionalTag': '(선택)',
  'onboardSkipStep': '이 단계 건너뛰기',
  'onboardBirthLabel': '생년월일',
  'onboardBirthYearHint': '년',
  'onboardBirthMonthHint': '월',
  'onboardBirthDayHint': '일',
  'onboardGenderLabel': '성별',
  'onboardBmiUnderweight': '저체중',
  'onboardBmiNormal': '정상',
  'onboardBmiPreObese': '비만 전단계',
  'onboardBmiObese1': '1단계 비만',
  'onboardBmiObese2': '2단계 비만',
  'onboardBmiObese3': '3단계 비만',
  'onboardBmiSourceNote': '기준: 대한비만학회 비만 진료지침(아시아·태평양 기준)',
  'onboardDietTitle': '식단 목표',
  'onboardDietSubtitle': '권장값을 미리 채워 뒀어요. 원하는 값으로 바꿔도 괜찮아요.',
  'onboardExerciseTitle': '운동 목표',
  'onboardExerciseSubtitle': '세계보건기구 권고를 기준으로 채워 뒀어요. 원하는 값으로 바꿔도 괜찮아요.',
  'onboardRecommendedPersonal': '나이·성별·키·체중으로 계산한 권장값이에요',
  'onboardRecommendedFallback': '기본 권장값이에요. 1단계에서 생년월일·성별·키·체중을 채우면 더 정확해져요',
  'onboardResetToRecommended': '권장값으로 되돌리기',
  'onboardDietSourceNote':
      '출처: 2020 한국인 영양소 섭취기준(에너지필요추정량·에너지적정비율) · WHO 나트륨·자유당 섭취 권고',
  'onboardExerciseSourceNote':
      '출처: WHO 신체활동 지침(2020) — 주 150분 중강도 유산소, 주 2회 이상 근력',
  // 고른 건강 목표를 반영한 권장값 안내와 근거(#1816).
  'onboardFocusAdjusted': '고른 건강 목표를 반영한 값이에요',
  'onboardFocusSourceNote':
      '목표 반영 기준: 감량 하루 500kcal(대한비만학회 진료지침) · 근력 단백질 체중 1kg당 1.6g(국제스포츠영양학회) · 당류 총열량 5%(WHO) · 유산소 주 150~300분(WHO)',
  // 2단계 건강 목표 — 옛 질환 선택지(고혈압·당뇨)를 바꿨다(#1814).
  'healthFocusWeightLoss': '체중 감량',
  'healthFocusStrength': '근력 향상',
  'healthFocusFitness': '체력 강화',
  'healthFocusPosture': '자세 교정',
  'healthFocusRehab': '재활',
  'healthFocusEating': '식습관 개선',
  'healthFocusExerciseHabit': '운동 습관',
  'healthFocusBloodPressure': '혈압 관리',
};

/// 두 표를 합친 것. 로케일 검사는 새 문구까지 함께 본다.
Map<String, String> get _koAll => <String, String>{..._koBefore, ..._koAdded};

/// 키 이름 → 그 로케일의 문구.
String _read(AppLocalizations l, String key) => switch (key) {
  'authTagline' => l.authTagline,
  'authEmailHint' => l.authEmailHint,
  'authPasswordHint' => l.authPasswordHint,
  'authSignInAction' => l.authSignInAction,
  'authNoAccountQuestion' => l.authNoAccountQuestion,
  'authSignUpAction' => l.authSignUpAction,
  'authDemoAction' => l.authDemoAction,
  'authOrDivider' => l.authOrDivider,
  'authKakaoAction' => l.authKakaoAction,
  'authGoogleAction' => l.authGoogleAction,
  'authMissingCredentials' => l.authMissingCredentials,
  'authSignInFailed' => l.authSignInFailed,
  'authSocialSignInFailed' => l.authSocialSignInFailed,
  'signUpTitle' => l.signUpTitle,
  'signUpSubtitle' => l.signUpSubtitle,
  'signUpNameHint' => l.signUpNameHint,
  'signUpPasswordHint' => l.signUpPasswordHint,
  'signUpPasswordConfirmHint' => l.signUpPasswordConfirmHint,
  'signUpAction' => l.signUpAction,
  'signUpHaveAccountQuestion' => l.signUpHaveAccountQuestion,
  'signUpPasswordTooShort' => l.signUpPasswordTooShort,
  'signUpPasswordMismatch' => l.signUpPasswordMismatch,
  'signUpEmailTaken' => l.signUpEmailTaken,
  'signUpFailed' => l.signUpFailed,
  'onboardSkip' => l.onboardSkip,
  'onboardPrevious' => l.onboardPrevious,
  'onboardNext' => l.onboardNext,
  'onboardDone' => l.onboardDone,
  'onboardSaveFailed' => l.onboardSaveFailed,
  'onboardBasicTitle' => l.onboardBasicTitle,
  'onboardBasicSubtitle' => l.onboardBasicSubtitle,
  'onboardHeightHint' => l.onboardHeightHint,
  'onboardHealthTitle' => l.onboardHealthTitle,
  'onboardHealthSubtitle' => l.onboardHealthSubtitle,
  'onboardGoalTitle' => l.onboardGoalTitle,
  'onboardGoalSubtitle' => l.onboardGoalSubtitle,
  'onboardGenderMale' => l.onboardGenderMale,
  'onboardGenderFemale' => l.onboardGenderFemale,
  'onboardGenderOther' => l.onboardGenderOther,
  'onboardFocusAdjusted' => l.onboardFocusAdjusted,
  'onboardFocusSourceNote' => l.onboardFocusSourceNote,
  'healthFocusWeightLoss' => l.healthFocusWeightLoss,
  'healthFocusStrength' => l.healthFocusStrength,
  'healthFocusFitness' => l.healthFocusFitness,
  'healthFocusPosture' => l.healthFocusPosture,
  'healthFocusRehab' => l.healthFocusRehab,
  'healthFocusEating' => l.healthFocusEating,
  'healthFocusExerciseHabit' => l.healthFocusExerciseHabit,
  'healthFocusBloodPressure' => l.healthFocusBloodPressure,
  'onboardOptionalTag' => l.onboardOptionalTag,
  'onboardSkipStep' => l.onboardSkipStep,
  'onboardBirthLabel' => l.onboardBirthLabel,
  'onboardBirthYearHint' => l.onboardBirthYearHint,
  'onboardBirthMonthHint' => l.onboardBirthMonthHint,
  'onboardBirthDayHint' => l.onboardBirthDayHint,
  'onboardGenderLabel' => l.onboardGenderLabel,
  'onboardBmiUnderweight' => l.onboardBmiUnderweight,
  'onboardBmiNormal' => l.onboardBmiNormal,
  'onboardBmiPreObese' => l.onboardBmiPreObese,
  'onboardBmiObese1' => l.onboardBmiObese1,
  'onboardBmiObese2' => l.onboardBmiObese2,
  'onboardBmiObese3' => l.onboardBmiObese3,
  'onboardBmiSourceNote' => l.onboardBmiSourceNote,
  'onboardDietTitle' => l.onboardDietTitle,
  'onboardDietSubtitle' => l.onboardDietSubtitle,
  'onboardExerciseTitle' => l.onboardExerciseTitle,
  'onboardExerciseSubtitle' => l.onboardExerciseSubtitle,
  'onboardRecommendedPersonal' => l.onboardRecommendedPersonal,
  'onboardRecommendedFallback' => l.onboardRecommendedFallback,
  'onboardResetToRecommended' => l.onboardResetToRecommended,
  'onboardDietSourceNote' => l.onboardDietSourceNote,
  'onboardExerciseSourceNote' => l.onboardExerciseSourceNote,
  _ => fail('알 수 없는 키: $key'),
};

/// [locale] 의 [AppLocalizations] 를 꺼낸다.
Future<AppLocalizations> _localizations(
  WidgetTester tester,
  Locale locale,
) async {
  late AppLocalizations found;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) {
          found = AppLocalizations.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return found;
}

void main() {
  testWidgets('ko 문구가 옮기기 전과 같다', (WidgetTester tester) async {
    final AppLocalizations l = await _localizations(tester, const Locale('ko'));

    for (final MapEntry<String, String> entry in _koAll.entries) {
      expect(_read(l, entry.key), entry.value, reason: entry.key);
    }
  });

  testWidgets('en 문구에 한국어가 남지 않는다', (WidgetTester tester) async {
    final AppLocalizations l = await _localizations(tester, const Locale('en'));

    final RegExp hangul = RegExp(r'[가-힣]');
    for (final String key in _koAll.keys) {
      final String value = _read(l, key);
      expect(
        hangul.hasMatch(value),
        isFalse,
        reason: '$key 가 en 로케일에서 한국어다: $value',
      );
      expect(value.trim(), isNotEmpty, reason: '$key 가 비어 있다');
    }
  });

  testWidgets('두 로케일의 문구가 실제로 다르다', (WidgetTester tester) async {
    // 같은 값이면 ARB 에 en 번역을 빠뜨리고 ko 를 복사해 둔 것이다. 위 두 테스트만으로는
    // 잡히지 않는 실수라(영문 그대로 둔 키는 한글 검사를 통과한다) 여기서 함께 본다.
    final AppLocalizations ko = await _localizations(
      tester,
      const Locale('ko'),
    );
    final AppLocalizations en = await _localizations(
      tester,
      const Locale('en'),
    );

    for (final String key in _koAll.keys) {
      expect(_read(en, key), isNot(_read(ko, key)), reason: key);
    }
  });
}
