// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get coachInviteUnavailable => '이미 처리되었거나 취소된 요청이에요.';

  @override
  String get appTitle => 'On-Care';

  @override
  String get notFoundTitle => '페이지를 찾을 수 없어요';

  @override
  String get notFoundMessage => '주소가 잘못됐거나 더 이상 없는 페이지예요. 주소를 다시 확인해 주세요.';

  @override
  String get notFoundGoHome => '홈으로';

  @override
  String get notFoundGoSignIn => '로그인하러 가기';

  @override
  String get updateRequiredTitle => '새 버전이 나왔어요';

  @override
  String get updateRequiredMessage => '계속 쓰려면 On-Care 를 업데이트해 주세요.';

  @override
  String updateRequiredVersions(String current, String min) {
    return '지금 버전 $current · 필요한 버전 $min';
  }

  @override
  String get updateRequiredAction => '업데이트';

  @override
  String get updateRequiredStoreHint => 'App Store 에서 On-Care 를 업데이트해 주세요.';

  @override
  String get updateRequiredOpenFailed =>
      '스토어를 열지 못했어요. 스토어 앱에서 On-Care 를 업데이트해 주세요.';

  @override
  String get misconfiguredBuildTitle => '이 빌드는 잘못 구성됐어요';

  @override
  String get misconfiguredBuildMessage =>
      '실제 사용자에게 쓸 수 없는 설정으로 빌드되어 앱을 열지 않았어요. 배포 담당자에게 아래 내용을 알려 주세요.';

  @override
  String get misconfiguredBuildDetailsTitle => '고쳐야 할 빌드 설정';

  @override
  String get misconfiguredBuildDevEnvironment => 'ENV 가 prod 또는 staging 이 아니에요';

  @override
  String get misconfiguredBuildMockWithoutDemo =>
      '데모 빌드 표시 없이 데모 데이터를 쓰고 있어요 (USE_MOCK_API, DEMO_BUILD)';

  @override
  String get misconfiguredBuildPlaceholderApiUrl =>
      'API 주소가 예시·로컬 주소예요 (API_BASE_URL)';

  @override
  String get misconfiguredBuildInsecureApiUrl =>
      'API 주소가 https:// 로 시작하지 않아요 (API_BASE_URL)';

  @override
  String get navDashboard => '홈';

  @override
  String get navDiet => '식단';

  @override
  String get navExercise => '운동';

  @override
  String get navMyHealth => 'MY';

  @override
  String get pageDietTitle => '식단';

  @override
  String get pageExerciseTitle => '운동';

  @override
  String get pageAiCoachTitle => 'AI 코치';

  @override
  String get pageNotificationTitle => '알림';

  @override
  String get actionRetry => '다시 시도';

  @override
  String get errorCancelled => '취소됨';

  @override
  String get errorUnknown => '알 수 없는 오류';

  @override
  String get errorForbidden => '이 기능을 쓸 권한이 없어요. 필요한 동의나 트레이너 연결을 확인해 주세요.';

  @override
  String get errorRateLimited => '요청이 많아 잠시 멈췄어요. 잠시 뒤 다시 시도해 주세요.';

  @override
  String get dashboardMetricCalories => '칼로리';

  @override
  String get dashboardMetricExercise => '주간 운동';

  @override
  String get homeDashboardLoadError => '대시보드 정보를 불러오지 못했어요.';

  @override
  String get homeDashboardEmpty => '아직 오늘 기록이 없어요. 식단이나 운동을 기록해 보세요.';

  @override
  String get homeAiAdviceTitle => '오늘의 AI 통합 조언';

  @override
  String get homeAdviceSodiumOver => '오늘 나트륨이 권장량을 넘었어요. 남은 끼니는 담백하게 드셔 보세요.';

  @override
  String homeAdviceExerciseOnTrack(int minutes) {
    return '이번 주 $minutes분 운동했어요. 목표 달성 중이에요!';
  }

  @override
  String homeAdviceExerciseMore(int minutes) {
    return '이번 주 $minutes분 운동했어요. 조금만 더 힘내요!';
  }

  @override
  String get homeAdviceExerciseStart => '이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요.';

  @override
  String homeAdviceSodiumOverSources(String foods) {
    return '$foods 섭취로 나트륨이 높아요.';
  }

  @override
  String homeAdviceFoodPair(String first, String second) {
    return '$first·$second';
  }

  @override
  String get homeAiAdviceBody =>
      '아침 식단과 저녁 PT는 완벽했습니다! 점심 짬뽕으로 나트륨이 높았으니 물을 충분히 마시고, 코치님이 강조하신 어깨 스트레칭으로 건강하게 마무리해 보세요.';

  @override
  String get homeAiAdviceNoRecord => '오늘 식단과 운동을 기록하면 하루를 돌아보는 AI 조언을 드릴게요.';

  @override
  String get homeMacroCarbs => '탄수화물';

  @override
  String get homeMacroProtein => '단백질';

  @override
  String get homeMacroFat => '지방';

  @override
  String get homeMealChickenSalad => '닭가슴살 샐러드';

  @override
  String get homeDetails => '자세히';

  @override
  String get homeGoal => '목표';

  @override
  String get homeDietNutritionTitle => '식단 · 영양';

  @override
  String get homeCalorieIntake => '오늘 섭취 칼로리';

  @override
  String get homeAchieveRate => '달성률';

  @override
  String homeWeeklyMetricTrend(String metric) {
    return '주간 $metric 추이';
  }

  @override
  String get homeExerciseTrendUnavailable => '주간 운동 기록을 불러오지 못했어요.';

  @override
  String get homeExerciseBurned => '소모 칼로리';

  @override
  String get homeMealReasonSodium => '나트륨 조절에 좋아요';

  @override
  String get homeMealSourceTrainer => '트레이너 추천';

  @override
  String get homeMealSourceAi => 'AI 추천';

  @override
  String get homeMealTagLowSodium => '저나트륨';

  @override
  String get homeMealBrownRiceBox => '현미 도시락';

  @override
  String get homeMealReasonGlucose => '혈당 안정에 도움돼요';

  @override
  String get homeMealTagLowSugar => '저당류';

  @override
  String get homeMealSalmon => '연어 구이 + 나물';

  @override
  String get homeMealReasonOmega => '오메가3 + 식이섬유';

  @override
  String get homeMealTagHighProtein => '고단백질';

  @override
  String get homeMealTofu => '두부 채소 볶음';

  @override
  String get homeMealReasonLowCal => '칼로리 낮고 포만감↑';

  @override
  String get homeMealTagLowCal => '저칼로리';

  @override
  String get homeMealNamulBibimbap => '나물 비빔밥';

  @override
  String get homeMealReasonFiber => '식이섬유가 풍부해요';

  @override
  String get homeMealTagLowFat => '저지방';

  @override
  String get homeTrainerPickReasonSodiumLow => '나트륨을 줄여 줘요';

  @override
  String get homeTrainerPickReasonProteinHigh => '단백질을 채워 줘요';

  @override
  String get homeTrainerPickReasonCalorieLow => '가볍게 먹기 좋아요';

  @override
  String get homeTrainerPickReasonCalorieHigh => '든든하게 채워 줘요';

  @override
  String get homeTrainerPickReasonSugarLow => '당류를 줄여 줘요';

  @override
  String get homeTrainerPickReasonFiberHigh => '식이섬유를 채워 줘요';

  @override
  String homeRecBasisSodium(int days, String sodium) {
    return '최근 $days일 평균 나트륨 ${sodium}mg';
  }

  @override
  String get homeRecBasisOverLimit => '권장 초과';

  @override
  String get homeRecMealsTitle => '추천 식단';

  @override
  String get homeRecMealsErrorTitle => '추천 식단을 불러오지 못했어요';

  @override
  String get unitKcal => 'kcal';

  @override
  String get unitMinutes => '분';

  @override
  String unitKcalValue(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString kcal';
  }

  @override
  String unitMinutesValue(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString분';
  }

  @override
  String get dietTitle => '식단';

  @override
  String get dietToday => '오늘로';

  @override
  String get dietWeekdayMon => '월';

  @override
  String get dietWeekdayTue => '화';

  @override
  String get dietWeekdayWed => '수';

  @override
  String get dietWeekdayThu => '목';

  @override
  String get dietWeekdayFri => '금';

  @override
  String get dietWeekdaySat => '토';

  @override
  String get dietWeekdaySun => '일';

  @override
  String get dietNutritionSummary => '영양 요약';

  @override
  String get dietAmount => '내용량';

  @override
  String get dietCalories => '칼로리';

  @override
  String get dietSodium => '나트륨';

  @override
  String get dietSugar => '당류';

  @override
  String get dietUnitMg => 'mg';

  @override
  String get dietUnitG => 'g';

  @override
  String get dietAiFeedback => 'AI 맞춤 조언';

  @override
  String get aiAdviceLoading => '이 기간의 조언을 살펴보는 중이에요…';

  @override
  String get aiAdviceError => '조언을 불러오지 못했어요.';

  @override
  String get dietMealLog => '식단 기록';

  @override
  String get dietAddMeal => '식단 추가';

  @override
  String get dietEmptyLog => '기록된 식단이 없어요.\n사진으로 끼니를 추가해 보세요!';

  @override
  String get dietLoadError => '식단 정보를 불러오지 못했어요.';

  @override
  String get dietMealNotFound => '삭제됐거나 없는 기록이에요';

  @override
  String get dietMealNotFoundMessage => '식단 탭에서 기록을 다시 확인해 주세요.';

  @override
  String get dietMealNotFoundAction => '식단 탭으로';

  @override
  String get dietPeriodAverage => '하루 평균';

  @override
  String get dietPeriodEmpty => '이 기간에 기록된 식단이 없어요.';

  @override
  String get dietPeriodNoRecord => '기록 없음';

  @override
  String get dietPeriodNotYet => '아직 오지 않은 날';

  @override
  String dietPeriodOverGoal(String amount, String unit) {
    return '목표 초과 +$amount $unit';
  }

  @override
  String otherDateEmpty(Object section) {
    return '선택한 날짜에 기록된 $section이 없어요.';
  }

  @override
  String get dietMealBreakfast => '아침';

  @override
  String get dietMealLunch => '점심';

  @override
  String get dietMealDinner => '저녁';

  @override
  String get dietMealSnack => '간식';

  @override
  String get dietMealLateNight => '야식';

  @override
  String dietMealSheetTitle(String meal) {
    return '$meal 식단';
  }

  @override
  String dietFoodDbMatch(String name) {
    return '공공 DB · $name';
  }

  @override
  String dietMoreFoods(String name, int count) {
    return '$name 외 $count';
  }

  @override
  String get dietFillFromDb => '값 채우기';

  @override
  String dietFoodFilledFromDb(String name) {
    return '공공 DB · $name 값으로 바꿨어요';
  }

  @override
  String get dietUndoFill => '되돌리기';

  @override
  String get dietFoodNotInDb => '공공 DB에 없는 음식이에요. 영양 값을 확인해 주세요';

  @override
  String get dietAddSheetTitle => '식단 추가';

  @override
  String get dietAddSheetSubtitle => '사진으로 음식을 분석해요';

  @override
  String get dietPickPhoto => '사진 선택';

  @override
  String get dietPickPhotoSub => '갤러리에서 음식 사진 선택';

  @override
  String get dietTakePhoto => '사진 찍기';

  @override
  String get dietTakePhotoSub => '카메라로 음식 촬영';

  @override
  String get dietAddPhoto => '사진 추가';

  @override
  String get dietAddPhotoSub => '앨범·카메라·파일에서 음식 사진 선택';

  @override
  String get dietPhotoLoadError => '사진을 불러오지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get dietCameraPermissionDenied =>
      '음식 사진을 촬영하려면 카메라 권한이 필요해요. 사진 찍기를 눌러 다시 시도해 주세요';

  @override
  String get dietCameraPermissionPermanentlyDenied =>
      '카메라 접근이 꺼져 있어요. 설정에서 카메라를 켜면 음식 사진을 촬영할 수 있어요';

  @override
  String get dietPhotoPermissionDenied =>
      '음식 사진을 고르려면 사진 권한이 필요해요. 사진 선택을 눌러 다시 시도해 주세요';

  @override
  String get dietPhotoPermissionPermanentlyDenied =>
      '사진 접근이 꺼져 있어요. 설정에서 사진을 켜면 보관함에서 음식 사진을 고를 수 있어요';

  @override
  String get dietPhotoPermissionRestricted =>
      '기기 설정이나 관리 정책으로 카메라·사진을 사용할 수 없어요';

  @override
  String get dietPhotoUnsupportedFormat =>
      '지원하지 않는 사진 형식이에요. JPG 또는 PNG 사진으로 다시 시도해 주세요';

  @override
  String get dietPhotoTooLarge => '사진 용량이 너무 커요. 다른 사진으로 다시 시도해 주세요';

  @override
  String get dietOpenSettings => '설정 열기';

  @override
  String get dietOpenSettingsFailed =>
      '설정을 열지 못했어요. 설정 > Oncare에서 카메라·사진 접근을 켜주세요';

  @override
  String get dietAnalyzing => '분석 중…';

  @override
  String get dietAnalysisFailed => '분석 실패';

  @override
  String get dietRecordDate => '기록 날짜';

  @override
  String get dietRecordDateChange => '날짜 변경';

  @override
  String dietRecordDateMoved(String date) {
    return '$date 식단으로 옮겼어요';
  }

  @override
  String get dietRecordDateFailed => '날짜를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get dietMealKind => '끼니';

  @override
  String get dietAnalysisDone => '분석 완료!';

  @override
  String get dietAiNutritionResult => 'AI 영양 분석 결과';

  @override
  String get dietAnalyzingBody => '사진 속 음식을 분석하고 있어요';

  @override
  String get dietAnalysisFailedBody => '분석에 실패했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get dietAnalysisUnsupportedFormat =>
      '이 사진 형식은 분석할 수 없어요. JPG 또는 PNG 사진으로 다시 골라주세요.';

  @override
  String get dietAnalysisBadRequest => '사진을 읽지 못했어요. 다른 사진으로 다시 골라주세요.';

  @override
  String get dietAnalysisUnauthorized => '로그인이 만료됐어요. 다시 로그인한 뒤 기록해 주세요.';

  @override
  String get dietAnalysisNotImplemented =>
      '지금은 사진 분석을 사용할 수 없어요. 직접 입력으로 기록해 주세요.';

  @override
  String get dietAnalysisNoFood => '사진에서 음식을 찾지 못했어요. 다른 사진을 고르거나 직접 추가해 주세요.';

  @override
  String get dietAnalysisDailyLimit =>
      '오늘 사진 분석 횟수를 다 썼어요. 내일 다시 쓸 수 있고, 지금은 직접 추가로 기록할 수 있어요.';

  @override
  String get dietAnalysisRateLimited =>
      '사진 분석 요청이 너무 잦아요. 잠시 후 다시 시도하거나 직접 추가해 주세요.';

  @override
  String get dietAnalysisUnavailable => '지금은 사진 분석을 쓸 수 없어요. 직접 추가로 기록해 주세요.';

  @override
  String get dietAnalysisPickAnother => '다른 사진 고르기';

  @override
  String get dietAnalysisSignIn => '다시 로그인';

  @override
  String get dietAnalysisClose => '닫기';

  @override
  String get dietRecognizedFood => '인식된 음식';

  @override
  String get dietNoRecognizedFood => '인식된 음식이 없어요';

  @override
  String get dietNutritionResult => '영양 분석 결과';

  @override
  String get dietSaved => '식단이 저장되었어요';

  @override
  String get dietSaveFailed => '저장에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get dietDeleteTitle => '식단 기록 삭제';

  @override
  String get dietDeleteConfirm => '이 식단 기록을 삭제할까요?';

  @override
  String get dietDeleteWhenEmpty => '음식이 하나도 남지 않았어요. 이 식단 기록을 삭제할까요?';

  @override
  String get dietCancel => '취소';

  @override
  String get dietDelete => '삭제';

  @override
  String get dietDeleted => '식단이 삭제되었어요';

  @override
  String get dietDeleteFailed => '삭제에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get dietSave => '저장';

  @override
  String get dietMealInfo => '식사 정보';

  @override
  String get dietEatenFood => '먹은 음식';

  @override
  String get dietNewFood => '새 음식';

  @override
  String get dietAddFood => '음식 추가';

  @override
  String get dietManualAdd => '직접 추가';

  @override
  String get dietManualAddTitle => '식단 직접 추가';

  @override
  String get dietManualAddHint => '음식 이름을 적으면 영양 정보를 찾아 채워요';

  @override
  String get dietManualAddEmpty => '음식을 하나 이상 적어 주세요';

  @override
  String get dietEditFoodHint => '내용량을 고치면 영양이 비례해 따라와요';

  @override
  String get dietTotalCalories => '총 칼로리';

  @override
  String get dietNutritionInfo => '영양 정보';

  @override
  String get dietEditNutritionHint => '음식별 영양을 고치면 여기에 합쳐져요';

  @override
  String get dietSugarOverCarbs => '당류는 탄수화물보다 클 수 없어요';

  @override
  String get dietDeleteMeal => '식단 삭제';

  @override
  String get dietEditMeal => '식사 수정';

  @override
  String get exTypeCardio => '유산소';

  @override
  String get exTypeStrength => '근력';

  @override
  String get exTypeFlexibility => '스트레칭';

  @override
  String get exTypeOtherChip => '기타';

  @override
  String get exLevelLight => '가벼움';

  @override
  String get exLevelModerate => '보통';

  @override
  String get exLevelHigh => '높음';

  @override
  String get exExerciseLog => '운동 기록';

  @override
  String get exGymTab => '헬스장';

  @override
  String get exMyGymSection => '내 헬스장';

  @override
  String get exConnected => '연결됨';

  @override
  String get exTrainerAffiliation => '소속 헬스장';

  @override
  String get exTrainerIntroSection => '트레이너 소개';

  @override
  String exTrainerCareer(String career) {
    return '경력 $career';
  }

  @override
  String get exTrainerCertifications => '자격증 · 인증';

  @override
  String get exTrainerRecommendationReason => '내 건강 목표 달성에 잘 맞는 트레이너예요';

  @override
  String get exNearbyGymsMapLabel => '내 주변 헬스장';

  @override
  String get exActivityTitle => '운동 현황';

  @override
  String exBurnWeekOfMonthTitle(int month, int week) {
    return '$month월 $week주차 소모';
  }

  @override
  String get exBurnTodayTitle => '오늘 소모';

  @override
  String get exBurnWeekTitle => '이번 주 소모';

  @override
  String get exBurnAllTitle => '평균 소모';

  @override
  String exGoalValue(String value) {
    return '목표 $value';
  }

  @override
  String get exLoadEmpty => '아직 기록이 없어요.';

  @override
  String get exThisWeek => '이번 주';

  @override
  String get exPeriodAll => '전체';

  @override
  String exRestSeconds(int seconds) {
    return '휴식 $seconds초';
  }

  @override
  String exStreakCheer(int days) {
    return '$days일 연속 운동 중이에요!';
  }

  @override
  String get exStreakStart => '오늘 운동으로 연속 기록을 시작해 봐요.';

  @override
  String get exStreakProtected => '보호권으로 이어짐';

  @override
  String get exToday => '오늘';

  @override
  String get exLoadError => '운동 정보를 불러오지 못했어요.';

  @override
  String get exCompletedPtTitle => '오늘 완료한 PT';

  @override
  String exCompletedPtTime(String time) {
    return '$time 완료';
  }

  @override
  String exPtSessionNumber(int count) {
    return '$count회차';
  }

  @override
  String get exCompletedPtNoProgram => '등록된 운동 프로그램이 없습니다.';

  @override
  String get exAddExercise => '운동 추가';

  @override
  String exDurationMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String get exEditExercise => '운동 기록 수정';

  @override
  String get exSave => '저장';

  @override
  String get exExerciseType => '운동 종류';

  @override
  String get exExerciseDate => '날짜';

  @override
  String get exExerciseName => '운동 이름';

  @override
  String get exExerciseNameHintCardio => '예) 러닝머신, 실내 자전거';

  @override
  String get exExerciseNameHintStrength => '예) 스쿼트, 벤치프레스';

  @override
  String get exExerciseNameHintFlexibility => '예) 전신 스트레칭, 요가';

  @override
  String get exExerciseNameHintOther => '예) 재활 운동, 스포츠 활동';

  @override
  String get exExerciseReps => '횟수';

  @override
  String get exExerciseHold => '버티는 시간';

  @override
  String get exExerciseStrengthAmount => '세트 · 횟수 · 중량';

  @override
  String get exExerciseStrengthAmountHold => '세트 · 버티는 시간 · 중량';

  @override
  String get exExerciseMeasure => '재는 방법';

  @override
  String get exExerciseWeight => '중량';

  @override
  String get exUnitMinutes => '분';

  @override
  String get exUnitSets => '세트';

  @override
  String get exUnitReps => '회';

  @override
  String get exUnitSeconds => '초';

  @override
  String get exUnitHours => '시간';

  @override
  String get exUnitKg => 'kg';

  @override
  String get exEnterName => '운동 이름을 입력해주세요';

  @override
  String get exExerciseDuration => '운동 시간';

  @override
  String get exExerciseSets => '세트 수';

  @override
  String exSetsCount(int sets) {
    return '$sets세트';
  }

  @override
  String exRepsCount(int reps) {
    return '$reps회';
  }

  @override
  String get exEnterSets => '세트 수를 입력해주세요';

  @override
  String get exExerciseIntensity => '운동 강도';

  @override
  String get exEstimatedCalories => '예상 소모 칼로리';

  @override
  String get exCaloriesNeedName => '운동 이름을 적어주세요';

  @override
  String get exCaloriesCalculating => '계산 중…';

  @override
  String exCaloriesFromCatalog(String activity) {
    return '$activity 기준 · 체중 반영';
  }

  @override
  String get exCaloriesRoughEstimate => '운동 종류 평균으로 낸 어림값이에요';

  @override
  String get exEnterDuration => '운동 시간을 입력해주세요';

  @override
  String get exCannotEdit => '이 기록은 수정할 수 없어요';

  @override
  String get exUpdated => '운동 기록이 수정됐어요';

  @override
  String get exLogged => '운동이 기록됐어요';

  @override
  String exQueueTitle(int count) {
    return '추가할 운동 $count';
  }

  @override
  String get exQueueRemove => '목록에서 빼기';

  @override
  String exQueueFull(int count) {
    return '한 번에 $count개까지 추가할 수 있어요';
  }

  @override
  String exSaveCount(int count) {
    return '$count개 저장';
  }

  @override
  String exLoggedCount(int count) {
    return '운동 $count개가 기록됐어요';
  }

  @override
  String get exQueueDiscardTitle => '추가할 운동을 버릴까요?';

  @override
  String exQueueDiscardBody(int count) {
    return '아직 저장하지 않은 운동 $count개가 사라져요.';
  }

  @override
  String get exQueueDiscard => '버리기';

  @override
  String get exOwnRecords => '직접 기록한 운동';

  @override
  String get exOwnRecordsEmpty => '직접 기록한 운동이 없어요';

  @override
  String get exRecordDetailOpen => '자세히';

  @override
  String get exRecordDetailInfo => '운동 정보';

  @override
  String get exRecordDetailTotalCalories => '총 소모 칼로리';

  @override
  String get exBurnedPrefix => '소모';

  @override
  String get exRecordMaxWeight => '최고 중량';

  @override
  String get exRecordLongest => '최장 시간';

  @override
  String get exRecordFirst => '첫 기록';

  @override
  String get exRecordDateChange => '날짜 변경';

  @override
  String exRecordDateMoved(String date) {
    return '$date 운동으로 옮겼어요';
  }

  @override
  String get exRecordDateFailed => '날짜를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get exCompletedPtDayTitle => '완료한 PT';

  @override
  String get exCompletedRoutineDayTitle => '완료한 개인운동';

  @override
  String get exDeleteExercise => '운동 기록 삭제';

  @override
  String get exDeleteExerciseBody => '이 기록을 삭제하면 되돌릴 수 없어요.';

  @override
  String get exDeleted => '운동 기록을 삭제했어요';

  @override
  String get exDeleteFailed => '삭제하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get exCannotDelete => '이 기록은 삭제할 수 없어요';

  @override
  String get exSaveFailed => '저장에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get exFindGym => '헬스장 찾기';

  @override
  String get exGymDetailTitle => '헬스장 상세';

  @override
  String get exTrainerDetailTitle => '트레이너 상세';

  @override
  String get exRating => '평점';

  @override
  String get exAffiliatedTrainer => '소속 트레이너';

  @override
  String get exRecommendationReason => '추천 이유';

  @override
  String get exGymNotFound => '헬스장 정보를 찾을 수 없어요.';

  @override
  String get exTrainerNotFound => '트레이너 정보를 찾을 수 없어요.';

  @override
  String get exGymSearchPlaceholder => '지역이나 헬스장 이름 검색';

  @override
  String get exSortRecommended => '추천순';

  @override
  String get exSortDistance => '거리순';

  @override
  String get exSortRating => '평점순';

  @override
  String exResultCount(int count) {
    return '$count개 결과';
  }

  @override
  String get exNoSearchResults => '검색 결과가 없어요.';

  @override
  String get exTrainersLoadError => '트레이너 정보를 불러오지 못했어요.';

  @override
  String get exNearbyGyms => '주변 헬스장';

  @override
  String get exGymListCollapse => '목록 접기';

  @override
  String get exGymListExpand => '목록 펼치기';

  @override
  String get exGymsLoadError => '헬스장을 불러오지 못했어요.';

  @override
  String exGymWeekdayHours(String hours) {
    return '평일 $hours';
  }

  @override
  String exGymWeekendHours(String hours) {
    return '주말 $hours';
  }

  @override
  String get exTrainerDedicated => '전담 트레이너';

  @override
  String exTrainerAvailability(String trainer) {
    return '$trainer 빈 예약 시간';
  }

  @override
  String exSlotWhen(String date, String time) {
    return '$date $time';
  }

  @override
  String get exSlotTypePersonalTraining => '1:1 PT';

  @override
  String get exSlotsEmpty => '예약 가능한 시간이 없어요';

  @override
  String get exSlotsAllBooked => '예약 가능한 시간이 모두 찼어요';

  @override
  String get exSlotsLoadError => '예약 시간을 불러오지 못했어요.';

  @override
  String get exReserveFailed => '예약에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get exReserveTimeTaken =>
      '트레이너의 다른 일정과 겹쳐 이 시간은 예약할 수 없어요. 다른 시간을 골라 주세요';

  @override
  String exReserveConfirmedSlotGym(String slot, String gym) {
    return '$slot · $gym 예약이 확정됐어요';
  }

  @override
  String exReserveConfirm(String slot) {
    return '$slot 예약 확정';
  }

  @override
  String get exAddress => '주소';

  @override
  String get exHours => '운영시간';

  @override
  String get exPhone => '전화';

  @override
  String get exSpecialty => '전문 분야';

  @override
  String get myTabTitle => 'MY';

  @override
  String get myDefaultUserName => '사용자';

  @override
  String get myProfileLoadFailed => '내 정보를 불러오지 못했어요';

  @override
  String get myPointsLoadFailed => '포인트 잔액을 불러오지 못했어요';

  @override
  String get mySettingsTitle => '설정';

  @override
  String get myProfileTitle => '내 프로필';

  @override
  String get myNotifTitle => '알림 설정';

  @override
  String get myGuideTitle => '앱 사용 가이드';

  @override
  String get mySupportTitle => '고객 지원';

  @override
  String get myPointsBenefitsTitle => '포인트 사용처';

  @override
  String myPointsBalance(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '보유 ${pointsString}P';
  }

  @override
  String get myPointsBenefitsSubtitle => '포인트로 받을 수 있는 혜택';

  @override
  String get myPointsBenefitsHint => '기록을 꾸준히 남기면 포인트가 쌓이고, 위 혜택에 사용할 수 있어요.';

  @override
  String myPointsCost(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '${pointsString}P';
  }

  @override
  String get myPointsExchange => '교환';

  @override
  String get myPointsExchangeConfirmTitle => '포인트로 교환할까요?';

  @override
  String myPointsExchangeConfirmMessage(String item, String cost) {
    return '$item에 $cost를 사용해요. 교환한 쿠폰은 내 혜택에서 볼 수 있어요.';
  }

  @override
  String get myPointsExchangeConfirmAction => '교환';

  @override
  String get myPointsExchangeDone => '교환했어요';

  @override
  String get myPointsExchangeFailed => '교환하지 못했어요. 다시 시도해 주세요.';

  @override
  String myPointsShortfall(String points) {
    return '$points 부족해요';
  }

  @override
  String get myPointsNeedTrainer => '담당 트레이너가 있어야 교환할 수 있어요';

  @override
  String get myPointsNeedGym => '헬스장을 연결해야 교환할 수 있어요';

  @override
  String get myPointsActiveCoupon => '사용하지 않은 쿠폰이 있어요';

  @override
  String get myPointsMonthlyLimit => '이번 달에는 이미 교환했어요';

  @override
  String get myPointsShieldLimit => '보호권은 최대 4개까지 가질 수 있어요';

  @override
  String get myShopStreakShieldTitle => '연속 기록 보호권';

  @override
  String get myShopStreakShieldDescription =>
      '아무것도 기록하지 못한 날을 연속 기록에 이어 붙여요. 최근 30일 안에서 쓰고, 최대 4개까지 가질 수 있어요.';

  @override
  String get myBenefitsStreakShields => '연속 기록 보호권';

  @override
  String myBenefitsShieldHeld(int held, int max) {
    return '보유 $held/$max개';
  }

  @override
  String myBenefitsShieldHeldCount(int held) {
    return '보유 $held개';
  }

  @override
  String get myBenefitsShieldGuide =>
      '기록이 빈 날을 기록 그래프에서 눌러 이어 붙여요. 최근 30일 안의 날만 돼요.';

  @override
  String get myBenefitsShieldUsedTitle => '보호한 날';

  @override
  String get myBenefitsShieldNoneUsed => '아직 보호한 날이 없어요';

  @override
  String get myShopGraphColorTitle => '그래프 색 바꾸기';

  @override
  String get myShopGraphColorDescription =>
      '포인트 화면 기록 그래프의 색을 골라 바꿔요. 한 번 연 색은 계속 쓸 수 있어요.';

  @override
  String get myGraphTitle => '기록 그래프';

  @override
  String myGraphMonthLabel(int month) {
    return '$month월';
  }

  @override
  String myGraphStreak(int days) {
    return '기록 연속 $days일';
  }

  @override
  String get myGraphLoadFailed => '기록 그래프를 불러오지 못했어요.';

  @override
  String myGraphDate(int month, int day) {
    return '$month월 $day일';
  }

  @override
  String get myGraphDayHint => '칸을 누르면 그날 기록이 보여요';

  @override
  String myGraphDayNone(String date) {
    return '$date · 기록 없음';
  }

  @override
  String myGraphDayDiet(String date) {
    return '$date · 식단만 기록';
  }

  @override
  String myGraphDayExercise(String date) {
    return '$date · 운동만 기록';
  }

  @override
  String myGraphDayBoth(String date) {
    return '$date · 식단 · 운동 모두 기록';
  }

  @override
  String myGraphDayProtected(String date) {
    return '$date · 보호권으로 이어짐';
  }

  @override
  String get myGraphProtectAction => '보호권 사용';

  @override
  String get myGraphProtectConfirmAction => '사용';

  @override
  String get myGraphProtectConfirmTitle => '보호권을 사용할까요?';

  @override
  String myGraphProtectConfirmMessage(String date, int held) {
    return '$date을 기록 연속에 이어 붙여요. 보호권 한 개를 사용해요(남은 보호권 $held개).';
  }

  @override
  String get myGraphProtectDone => '연속을 이어 붙였어요';

  @override
  String get myGraphProtectFailed => '보호권을 사용하지 못했어요';

  @override
  String get myGraphProtectBuyConfirmTitle => '보호권을 구매할까요?';

  @override
  String myGraphProtectBuyConfirmMessage(String date, String cost) {
    return '지금 가진 보호권이 없어요. $cost로 보호권을 구매하고 $date을 바로 기록 연속에 이어 붙여요.';
  }

  @override
  String get myGraphProtectBuyAction => '구매하고 사용';

  @override
  String get myGraphProtectBoughtNotUsed => '보호권은 구매했지만 사용하지 못했어요. 내 혜택에 보관돼요.';

  @override
  String get myGraphColorTitle => '그래프 색';

  @override
  String get myGraphColorPickTitle => '열 색 고르기';

  @override
  String myGraphColorLocked(String cost) {
    return '$cost로 열기';
  }

  @override
  String get myGraphColorDone => '그래프 색을 바꿨어요';

  @override
  String myGraphColorExchangeConfirm(String color, String cost) {
    return '$color 그래프를 $cost로 열까요? 한 번 열면 계속 쓸 수 있어요.';
  }

  @override
  String get myGraphColorUnlocked => '그래프 색을 열었어요';

  @override
  String get myGraphColorFailed => '그래프 색을 바꾸지 못했어요';

  @override
  String get myGraphColorBlue => '파랑';

  @override
  String get myGraphColorGreen => '초록';

  @override
  String get myGraphColorPurple => '보라';

  @override
  String get myGraphColorOrange => '주황';

  @override
  String get myGraphColorPink => '분홍';

  @override
  String get myShopProfilePetTitle => '프로필 펫 이모지';

  @override
  String get myShopProfilePetDescription =>
      '강아지나 고양이를 골라 7일 동안 MY 프로필 이름 옆에 달아요.';

  @override
  String get myProfilePetDog => '강아지';

  @override
  String get myProfilePetCat => '고양이';

  @override
  String get myProfilePetSheetTitle => '이름 옆에 달 펫을 골라요';

  @override
  String myProfilePetActive(String pet, String left) {
    return '$pet · $left';
  }

  @override
  String myProfilePetDaysLeft(int days) {
    return '$days일 남음';
  }

  @override
  String myProfilePetHoursLeft(int hours) {
    return '$hours시간 남음';
  }

  @override
  String myProfilePetExchangeConfirm(String pet, String cost) {
    return '$pet를 $cost로 7일 동안 이름 옆에 달까요?';
  }

  @override
  String get myProfilePetDone => '이름 옆에 펫을 달았어요';

  @override
  String get myShopWeeklyReportTitle => '주간 리포트';

  @override
  String myShopWeeklyReportDescription(String range) {
    return '$range 식단·운동 기록과 참고 기록으로 한 주를 돌아보는 리포트를 만들어요.';
  }

  @override
  String get myWeeklyReportOwned => '지난주 리포트는 이미 받았어요';

  @override
  String myWeeklyReportExchangeConfirm(String range, String cost) {
    return '$range 리포트를 $cost로 만들까요?';
  }

  @override
  String get myWeeklyReportDone => '지난주 리포트를 만들었어요';

  @override
  String get myBenefitsWeeklyReports => '주간 리포트';

  @override
  String get myWeeklyReportCardTitle => '포인트로 받은 리포트';

  @override
  String get coachReportPdfSelfMadeNote =>
      '담당 트레이너 없이 포인트로 받은 리포트라 트레이너 피드백이 없어요.';

  @override
  String get coachReportPdfSectionInsights => '참고 기록';

  @override
  String get coachReportPdfNoInsights => '이 주의 AI 코치 대화에서 감지된 통증·부정적 반응이 없어요.';

  @override
  String coachReportPdfInsightSummary(String label, int count) {
    return '$label $count회';
  }

  @override
  String coachReportPdfInsightMore(int count) {
    return '외 $count건';
  }

  @override
  String myProfilePetLabel(String pet) {
    return '$pet 펫 이모지';
  }

  @override
  String myPointsValidDays(int days) {
    return '교환 후 $days일 동안 사용';
  }

  @override
  String get myPointsShopLoadFailed => '사용처를 불러오지 못했어요';

  @override
  String get myShopPtRenewalTitle => 'PT 재등록 3만원 할인';

  @override
  String get myShopPtRenewalDescription =>
      '담당 트레이너에게 PT를 다시 등록할 때 30,000원을 할인받아요.';

  @override
  String get myShopLockerTitle => '개인 락커 1개월 무료';

  @override
  String get myShopLockerDescription => '연결한 헬스장에서 개인 락커를 한 달 동안 무료로 써요.';

  @override
  String get myCouponPtRenewalBenefit => 'PT 재등록 30,000원 할인';

  @override
  String get myBenefitsTitle => '내 혜택';

  @override
  String get myPointsHistoryTitle => '포인트 내역';

  @override
  String get myPointsHistoryEmpty => '아직 포인트 내역이 없어요';

  @override
  String get myPointsHistoryEmptyMessage => '식단·운동을 기록하면 포인트가 쌓여요.';

  @override
  String get myPointsHistoryLoadFailed => '포인트 내역을 불러오지 못했어요';

  @override
  String get myPointsHistoryMore => '더 보기';

  @override
  String get myPointsHistoryMoreFailed => '더 불러오지 못했어요. 다시 시도해 주세요';

  @override
  String get myPointsReasonDiet => '식단 기록';

  @override
  String get myPointsReasonExercise => '운동 기록';

  @override
  String get myPointsReasonRoutine => '추천·배정 운동 완료';

  @override
  String get myPointsReasonPtRenewal => 'PT 재등록 할인 쿠폰';

  @override
  String get myPointsReasonLocker => '개인 락커 쿠폰';

  @override
  String get myPointsReasonShield => '연속 기록 보호권';

  @override
  String get myPointsReasonGraphColor => '그래프 색';

  @override
  String get myPointsReasonEmotePass => '채팅 이모티콘 24시간';

  @override
  String get myPointsReasonEmoteUnlock => '채팅 이모티콘';

  @override
  String get myPointsReasonProfilePet => '프로필 펫 이모지';

  @override
  String get myPointsReasonWeeklyReport => '주간 리포트';

  @override
  String get myPointsReasonChallengeStake => '주간 챌린지 참가';

  @override
  String get myPointsReasonChallengeReward => '주간 챌린지 보상';

  @override
  String myPointsReasonAiChat(int count) {
    return 'AI 코치 대화 $count회';
  }

  @override
  String get myPointsReasonOther => '포인트';

  @override
  String myPointsKindRevoked(String label) {
    return '$label · 기록 삭제로 회수';
  }

  @override
  String myPointsKindRefunded(String label) {
    return '$label · 취소로 반환';
  }

  @override
  String get myBenefitsView => '보기';

  @override
  String get myBenefitsCoupons => '쿠폰';

  @override
  String get myBenefitsEmpty => '보유한 쿠폰이 없어요';

  @override
  String get myBenefitsEmptyMessage => '포인트로 쿠폰을 교환해 보세요.';

  @override
  String get myBenefitsLoadFailed => '혜택을 불러오지 못했어요';

  @override
  String get challengeTitle => '주간 운동 챌린지';

  @override
  String challengeShortWithRange(String range) {
    return '주간 챌린지 · $range';
  }

  @override
  String challengeDescription(String stake, int goal, String reward) {
    return '$stake를 걸고 이번 주 $goal회 운동하면 $reward를 돌려받아요';
  }

  @override
  String get challengeJoinWindow => '월·화요일에만 참가할 수 있어요';

  @override
  String get challengeJoin => '참가';

  @override
  String get challengeJoinConfirmTitle => '주간 챌린지에 참가할까요?';

  @override
  String challengeJoinConfirmMessage(String stake, int goal, String reward) {
    return '$stake를 걸고 이번 주 $goal회 운동에 도전해요. 일요일까지 채우면 $reward를 돌려받고, 못 채우면 건 포인트는 사라져요.';
  }

  @override
  String get challengeJoinConfirmAction => '참가';

  @override
  String get challengeJoinDone => '챌린지에 참가했어요';

  @override
  String get challengeJoinFailed => '참가하지 못했어요. 다시 시도해 주세요.';

  @override
  String get challengeJoinClosed => '다음 주 월요일에 다시 참가할 수 있어요';

  @override
  String get challengeThisWeek => '이번 주 진행';

  @override
  String challengeProgress(int progress, int goal) {
    return '$progress / $goal회';
  }

  @override
  String challengeRemaining(int count, String reward) {
    return '일요일까지 $count회 더 운동하면 $reward를 돌려받아요';
  }

  @override
  String challengeAchieved(String reward) {
    return '목표 달성! 주가 끝나면 $reward를 받아요';
  }

  @override
  String get myCouponStatusUsable => '사용 가능';

  @override
  String get myCouponStatusUsed => '사용 완료';

  @override
  String get myCouponStatusExpired => '만료';

  @override
  String get myCouponStatusCancelled => '취소됨';

  @override
  String myCouponDaysLeft(int days) {
    return 'D-$days';
  }

  @override
  String get myCouponDDay => 'D-day';

  @override
  String myCouponUntil(String date) {
    return '$date까지';
  }

  @override
  String get myCouponTrainer => '담당 트레이너';

  @override
  String get myCouponGym => '헬스장';

  @override
  String get myCouponIssuedOn => '교환일';

  @override
  String get myCouponExpiry => '만료일';

  @override
  String myCouponExpiryWithDday(String date, String dday) {
    return '$date ($dday)';
  }

  @override
  String get myCouponStatus => '상태';

  @override
  String get myCouponStaffNote => '트레이너·헬스장 직원이 확인한 뒤 눌러 주세요';

  @override
  String get myCouponGymStaffNote => '헬스장 직원이 확인한 뒤 눌러 주세요';

  @override
  String get myCouponNoExpiry => '기한 없음';

  @override
  String get myDietTrayTitle => '분석용 식판 무료 제공';

  @override
  String get myDietTrayFree => '무료';

  @override
  String myDietTrayDescription(int window, int days) {
    return '최근 $window일 중 $days일 식단 사진을 남기면 분석에 맞춘 규격 식판을 드려요. 같은 식판에 담아 찍으면 양을 더 정확하게 분석해요.';
  }

  @override
  String myDietTrayProgressLabel(int window) {
    return '최근 $window일 사진 기록';
  }

  @override
  String myDietTrayProgress(int days, int required) {
    return '$days / $required일';
  }

  @override
  String myDietTrayDaysLeft(int days) {
    return '$days일 더 찍으면 받을 수 있어요';
  }

  @override
  String get myDietTrayNeedTrainer => '담당 트레이너를 연결하면 받을 수 있어요';

  @override
  String get myDietTrayClaimable => '조건을 채웠어요! 담당 트레이너의 헬스장에서 받아요';

  @override
  String myDietTrayIssued(String gym) {
    return '$gym에서 받아요. 가기 전에 담당 트레이너에게 준비됐는지 채팅으로 물어보세요';
  }

  @override
  String get myDietTrayReceived => '식판을 받았어요. 식판에 담아 찍어 보세요';

  @override
  String get myDietTrayClaim => '받기';

  @override
  String get myDietTrayViewCoupon => '쿠폰 보기';

  @override
  String get myDietTrayClaimConfirmTitle => '식판 수령 쿠폰을 받을까요?';

  @override
  String get myDietTrayClaimConfirmMessage =>
      '담당 트레이너의 헬스장에서 받아요. 기한은 없고, 식판은 한 사람당 한 번 받을 수 있어요.';

  @override
  String get myDietTrayClaimDone => '식판 수령 쿠폰을 받았어요';

  @override
  String get myDietTrayClaimFailed => '식판 수령 쿠폰을 받지 못했어요';

  @override
  String get myDietTrayNotice =>
      '1인 1회 · 사진으로 기록한 날만 세요(손으로 적은 끼니, 보호권으로 이은 날 제외) · 수령 기한 없음 · 헬스장에 가기 전에 담당 트레이너에게 식판이 준비됐는지 확인해 주세요 · 재고와 운영 사정에 따라 조건이 바뀔 수 있어요';

  @override
  String get myDietTrayCouponBenefit => '분석용 규격 식판';

  @override
  String get myDietTrayStaffNote => '헬스장 직원에게 식판을 받은 뒤 눌러 주세요';

  @override
  String get myDietTrayIssuedOn => '받은 날';

  @override
  String get myDietTrayExpireNotice =>
      '기한 없이 쓸 수 있어요. 헬스장에 가기 전에 담당 트레이너에게 식판이 준비됐는지 채팅으로 물어보세요.';

  @override
  String get myCouponStaffConfirmTitle => '쿠폰을 사용 완료할까요?';

  @override
  String get myCouponStaffConfirmMessage => '직원 확인용 · 사용 후 되돌릴 수 없어요';

  @override
  String get myCouponUsedAt => '사용 시각';

  @override
  String myCouponUsedBanner(String time) {
    return '$time에 사용 완료했어요';
  }

  @override
  String get myCouponExpireNotice => '만료되면 포인트는 돌려받을 수 없어요.';

  @override
  String get myCouponUse => '사용 완료';

  @override
  String get myCouponUseDone => '사용 완료로 바꿨어요';

  @override
  String get myCouponUseFailed => '사용 처리하지 못했어요. 다시 시도해 주세요.';

  @override
  String get myCouponNotFound => '쿠폰을 찾을 수 없어요';

  @override
  String get a11yCoachPhoto => '트레이너가 보낸 사진';

  @override
  String get a11yMealPhoto => '끼니 사진';

  @override
  String a11yMealPhotoOf(String name) {
    return '$name 사진';
  }

  @override
  String get myLogout => '로그아웃';

  @override
  String get myLogoutConfirm => '로그아웃 하시겠어요?';

  @override
  String get emoteSheetTitle => '이모티콘';

  @override
  String get emoteBuyTitle => '이모티콘 구매';

  @override
  String emoteBuyConfirm(int cost, int days) {
    return '${cost}P로 $days일 동안 쓸까요?\n산 때부터 기간이 흘러가요.';
  }

  @override
  String get emoteBuyAction => '구매';

  @override
  String get emoteBought => '이제 이 이모티콘을 보낼 수 있어요';

  @override
  String get emoteBuyFailed => '이모티콘을 사지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get emoteAlreadyUnlocked => '이미 열려 있는 이모티콘이에요. 바로 보낼 수 있어요';

  @override
  String get emoteTrainerRequired => '담당 트레이너가 있어야 이모티콘을 살 수 있어요';

  @override
  String get emoteShortfall => '포인트가 부족해요';

  @override
  String get emoteLoadFailed => '이모티콘을 불러오지 못했어요';

  @override
  String get emoteSendFailed => '이모티콘을 보내지 못했어요';

  @override
  String get a11yOpenEmotes => '이모티콘';

  @override
  String get a11yEmote => '이모티콘';

  @override
  String get myWithdrawTitle => '회원 탈퇴';

  @override
  String get myWithdrawConfirm =>
      '탈퇴하면 계정과 함께 기록한 식단·운동·건강 지표가 모두 지워지고, 트레이너와의 연결과 주고받은 대화, 포인트와 사용 전 쿠폰·보호권·꾸밈 아이템도 사라집니다. 예정된 PT 예약과 대기 중인 상담 요청은 취소돼요. 되돌릴 수 없어요.';

  @override
  String myWithdrawLosePoints(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '• 보유 포인트 ${pointsString}P가 사라져요';
  }

  @override
  String myWithdrawLoseCoupons(int count) {
    return '• 사용 전 쿠폰 $count장이 사라져요';
  }

  @override
  String myWithdrawCancelReservations(int count) {
    return '• 예정된 PT 예약 $count건이 취소돼요';
  }

  @override
  String myWithdrawCancelConsultations(int count) {
    return '• 대기 중인 상담 요청 $count건이 취소돼요';
  }

  @override
  String get myWithdrawAction => '탈퇴';

  @override
  String get myWithdrawFailed => '탈퇴하지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get myWithdrawReasonTitle => '정말 탈퇴를 원하시나요?';

  @override
  String get myWithdrawReasonQuestion => '어떤 부분이 불편하셨나요?';

  @override
  String get myWithdrawReasonHint => '복수 선택 가능';

  @override
  String get myWithdrawReasonPrivacy => '개인정보 노출이 걱정돼요';

  @override
  String get myWithdrawReasonRarelyUsed => '자주 사용하지 않아요';

  @override
  String get myWithdrawReasonHardToUse => '쓰기가 불편해요';

  @override
  String get myWithdrawReasonNotifications => '알림이 너무 많아요';

  @override
  String get myWithdrawReasonAlternative => '다른 앱을 쓰고 있어요';

  @override
  String get myWithdrawReasonOther => '그 밖의 이유';

  @override
  String get myWithdrawNext => '다음';

  @override
  String get myWithdrawKeepTitle => '탈퇴하기 전에';

  @override
  String get myWithdrawKeepPrivacy =>
      '회원님의 기록은 절대 불특정 타인에게 공개하지 않아요. 볼 수 있는 사람은 회원님과 연결된 담당 트레이너뿐이고, 트레이너 연결을 끊으면 회원님만 볼 수 있어요 — MY 탭의 내 헬스장 · 트레이너에서 바로 끊을 수 있습니다.';

  @override
  String get myWithdrawKeepRarelyUsed =>
      '매일 다 적지 않아도 괜찮아요. 가운데 + 를 누르면 어느 화면에서든 끼니 하나, 운동 하나를 바로 남길 수 있어요.';

  @override
  String get myWithdrawKeepHardToUse =>
      '어디가 불편했는지 알려주시면 고칩니다. MY > 고객 지원의 1:1 문의로 바로 닿아요.';

  @override
  String get myWithdrawKeepNotifications =>
      '알림은 종류별로 끌 수 있어요. MY > 알림 설정에서 받고 싶은 것만 남겨 보세요.';

  @override
  String get myWithdrawKeepAlternative =>
      '앱을 지워도 기록은 그대로 남습니다. 탈퇴하면 그때 사라지고 되살릴 수 없어요.';

  @override
  String get myWithdrawKeepOther =>
      '무엇이든 알려주시면 반영합니다. MY > 고객 지원의 1:1 문의로 남겨 주세요.';

  @override
  String get myWithdrawKeepDefault =>
      '지금까지 쌓은 식단·운동 기록과 포인트, 사용 전 쿠폰은 탈퇴와 함께 사라지고 되살릴 수 없어요. 예정된 예약도 취소돼요.';

  @override
  String get myWithdrawStay => '계속 사용하기';

  @override
  String get myWithdrawContinue => '탈퇴 계속';

  @override
  String get myCancel => '취소';

  @override
  String get myGymTrainerTitle => '내 헬스장 · 트레이너';

  @override
  String get myConnectionDeleteTitle => '연결 삭제';

  @override
  String get myConnectionDeleteFailed => '연결을 해제하지 못했어요. 다시 시도해 주세요.';

  @override
  String get myDelete => '삭제';

  @override
  String myGymDisconnectWithTrainerConfirm(String gym, String trainer) {
    return '$gym 연결을 삭제하시겠습니까?\n담당 트레이너 $trainer 연결도 함께 해제됩니다.\n데이터 공유 동의도 함께 철회되어 트레이너가 회원님의 새 기록을 더는 볼 수 없습니다. 이미 주고받은 대화와 리포트는 지워지지 않고, 같은 트레이너와 다시 연결하면 다시 볼 수 있습니다.';
  }

  @override
  String myGymDisconnectConfirm(String gym) {
    return '$gym 연결을 삭제하시겠습니까?';
  }

  @override
  String myTrainerDisconnectConfirm(String trainer, String gym) {
    return '담당 트레이너 $trainer 연결을 삭제하시겠습니까?\n$gym 헬스장 연결은 유지됩니다.\n데이터 공유 동의도 함께 철회되어 트레이너가 회원님의 새 기록을 더는 볼 수 없습니다. 이미 주고받은 대화와 리포트는 지워지지 않고, 같은 트레이너와 다시 연결하면 다시 볼 수 있습니다.';
  }

  @override
  String get myGymDetailTooltip => '헬스장 상세 보기';

  @override
  String get myTrainerDetailTooltip => '트레이너 상세 보기';

  @override
  String get myGymDisconnectTooltip => '헬스장 연결 삭제';

  @override
  String get myTrainerDisconnectTooltip => '트레이너 연결 삭제';

  @override
  String get myNoTrainer => '담당 트레이너 없음';

  @override
  String get myNoGymConnected => '아직 등록된 헬스장이 없어요';

  @override
  String get myGymLoadFailed => '헬스장 연결 정보를 불러오지 못했어요.';

  @override
  String get mySave => '저장';

  @override
  String get myProfileSaved => '프로필이 저장되었어요';

  @override
  String get mySaveFailed => '저장에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get myProfileEmailTaken => '이미 사용 중인 이메일이에요';

  @override
  String get myProfilePhoneRequired => '등록된 전화번호는 비울 수 없어요';

  @override
  String get myProfileInvalid => '입력한 내용을 다시 확인해 주세요';

  @override
  String get myFieldName => '이름';

  @override
  String get myFieldEmail => '이메일';

  @override
  String get myFieldPhone => '전화번호';

  @override
  String get myFieldBirth => '생년월일';

  @override
  String get myFieldGender => '성별';

  @override
  String get myFieldHeight => '키 (cm)';

  @override
  String get myFieldWeight => '체중 (kg)';

  @override
  String get myNotifExercise => '운동 리마인더';

  @override
  String get myNotifTrainer => '트레이너 메시지';

  @override
  String get myNotifWeeklyReport => '주간 리포트';

  @override
  String get mySupportFaq => '자주 묻는 질문';

  @override
  String get mySupportInquiry => '1:1 문의';

  @override
  String get myLegalTermsTitle => '이용약관';

  @override
  String get myLegalPrivacyTitle => '개인정보 처리방침';

  @override
  String get myLegalTermsBody =>
      '제1조 (목적)\n이 약관은 On-Care(이하 \"회사\")가 제공하는 건강 관리 서비스(이하 \"서비스\")의 이용과 관련하여 회사와 회원 간의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.\n\n제2조 (약관의 효력 및 변경)\n① 이 약관은 서비스를 이용하는 모든 회원에게 효력이 발생합니다.\n② 회사는 관련 법령을 위반하지 않는 범위에서 이 약관을 변경할 수 있으며, 변경 시 적용일자와 변경 사유를 명시하여 적용일 전에 서비스 내에 공지합니다.\n③ 동의가 필요한 변경은 다시 동의를 받습니다. 회원은 변경된 약관에 동의하지 않으면 이용 계약을 해지할 수 있습니다.\n\n제3조 (회원 가입과 계정)\n① 회원 가입은 만 14세 이상만 할 수 있습니다.\n② 회원은 한 사람이 하나의 계정을 쓰며, 다른 사람의 정보로 가입하거나 계정을 다른 사람에게 넘기거나 빌려줄 수 없습니다.\n③ 비밀번호와 소셜 로그인 연결 등 계정 정보의 관리 책임은 회원에게 있습니다. 다른 사람이 계정을 쓰고 있다는 것을 알게 되면 바로 비밀번호를 바꾸고 회사에 알려야 합니다.\n\n제4조 (서비스의 제공)\n회사는 식단 기록, 운동 기록, 건강 지표 관리, AI 코칭, 담당 트레이너와의 연결·메시지·예약 등 회원의 건강 관리를 돕는 기능을 제공합니다. 서비스의 구체적인 내용은 회사의 정책에 따라 변경될 수 있습니다.\n\n제5조 (포인트)\n① 회원은 식단·운동 기록 등 앱에 안내된 활동으로 포인트를 받습니다. 활동마다 받는 포인트와 하루 한도는 앱의 안내를 따릅니다.\n② 포인트는 서비스 안에서 쿠폰·교환 상품으로 바꾸는 데에만 쓸 수 있습니다. 포인트는 현금 가치가 없어 현금으로 바꾸거나 환불받을 수 없고, 다른 사람에게 넘길 수 없습니다.\n③ 포인트를 받은 기록을 지우면 받은 포인트를 회수합니다. 같은 기록을 되풀이해 올리는 등 정상적이지 않은 방법으로 받은 포인트도 회수할 수 있습니다.\n④ 회사는 적립 기준과 교환 가격을 바꿀 수 있으며, 바꾸기 전에 서비스 안에 알립니다. 이미 교환한 쿠폰과 상품에는 바뀐 기준을 적용하지 않습니다.\n⑤ 탈퇴하면 남은 포인트와 그 내역은 함께 사라지고 되살릴 수 없습니다.\n\n제6조 (쿠폰과 교환 상품)\n① 회원은 포인트로 PT 재등록 할인 쿠폰, 개인 락커 이용 쿠폰 등 앱에 안내된 쿠폰을 교환할 수 있습니다. 쿠폰의 혜택은 회원과 연결된 담당 트레이너 또는 헬스장이 현장에서 제공합니다.\n② 쿠폰은 앱에 표시된 유효기간 안에만 쓸 수 있으며, 포인트로 교환한 쿠폰의 유효기간은 교환한 날부터 30일입니다. 유효기간이 지난 쿠폰은 소멸하고, 교환에 쓴 포인트는 돌려주지 않습니다.\n③ 쿠폰을 쓸 곳인 담당 트레이너 또는 헬스장과의 연결이 끊기면 사용 전 쿠폰은 취소되고, 교환에 쓴 포인트를 돌려줍니다.\n④ 쿠폰은 현장 직원이 확인한 뒤 회원이 자기 휴대폰에서 사용 완료를 눌러 사용합니다. 사용 처리한 쿠폰은 되돌릴 수 없습니다.\n⑤ 쿠폰은 다른 사람에게 넘기거나 현금으로 바꿀 수 없습니다.\n\n제7조 (기간제 아이템과 보호권)\n① 프로필 펫·이모티콘 등 꾸밈 아이템은 앱에 표시된 기간 동안만 쓸 수 있으며, 기간이 끝나면 사라집니다.\n② 연속 기록 보호권은 기록하지 못한 날에도 연속 기록이 끊기지 않게 지켜 주는 데 쓰이며, 쓰는 방법과 보유 한도는 앱의 안내를 따릅니다.\n③ 이 조의 아이템과 보호권도 현금 가치가 없고 다른 사람에게 넘길 수 없으며, 탈퇴하면 함께 사라집니다.\n\n제8조 (예약과 상담 신청)\n① 회원은 담당 트레이너가 열어 둔 시간에 PT를 예약하거나, 트레이너에게 상담을 신청할 수 있습니다. 신청과 취소를 할 수 있는 때와 대기 중인 상담 요청이 만료되는 때는 앱의 안내를 따릅니다.\n② PT 이용 계약과 그 결제·환불은 회원과 트레이너 또는 헬스장 사이의 별도 계약입니다. 회사는 이를 위한 연결·예약 도구를 제공합니다.\n\n제9조 (회원의 의무)\n회원은 본인의 건강 정보를 정확하게 입력하여야 하며, 서비스가 제공하는 정보는 의학적 진단이나 치료를 대체하지 않습니다. 건강상 문제가 있는 경우 반드시 전문 의료기관의 진료를 받으시기 바랍니다.\n\n제10조 (이용 제한)\n회사는 회원이 다음 행위를 하면 미리 알린 뒤 서비스 이용의 일부 또는 전부를 제한하거나 계정을 정지할 수 있습니다. 다른 이용자의 피해를 막아야 하는 등 급한 경우에는 먼저 제한한 뒤 바로 알립니다.\n- 다른 사람의 정보를 도용하거나 계정을 넘기는 행위\n- 정상적이지 않은 방법으로 포인트를 받거나 쿠폰을 쓰는 행위\n- 트레이너나 다른 이용자에게 욕설·괴롭힘 등으로 피해를 주는 행위\n- 서비스의 운영을 방해하는 행위\n\n제11조 (이용 계약의 해지와 그 효과)\n① 회원은 언제든지 MY 탭의 회원 탈퇴로 이용 계약을 해지할 수 있습니다.\n② 탈퇴하면 계정과 함께 프로필, 식단·운동·건강 기록, AI 코치 대화, 담당 트레이너와의 연결과 대화가 지워지고, 남은 포인트와 그 내역, 사용 전 쿠폰, 보호권과 꾸밈 아이템도 함께 사라집니다. 사라진 것은 되살릴 수 없습니다.\n③ 예정된 PT 예약과 대기 중인 상담 요청은 취소되고, 관련 트레이너에게 탈퇴 사실이 안내됩니다.\n④ 트레이너의 일정표에 이미 잡혀 있던 수업 기록처럼 개인정보 처리방침의 파기 절차에서 남는다고 정한 기록은 그 범위에서 남습니다.\n\n제12조 (서비스의 변경과 중단)\n① 회사는 서비스의 내용을 바꾸거나 일부 기능을 끝낼 수 있으며, 회원에게 영향이 있는 변경은 미리 서비스 안에 알립니다.\n② 회사는 설비 점검·교체, 장애, 천재지변 등 부득이한 사유가 있으면 서비스를 일시 중단할 수 있으며, 미리 알릴 수 없었던 경우에는 사후에 알립니다.\n③ 서비스 전체를 끝내는 경우 회사는 미리 알리고, 남은 포인트와 사용 전 쿠폰을 어떻게 처리하는지 함께 안내합니다.\n\n제13조 (책임의 제한)\n회사는 회원이 서비스를 통해 얻은 정보에 기반하여 내린 판단과 그 결과에 대하여 법령이 허용하는 범위 내에서 책임을 부담하지 않습니다.\n\n제14조 (분쟁 해결과 관할)\n① 회사와 회원은 서비스와 관련한 분쟁을 원만하게 해결하기 위해 성실히 협의합니다. 회원은 개인정보 처리방침에 적힌 연락처로 문의나 불만을 보낼 수 있습니다.\n② 협의로 해결되지 않아 소송이 제기되는 경우 민사소송법에 따른 관할 법원을 관할 법원으로 합니다.\n③ 이 약관과 서비스 이용에는 대한민국 법을 적용합니다.\n\n부칙\n이 약관은 2026년 10월 3일부터 시행합니다.\n- 2026년 10월 3일: 회원 가입과 계정, 포인트, 쿠폰과 교환 상품, 기간제 아이템과 보호권, 예약과 상담 신청, 이용 제한, 이용 계약의 해지와 그 효과, 서비스의 변경과 중단, 분쟁 해결과 관할 조항 추가\n- 2026년 10월 1일: 제정';

  @override
  String myLegalPrivacyBody(String contact) {
    return 'On-Care(이하 \"회사\")는 「개인정보 보호법」 등 관련 법령을 준수하며, 회원의 개인정보를 소중히 보호합니다.\n\n1. 수집하는 개인정보 항목\n① 회원가입: 이메일, 비밀번호(암호화하여 저장), 이름. 소셜 로그인(카카오·구글·네이버·애플)으로 가입하면 해당 서비스가 넘겨주는 회원 식별자와 이메일·이름을 받습니다.\n② 프로필과 첫 설정: 전화번호, 생년월일, 성별, 키, 체중, 건강 목표와 식단·운동 목표.\n③ 서비스 이용 중 회원이 남기는 정보: 식단 기록과 음식 사진, 운동 기록, 체중 등 건강 지표, AI 코치와의 대화, 트레이너와 주고받은 메시지와 첨부 사진, 상담·예약 신청 내용.\n④ 자동으로 생성되는 정보: 로그인·비밀번호 변경 등 접속 기록(일시, IP 주소)과, 오류가 났을 때의 오류 내용·기기 종류·운영체제·앱 버전.\n⑤ 위치 정보: 헬스장 찾기에서 현재 위치 사용을 허용한 경우에만 기기의 현재 좌표를 받아 주변 검색에 쓰며, 계정에 저장하지 않습니다.\n\n2. 개인정보의 수집 및 이용 목적\n수집한 개인정보는 회원 식별, 음식 사진 분석과 영양 계산 등 건강 관리 기능 제공, 맞춤형 AI 코칭, 담당 트레이너 연결, 서비스 개선 및 고객 문의 응대의 목적으로만 이용됩니다.\n\n3. 개인정보의 보유 및 이용 기간\n회원의 개인정보는 회원 탈퇴 시까지 보유·이용하며, 탈퇴하면 10항의 절차에 따라 지체 없이 파기합니다. 다만 다음 기록은 정해진 기간 동안 보관한 뒤 파기합니다.\n- 로그인 등 접속 기록: 1년(「통신비밀보호법」상 로그인 기록 보존 의무 3개월 포함)\n- 트레이너의 회원 건강정보 열람 기록, 데이터 공유 동의·철회 기록, 탈퇴 기록: 2년(「개인정보의 안전성 확보조치 기준」에 따른 처리 기록 보관)\n탈퇴할 때 고른 탈퇴 사유는 회원과 연결되지 않는 사유 항목과 시각만 남깁니다.\n\n4. 개인정보의 제3자 제공\n회사는 회원의 동의 없이 개인정보를 외부에 제공하지 않습니다. 담당 트레이너와의 공유는 5항, 업무 처리를 맡기는 위탁은 6항과 7항을 따릅니다. 다만 법령에 특별한 규정이 있는 경우는 예외로 합니다.\n\n5. 담당 트레이너와의 정보 공유 및 동의 철회\n회원이 상담 신청, 담당 요청 수락, 연결 코드 발급 중 하나로 데이터 공유에 동의하면 담당 트레이너는 회원의 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 볼 수 있습니다. 회원은 MY 탭에서 담당 트레이너 또는 헬스장 연결을 삭제하여 언제든지 동의를 철회할 수 있으며, 트레이너가 담당을 해제한 경우에도 동의는 철회된 것으로 봅니다. 회사는 동의한 시각과 철회한 시각을 기록합니다. 철회한 뒤에는 트레이너가 회원의 새 기록을 볼 수 없고, 같은 트레이너와 다시 연결하려면 새로 동의해야 합니다. 다만 철회 전에 트레이너와 주고받은 대화와 전달된 리포트는 삭제되지 않고 남습니다.\n\n6. 개인정보 처리의 위탁\n회사는 서비스 제공을 위해 다음 업무를 외부 업체에 위탁합니다. 수탁자가 바뀌면 이 처리방침을 고쳐 알립니다.\n- Amazon Web Services, Inc.: 서버 운영, 채팅 사진·리포트 PDF 파일 보관\n- Neon: 데이터베이스 운영(계정 정보와 모든 기록 보관)\n- Google LLC: 음식 사진 인식, AI 코치 답변·추천 생성, AI 코치가 회원 기록을 찾아 쓰기 위한 검색 색인 생성(Gemini API)\n- 주식회사 카카오: 헬스장·장소 검색과 지도 표시\n- Functional Software, Inc.(Sentry): 앱·서버 오류 수집과 분석\n\n7. 개인정보의 국외 이전\n회사는 회원과의 계약을 이행하기 위해 다음과 같이 개인정보를 국외에서 처리·보관하도록 위탁하며, 「개인정보 보호법」 제28조의8 제1항 제3호에 따라 이 처리방침으로 알립니다. 이전은 서비스를 이용할 때마다 암호화된 네트워크로 전송하는 방법으로 이루어집니다.\n① Amazon Web Services, Inc. / 싱가포르 / 회원 정보와 기록 전반, 채팅 첨부 사진과 리포트 PDF / 서버 운영과 파일 보관 / 회원 탈퇴 또는 위탁 계약 종료 시까지\n② Neon / 싱가포르 / 계정·프로필·식단·운동·건강 기록과 대화 기록 / 데이터베이스 운영 / 회원 탈퇴 또는 위탁 계약 종료 시까지\n③ Google LLC / 미국 등 Google이 운영하는 데이터센터 소재 국가 / 음식 사진, 분석에 필요한 식단·운동 기록·신체 정보·건강 목표, AI 코치와의 대화 내용 / AI 분석·답변 생성과 검색 색인 생성 / 요청 처리 후 수탁자의 서비스 약관에서 정한 기간\n④ Functional Software, Inc.(Sentry) / 미국 / 오류 내용, 기기 종류·운영체제·앱 버전(이름·이메일·IP 주소·요청 내용은 보내지 않음) / 오류 분석 / 수탁자의 보관 기간\n식단·운동 기록을 저장할 때마다 AI 코치용 검색 색인을 만들기 위해 그 내용이 ③으로 전송됩니다. 국외 이전을 원하지 않으면 탈퇴로 거부할 수 있으나, 이 경우 서비스를 이용할 수 없습니다.\n\n8. 민감정보(건강정보)의 처리\n식단·운동 기록, 신체 정보, 건강 목표, 건강상태·주의사항 등 건강에 관한 정보는 「개인정보 보호법」 제23조에 따라 가입할 때 다른 개인정보와 구분하여 별도로 동의를 받아 처리합니다. 담당 트레이너와의 공유는 5항의 동의가 있을 때만 이루어집니다.\n\n9. 만 14세 미만 아동의 개인정보\n회사는 만 14세 미만 아동의 회원가입을 받지 않으며, 가입할 때 만 14세 이상인지 확인합니다.\n\n10. 개인정보의 파기 절차 및 방법\n① 절차: 회원이 MY 탭에서 탈퇴하면 즉시 계정과 함께 프로필, 식단·운동 기록과 음식 사진, AI 코치 대화와 검색 색인, 알림, 소셜 로그인 연결, 담당 트레이너와의 연결과 대화(첨부 사진·리포트 PDF 파일 포함)를 삭제합니다. 대기 중인 상담 요청과 예약은 취소되고, 관련 트레이너에게 탈퇴 사실이 안내됩니다. 트레이너의 일정표에 이미 잡혀 있던 수업 기록에는 회원 표시 이름과 일시가 트레이너의 업무 기록으로 남습니다. 3항에 따라 보관하는 기록은 기간이 지나면 자동으로 삭제합니다.\n② 방법: 전자적 파일 형태의 정보는 데이터베이스와 파일 저장소에서 삭제하며, 데이터베이스 복구용 백업에 남은 사본은 백업 보관 기간이 지나면 함께 사라집니다. 회사는 개인정보를 종이 문서로 처리하지 않습니다.\n\n11. 개인정보 자동 수집 장치의 설치·운영 및 거부\n회사는 광고·행태 분석을 위한 쿠키나 추적 도구를 쓰지 않습니다. 웹에서는 로그인 상태를 유지하기 위해 브라우저 저장소에 인증 정보를 보관하며, 로그아웃하거나 브라우저 데이터를 지우면 삭제됩니다.\n\n12. 개인정보의 안전성 확보 조치\n회사는 비밀번호를 암호화하여 저장하고, 전송 구간을 암호화하며, 회원 정보에 대한 트레이너의 접근을 담당 관계를 기준으로 제한합니다. 트레이너가 회원의 건강정보를 열람하면 열람한 트레이너, 대상 회원, 정보의 종류와 시각만 기록하며 건강정보의 내용은 담지 않습니다. 오류 보고에서는 이름·이메일·IP 주소와 요청 내용을 지우고 보냅니다.\n\n13. 이용자의 권리와 행사 방법\n회원은 언제든지 자신의 개인정보를 조회·수정하거나 처리 정지 및 삭제를 요청할 수 있습니다. 프로필은 MY 탭에서 직접 고칠 수 있고, 탈퇴와 트레이너 공유 동의 철회도 MY 탭에서 할 수 있습니다. 그 밖의 요청은 14항의 연락처로 보내 주시면 지체 없이 조치합니다.\n\n14. 개인정보 보호책임자\n회사는 개인정보 처리에 관한 업무를 총괄하고 관련 불만 처리와 피해 구제를 위해 개인정보 보호책임자를 지정하고 있습니다.\n- 직책: On-Care 서비스 운영팀 개인정보 보호책임자\n- 연락처: $contact\n\n15. 권익침해 구제 방법\n개인정보 침해에 대한 신고나 상담이 필요하면 다음 기관에 문의할 수 있습니다.\n- 개인정보분쟁조정위원회: 국번없이 1833-6972 (www.kopico.go.kr)\n- 개인정보침해신고센터: 국번없이 118 (privacy.kisa.or.kr)\n- 대검찰청: 국번없이 1301 (www.spo.go.kr)\n- 경찰청: 국번없이 182 (ecrm.police.go.kr)\n\n16. 처리방침의 변경\n이 처리방침을 바꾸면 시행일 전에 앱 안에 알리며, 동의가 필요한 변경은 다시 동의를 받습니다.\n- 2026년 10월 3일: 처리 위탁·국외 이전·민감정보·만 14세 미만·파기 절차·자동 수집 장치·안전성 확보 조치·보호책임자·권익침해 구제 항목 추가\n- 2026년 10월 1일: 제정\n\n시행일: 2026년 10월 3일';
  }

  @override
  String get myLegalTermsEffectiveDate => '시행일 2026. 10. 03.';

  @override
  String get myLegalPrivacyEffectiveDate => '시행일 2026. 10. 03.';

  @override
  String myAppVersion(String version) {
    return 'On-Care · 버전 $version';
  }

  @override
  String get myAppName => 'On-Care';

  @override
  String get coachHeaderPill => 'AI 건강 도우미';

  @override
  String get coachHeaderSubtitle => '오늘의 맞춤 조언을 모아봤어요';

  @override
  String get coachCardDietTag => '식단';

  @override
  String get coachCardDietTitle => '아침 식단 훌륭, 점심 나트륨 주의';

  @override
  String get coachCardDietBody =>
      '아침 식단은 균형 있게 잘 챙겼어요. 다만 점심으로 드신 짬뽕은 나트륨과 당류 부담이 있을 수 있으니, 오늘은 물을 충분히 섭취해 주세요. 이후 식사에서는 채소와 단백질을 함께 챙겨 균형을 맞춰보세요.';

  @override
  String get coachCardExerciseTag => '운동';

  @override
  String get coachCardExerciseTitle => '이번 주 운동 3회 완료';

  @override
  String get coachCardExerciseBody =>
      '이번 주 운동을 세 번 마쳤어요. 꾸준히 이어가고 있는 점이 좋습니다. 어깨 회전근개 스트레칭을 충분히 진행하고, 가벼운 유산소 운동으로 마무리해 주세요. 운동 후에는 무리한 활동보다 충분한 휴식과 수분 섭취로 회복을 도와주세요.';

  @override
  String get coachCardWaterTag => '수분';

  @override
  String get coachSheetErrorTitle => '조언을 불러오지 못했어요';

  @override
  String get coachSheetErrorBody => '연결 상태를 확인하고 다시 시도해 주세요.';

  @override
  String get coachSheetEmptyTitle => '기록이 쌓이면 조언을 드릴게요';

  @override
  String get coachSheetEmptyBody => '오늘 먹은 음식과 운동을 기록해 보세요.';

  @override
  String get coachInviteTitle => '담당 요청이 왔어요';

  @override
  String coachInviteFrom(String name) {
    return '$name 트레이너';
  }

  @override
  String coachInviteGym(String gym) {
    return '$gym 소속';
  }

  @override
  String get coachInviteExplain =>
      '수락하면 내 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 이 트레이너가 볼 수 있어요. 수락하기 전에 공유 동의를 받아요.';

  @override
  String get coachInviteAccept => '수락';

  @override
  String get coachInviteReject => '거절';

  @override
  String coachInviteAccepted(String name) {
    return '$name 트레이너가 담당으로 연결됐어요';
  }

  @override
  String get coachInviteRejected => '요청을 거절했어요';

  @override
  String get coachInviteFailed => '처리하지 못했어요. 다시 시도해 주세요';

  @override
  String get coachImageUnavailable => '사진을 불러오지 못했어요';

  @override
  String get coachChatSubtitle => '담당 트레이너';

  @override
  String get coachChatLoadOlder => '이전 메시지 더 보기';

  @override
  String get coachChatLoadFailed => '대화를 불러오지 못했어요';

  @override
  String get coachChatUnassigned => '담당이 해제되어 더 이상 대화를 보낼 수 없어요';

  @override
  String coachChatEmptyTitle(String trainer) {
    return '$trainer님과 대화를 시작해 보세요';
  }

  @override
  String get coachChatEmptyBody => '오늘 먹은 식단 사진이나 운동하며 궁금한 점을 보내 보세요';

  @override
  String get coachChatSendFailed => '메시지 전송에 실패했어요. 다시 시도해 주세요';

  @override
  String get coachPhotoAttach => '사진 보내기';

  @override
  String get coachPhotoSheetSubtitle => '식사·자세·인바디 사진을 트레이너에게 보내요';

  @override
  String get coachPhotoPickSub => '보관함에서 사진 고르기';

  @override
  String get coachPhotoTakeSub => '카메라로 바로 찍기';

  @override
  String get coachPhotoSending => '보내는 중';

  @override
  String get coachPhotoSendFailed => '사진을 보내지 못했어요';

  @override
  String get coachPhotoRetry => '다시 보내기';

  @override
  String get coachPhotoDiscard => '지우기';

  @override
  String get coachPhotoPermissionDenied => '사진을 보내려면 카메라·사진 접근을 허용해 주세요';

  @override
  String get coachPhotoPermissionPermanentlyDenied =>
      '카메라·사진 접근이 꺼져 있어요. 설정에서 켜면 사진을 보낼 수 있어요';

  @override
  String get coachPhotoReadFailed => '사진을 읽지 못했어요. 다른 사진으로 다시 시도해 주세요';

  @override
  String get a11yMyPhoto => '내가 보낸 사진';

  @override
  String get coachChatPdfOpenFailed => 'PDF를 열지 못했어요. 다시 시도해 주세요';

  @override
  String get coachChatReportRegistered => '리포트가 등록되었어요';

  @override
  String coachChatReportWeek(int sm, int sd, int em, int ed) {
    return '$sm월 $sd일 – $em월 $ed일';
  }

  @override
  String get coachChatReportPreviewPdf => 'PDF 미리보기';

  @override
  String coachReportPdfBullet(String label, String value) {
    return '· $label: $value';
  }

  @override
  String coachReportPdfFileName(String date) {
    return '주간리포트_$date.pdf';
  }

  @override
  String get coachChatInputHint => '트레이너에게 메시지 보내기...';

  @override
  String get coachChatRoutineReceived => '트레이너가 운동을 보냈어요';

  @override
  String get coachChatRoutineReceivedPt => 'PT 프로그램과 개인운동을 받았어요';

  @override
  String get coachChatRoutineReceivedPersonal => '개인운동을 받았어요';

  @override
  String get coachChatRoutineReceivedAfterCancel => '취소된 PT 대신 개인운동을 받았어요';

  @override
  String get coachChatRoutineReceivedProgram => '운동 프로그램을 받았어요';

  @override
  String coachChatRoutineReceivedMore(String names, int count) {
    return '$names 외 $count개';
  }

  @override
  String coachChatDateDivider(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMEEEEd(
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get coachCtaChat => 'AI와 대화하기';

  @override
  String get navAddRecordTitle => '새 기록 추가';

  @override
  String get navAddRecordSubtitle => '식단 또는 운동을 선택해 주세요';

  @override
  String get navDietOptionSub => '사진으로 영양 분석';

  @override
  String get navExerciseOptionSub => '종류와 시간 기록';

  @override
  String get aicHeaderSubtitle => '언제든 물어보세요';

  @override
  String get aicMedicalDisclaimer =>
      'AI 코치는 식단·운동 관리를 돕는 참고용이에요. 진단·처방이 아니니 증상이 있으면 전문의와 상담해 주세요.';

  @override
  String get aicInputHint => 'AI에게 무엇이든 물어보세요';

  @override
  String aicQuotaFreeLeft(int count) {
    return '오늘 무료 대화 $count회 남음';
  }

  @override
  String aicQuotaPaidNext(String cost, int used, int limit) {
    return '다음 대화 $cost · 오늘 구매 $used/$limit';
  }

  @override
  String get aicQuotaExhausted => '오늘 대화를 다 썼어요. 내일 다시 열려요';

  @override
  String get aicQuotaFindTrainer => '트레이너 찾기';

  @override
  String get aicPaidConfirmTitle => '포인트로 대화를 이어갈까요?';

  @override
  String aicPaidConfirmMessage(String cost, int limit, String balance) {
    return '오늘 무료 대화를 다 썼어요. 이 대화를 보내면 $cost가 차감돼요 (오늘 $limit회까지).\n\n현재 포인트 $balance';
  }

  @override
  String get aicPaidConfirmAction => '포인트로 보내기';

  @override
  String aicPaidInsufficient(String shortfall) {
    return '포인트가 $shortfall 모자라요. 식단·운동을 기록하면 포인트가 쌓여요.';
  }

  @override
  String aicPointsSpent(String spent) {
    return '−$spent';
  }

  @override
  String get aicQuickRepliesLabel => '이런 걸 물어보세요';

  @override
  String get aicGeneratingReply => '맞춤 답변 생성 중';

  @override
  String aicInsightDiscomfortPart(String part) {
    return '$part 통증 감지';
  }

  @override
  String get aicBodyPartKnee => '무릎';

  @override
  String get aicBodyPartBack => '허리';

  @override
  String get aicBodyPartAnkle => '발목';

  @override
  String get aicBodyPartShoulder => '어깨';

  @override
  String get aicBodyPartWrist => '손목';

  @override
  String get aicBodyPartNeck => '목';

  @override
  String get aicInsightDiscomfort => '통증 감지';

  @override
  String get aicInsightNegative => '부정적 반응 감지';

  @override
  String get aicInsightDelete => '삭제';

  @override
  String get aicInsightDeleteConfirm => '이 감지를 참고 기록에서 지울까요? 대화에 쓴 말은 그대로 남아요.';

  @override
  String get aicInsightDeleteFailed => '지우지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get aicInsightHistoryTitle => '참고 기록';

  @override
  String get aicInsightHistoryAction => '참고 기록';

  @override
  String aicInsightHistorySubtitle(int days) {
    return '최근 $days일 동안 감지한 통증·부정적 반응이에요. AI가 답할 때 참고해요';
  }

  @override
  String aicInsightHistoryEmpty(int days) {
    return '최근 $days일 동안 감지된 내용이 없어요';
  }

  @override
  String get aicInsightHistoryFailed => '참고 기록을 불러오지 못했어요';

  @override
  String aicRetentionNotice(int days) {
    return 'AI 챗봇 대화는 최근 $days일 동안만 보관돼요';
  }

  @override
  String get aicTrainerConnectedTitle => '담당 트레이너와 대화해 주세요';

  @override
  String aicTrainerConnectedBody(String name) {
    return '$name 트레이너와 연결되어 있어요. 담당 트레이너가 있는 회원은 AI 챗봇 대신 트레이너와 채팅해요';
  }

  @override
  String get aicQuickReply1 => '오늘 저녁 메뉴 추천해줘';

  @override
  String get aicQuickReply2 => '오늘 운동은 얼마나 하면 좋을까?';

  @override
  String get aicQuickReply3 => '오늘 나트륨 얼마나 먹었어?';

  @override
  String get exConsultRequestTitle => '상담 요청';

  @override
  String get exGymConsultRequest => '상담 요청하기';

  @override
  String get exGymConsultPickTrainer => '상담받을 트레이너 선택';

  @override
  String get exGymConsultPickTrainerHint => '상담은 트레이너 한 분에게 전달돼요.';

  @override
  String get exGymConsultNoTrainers => '아직 소속 트레이너가 없어요.';

  @override
  String get exGymTrainersLoadError => '소속 트레이너를 불러오지 못했어요.';

  @override
  String get exTrainerConsultRequest => '트레이너 상담 요청하기';

  @override
  String get exConsultPendingCta => '상담 요청 대기 중';

  @override
  String get exConsultLinkedToOtherTrainer =>
      '담당 트레이너와 연결되어 있어요. 다른 트레이너에게 상담을 요청하려면 담당 연결을 먼저 해제해 주세요.';

  @override
  String get exConsultGoToMyTrainer => '담당 트레이너 보기';

  @override
  String get exViewConsultationRequest => '상담 요청 확인';

  @override
  String get exConsultTarget => '상담 대상';

  @override
  String get exTrainerConsultType => '트레이너 상담';

  @override
  String get exAssignedTrainer => '담당 트레이너';

  @override
  String get exConsultDataSharingNotice =>
      '상담 신청 정보(이름·운동 목표·문의 내용)는 상담을 위해 이 트레이너에게 전달되고, 보낸 뒤에는 상담 요청과 일정에 남아요. 동의하지 않으면 상담 신청만 보낼 수 없고 다른 기능은 그대로 쓸 수 있어요. 식단·운동 기록은 상담 뒤 연결 코드로 등록할 때 따로 동의를 받아요.';

  @override
  String get exConsultDataSharingAgree =>
      '위 내용을 확인했고, 상담 신청 정보를 이 트레이너에게 전달하는 데 동의해요';

  @override
  String get exConsultDataSharingRequired => '전달에 동의해야 상담을 신청할 수 있어요';

  @override
  String get exConsultDataSharingLinked =>
      '담당 트레이너라 식단·운동 기록과 신체 정보를 이미 공유하고 있어요. 다시 동의하지 않아도 돼요.';

  @override
  String get exConsultGoalPrefilled => 'MY 건강 목표를 채워 두었어요. 이번 상담에 맞게 바꿔도 돼요.';

  @override
  String get coachInviteConsentTitle => '담당 연결 전에 확인해 주세요';

  @override
  String coachInviteConsentBody(String name) {
    return '$name 트레이너와 담당으로 연결되면, 코칭·상담·리포트 작성을 위해 회원님의 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 이 트레이너가 볼 수 있어요. 연결을 해제하면 열람 권한도 함께 사라지지만, 그 전에 주고받은 대화와 전달된 리포트는 남아요. 동의하지 않아도 개인 기록 기능은 그대로 쓸 수 있어요.';
  }

  @override
  String get coachInviteConsentAgree => '동의하고 연결';

  @override
  String get exConsultSlotTitle => '예약 가능한 시간';

  @override
  String get exConsultSlotRequired => '예약 가능한 시간을 선택해주세요.';

  @override
  String get exConsultSlotsEmptyTitle => '지금은 예약 가능한 상담 시간이 없어요.';

  @override
  String exConsultSlotsEmptyBody(String gym, String phone) {
    return '$gym $phone 로 문의해 상담 시간을 요청해 주세요.';
  }

  @override
  String exConsultSlotsEmptyNoPhone(String gym) {
    return '$gym 상세에서 위치와 영업시간을 확인해 문의해 주세요.';
  }

  @override
  String get exConsultSlotsError => '예약 가능한 시간을 불러오지 못했어요.';

  @override
  String get exConsultSlotTaken => '방금 다른 회원이 그 시간을 예약했어요. 다른 시간을 선택해주세요.';

  @override
  String exConsultTooManyPending(int count) {
    return '답을 기다리는 상담 요청이 이미 $count건 있어요. 답을 받거나 요청을 취소한 뒤 다시 신청해 주세요.';
  }

  @override
  String exConsultRateLimitedHours(int hours) {
    return '상담 신청이 너무 잦아요. $hours시간 뒤에 다시 신청해 주세요.';
  }

  @override
  String exConsultRateLimitedMinutes(int minutes) {
    return '상담 신청이 너무 잦아요. $minutes분 뒤에 다시 신청해 주세요.';
  }

  @override
  String get exConsultRateLimited => '상담 신청이 너무 잦아요. 잠시 후 다시 신청해 주세요.';

  @override
  String get exConsultTooManyPendingNoCount =>
      '답을 기다리는 상담 요청이 너무 많아요. 답을 받거나 요청을 취소한 뒤 다시 신청해 주세요.';

  @override
  String get exGymCall => '전화 걸기';

  @override
  String get exGymCallFailed => '전화 앱을 열 수 없어요.';

  @override
  String get exGymDetail => '헬스장 상세 보기';

  @override
  String get exConsultChosenSlot => '신청한 시간';

  @override
  String get exConsultConfirmedAt => '확정 일시';

  @override
  String get exConsultExpired => '만료됨';

  @override
  String get exConsultExpiredBody =>
      '트레이너가 시간 안에 확인하지 않았어요. 다른 시간으로 다시 신청해 보세요.';

  @override
  String get exConsultCancelledByTrainerBody =>
      '트레이너가 상담 일정을 취소했어요. 다른 시간으로 다시 신청해 보세요.';

  @override
  String get exExerciseGoal => '운동 목표';

  @override
  String get exGoalHealth => '건강 관리';

  @override
  String get exOptionOther => '기타';

  @override
  String get exOtherGoalHint => '구체적인 운동 목표는 문의 내용에 작성해주세요.';

  @override
  String get exPreferredDate => '희망 날짜';

  @override
  String get exTimeFlexible => '시간 협의';

  @override
  String get exConsultMessage => '문의 내용';

  @override
  String get exConsultMessageHint => '운동 경험이나 상담 시 참고할 내용을 자유롭게 작성해주세요.';

  @override
  String get exSendConsultRequest => '상담 요청 보내기';

  @override
  String get exGoalRequired => '운동 목표를 선택해주세요.';

  @override
  String get exOtherGoalDetailRequired => '구체적인 운동 목표를 문의 내용에 입력해주세요.';

  @override
  String get exConsultTargetNotFound => '상담 대상 정보를 찾을 수 없어요.';

  @override
  String get exConsultPendingExists => '이미 확인 대기 중인 상담 요청이 있어요.';

  @override
  String get exConsultReceived => '상담 요청이 접수되었어요';

  @override
  String get exConsultCompletionInfo => '상대방이 요청을 확인하면 안내해드릴게요.';

  @override
  String get exConsultStatus => '현재 상태';

  @override
  String get exConsultPendingStatus => '요청 대기';

  @override
  String get exConsultAcceptedStatus => '요청 수락';

  @override
  String get exConsultRejectedStatus => '요청 거절';

  @override
  String get exReturnExercise => '운동 탭으로 돌아가기';

  @override
  String get exConsultHistoryTitle => '내 상담 요청';

  @override
  String get exConsultHistoryEmpty => '아직 보낸 상담 요청이 없어요.';

  @override
  String get exConsultHistoryInProgress => '진행 중';

  @override
  String get exConsultRejectedReasonLabel => '거절 사유';

  @override
  String get exConsultRejectedNoReason =>
      '사유를 남기지 않았어요. 다른 트레이너에게 상담을 요청해 보세요.';

  @override
  String get exConsultAcceptedGuide =>
      '상담이 확정됐어요. 등록하기로 하면 상담 때 MY 탭의 연결 코드로 트레이너와 연결할 수 있어요.';

  @override
  String get exMyReservations => '내 예약';

  @override
  String get exCancelReservation => '예약 취소';

  @override
  String get exCancelKeep => '유지';

  @override
  String get exCancelConfirmTitle => '예약을 취소할까요?';

  @override
  String get exCancelFailed => '예약을 취소하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get exReservationPast => '지난 예약';

  @override
  String exReservationPastMore(int count) {
    return '지난 예약 $count건 더 보기';
  }

  @override
  String get exReservationPastLess => '지난 예약 접기';

  @override
  String exCancelConfirmBody(String when) {
    return '$when 예약이 취소되고 그 자리가 다시 열려요.';
  }

  @override
  String exCancelDone(String when) {
    return '$when 예약을 취소했어요';
  }

  @override
  String get mySupportOpenFailed => '링크를 열지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get mySupportExternalHint => '카카오톡 채널로 연결돼요';

  @override
  String get authRestoring => '로그인 정보를 불러오는 중이에요';

  @override
  String get authRestoreFailed => '연결이 불안정해 로그인 정보를 불러오지 못했어요.';

  @override
  String get authRestoreRetry => '다시 시도';

  @override
  String get authRestoreSignIn => '로그인 화면으로';

  @override
  String get authTagline => '기록하면 코칭이 돌아오는 식단·운동 관리';

  @override
  String get authEmailHint => '이메일';

  @override
  String get authPasswordHint => '비밀번호';

  @override
  String get authSignInAction => '로그인';

  @override
  String get authNoAccountQuestion => '계정이 없으신가요?';

  @override
  String get authSignUpAction => '회원가입';

  @override
  String get authDemoAction => '로그인 없이 데모 둘러보기';

  @override
  String get authSocialDivider => 'SNS 계정으로 로그인';

  @override
  String get authKakaoAction => '카카오로 시작하기';

  @override
  String get authGoogleAction => '구글로 시작하기';

  @override
  String get authEmailEmpty => '이메일을 입력해 주세요';

  @override
  String get authEmailInvalid => '이메일 형식이 올바르지 않아요';

  @override
  String get authEmailTooLong => '이메일은 255자까지 입력할 수 있어요';

  @override
  String get authPasswordEmpty => '비밀번호를 입력해 주세요';

  @override
  String get authSignInFailed => '로그인에 실패했어요. 이메일·비밀번호를 확인해 주세요';

  @override
  String get authSignInNetworkFailed => '인터넷 연결을 확인하고 다시 시도해 주세요';

  @override
  String get authSignInUnavailable => '지금은 로그인할 수 없어요. 잠시 후 다시 시도해 주세요';

  @override
  String get authSessionExpired => '로그인이 만료되었어요. 다시 로그인해 주세요';

  @override
  String get authSocialSignInFailed => '소셜 로그인에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get authSocialComingSoon => '소셜 로그인은 준비 중이에요. 이메일로 로그인해 주세요';

  @override
  String get signUpTitle => '회원가입';

  @override
  String get signUpSubtitle => 'On-Care 계정을 만들어 건강 관리를 시작하세요';

  @override
  String get signUpNameHint => '이름';

  @override
  String get signUpNameEmpty => '이름을 입력해 주세요';

  @override
  String get signUpNameTooLong => '이름은 100자까지 입력할 수 있어요';

  @override
  String get signUpPhoneHint => '010-0000-0000';

  @override
  String get signUpPhoneHelper => '트레이너가 회원님을 확인할 때 쓰는 연락처예요';

  @override
  String get signUpPasswordHint => '비밀번호 (영문·숫자 포함 8자 이상)';

  @override
  String get signUpPasswordConfirmHint => '비밀번호 확인';

  @override
  String get signUpAction => '가입하고 시작하기';

  @override
  String get signUpHaveAccountQuestion => '이미 계정이 있으신가요?';

  @override
  String get signUpPasswordWeak => '영문과 숫자를 포함해 8자 이상 입력해 주세요';

  @override
  String get signUpPasswordTooLong => '비밀번호는 64자까지 입력할 수 있어요 (한글·이모지는 더 짧게)';

  @override
  String get signUpPasswordMismatch => '비밀번호가 일치하지 않아요';

  @override
  String get signUpPhoneFormatInvalid => '전화번호를 010-0000-0000 형식으로 입력해 주세요';

  @override
  String get myFieldBirthInvalid => '생년월일을 1996-03-21 형식으로 입력해 주세요';

  @override
  String get trainerSyncEntryLabel => '트레이너와 데이터 동기화';

  @override
  String get trainerSyncEntryHint => '6자리 코드로 담당 트레이너와 연결해요';

  @override
  String get trainerSyncTitle => '트레이너와 데이터 동기화';

  @override
  String get trainerSyncConsent =>
      '이 코드를 입력한 트레이너가 담당이 되면, 코칭·상담·리포트 작성을 위해 회원님의 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 볼 수 있어요. 연결을 해제하면 열람 권한도 함께 사라지지만, 그 전에 주고받은 대화와 전달된 리포트는 남아요. 동의하지 않아도 개인 기록 기능은 그대로 쓸 수 있어요.';

  @override
  String get trainerShareDetailMore => '자세히 보기';

  @override
  String get trainerShareDetailLess => '접기';

  @override
  String get trainerShareRecipientLabel => '받는 사람';

  @override
  String get trainerShareRecipient => '담당으로 연결된 트레이너';

  @override
  String get trainerShareItemsLabel => '공유 항목';

  @override
  String get trainerShareItems => '식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항';

  @override
  String get trainerSharePurposeLabel => '이용 목적';

  @override
  String get trainerSharePurpose => '코칭·상담·리포트 작성';

  @override
  String get trainerSharePeriodLabel => '이용 기간';

  @override
  String get trainerSharePeriod =>
      '연결을 해제해 동의를 철회할 때까지예요. MY 탭에서 담당 트레이너 연결을 삭제하면 철회되고, 그 뒤로 트레이너는 새 기록을 볼 수 없어요. 다만 철회 전에 주고받은 대화와 전달된 리포트는 지워지지 않고 남아요.';

  @override
  String get trainerShareRefuseLabel => '거부할 권리';

  @override
  String get trainerShareRefuse =>
      '동의하지 않을 수 있어요. 동의하지 않아도 앱의 개인 기록 기능은 그대로 쓸 수 있고, 트레이너 연결만 되지 않아요.';

  @override
  String get trainerSyncAgree => '동의하고 코드 받기';

  @override
  String get trainerSyncHint => '트레이너에게 이 6자리를 불러 주세요.';

  @override
  String trainerSyncCountdown(String remaining) {
    return '$remaining 뒤에 만료돼요';
  }

  @override
  String get trainerSyncExpired => '코드가 만료됐어요.';

  @override
  String get trainerSyncFailed => '코드를 받지 못했어요.';

  @override
  String get trainerSyncRetry => '새 코드 받기';

  @override
  String get signUpCreatedSignInNeeded => '계정이 만들어졌어요. 로그인해 주세요';

  @override
  String get signUpEmailTaken => '이미 가입된 이메일이에요. 로그인해 주세요.';

  @override
  String get signUpFailed => '회원가입에 실패했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get consentAll => '전체 동의';

  @override
  String get consentRequiredTag => '[필수]';

  @override
  String get consentOptionalTag => '[선택]';

  @override
  String get consentView => '보기';

  @override
  String get consentTerms => '이용약관 동의';

  @override
  String get consentPrivacy => '개인정보 수집·이용 동의';

  @override
  String get consentHealth => '건강정보(민감정보) 처리 동의';

  @override
  String get consentHealthDetail =>
      '식단·운동 기록, 체중 같은 신체 정보, 건강 목표와 건강상태·주의사항이 여기에 해당해요. 다른 개인정보와 따로 동의를 받아요.';

  @override
  String get consentAge14 => '만 14세 이상이에요';

  @override
  String get consentAge14Detail => '만 14세 미만은 가입할 수 없어요.';

  @override
  String get consentRequiredHint => '필수 항목에 모두 동의해야 다음으로 넘어갈 수 있어요.';

  @override
  String get consentPageTitle => '서비스 이용 동의';

  @override
  String get consentPageSubtitle => '계속 이용하려면 아래 항목을 확인하고 동의해 주세요.';

  @override
  String get consentPageAction => '동의하고 계속하기';

  @override
  String get consentPageFailed => '동의를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get onboardSkip => '나중에 하기';

  @override
  String get onboardPrevious => '이전';

  @override
  String get onboardNext => '다음';

  @override
  String get onboardDone => '완료';

  @override
  String get onboardSaveFailed => '저장에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get onboardBasicTitle => '기본 정보';

  @override
  String get onboardBasicSubtitle => '맞춤 건강 관리를 위해 기본 정보를 알려주세요.';

  @override
  String get onboardHeightHint => '키 (cm)';

  @override
  String get onboardWeightHint => '체중 (kg)';

  @override
  String get onboardHealthTitle => '건강 목표';

  @override
  String get onboardHealthSubtitle => '건강 관리에서 더 집중하고 싶은 항목을 선택해 주세요. (최대 2개)';

  @override
  String get onboardOptionalTag => '(선택)';

  @override
  String guideBadgeWithStep(int current, int total) {
    return '앱 사용 가이드 $current/$total';
  }

  @override
  String get guideSampleBadge => '예시 화면';

  @override
  String get guideSkip => '건너뛰기';

  @override
  String get guidePrev => '이전';

  @override
  String get guideNext => '다음';

  @override
  String get guideDone => '완료';

  @override
  String get guideHomeAdviceTitle => '오늘의 AI 통합 조언';

  @override
  String get guideHomeAdviceBody => '식단과 운동을 함께 읽고, 오늘 무엇을 하면 좋을지 짚어 줘요';

  @override
  String get guideQuickAddTitle => '빠른 기록';

  @override
  String get guideQuickAddBody => '가운데 + 로 식단과 운동을 어느 화면에서든 바로 추가해요';

  @override
  String get guideDietNutritionTitle => '영양 요약';

  @override
  String get guideDietNutritionBody =>
      '오늘 먹은 것의 칼로리와 탄단지, 나트륨·당류가 목표까지 얼마나 남았는지 봐요';

  @override
  String get guideExerciseStatusTitle => '운동 현황';

  @override
  String get guideExerciseStatusBody => '오늘과 이번 주에 얼마나 움직였는지, 목표까지 얼마나 남았는지 봐요';

  @override
  String get guideGymTitle => '내 헬스장과 트레이너';

  @override
  String get guideGymBody => '연결한 헬스장과 담당 트레이너예요. 트레이너가 짠 운동과 피드백이 앱으로 와요';

  @override
  String get guideMySettingsTitle => '설정';

  @override
  String get guideMySettingsBody =>
      '프로필과 건강 목표, 알림을 여기서 바꿔요. 이 안내도 여기서 다시 볼 수 있어요';

  @override
  String get guidePointsTitle => '포인트';

  @override
  String guidePointsBody(int diet, int exercise, int routine) {
    return '기록할 때마다 포인트가 쌓여요.\n식단 기록 +${diet}P, 운동 추가 +${exercise}P, 추천 운동 완료 +${routine}P\n모은 포인트는 MY › 포인트 사용처에서 써요';
  }

  @override
  String get guideSampleFoodScrambledEggs => '스크램블에그';

  @override
  String get guideSampleFoodWholeWheatToast => '통밀 토스트';

  @override
  String get guideSampleFoodChickenSalad => '닭가슴살 샐러드';

  @override
  String get guideSampleFoodBrownRice => '현미밥';

  @override
  String get guideSampleFoodGrilledSalmon => '연어구이';

  @override
  String get guideSampleFoodRoastedVegetables => '구운 채소';

  @override
  String get onboardRequiredTag => '(필수)';

  @override
  String get onboardBirthRequired => '생년월일을 골라 주세요';

  @override
  String get onboardGenderRequired => '성별을 골라 주세요';

  @override
  String get onboardHeightRequired => '키를 입력해 주세요';

  @override
  String onboardHeightRange(int min, int max) {
    return '키는 $min~${max}cm 사이로 입력해 주세요';
  }

  @override
  String get onboardWeightRequired => '체중을 입력해 주세요';

  @override
  String onboardWeightRange(int min, int max) {
    return '체중은 $min~${max}kg 사이로 입력해 주세요';
  }

  @override
  String get onboardSkipStep => '이 단계 건너뛰기';

  @override
  String get onboardBirthLabel => '생년월일';

  @override
  String get onboardBirthYearHint => '년';

  @override
  String get onboardBirthMonthHint => '월';

  @override
  String get onboardBirthDayHint => '일';

  @override
  String onboardBirthYearValue(int year) {
    return '$year년';
  }

  @override
  String onboardBirthMonthValue(int month) {
    return '$month월';
  }

  @override
  String onboardBirthDayValue(int day) {
    return '$day일';
  }

  @override
  String get onboardGenderLabel => '성별';

  @override
  String onboardAgeSummary(int age) {
    return '만 $age세';
  }

  @override
  String onboardBmiSummary(String bmi, String category) {
    return 'BMI $bmi · $category';
  }

  @override
  String get onboardBmiUnderweight => '저체중';

  @override
  String get onboardBmiNormal => '정상';

  @override
  String get onboardBmiPreObese => '비만 전단계';

  @override
  String get onboardBmiObese1 => '1단계 비만';

  @override
  String get onboardBmiObese2 => '2단계 비만';

  @override
  String get onboardBmiObese3 => '3단계 비만';

  @override
  String get onboardBmiSourceNote => '기준: 대한비만학회 비만 진료지침(아시아·태평양 기준)';

  @override
  String get onboardDietTitle => '식단 목표';

  @override
  String get onboardDietSubtitle => '권장값을 미리 채워 뒀어요. 원하는 값으로 바꿔도 괜찮아요.';

  @override
  String get onboardExerciseTitle => '운동 목표';

  @override
  String get onboardExerciseSubtitle =>
      '세계보건기구 권고를 기준으로 채워 뒀어요. 원하는 값으로 바꿔도 괜찮아요.';

  @override
  String get onboardRecommendedPersonal => '나이·성별·키·체중으로 계산한 권장값이에요';

  @override
  String get onboardRecommendedFallback =>
      '기본 권장값이에요. 1단계에서 생년월일·성별·키·체중을 채우면 더 정확해져요';

  @override
  String get onboardResetToRecommended => '권장값으로 되돌리기';

  @override
  String get onboardDietSourceNote =>
      '출처: 2020 한국인 영양소 섭취기준(에너지필요추정량·에너지적정비율) · WHO 나트륨·자유당 섭취 권고';

  @override
  String get onboardExerciseSourceNote =>
      '출처: WHO 신체활동 지침(2020) — 주 150분 중강도 유산소, 주 2회 이상 근력';

  @override
  String get onboardFocusAdjusted => '고른 건강 목표를 반영한 값이에요';

  @override
  String get onboardFocusSourceNote =>
      '목표 반영 기준: 감량 하루 500kcal(대한비만학회 진료지침) · 근력 단백질 체중 1kg당 1.6g(국제스포츠영양학회) · 당류 총열량 5%(WHO) · 유산소 주 150~300분(WHO)';

  @override
  String get onboardGenderMale => '남성';

  @override
  String get onboardGenderFemale => '여성';

  @override
  String get onboardGenderOther => '기타';

  @override
  String get aiCoachWelcome =>
      '안녕하세요, AI 건강 코치 온이예요 🙂\n식단·운동 기록을 보고 도와드릴게요. 무엇이든 편하게 물어보세요.';

  @override
  String get aiCoachFailure => '앗, 잠시 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get aicResend => '다시 보내기';

  @override
  String get aicSendFailedMine => '보내지 못했어요 · 길게 누르면 고쳐 쓸 수 있어요';

  @override
  String get actionCancel => '취소';

  @override
  String get actionDelete => '삭제';

  @override
  String get actionEdit => '수정';

  @override
  String get actionConfirm => '확인';

  @override
  String get coachCardSleepTag => '수면';

  @override
  String get myHealthGoalsTitle => '건강 목표';

  @override
  String get myFirstRunPromptTitle => '기본 정보를 입력하면 맞춤 목표를 계산해요';

  @override
  String get myFirstRunPromptBody =>
      '첫 설정을 건너뛰었어요. 생년월일·키·체중을 넣으면 식단·운동 목표를 몸에 맞게 추천해요.';

  @override
  String get myFirstRunPromptAction => '기본 정보 입력';

  @override
  String get myGoalsFocusSection => '주로 관리하고 싶은 항목';

  @override
  String get myGoalsFocusHint => '건강 관리에서 더 집중하고 싶은 항목을 골라 주세요. (최대 2개)';

  @override
  String myGoalsFocusLastChanged(String who, String date) {
    return '마지막 변경: $who · $date';
  }

  @override
  String get myGoalsFocusChangedByTrainer => '트레이너';

  @override
  String get myGoalsFocusChangedByMe => '나';

  @override
  String get healthNotesLabel => '건강상태·주의사항';

  @override
  String get healthNotesHint => '예) 왼쪽 무릎 수술 이력, 허리 디스크';

  @override
  String get healthNotesHelper => '추천할 때 참고해요';

  @override
  String get healthFocusWeightLoss => '체중 감량';

  @override
  String get healthFocusStrength => '근력 향상';

  @override
  String get healthFocusFitness => '체력 강화';

  @override
  String get healthFocusPosture => '자세 교정';

  @override
  String get healthFocusRehab => '재활';

  @override
  String get healthFocusEating => '식습관 개선';

  @override
  String get healthFocusExerciseHabit => '운동 습관';

  @override
  String get healthFocusBloodPressure => '혈압 관리';

  @override
  String get myGoalsDietSection => '식단 목표';

  @override
  String get myGoalsExerciseSection => '운동 수치 목표';

  @override
  String get myGoalBurnDaily => '일일 소모 칼로리 (kcal)';

  @override
  String get myGoalCardioWeekly => '주간 유산소 (분)';

  @override
  String get myGoalStrengthWeekly => '주간 근력 (세트)';

  @override
  String get myGoalFlexibilityWeekly => '주간 스트레칭 (분)';

  @override
  String myGoalExerciseSuggestionNote(
    int burn,
    int cardio,
    int strength,
    int flexibility,
  ) {
    return '권장: 하루 ${burn}kcal · 주 유산소 $cardio분 · 근력 $strength세트 · 스트레칭 $flexibility분';
  }

  @override
  String get myGoalExerciseApplySuggestion => '권장 비율로 채우기';

  @override
  String get myGoalCalories => '일일 칼로리 제한 (kcal)';

  @override
  String get myGoalSodium => '일일 나트륨 제한 (mg)';

  @override
  String get myGoalSugar => '일일 당류 제한 (g)';

  @override
  String get myGoalCarbs => '일일 탄수화물 제한 (g)';

  @override
  String get myGoalProtein => '일일 단백질 제한 (g)';

  @override
  String get myGoalFat => '일일 지방 제한 (g)';

  @override
  String get myGoalCaloriesFromMacros => '탄·단·지 목표로 계산한 값이에요';

  @override
  String myGoalMacroSuggestionNote(
    int kcal,
    int carbs,
    int protein,
    int fat,
    int sugar,
  ) {
    return '${kcal}kcal 기준 권장 배분: 탄수화물 ${carbs}g · 단백질 ${protein}g · 지방 ${fat}g · 당류 ${sugar}g';
  }

  @override
  String get myGoalMacroApplySuggestion => '권장 비율로 채우기';

  @override
  String get myGoalUnsetHint => '흐린 값은 목표를 세우기 전의 기본 기준이에요';

  @override
  String get myGoalsSaved => '건강 목표가 저장되었어요';

  @override
  String myGoalRange(int min, int max) {
    return '$min~$max 사이로 입력해 주세요';
  }

  @override
  String get mySettingsLoadFailed => '설정을 불러오지 못했어요';

  @override
  String get mySettingsLoadFailedBody => '지금 저장하면 기존 설정이 지워질 수 있어 편집을 잠갔어요.';

  @override
  String get myNotificationSaveFailed => '알림 설정을 저장하지 못했어요';

  @override
  String get myNotifLoadFailed => '알림 설정을 불러오지 못했어요';

  @override
  String get myNotifLoadFailedBody => '지금 보이는 값은 기본값이라 저장된 설정과 다를 수 있어요';

  @override
  String get myPointsGuideTitle => '포인트 적립 안내';

  @override
  String get myPointsDietAdd => '식단 추가';

  @override
  String get myPointsRoutineComplete => '추천·배정 운동 완료';

  @override
  String get myPointsExerciseAdd => '운동 직접 추가';

  @override
  String myPointsRuleWithDailyCap(String action, int count) {
    return '$action (하루 $count회)';
  }

  @override
  String get coachAssignedTrainer => '담당 트레이너';

  @override
  String get coachRoutineTitle => '추천 개인운동';

  @override
  String get coachRoutineAiTitle => 'AI 추천 개인운동';

  @override
  String get coachRoutinePastEditHint =>
      '빠뜨린 체크를 지금 할 수 있어요. 트레이너에게는 나중에 체크한 것으로 보여요.';

  @override
  String get coachRoutinePastEditDone => '완료';

  @override
  String get coachRoutineLogged => '운동 기록에 반영했어요';

  @override
  String get coachRoutineGone => '이 프로그램은 더 이상 없어요. 목록을 새로 불러와 주세요';

  @override
  String get coachRoutineNetworkError => '네트워크 연결을 확인하고 다시 시도해 주세요';

  @override
  String get coachRoutineLogFailed => '완료 기록에 실패했어요.';

  @override
  String get coachRoutineDone => '수행 완료';

  @override
  String get coachRoutineUndo => '완료 취소';

  @override
  String coachRoutineUndoConfirm(String name) {
    return '\'$name\' 완료를 취소할까요? 운동 기록에서도 빠져요.';
  }

  @override
  String get coachRoutineUndone => '완료를 취소했어요';

  @override
  String get coachRoutineUndoFailed => '완료 취소에 실패했어요.';

  @override
  String get coachRoutineCancel => '이 개인 운동 삭제';

  @override
  String coachRoutineCancelConfirm(String name) {
    return '\'$name\'을(를) 목록에서 지울까요? 이미 수행한 기록은 그대로 남아요.';
  }

  @override
  String get coachCardRoutineUndoTitle => '완료를 취소할까요?';

  @override
  String get coachCardRoutineCancelTitle => '개인 운동을 삭제할까요?';

  @override
  String get coachRoutineKeep => '유지';

  @override
  String get coachRoutineCancelled => '개인 운동을 삭제했어요';

  @override
  String get coachRoutineCancelFailed => '개인 운동을 삭제하지 못했어요';

  @override
  String get coachRoutineCompleteTitle => '개인운동 수행 완료';

  @override
  String get coachRoutineIntensity => '수행 강도';

  @override
  String coachRoutinePlannedIntensity(String level) {
    return '권장 $level';
  }

  @override
  String get coachRoutineSubmit => '완료';

  @override
  String get coachChatWithTrainer => '트레이너와 채팅';

  @override
  String get coachTrainerLoading => '담당 트레이너를 불러오는 중이에요';

  @override
  String get coachTrainerNone => '담당 트레이너가 아직 없어요. 운동 탭에서 헬스장·트레이너를 연결해 보세요';

  @override
  String get coachTrainerLoadFailed => '담당 트레이너 정보를 불러오지 못했어요';

  @override
  String get coachTrainerRetrying => '담당 트레이너 정보를 불러오지 못해 다시 불러오고 있어요';

  @override
  String get alertCategoryReminder => '리마인더';

  @override
  String get alertCategoryCoachChat => '트레이너 메시지';

  @override
  String get alertCategoryCoachReport => '주간 리포트';

  @override
  String get alertCategoryRoutine => '운동 루틴';

  @override
  String get alertCategorySchedule => 'PT 일정';

  @override
  String get alertCategoryPtDone => 'PT 기록';

  @override
  String get alertCategoryTrainer => '담당 트레이너';

  @override
  String get alertCategoryConsultation => '상담 요청';

  @override
  String get alertCategoryHealthGoals => '건강 목표';

  @override
  String get alertCategoryBenefits => '혜택';

  @override
  String get alertCategoryChallenge => '챌린지';

  @override
  String get alertCategoryAchievement => '달성';

  @override
  String get alertCategorySystem => '시스템';

  @override
  String get alertMarkAllRead => '모두 읽음';

  @override
  String get alertEmpty => '알림이 없습니다';

  @override
  String get alertLoadFailed => '최신 알림을 불러오지 못했어요';

  @override
  String get alertMarkAllReadFailed => '모두 읽음 처리에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get alertCoachChatFailed =>
      '트레이너 정보를 불러오지 못해 대화를 열 수 없어요. 잠시 후 다시 시도해 주세요';

  @override
  String get alertCoachChatNoTrainer => '담당 트레이너가 없어 대화를 열 수 없어요';

  @override
  String get alertTimeJustNow => '방금';

  @override
  String alertTimeMinutesAgo(int minutes) {
    return '$minutes분 전';
  }

  @override
  String alertTimeHoursAgo(int hours) {
    return '$hours시간 전';
  }

  @override
  String get alertTimeYesterday => '어제';

  @override
  String alertTimeDaysAgo(int days) {
    return '$days일 전';
  }

  @override
  String get demoAlertRoutineTitle => '새 운동 루틴이 도착했어요';

  @override
  String demoAlertRoutineBody(String trainerName) {
    return '$trainerName 트레이너님이 무릎 상태에 맞춰 걷기 루틴으로 조정해 보냈어요.';
  }

  @override
  String get demoAlertReportTitle => '이번 주 리포트가 등록됐어요';

  @override
  String demoAlertReportBody(String trainerName) {
    return '$trainerName 트레이너님이 이번 주 리포트를 등록했어요.';
  }

  @override
  String get demoAlertPtDoneTitle => 'PT 수업 완료';

  @override
  String demoAlertPtDoneBody(String trainerName) {
    return '오늘 18:00 $trainerName 트레이너와 12회차 PT를 마쳤어요!';
  }

  @override
  String get demoAlertTrainerFeedbackTitle => '트레이너 피드백 도착';

  @override
  String get demoAlertTrainerFeedbackBody => '마무리로 어깨 회전근개 스트레칭을 꼭 해주세요.';

  @override
  String get demoAlertWeeklyGoalTitle => '이번 주 운동 목표까지 조금 남았어요';

  @override
  String get demoAlertWeeklyGoalBody => '저강도 유산소(걷기) 30분부터 채워 봐요.';

  @override
  String get demoAlertMealStreakTitle => '식단 기록을 꾸준히 이어가고 있어요';

  @override
  String get demoAlertMealStreakBody => '보름 넘게 하루도 빠짐없이 식단을 기록하고 있어요.';

  @override
  String get demoAlertMaintenanceTitle => '서비스 점검 안내';

  @override
  String get demoAlertMaintenanceBody => '내일 02:00~03:00 점검 예정입니다.';

  @override
  String get exPtFeedbackTitle => '오늘의 피드백';

  @override
  String exNextPtSchedule(String when) {
    return '다음 PT · $when';
  }

  @override
  String get exNextPtNone => '다음 PT 일정이 아직 없어요';

  @override
  String exDatedTitle(int month, int day, String title) {
    return '$month월 $day일 $title';
  }

  @override
  String a11yChartSummary(String title, String detail) {
    return '$title. $detail';
  }

  @override
  String a11yChartEmpty(String title) {
    return '$title. 기록이 없어요';
  }

  @override
  String a11yChartPoint(String day, String value) {
    return '$day $value';
  }

  @override
  String get a11yShowPassword => '비밀번호 표시';

  @override
  String get a11yHidePassword => '비밀번호 숨기기';

  @override
  String get a11yOpenCoaching => '코칭 조언 열기';

  @override
  String get a11ySendMessage => '메시지 보내기';

  @override
  String get a11yClearSearch => '검색어 지우기';

  @override
  String get a11yRemoveFood => '음식 지우기';

  @override
  String get a11yPrevWeek => '지난 주';

  @override
  String get a11yNextWeek => '다음 주';

  @override
  String get exConsultHistoryCancelTitle => '상담 요청을 취소할까요?';

  @override
  String get exConsultHistoryCancelAction => '요청 취소';

  @override
  String get exConsultCancelFailed => '상담 요청을 취소하지 못했어요. 다시 시도해 주세요.';

  @override
  String get exConsultCancelStale => '이미 처리된 요청이에요. 최신 상태로 바꿨어요.';

  @override
  String get exConsultHistoryLoadError => '상담 요청을 불러오지 못했어요.';

  @override
  String get exConsultHistoryCancelBody => '취소한 요청은 다시 되돌릴 수 없어요.';

  @override
  String pointsRewardBadge(int points) {
    return '+${points}P';
  }

  @override
  String get gymLocationDenied => '위치 사용을 허용하면 주변 헬스장을 찾을 수 있어요.';

  @override
  String get gymLocationBrowserBlocked =>
      '브라우저 사이트 설정에서 위치 사용을 허용한 뒤 다시 눌러 주세요.';

  @override
  String get gymLocationBlocked => '앱 설정에서 위치 사용을 허용한 뒤 다시 눌러 주세요.';

  @override
  String get gymLocationDisabled => '기기의 위치 서비스를 켠 뒤 다시 눌러 주세요.';

  @override
  String get gymLocationUnavailable => '현재 위치를 가져오지 못했어요. 다시 시도해 주세요.';

  @override
  String get gymLocateAction => '현재 위치로 찾기';

  @override
  String get gymLocationSettings => '설정';

  @override
  String get gymDefaultAreaTitle => '신촌 주변 결과예요';

  @override
  String get gymDefaultAreaMessage => '현재 위치를 허용하면 내 주변으로 바뀌어요.';

  @override
  String get gymUseLocation => '위치 사용';

  @override
  String get gymDistanceSortNeedsLocation => '거리순은 현재 위치를 쓸 때 볼 수 있어요.';

  @override
  String get exGymCopyPhone => '전화번호 복사';

  @override
  String get exGymPhoneCopied => '전화번호를 복사했어요.';

  @override
  String get exerciseAdviceRecordEmptyToday =>
      '오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';

  @override
  String get exerciseAdviceRecordEmptyWeek =>
      '이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';

  @override
  String get exerciseAdviceRecordEmptyAll => '기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.';

  @override
  String exerciseAdviceRecordToday(int calories, int minutes, String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '오늘 $_temp0 위주로 $minutes분, ${calories}kcal 썼어요. 스트레칭으로 마무리해요.';
  }

  @override
  String exerciseAdviceRecordWeekOneDay(int minutes) {
    return '이번 주는 $minutes분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.';
  }

  @override
  String exerciseAdviceRecordWeekSkew(
    int days,
    int minutes,
    String missing,
    String top,
  ) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    String _temp1 = intl.Intl.selectLogic(missing, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '이번 주 $days일 $minutes분이 $_temp0에 몰렸어요. $_temp1도 섞어 볼까요?';
  }

  @override
  String exerciseAdviceRecordWeekBalanced(int days, int minutes) {
    return '이번 주 $days일 $minutes분, 유형도 고르게 섞였어요.';
  }

  @override
  String get exerciseAdviceRecordAllUp =>
      '최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요.';

  @override
  String get exerciseAdviceRecordAllDown =>
      '최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요.';

  @override
  String exerciseAdviceRecordAllSteady(int days, int minutes, int weeks) {
    return '$weeks주 동안 $days일 $minutes분, 기복 없이 이어가고 있어요.';
  }

  @override
  String exerciseAdviceRoutineTodayAllDone(int count) {
    return '오늘 추천 운동 $count개를 모두 마쳤어요. 잘했어요!';
  }

  @override
  String exerciseAdviceRoutineTodayDoneNextOrder(
    String done,
    String doneObj,
    String next,
    String then,
  ) {
    return '$done$doneObj 마쳤어요. 다음은 $next → $then 순서로 해 보세요.';
  }

  @override
  String exerciseAdviceRoutineTodayDoneNext(
    String done,
    String doneObj,
    String next,
  ) {
    return '$done$doneObj 마쳤어요. 다음은 $next 차례예요.';
  }

  @override
  String exerciseAdviceRoutineTodayNextOrder(String next, String then) {
    return '다음은 $next → $then 순서로 해 보세요.';
  }

  @override
  String exerciseAdviceRoutineTodayNext(String next) {
    return '다음은 $next 차례예요.';
  }

  @override
  String exerciseAdviceRoutineTodayLeft(int count) {
    return '남은 추천 운동이 $count개예요. 목록 순서대로 해 보세요.';
  }

  @override
  String exerciseAdviceRoutineTodayStartOrder(String next, String then) {
    return '오늘 추천 운동은 $next → $then 순서로 시작해 보세요.';
  }

  @override
  String exerciseAdviceRoutineTodayStart(String next) {
    return '오늘은 $next부터 시작해 보세요.';
  }

  @override
  String exerciseAdviceRoutineWeekNoneToday(String next) {
    return '이번 주엔 추천 운동을 아직 안 했어요. 오늘 $next부터 해 볼까요?';
  }

  @override
  String exerciseAdviceRoutineWeekNoneNext(String next) {
    return '이번 주엔 추천 운동을 아직 안 했어요. $next부터 해 봐요.';
  }

  @override
  String get exerciseAdviceRoutineWeekNone =>
      '이번 주엔 추천 운동을 아직 안 했어요. 오늘 하나부터 해 봐요.';

  @override
  String exerciseAdviceRoutineWeekOnly(
    String missing,
    String rest,
    String top,
  ) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    String _temp1 = intl.Intl.selectLogic(rest, {
      'next_week': '다음 주엔',
      'other': '남은 날엔',
    });
    String _temp2 = intl.Intl.selectLogic(missing, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '이번 주엔 $_temp0 추천 운동만 했어요. $_temp1 $_temp2부터 해 보세요.';
  }

  @override
  String exerciseAdviceRoutineWeekOnlyShort(String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '이번 주엔 $_temp0 추천 운동만 했어요.';
  }

  @override
  String exerciseAdviceRoutineWeekSkew(
    String missing,
    String rest,
    int share,
    String top,
  ) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소가',
      'strength': '근력이',
      'stretching': '스트레칭이',
      'other': '기타가',
    });
    String _temp1 = intl.Intl.selectLogic(rest, {
      'next_week': '다음 주엔',
      'other': '남은 날엔',
    });
    String _temp2 = intl.Intl.selectLogic(missing, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '이번 주 추천 운동 중 $_temp0 $share%예요. $_temp1 $_temp2부터 해 보세요.';
  }

  @override
  String exerciseAdviceRoutineWeekSkewShort(int share, String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소가',
      'strength': '근력이',
      'stretching': '스트레칭이',
      'other': '기타가',
    });
    return '이번 주 추천 운동은 $_temp0 $share%예요.';
  }

  @override
  String exerciseAdviceRoutineWeekPraise(String how) {
    String _temp0 = intl.Intl.selectLogic(how, {'even': '고르게', 'other': '꾸준히'});
    return '이번 주 추천 운동을 $_temp0 해냈어요. 이대로 이어 가요!';
  }

  @override
  String exerciseAdviceRoutineWeekCountsToday(
    int assigned,
    int completed,
    String next,
  ) {
    return '이번 주 추천 운동 $assigned개 중 $completed개를 했어요. 오늘 $next부터 이어 가요.';
  }

  @override
  String exerciseAdviceRoutineWeekCountsKeep(
    int assigned,
    int completed,
    String rest,
  ) {
    String _temp0 = intl.Intl.selectLogic(rest, {
      'next_week': '다음 주도 이어 가요.',
      'other': '남은 날도 이어 가요.',
    });
    return '이번 주 추천 운동 $assigned개 중 $completed개를 했어요. $_temp0';
  }

  @override
  String exerciseAdviceRoutineWeekCounts(int assigned, int completed) {
    return '이번 주 추천 운동 $assigned개 중 $completed개를 했어요.';
  }

  @override
  String exerciseAdviceRoutineLastWeekNoneNext(String next) {
    return '지난주엔 추천 운동을 못 했어요. 이번 주는 $next부터 해 봐요.';
  }

  @override
  String get exerciseAdviceRoutineLastWeekNone =>
      '지난주엔 추천 운동을 못 했어요. 이번 주는 하나씩 해 봐요.';

  @override
  String exerciseAdviceRoutineLastWeekOnly(String missing, String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    String _temp1 = intl.Intl.selectLogic(missing, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '지난주엔 $_temp0 추천 운동만 했어요. 이번 주는 $_temp1부터 해 보세요.';
  }

  @override
  String exerciseAdviceRoutineLastWeekOnlyShort(String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '지난주엔 $_temp0 추천 운동만 했어요.';
  }

  @override
  String exerciseAdviceRoutineLastWeekSkew(
    String missing,
    int share,
    String top,
  ) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소가',
      'strength': '근력이',
      'stretching': '스트레칭이',
      'other': '기타가',
    });
    String _temp1 = intl.Intl.selectLogic(missing, {
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    });
    return '지난주 추천 운동 중 $_temp0 $share%였어요. 이번 주는 $_temp1부터 해 보세요.';
  }

  @override
  String exerciseAdviceRoutineLastWeekSkewShort(int share, String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': '유산소가',
      'strength': '근력이',
      'stretching': '스트레칭이',
      'other': '기타가',
    });
    return '지난주 추천 운동은 $_temp0 $share%였어요.';
  }

  @override
  String exerciseAdviceRoutineLastWeekPraise(String how) {
    String _temp0 = intl.Intl.selectLogic(how, {'even': '고르게', 'other': '꾸준히'});
    return '지난주 추천 운동을 $_temp0 해냈어요. 이번 주도 이어 가요!';
  }

  @override
  String exerciseAdviceRoutineLastWeekCountsMore(int assigned, int completed) {
    return '지난주 추천 운동 $assigned개 중 $completed개를 했어요. 이번 주는 더 채워 봐요.';
  }

  @override
  String exerciseAdviceRoutineLastWeekCounts(int assigned, int completed) {
    return '지난주 추천 운동 $assigned개 중 $completed개를 했어요.';
  }

  @override
  String exerciseAdviceRoutineAllNew(int days) {
    return '추천 목록을 받은 지 $days일째예요. 일주일 뒤 빠진 운동을 짚어 드릴게요.';
  }

  @override
  String exerciseAdviceRoutineAllNoneNext(int days, String next) {
    return '추천 목록을 받은 지 $days일째예요. 오늘 $next부터 시작해 볼까요?';
  }

  @override
  String exerciseAdviceRoutineAllNone(int days) {
    return '추천 목록을 받은 지 $days일째예요. 오늘 하나부터 시작해 봐요.';
  }

  @override
  String exerciseAdviceRoutineAllDoneTodayPart(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'lower': '하체',
      'upper': '상체',
      'core': '코어',
      'full': '전신',
      'other': '전신',
    });
    return '자주 빠지던 $_temp0 운동을 오늘 해냈어요. 이대로 이어 가요!';
  }

  @override
  String exerciseAdviceRoutineAllDoneTodayName(String name, String nameObj) {
    return '자주 빠지던 $name$nameObj 오늘 해냈어요. 이대로 이어 가요!';
  }

  @override
  String exerciseAdviceRoutineAllDoneTodayNamePlain(String name) {
    return '자주 빠지던 $name, 오늘 해냈어요. 이대로 이어 가요!';
  }

  @override
  String get exerciseAdviceRoutineAllDoneToday =>
      '자주 빠지던 운동을 오늘 해냈어요. 이대로 이어 가요!';

  @override
  String exerciseAdviceRoutineAllMissedPart(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'lower': '하체',
      'upper': '상체',
      'core': '코어',
      'full': '전신',
      'other': '전신',
    });
    String _temp1 = intl.Intl.selectLogic(part, {
      'lower': '하체',
      'upper': '상체',
      'core': '코어',
      'full': '전신',
      'other': '전신',
    });
    return '추천 운동 중 $_temp0 운동이 자주 빠졌어요. $_temp1 운동을 먼저 해 볼까요?';
  }

  @override
  String exerciseAdviceRoutineAllMissedPartShort(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'lower': '하체',
      'upper': '상체',
      'core': '코어',
      'full': '전신',
      'other': '전신',
    });
    return '$_temp0 추천 운동이 자주 빠졌어요. 먼저 하는 순서로 바꿔 볼까요?';
  }

  @override
  String exerciseAdviceRoutineAllMissedName(String name, String nameSubj) {
    return '추천 운동 중 $name$nameSubj 자주 빠졌어요. 다음엔 먼저 해 볼까요?';
  }

  @override
  String exerciseAdviceRoutineAllMissedNameShort(String name, String nameSubj) {
    return '$name$nameSubj 자주 빠졌어요. 먼저 해 볼까요?';
  }

  @override
  String exerciseAdviceRoutineAllMissedNamePlain(String name) {
    return '추천 운동 $name, 자주 빠졌어요. 다음엔 먼저 해 볼까요?';
  }

  @override
  String exerciseAdviceRoutineAllMissedNamePlainShort(String name) {
    return '$name, 자주 빠졌어요. 먼저 해 볼까요?';
  }

  @override
  String get exerciseAdviceRoutineAllMissed =>
      '자주 빠진 추천 운동이 있어요. 목록 순서를 바꿔 볼까요?';

  @override
  String exerciseAdviceRoutineAllPraise(int weeks) {
    return '추천 운동을 $weeks주째 꾸준히 하고 있어요. 앞으로도 화이팅!';
  }

  @override
  String exerciseAdviceRoutineAllRate(int pct) {
    return '지금 추천 운동의 $pct%를 했어요. 빠지는 날 없이 이어 가 봐요.';
  }

  @override
  String get dietAdviceTodayEmpty => '오늘 식단 기록이 아직 없어요.';

  @override
  String get dietAdviceTodayMissingMeal => '적지 않은 끼니가 있나요?';

  @override
  String dietAdviceTodaySodiumOver(int sodiumMg) {
    final intl.NumberFormat sodiumMgNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String sodiumMgString = sodiumMgNumberFormat.format(sodiumMg);

    return '나트륨 **${sodiumMgString}mg**, 권장량 초과예요.';
  }

  @override
  String dietAdviceTodayCalorieOver(int kcal) {
    final intl.NumberFormat kcalNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String kcalString = kcalNumberFormat.format(kcal);

    return '오늘 **${kcalString}kcal**, 목표 초과예요.';
  }

  @override
  String dietAdviceTodayProteinLeft(int proteinG) {
    return '단백질 **${proteinG}g** 더 필요해요.';
  }

  @override
  String dietAdviceTodayBalanced(int kcal) {
    final intl.NumberFormat kcalNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String kcalString = kcalNumberFormat.format(kcal);

    return '오늘 **${kcalString}kcal**, 균형이 좋아요.';
  }

  @override
  String dietAdviceNextMeal(String slot, String menu) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': '아침',
      'lunch': '점심',
      'dinner': '저녁',
      'other': '끼니',
    });
    return '$_temp0은 **$menu** 어때요?';
  }

  @override
  String dietAdviceNextSnack(String menu) {
    return '간식으로 **$menu** 어때요?';
  }

  @override
  String get dietAdviceTodayDone => '오늘 식단을 잘 마무리했어요!';

  @override
  String get dietAdviceTodayLogFirst => '기록하면 다음 메뉴를 골라 드릴게요.';

  @override
  String get dietAdviceWeekEmpty => '이번 주 식단 기록이 아직 없어요.';

  @override
  String dietAdviceWeekSkipBreakfast(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': '지난주',
      'other': '이번 주',
    });
    return '$_temp0 아침을 **$days번** 걸렀어요.';
  }

  @override
  String dietAdviceWeekSkipBreakfastSnack(
    String scope,
    int days,
    int snackDays,
  ) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': '지난주',
      'other': '이번 주',
    });
    return '$_temp0 아침 거른 $days일 중 **$snackDays일** 간식을 드셨어요.';
  }

  @override
  String dietAdviceWeekFocusSodium(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': '지난주',
      'other': '이번 주',
    });
    return '$_temp0 나트륨을 **$days일** 넘겼어요.';
  }

  @override
  String dietAdviceWeekFocusCalorie(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': '지난주',
      'other': '이번 주',
    });
    return '$_temp0 칼로리 목표를 **$days일** 넘겼어요.';
  }

  @override
  String dietAdviceWeekFocusSugar(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': '지난주',
      'other': '이번 주',
    });
    return '$_temp0 당류를 **$days일** 넘겼어요.';
  }

  @override
  String dietAdviceWeekFocusProtein(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': '지난주',
      'other': '이번 주',
    });
    return '$_temp0 단백질이 **$days일** 부족했어요.';
  }

  @override
  String dietAdviceWeekGood(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': '지난주',
      'other': '이번 주',
    });
    return '$_temp0 기록한 **$days일** 모두 목표 안이에요.';
  }

  @override
  String get dietAdviceWeekEmptyHint => '한 끼만 남겨도 흐름이 보여요.';

  @override
  String get dietAdviceTipBreakfast => '삶은 달걀로 아침을 챙겨요.';

  @override
  String get dietAdviceTipSodium => '국물은 남기고 건더기 위주로 드세요.';

  @override
  String get dietAdviceTipCalorie => '저녁 양을 조금만 줄여 봐요.';

  @override
  String get dietAdviceTipSugar => '단 음료 대신 물이나 차를 드세요.';

  @override
  String get dietAdviceTipProtein => '끼니마다 달걀·두부를 더해 봐요.';

  @override
  String get dietAdviceTipKeep => '지금 흐름을 그대로 이어 가요!';

  @override
  String dietAdviceAllFewRecords(int days) {
    return '최근 4주 기록이 **$days일**이에요.';
  }

  @override
  String dietAdviceAllSlotSodium(String slot, int days) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': '아침',
      'lunch': '점심',
      'dinner': '저녁',
      'other': '끼니',
    });
    return '최근 4주 $_temp0 나트륨이 **$days번** 높았어요.';
  }

  @override
  String dietAdviceAllCarbHeavy(int pct) {
    return '최근 4주 탄수화물 비중이 **$pct%**예요.';
  }

  @override
  String dietAdviceAllProteinLight(int pct) {
    return '최근 4주 단백질 비중이 **$pct%**로 낮아요.';
  }

  @override
  String dietAdviceAllProteinTrendUp(int before, int after) {
    return '단백질 목표 달성일이 **$before일→$after일**로 늘었어요.';
  }

  @override
  String dietAdviceAllProteinTrendDown(int before, int after) {
    return '단백질 목표 달성일이 **$before일→$after일**로 줄었어요.';
  }

  @override
  String dietAdviceAllFrequentMenu(String slot, String food, int count) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': '아침',
      'lunch': '점심',
      'dinner': '저녁',
      'other': '끼니',
    });
    return '4주간 $_temp0 1위 메뉴는 **$food**($count회)예요.';
  }

  @override
  String dietAdviceAllRepeatedFoods(String food1, String food2) {
    return '4주간 **$food1·$food2** 비중이 높아요.';
  }

  @override
  String dietAdviceAllGood(int days) {
    return '최근 4주 **$days일** 기록, 흐름이 좋아요.';
  }

  @override
  String get dietAdviceAllFewHint => '7일이 넘으면 흐름을 짚어 드릴게요.';

  @override
  String get dietAdviceTipCarb => '밥 양을 줄이고 반찬을 늘려 봐요.';

  @override
  String get dietAdviceTipSwap => '곁들임 반찬만 바꿔 봐요.';

  @override
  String get dietAdviceTipVariety => '생선·두부를 주 2회 더해요.';

  @override
  String get weeklyFeedbackSheetTitle => '이번 주 어땠어요?';

  @override
  String weeklyFeedbackSheetSubtitle(String range) {
    return '$range 한 주를 담당 트레이너에게 알려 주세요';
  }

  @override
  String get weeklyFeedbackWhy => '30초면 끝나요. 다음 주 운동 강도가 이 답에서 정해져요.';

  @override
  String get weeklyFeedbackConditionQuestion => '한 주 컨디션은 어땠나요?';

  @override
  String get weeklyFeedbackIntensityQuestion => '운동 강도는 어땠나요?';

  @override
  String get weeklyFeedbackPainQuestion => '아팠던 곳이 있나요?';

  @override
  String get weeklyFeedbackPainHint => '예: 오른 무릎';

  @override
  String get weeklyFeedbackPainDateLabel => '아팠던 날';

  @override
  String get weeklyFeedbackPainDatePick => '날짜 고르기';

  @override
  String get weeklyFeedbackNoteQuestion => '트레이너에게 한 줄 피드백 (선택)';

  @override
  String get weeklyFeedbackNoteHint => '그 주에 있었던 일을 적어 주세요';

  @override
  String get weeklyFeedbackSend => '보내기';

  @override
  String get weeklyFeedbackResend => '다시 보내기';

  @override
  String get weeklyFeedbackLater => '나중에';

  @override
  String get weeklyFeedbackIncomplete => '컨디션과 운동 강도를 골라 주세요';

  @override
  String get weeklyFeedbackSent => '주간 피드백을 보냈어요';

  @override
  String get weeklyFeedbackSendFailed => '주간 피드백을 보내지 못했어요. 다시 시도해 주세요';

  @override
  String get weeklyFeedbackAlreadySent => '이미 보낸 주예요. 다시 보내면 마지막 답으로 바뀌어요.';

  @override
  String get weekConditionGreat => '아주 좋았어요';

  @override
  String get weekConditionGood => '좋았어요';

  @override
  String get weekConditionOk => '보통이었어요';

  @override
  String get weekConditionTired => '지쳤어요';

  @override
  String get weekConditionBad => '많이 안 좋았어요';

  @override
  String get weekIntensityTooEasy => '너무 쉬웠어요';

  @override
  String get weekIntensityRight => '딱 맞았어요';

  @override
  String get weekIntensityHard => '조금 힘들었어요';

  @override
  String get weekIntensityTooHard => '너무 힘들었어요';

  @override
  String get myCoachReportsEntry => '트레이너 리포트';

  @override
  String get myCoachReportsEntryHint => '받은 리포트와 보낸 주간 피드백';

  @override
  String get coachReportsSectionTitle => '받은 리포트';

  @override
  String get coachReportsEmpty => '아직 받은 리포트가 없어요';

  @override
  String get coachReportsEmptyHint => '담당 트레이너가 주간 리포트를 보내면 여기에 쌓여요';

  @override
  String get coachReportsLoadFailed => '받은 리포트를 불러오지 못했어요';

  @override
  String get weeklyFeedbackLoadFailed => '보낸 주간 피드백을 불러오지 못했어요';

  @override
  String coachReportSentOn(int month, int day) {
    return '$month월 $day일 보냄';
  }

  @override
  String get myWeeklyFeedbackSectionTitle => '보낸 주간 피드백';

  @override
  String get myWeeklyFeedbackOnlyLastWeek => '직전 주에 보낸 답만 보여 드려요';

  @override
  String get myWeeklyFeedbackEmpty => '직전 주 피드백을 아직 보내지 않았어요';

  @override
  String get myWeeklyFeedbackConditionLabel => '컨디션';

  @override
  String get myWeeklyFeedbackIntensityLabel => '운동 강도';

  @override
  String get myWeeklyFeedbackPainLabel => '통증';

  @override
  String get myWeeklyFeedbackPainNone => '없음';

  @override
  String myWeeklyFeedbackPainWithDate(String area, int month, int day) {
    return '$area ($month월 $day일)';
  }

  @override
  String get myWeeklyFeedbackNoteLabel => '한 줄 피드백';

  @override
  String myWeeklyFeedbackSentAt(int month, int day) {
    return '$month월 $day일 보냄';
  }

  @override
  String get weeklyFeedbackNowButton => '지금 피드백 보내기';

  @override
  String get authForgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get passwordChangeTitle => '비밀번호 변경';

  @override
  String get passwordChangeCurrentHint => '현재 비밀번호';

  @override
  String get passwordChangeNewHint => '새 비밀번호 (영문·숫자 포함 8자 이상)';

  @override
  String get passwordChangeConfirmHint => '새 비밀번호 확인';

  @override
  String get passwordChangeNote => '이 기기는 로그인이 유지되고, 다른 기기에서는 다시 로그인해야 해요.';

  @override
  String get passwordChangeAction => '비밀번호 바꾸기';

  @override
  String get passwordChangeDone => '비밀번호를 바꿨어요';

  @override
  String get passwordChangeWrongCurrent => '현재 비밀번호가 맞지 않아요';

  @override
  String get passwordChangeSameAsCurrent => '현재와 다른 비밀번호를 입력해 주세요';

  @override
  String get passwordChangeDemoTitle => '데모 계정은 비밀번호를 바꿀 수 없어요';

  @override
  String get passwordChangeDemoBody =>
      '데모 모드에는 서버 계정이 없어요. 실제 계정으로 로그인하면 여기서 바꿀 수 있어요.';

  @override
  String get passwordChangeSocialTitle => '이 계정에는 비밀번호가 없어요';

  @override
  String get passwordChangeSocialBody => '카카오·구글로 로그인한 계정은 그 서비스에서 계정을 관리해요.';

  @override
  String get passwordTooManyAttempts => '시도가 너무 많아요. 잠시 후 다시 시도해 주세요.';

  @override
  String get passwordTemporaryFailure => '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get passwordResetTitle => '비밀번호 재설정';

  @override
  String get passwordResetRequestSubtitle => '가입한 이메일로 재설정 코드를 보내 드려요.';

  @override
  String get passwordResetSendAction => '코드 받기';

  @override
  String get passwordResetHaveCode => '이미 코드가 있어요';

  @override
  String get passwordResetSentTitle => '메일을 확인해 주세요';

  @override
  String passwordResetSentBody(String email, int minutes) {
    return '$email 로 가입된 계정이 있다면 $minutes분 동안 한 번 쓸 수 있는 코드를 보냈어요.';
  }

  @override
  String get passwordResetConfirmSubtitle => '메일로 받은 코드와 새 비밀번호를 입력해 주세요.';

  @override
  String get passwordResetCodeHint => '재설정 코드 16자리';

  @override
  String get passwordResetCodeEmpty => '코드를 입력해 주세요';

  @override
  String get passwordResetCodeMalformed => '메일에 적힌 16자리 코드를 입력해 주세요';

  @override
  String get passwordResetCodeInvalid => '코드가 맞지 않거나 만료됐어요. 코드를 다시 받아 주세요.';

  @override
  String get passwordResetConfirmAction => '새 비밀번호 저장';

  @override
  String get passwordResetResend => '코드 다시 받기';

  @override
  String get passwordResetDemoNote => '데모 모드에서는 메일이 가지 않아요. 코드 칸을 미리 채워 두었어요.';

  @override
  String get passwordResetUnavailable => '지금은 재설정 메일을 보낼 수 없어요. 고객센터로 문의해 주세요.';

  @override
  String get passwordResetDoneTitle => '비밀번호를 바꿨어요';

  @override
  String get passwordResetDoneBody => '새 비밀번호로 다시 로그인해 주세요. 모든 기기의 로그인이 끝났어요.';

  @override
  String get passwordResetBackToSignIn => '로그인하러 가기';

  @override
  String get releaseUpdateTitle => '새 버전이 배포되었어요';

  @override
  String get releaseUpdateMessage =>
      '새로고침하면 최신 화면으로 바뀌어요. 작성 중인 내용이 있으면 먼저 저장해 주세요.';

  @override
  String get releaseUpdateReload => '새로고침';

  @override
  String get releaseUpdateDismiss => '안내 닫기';
}
