// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'On-Care';

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
  String get errorNetwork => '네트워크 문제';

  @override
  String get errorUnauthorized => '로그인이 필요합니다';

  @override
  String get errorNotFound => '찾을 수 없습니다';

  @override
  String get errorServer => '서버 오류';

  @override
  String get errorCancelled => '취소됨';

  @override
  String get errorUnknown => '알 수 없는 오류';

  @override
  String get dashboardMetricCalories => '칼로리';

  @override
  String get dashboardMetricExercise => '주간 운동';

  @override
  String get homeDashboardLoadError => '대시보드 정보를 불러오지 못했어요.';

  @override
  String get homeDashboardEmpty => '아직 오늘 기록이 없어요. 식단이나 운동을 기록해 보세요.';

  @override
  String get homeScheduleEmpty => '오늘 예정된 일정이 없어요.';

  @override
  String get homeAiAdviceTitle => '오늘의 AI 통합 조언';

  @override
  String get homeAiAdviceBody =>
      '아침 식단과 저녁 PT는 완벽했습니다! 점심 짬뽕으로 높아진 나트륨과 혈당을 낮추기 위해 물을 충분히 마시고, 코치님이 강조하신 어깨 스트레칭으로 건강하게 마무리해 보세요.';

  @override
  String get homeSodiumExceededBadge => '나트륨 초과';

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
  String get homeWeeklyExerciseTrend => '운동 추이';

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
  String homeRecBasisSodium(int days, String sodium) {
    return '최근 $days일 평균 나트륨 ${sodium}mg';
  }

  @override
  String get homeRecBasisOverLimit => '권장 초과';

  @override
  String get homeRecMealsTitle => '추천 식단';

  @override
  String get homeViewAll => '전체 보기';

  @override
  String homeScheduleDate(String weekday, int month, int day) {
    return '$month월 $day일 $weekday요일';
  }

  @override
  String get homeScheduleTitle => '오늘의 일정';

  @override
  String get unitKcal => 'kcal';

  @override
  String get unitMinutes => '분';

  @override
  String get unitSets => '세트';

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
  String get dietPeriodAverage => '하루 평균';

  @override
  String get dietPeriodEmpty => '이 기간에 기록된 식단이 없어요.';

  @override
  String dietPeriodRange(String start, String end) {
    return '$start ~ $end';
  }

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
  String dietMealSheetTitle(String meal) {
    return '$meal 식단';
  }

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
  String get dietSaveEntry => '저장하기';

  @override
  String get dietSaveFailed => '저장에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get dietDeleteTitle => '식단 기록 삭제';

  @override
  String get dietDeleteConfirm => '이 식단 기록을 삭제할까요?';

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
  String get dietEatenTime => '먹은 시간';

  @override
  String get dietEatenFood => '먹은 음식';

  @override
  String get dietNewFood => '새 음식';

  @override
  String get dietAddFood => '+ 음식 추가';

  @override
  String get dietEditFoodHint => '음식명과 칼로리를 수정할 수 있어요';

  @override
  String get dietTotalCalories => '총 칼로리';

  @override
  String get dietNutritionInfo => '영양 정보';

  @override
  String get dietEditNutritionHint => '분석된 값을 직접 수정할 수 있어요';

  @override
  String get dietSodiumHint => '하루 권장 2,000mg 이하';

  @override
  String get dietSugarHint => '하루 권장 50g 이하';

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
  String get exRecommendedGyms => '추천 헬스장';

  @override
  String get exRecommendedTrainers => '추천 트레이너';

  @override
  String get exSeeMore => '더보기';

  @override
  String get exNoConnectedGym => '아직 연결된 헬스장이 없어요.';

  @override
  String get exNoRecommendedGyms => '추천할 헬스장이 아직 없어요.';

  @override
  String get exNoRecommendedTrainers => '추천할 트레이너가 아직 없어요.';

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
  String get exWeekSummary => '이번 주 운동 요약';

  @override
  String get exActivityTitle => '운동 현황';

  @override
  String exWeekOfMonthLabel(int month, int week) {
    return '$month월 $week주차';
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
  String get exExerciseContent => '운동 내용';

  @override
  String get exViewDetail => '상세보기';

  @override
  String get exRegister => '등록하기';

  @override
  String exGymRegistered(String gym) {
    return '$gym을(를) 등록했어요';
  }

  @override
  String get actionClose => '닫기';

  @override
  String exWeekNumber(int n) {
    return '$n주';
  }

  @override
  String get exTodayTotalTime => '오늘 총 운동 시간';

  @override
  String get exRest => '휴식';

  @override
  String get exAiRecommendedExercise => 'AI 추천 운동';

  @override
  String get exStatTime => '시간';

  @override
  String get exStatCalories => '칼로리';

  @override
  String get exStatStreak => '연속';

  @override
  String get exUnitStreakDays => '일 연속';

  @override
  String exStreakCheer(int days) {
    return '$days일 연속 운동 중이에요!';
  }

  @override
  String get exStreakStart => '오늘 운동으로 연속 기록을 시작해 봐요.';

  @override
  String get exToday => '오늘';

  @override
  String get exLoadError => '운동 정보를 불러오지 못했어요.';

  @override
  String get exCompletedPtTitle => '오늘 완료한 PT';

  @override
  String exCompletedPtTime(String time) {
    return '$time 수업 완료';
  }

  @override
  String get exCompletedPtNoProgram => '등록된 운동 프로그램이 없습니다.';

  @override
  String exCompletedPtFeedback(String coachName) {
    return '$coachName · 오늘의 피드백';
  }

  @override
  String exProgramSets(int count) {
    return '$count세트';
  }

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
  String get exExerciseNameHint => '예) 스쿼트, 러닝머신';

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
  String get exExerciseWeight => '중량';

  @override
  String get exUnitMinutes => '분';

  @override
  String get exUnitSets => '세트';

  @override
  String get exUnitReps => '회';

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
  String get exOwnRecords => '직접 기록한 운동';

  @override
  String get exOwnRecordsEmpty => '직접 추가한 운동이 없어요';

  @override
  String get exOwnRecordSource => '직접 기록';

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
  String get exFindTrainer => '트레이너 찾기';

  @override
  String get exGymDetailTitle => '헬스장 상세';

  @override
  String get exTrainerDetailTitle => '트레이너 상세';

  @override
  String get exDistance => '거리';

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
  String get exTrainerSearchPlaceholder => '전문 분야나 트레이너 이름 검색';

  @override
  String get exSortRecommended => '추천순';

  @override
  String get exSortDistance => '거리순';

  @override
  String get exSortRating => '평점순';

  @override
  String get exSortName => '이름순';

  @override
  String exResultCount(int count) {
    return '$count개 결과';
  }

  @override
  String get exNoSearchResults => '검색 결과가 없어요.';

  @override
  String get exTrainersLoadError => '트레이너 정보를 불러오지 못했어요.';

  @override
  String get exGymSearchHint => '헬스장, 지역으로 검색';

  @override
  String get exNearbyGyms => '주변 헬스장';

  @override
  String get exGymListCollapse => '목록 접기';

  @override
  String get exGymListExpand => '목록 펼치기';

  @override
  String get exAiAnalysis => '✦ AI 분석';

  @override
  String exNoGymMatch(String query) {
    return '\'$query\'에 맞는 헬스장이 없어요';
  }

  @override
  String get exGymsLoadError => '헬스장을 불러오지 못했어요.';

  @override
  String get exAiTopPick => '✦ AI 추천 1순위';

  @override
  String get exGymDetailHint => '소속 트레이너 보고 상담 신청하기';

  @override
  String exReasonTrainer(String name, String role) {
    return '전담 트레이너 $name$role 상주';
  }

  @override
  String exReasonHours(String hours, String weekend) {
    return '$hours$weekend 운영';
  }

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
  String get exSlotFull => '예약 마감';

  @override
  String get exSlotTypePersonalTraining => '1:1 PT';

  @override
  String get exSlotTypeConsultation => '상담';

  @override
  String get exSlotsEmpty => '예약 가능한 시간이 없어요';

  @override
  String get exSlotsAllBooked => '예약 가능한 시간이 모두 찼어요';

  @override
  String get exSlotsLoadError => '예약 시간을 불러오지 못했어요.';

  @override
  String get exReserveFailed => '예약에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String exReserveConfirmedSlotGym(String slot, String gym) {
    return '$slot · $gym 예약이 확정됐어요';
  }

  @override
  String exReserveConfirm(String slot) {
    return '$slot 예약 확정';
  }

  @override
  String get exGymInfo => '헬스장 정보';

  @override
  String get exConsultButton => '💬 1:1 상담';

  @override
  String get exAddress => '주소';

  @override
  String get exHours => '운영시간';

  @override
  String get exPhone => '전화';

  @override
  String get exSpecialty => '전문 분야';

  @override
  String get exKakaoMapArea => '카카오맵 영역';

  @override
  String get myTabTitle => 'MY';

  @override
  String get myDefaultUserName => '사용자';

  @override
  String get mySettingsTitle => '설정';

  @override
  String get myProfileTitle => '내 프로필';

  @override
  String get myNotifTitle => '알림 설정';

  @override
  String get mySupportTitle => '고객 지원';

  @override
  String get myPointsBenefitsTitle => '포인트 사용처';

  @override
  String myPointsBalance(int points) {
    return '보유 ${points}P';
  }

  @override
  String get myPointsBenefitsSubtitle => '포인트로 받을 수 있는 혜택';

  @override
  String get myPointsBenefitsHint => '기록을 꾸준히 남기면 포인트가 쌓이고, 위 혜택에 사용할 수 있어요.';

  @override
  String get myPointsDiscountTitle => '포인트 차감 현금성 할인';

  @override
  String get myPointsDiscountDescription =>
      '1:1 코칭권·PT 결제 시 보유 포인트를 최대 10%까지 현금처럼 차감해요.';

  @override
  String get myPointsDiscountCost => '최대 10%';

  @override
  String get myPointsReportTitle => '혈당·혈압 예측 리포트 잠금 해제';

  @override
  String get myPointsReportDescription => '주간·월간 건강 데이터 종합 리포트를 열람할 수 있어요.';

  @override
  String get myPointsReportCost => '500P';

  @override
  String get myPointsRecipeTitle => '맞춤형 건강 식단 레시피 패키지';

  @override
  String get myPointsRecipeDescription =>
      '건강 목표(당뇨 예방·체중 감량 등)에 맞춘 식단 가이드를 PDF·인터랙티브로 받아요.';

  @override
  String get myPointsRecipeCost => '500P';

  @override
  String get myLogout => '로그아웃';

  @override
  String get myLogoutConfirm => '로그아웃 하시겠어요?';

  @override
  String get myCancel => '취소';

  @override
  String get myTrainerGymTitle => '내 트레이너 · 헬스장';

  @override
  String get myConnectionDeleteTitle => '연결 삭제';

  @override
  String get myDelete => '삭제';

  @override
  String myGymDisconnectWithTrainerConfirm(String gym, String trainer) {
    return '$gym 연결을 삭제하시겠습니까?\n담당 트레이너 $trainer 연결도 함께 해제됩니다.';
  }

  @override
  String myGymDisconnectConfirm(String gym) {
    return '$gym 연결을 삭제하시겠습니까?';
  }

  @override
  String myTrainerDisconnectConfirm(String trainer, String gym) {
    return '담당 트레이너 $trainer 연결을 삭제하시겠습니까?\n$gym 헬스장 연결은 유지됩니다.';
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
  String get myFieldGoals => '건강·운동 목표';

  @override
  String get myNotifDietLog => '식단 기록 알림';

  @override
  String get myNotifExercise => '운동 리마인더';

  @override
  String get myNotifTrainer => '트레이너 메시지';

  @override
  String get myNotifAiCoaching => 'AI 코칭 조언';

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
      '제1조 (목적)\n이 약관은 On-Care(이하 \"회사\")가 제공하는 건강 관리 서비스(이하 \"서비스\")의 이용과 관련하여 회사와 회원 간의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.\n\n제2조 (약관의 효력 및 변경)\n① 이 약관은 서비스를 이용하는 모든 회원에게 효력이 발생합니다.\n② 회사는 관련 법령을 위반하지 않는 범위에서 이 약관을 변경할 수 있으며, 변경 시 적용일자와 변경 사유를 명시하여 서비스 내에 공지합니다.\n\n제3조 (서비스의 제공)\n회사는 식단 기록, 운동 기록, 건강 지표 관리, AI 코칭 등 회원의 건강 관리를 돕는 기능을 제공합니다. 서비스의 구체적인 내용은 회사의 정책에 따라 변경될 수 있습니다.\n\n제4조 (회원의 의무)\n회원은 본인의 건강 정보를 정확하게 입력하여야 하며, 서비스가 제공하는 정보는 의학적 진단이나 치료를 대체하지 않습니다. 건강상 문제가 있는 경우 반드시 전문 의료기관의 진료를 받으시기 바랍니다.\n\n제5조 (책임의 제한)\n회사는 회원이 서비스를 통해 얻은 정보에 기반하여 내린 판단과 그 결과에 대하여 법령이 허용하는 범위 내에서 책임을 부담하지 않습니다.\n\n부칙\n이 약관은 2026년 1월 1일부터 시행합니다.';

  @override
  String get myLegalPrivacyBody =>
      'On-Care(이하 \"회사\")는 「개인정보 보호법」 등 관련 법령을 준수하며, 회원의 개인정보를 소중히 보호합니다.\n\n1. 수집하는 개인정보 항목\n회사는 회원가입 및 서비스 제공을 위하여 이름, 이메일, 전화번호, 생년월일과 함께 식단·운동·건강 지표 등 건강 관련 정보를 수집합니다.\n\n2. 개인정보의 수집 및 이용 목적\n수집한 개인정보는 회원 식별, 건강 관리 기능 제공, 맞춤형 AI 코칭, 서비스 개선 및 고객 문의 응대의 목적으로만 이용됩니다.\n\n3. 개인정보의 보유 및 이용 기간\n회원의 개인정보는 원칙적으로 회원 탈퇴 시 지체 없이 파기합니다. 다만 관련 법령에 따라 보존할 필요가 있는 경우 해당 기간 동안 안전하게 보관합니다.\n\n4. 개인정보의 제3자 제공\n회사는 회원의 동의 없이 개인정보를 외부에 제공하지 않습니다. 다만 법령에 특별한 규정이 있는 경우는 예외로 합니다.\n\n5. 이용자의 권리\n회원은 언제든지 자신의 개인정보를 조회·수정하거나 처리 정지 및 삭제를 요청할 수 있습니다.\n\n6. 개인정보 보호책임자\n개인정보와 관련한 문의는 고객 지원(support@oncare.com)으로 연락하실 수 있습니다.\n\n시행일: 2026년 1월 1일';

  @override
  String get myLegalEffectiveDate => '시행일 2026. 01. 01.';

  @override
  String get myAppVersion => 'On-Care · 버전 1.0.0';

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
  String get coachCardExerciseTitle => '12회차 PT 완료';

  @override
  String get coachCardExerciseBody =>
      '12회차 PT를 잘 마쳤어요. 꾸준히 운동을 이어가고 있는 점이 좋습니다. 코치님 피드백대로 어깨 회전근개 스트레칭을 충분히 진행하고, 가벼운 유산소 운동으로 마무리해 주세요. 운동 후에는 무리한 활동보다 충분한 휴식과 수분 섭취로 회복을 도와주세요.';

  @override
  String get coachCardWaterTag => '수분';

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
  String get coachInviteExplain => '수락하면 내 식단·운동 기록을 이 트레이너가 볼 수 있어요.';

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
  String get coachChatSubtitle => '담당 트레이너 · 상담 가능';

  @override
  String get coachChatBack => '뒤로가기';

  @override
  String get coachChatLoadFailed => '대화를 불러오지 못했어요';

  @override
  String get coachChatSendFailed => '메시지 전송에 실패했어요. 다시 시도해 주세요';

  @override
  String get coachChatPdfOpenFailed => 'PDF를 열지 못했어요. 다시 시도해 주세요';

  @override
  String get coachChatReportRegistered => '리포트가 등록되었어요';

  @override
  String coachChatReportWeek(int sm, int sd, int em, int ed) {
    return '$sm월 $sd일 – $em월 $ed일';
  }

  @override
  String get coachChatReportOpenPdf => 'PDF 열기';

  @override
  String get coachChatReportPreviewPdf => 'PDF 미리보기';

  @override
  String get coachReportPdfDocTitle => '주간 리포트';

  @override
  String get coachReportPdfDocTitleContinued => '주간 리포트 (계속)';

  @override
  String coachReportPdfPeriod(String from, String to) {
    return '기간 $from ~ $to';
  }

  @override
  String get coachReportPdfSectionMetrics => '주요 지표';

  @override
  String get coachReportPdfSectionTrend => '요일별 추이';

  @override
  String get coachReportPdfSectionDaily => '요일별 상세';

  @override
  String coachReportPdfBullet(String label, String value) {
    return '· $label: $value';
  }

  @override
  String get coachReportPdfLabelWorkoutDays => '운동한 날';

  @override
  String get coachReportPdfLabelWorkoutMinutes => '총 운동 시간';

  @override
  String get coachReportPdfLabelBurned => '소모 칼로리';

  @override
  String get coachReportPdfLabelSessions => 'PT 세션';

  @override
  String get coachReportPdfLabelCalories => '평균 섭취 칼로리';

  @override
  String get coachReportPdfLabelSodium => '평균 나트륨';

  @override
  String get coachReportPdfLabelSugar => '평균 당류';

  @override
  String get coachReportPdfLabelMinutesShort => '운동 시간';

  @override
  String get coachReportPdfLabelCaloriesShort => '섭취 칼로리';

  @override
  String get coachReportPdfLabelSodiumShort => '나트륨';

  @override
  String get coachReportPdfLabelSugarShort => '당류';

  @override
  String coachReportPdfValueDays(String value) {
    return '$value일';
  }

  @override
  String coachReportPdfValueMinutes(String value) {
    return '$value분';
  }

  @override
  String coachReportPdfValueKcal(String value) {
    return '${value}kcal';
  }

  @override
  String coachReportPdfValueMg(String value) {
    return '${value}mg';
  }

  @override
  String coachReportPdfValueGram(String value) {
    return '${value}g';
  }

  @override
  String coachReportPdfAttendance(String done, String booked) {
    return '$booked회 중 $done회';
  }

  @override
  String get coachReportPdfNoData => '기록 없음';

  @override
  String coachReportPdfDay(String weekday, String exercise, String intake) {
    return '$weekday요일 — 운동 $exercise, 섭취 $intake';
  }

  @override
  String get coachReportPdfSectionTrainerNote => '트레이너 메시지';

  @override
  String get coachReportPdfNoTrainerNote => '함께 온 메시지가 없어요.';

  @override
  String get coachReportPdfSectionChange => '지난주 대비';

  @override
  String get coachReportPdfSectionMacros => '평균 탄단지';

  @override
  String get coachReportPdfLabelLoggedDays => '식단 기록한 날';

  @override
  String get coachReportPdfLabelSodiumOver => '나트륨 목표 초과';

  @override
  String get coachReportPdfLabelPtDone => '진행한 PT';

  @override
  String coachReportPdfValueSessions(String value) {
    return '$value회';
  }

  @override
  String get coachReportPdfLabelCardio => '유산소';

  @override
  String get coachReportPdfLabelStrength => '근력';

  @override
  String get coachReportPdfLabelStretching => '스트레칭';

  @override
  String get coachReportPdfSectionTypes => '운동 유형별 시간';

  @override
  String get coachReportPdfNoSessions => '잡힌 일정 없음';

  @override
  String get coachReportPdfBandPeriod => '기간';

  @override
  String get coachReportPdfSectionGoals => '목표 대비';

  @override
  String get coachReportPdfColumnMetric => '지표';

  @override
  String get coachReportPdfColumnThisWeek => '이번 주';

  @override
  String get coachReportPdfColumnLastWeek => '지난주';

  @override
  String get coachReportPdfColumnChange => '변화';

  @override
  String get coachReportPdfColumnWeekday => '요일';

  @override
  String get coachReportPdfColumnWorkout => '운동';

  @override
  String get coachReportPdfColumnIntake => '섭취';

  @override
  String get coachReportPdfUpcoming => '아직 지나지 않았어요';

  @override
  String coachReportPdfGoalOf(String value, String target) {
    return '$value (목표 $target)';
  }

  @override
  String coachReportPdfChartTarget(String value) {
    return '목표 $value';
  }

  @override
  String coachReportPdfDayUpcoming(String weekday) {
    return '$weekday요일 — 아직 지나지 않았어요';
  }

  @override
  String coachReportPdfChange(
    String label,
    String current,
    String previous,
    String delta,
  ) {
    return '· $label: $current (지난주 $previous, $delta)';
  }

  @override
  String coachReportPdfDeltaUp(String value) {
    return '+$value';
  }

  @override
  String coachReportPdfDeltaDown(String value) {
    return '-$value';
  }

  @override
  String get coachReportPdfDeltaSame => '변화 없음';

  @override
  String get coachReportPdfNoPreviousWeek => '지난주 기록이 없어 견줄 값이 없어요.';

  @override
  String coachReportPdfSodiumTargetNote(String target) {
    return '나트륨 목표는 회원님이 MY 화면에 적어 둔 하루 ${target}mg 기준이에요.';
  }

  @override
  String get coachReportPdfPreviewNote =>
      '트레이너 리포트가 보는 주를 회원님 기록으로 정리한 미리보기예요.';

  @override
  String coachReportPdfFileName(String date) {
    return '주간리포트_$date.pdf';
  }

  @override
  String get coachChatInputHint => '트레이너에게 메시지 보내기...';

  @override
  String get coachChatDemoAnalyzed => 'AI가 내 식단·운동 데이터를 분석했어요';

  @override
  String coachChatDemoReportSent(String trainer) {
    return '$trainer님께 요약 리포트가 전송됐어요';
  }

  @override
  String get coachChatDemoRoutineReceived => '개인 추천운동을 받았어요';

  @override
  String get coachChatDemoNotified => '알림으로도 전달됐어요';

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
  String get aicDatePillToday => '오늘';

  @override
  String get aicMedicalDisclaimer =>
      'AI 코치는 식단·운동 관리를 돕는 참고용이에요. 진단·처방이 아니니 증상이 있으면 전문의와 상담해 주세요.';

  @override
  String get aicInputHint => 'AI에게 무엇이든 물어보세요';

  @override
  String get aicQuickRepliesLabel => '이런 걸 물어보세요';

  @override
  String get aicGeneratingReply => '맞춤 답변 생성 중';

  @override
  String get aicQuickReply1 => '오늘 저녁 메뉴 추천해줘';

  @override
  String get aicQuickReply2 => '오늘 운동은 얼마나 하면 좋을까?';

  @override
  String get aicQuickReply3 => '내 혈당 기록은 괜찮아?';

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
  String get exTrainerConsultRequest => '트레이너 상담 요청하기';

  @override
  String get exConsultPendingCta => '상담 요청 대기 중';

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
      '요청이 수락되면 이 트레이너가 회원님의 식단 기록, 운동 기록, 신체 정보와 건강 목표를 확인할 수 있어요.';

  @override
  String get exConsultDataSharingAgree =>
      '위 내용을 확인했고, 식단·운동 기록과 신체 정보를 이 트레이너에게 공유하는 데 동의해요';

  @override
  String get exConsultDataSharingRequired => '공유에 동의해야 상담을 신청할 수 있어요';

  @override
  String get coachInviteConsentTitle => '담당 연결 전에 확인해 주세요';

  @override
  String coachInviteConsentBody(String name) {
    return '$name 트레이너와 담당으로 연결되면, 회원님의 식단 기록·운동 기록·신체 정보와 건강 목표를 이 트레이너가 볼 수 있어요. 연결을 해제하면 열람 권한도 함께 사라져요.';
  }

  @override
  String get coachInviteConsentAgree => '동의하고 연결';

  @override
  String get exExerciseGoal => '운동 목표';

  @override
  String get exGoalWeightLoss => '체중 감량';

  @override
  String get exGoalStrength => '근력 향상';

  @override
  String get exGoalFitness => '체력 향상';

  @override
  String get exGoalPosture => '자세 교정';

  @override
  String get exGoalHealth => '건강 관리';

  @override
  String get exOptionOther => '기타';

  @override
  String get exOtherGoalHint => '구체적인 운동 목표는 문의 내용에 작성해주세요.';

  @override
  String get exPreferredDate => '희망 날짜';

  @override
  String get exSelectDate => '날짜를 선택해주세요';

  @override
  String get exSelectTime => '시간을 선택해주세요';

  @override
  String get exPreferredTime => '희망 시간대';

  @override
  String get exTimeFlexible => '시간 협의';

  @override
  String get exTimeRangeTitle => '시간 선택';

  @override
  String get exTimeRangeStartTime => '시작 시간';

  @override
  String get exTimeRangeEndTime => '종료 시간';

  @override
  String get exTimeRangeStartHourStep => '시작 시';

  @override
  String get exTimeRangeStartMinuteStep => '시작 분';

  @override
  String get exTimeRangeEndHourStep => '종료 시';

  @override
  String get exTimeRangeEndMinuteStep => '종료 분';

  @override
  String get exSlotAm => '오전';

  @override
  String get exSlotPm => '오후';

  @override
  String get exTimeRangeInvalidEnd => '종료 시간이 시작 시간보다 빠릅니다';

  @override
  String get exTimeRangePrevStep => '이전 단계';

  @override
  String get exTimeRangeNextStep => '다음 단계';

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
  String get exDateRequired => '희망 날짜를 선택해주세요.';

  @override
  String get exTimeRequired => '희망 시간대를 선택해주세요.';

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
  String get exConsultStatusSection => '상담 요청 현황';

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
  String get exConsultAcceptedGuide => '담당 트레이너와 연결되었어요. 이제 채팅으로 상담할 수 있어요.';

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
  String get authTagline => '고혈압·당뇨 관리를 위한 AI 헬스케어';

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
  String get authOrDivider => '또는';

  @override
  String get authKakaoAction => '카카오로 시작하기';

  @override
  String get authGoogleAction => '구글로 시작하기';

  @override
  String get authMissingCredentials => '이메일과 비밀번호를 입력해 주세요';

  @override
  String get authSignInFailed => '로그인에 실패했어요. 이메일·비밀번호를 확인해 주세요';

  @override
  String get authSocialSignInFailed => '소셜 로그인에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get signUpTitle => '회원가입';

  @override
  String get signUpSubtitle => 'On-Care 계정을 만들어 건강 관리를 시작하세요';

  @override
  String get signUpNameHint => '이름';

  @override
  String get signUpPhoneHint => '전화번호';

  @override
  String get signUpPhoneHelper => '트레이너가 회원님을 확인할 때 쓰는 연락처예요';

  @override
  String get signUpPasswordHint => '비밀번호 (8자 이상)';

  @override
  String get signUpPasswordConfirmHint => '비밀번호 확인';

  @override
  String get signUpAction => '가입하고 시작하기';

  @override
  String get signUpHaveAccountQuestion => '이미 계정이 있으신가요?';

  @override
  String get signUpPasswordTooShort => '비밀번호는 8자 이상이어야 해요';

  @override
  String get signUpPasswordMismatch => '비밀번호가 일치하지 않아요';

  @override
  String get signUpPhoneInvalid => '전화번호를 4자리 이상 입력해 주세요';

  @override
  String get trainerSyncEntryLabel => '트레이너와 데이터 동기화';

  @override
  String get trainerSyncEntryHint => '6자리 코드로 담당 트레이너와 연결해요';

  @override
  String get trainerSyncTitle => '트레이너와 데이터 동기화';

  @override
  String get trainerSyncConsent => '이 코드를 입력한 트레이너가 담당이 되고, 식단·운동·건강 기록이 공유돼요.';

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
  String get signUpEmailTaken => '이미 가입된 이메일이에요. 로그인해 주세요.';

  @override
  String get signUpFailed => '회원가입에 실패했어요. 잠시 후 다시 시도해 주세요.';

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
  String get onboardHealthSubtitle =>
      '건강 관리에서 더 집중하고 싶은 항목을 선택해 주세요. (복수 선택 가능)';

  @override
  String get onboardGoalTitle => '운동 목표';

  @override
  String get onboardGoalSubtitle => '달성하고 싶은 목표를 입력해 주세요. 나중에 바꿀 수 있어요.';

  @override
  String get onboardGoalHint => '예) 3개월 안에 5km 완주';

  @override
  String get onboardOptionalTag => '(선택)';

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
  String get onboardGenderMale => '남성';

  @override
  String get onboardGenderFemale => '여성';

  @override
  String get onboardGenderOther => '기타';

  @override
  String get onboardConditionHypertension => '고혈압';

  @override
  String get onboardConditionDiabetes => '당뇨';

  @override
  String get onboardConditionDyslipidemia => '고지혈증';

  @override
  String get onboardConditionObesity => '비만';

  @override
  String get aiCoachWelcome =>
      '안녕하세요, AI 건강 코치 온이예요 🙂\n고혈압·당뇨 관리를 위한 식단·운동·혈압·혈당 무엇이든 편하게 물어보세요.';

  @override
  String get aiCoachFailure => '앗, 잠시 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get actionCancel => '취소';

  @override
  String get actionDelete => '삭제';

  @override
  String get actionEdit => '수정';

  @override
  String get actionConfirm => '확인';

  @override
  String get scheduleCategoryHospital => '병원';

  @override
  String get scheduleCategoryExercise => '운동';

  @override
  String get scheduleCategoryMeal => '식사';

  @override
  String get scheduleCategoryMedication => '약 복용';

  @override
  String get scheduleCategoryOther => '기타';

  @override
  String get eventAddTitle => '일정 추가';

  @override
  String get eventEditTitle => '일정 수정';

  @override
  String get eventTitleLabel => '일정 제목';

  @override
  String get eventTitleHint => '예: 병원 정기검진';

  @override
  String get eventDateLabel => '날짜';

  @override
  String get eventTimeLabel => '시간';

  @override
  String get eventTimeNone => '시간 없음';

  @override
  String get eventTitleRequired => '일정 제목을 입력해 주세요';

  @override
  String get eventAddFailed => '일정 추가에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get eventEditFailed => '일정 수정에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get eventSaving => '저장 중...';

  @override
  String get eventAdding => '추가 중...';

  @override
  String get eventSave => '저장하기';

  @override
  String get eventAdd => '추가하기';

  @override
  String eventClearField(String label) {
    return '$label 지우기';
  }

  @override
  String get eventDeleteTitle => '일정 삭제';

  @override
  String eventDeleteConfirm(String title) {
    return '‘$title’ 일정을 삭제할까요? 되돌릴 수 없어요.';
  }

  @override
  String get eventDeleteFailed => '일정 삭제에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get eventDeleted => '일정을 삭제했어요';

  @override
  String get eventsEmptyForDay => '이 날에는 일정이 없어요';

  @override
  String get eventAddForDay => '이 날에 일정 추가';

  @override
  String get eventTimeUnset => '시간 미정';

  @override
  String get scheduleSheetTitle => '일정 관리';

  @override
  String get eventsLoadFailed => '일정을 불러오지 못했어요';

  @override
  String get coachCardSleepTag => '수면';

  @override
  String get myHealthGoalsTitle => '건강 목표';

  @override
  String get myGoalsFocusSection => '주로 관리하고 싶은 항목';

  @override
  String get myGoalsFocusHint => '건강 관리에서 더 집중하고 싶은 항목을 골라 주세요. (복수 선택 가능)';

  @override
  String get myGoalsFocusHypertension => '고혈압';

  @override
  String get myGoalsFocusDiabetes => '당뇨';

  @override
  String get myGoalsExerciseNote => '운동 목표';

  @override
  String get myGoalsExerciseNoteHint => '예) 3개월 안에 5km 완주';

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
  String get myGoalExerciseSuggestionNote =>
      '권장: 하루 300kcal · 주 유산소 150분 · 근력 21세트 · 스트레칭 60분';

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
  String myGoalMacroSuggestionNote(int kcal) {
    return '${kcal}kcal 기준 권장 배분: 탄수화물 50% · 단백질 30% · 지방 20%';
  }

  @override
  String get myGoalMacroApplySuggestion => '권장 비율로 채우기';

  @override
  String get myGoalWorkoutCount => '주간 운동 횟수 목표 (회)';

  @override
  String get myGoalWorkoutMinutes => '주간 운동 시간 목표 (분)';

  @override
  String get myGoalWorkoutCalories => '주간 소모 칼로리 목표 (kcal)';

  @override
  String get myGoalsSaved => '건강 목표가 저장되었어요';

  @override
  String get mySettingsLoadFailed => '설정을 불러오지 못했어요';

  @override
  String get mySettingsLoadFailedBody => '지금 저장하면 기존 설정이 지워질 수 있어 편집을 잠갔어요.';

  @override
  String get myNotificationSaveFailed => '알림 설정을 저장하지 못했어요';

  @override
  String get myPointsGuideTitle => '포인트 적립 안내';

  @override
  String get myPointsDietAdd => '식단 추가';

  @override
  String get myPointsAiExercise => 'AI 추천 운동 완료';

  @override
  String get myPointsExerciseAdd => '운동 직접 추가';

  @override
  String get coachAssignedTrainer => '담당 트레이너';

  @override
  String get coachPointsTitle => '이번 코칭 포인트';

  @override
  String get coachRoutineTitle => '추천 개인운동';

  @override
  String get coachRoutineByTrainer => '트레이너 직접 추천';

  @override
  String coachRoutineAiChecked(String name) {
    return 'AI 추천 · $name 확인';
  }

  @override
  String get coachRoutineAiAuto => 'AI 자동 추천';

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
  String get coachRoutineCancel => '이 개인 운동 취소';

  @override
  String coachRoutineCancelConfirm(String name) {
    return '\'$name\'을(를) 목록에서 지울까요? 이미 수행한 기록은 그대로 남아요.';
  }

  @override
  String get coachRoutineCancelled => '개인 운동을 취소했어요';

  @override
  String get coachRoutineCancelFailed => '개인 운동을 취소하지 못했어요';

  @override
  String coachRoutineMyNote(String note) {
    return '내 피드백: $note';
  }

  @override
  String coachRoutineTrainerFeedback(String feedback) {
    return '트레이너 피드백: $feedback';
  }

  @override
  String get coachRoutineCompleteTitle => '개인운동 수행 완료';

  @override
  String get coachRoutineIntensity => '수행 강도';

  @override
  String get coachIntensityLight => '가벼움';

  @override
  String get coachIntensityModerate => '보통';

  @override
  String get coachIntensityHigh => '높음';

  @override
  String get coachRoutineNoteLabel => '피드백(선택)';

  @override
  String get coachRoutineNoteHint => '힘들었던 점이나 몸 상태를 남겨 보세요';

  @override
  String get coachRoutineSubmit => '완료 기록';

  @override
  String get coachChatWithTrainer => '트레이너와 채팅';

  @override
  String get coachTrainerLoading => '담당 트레이너를 불러오는 중이에요';

  @override
  String get coachTrainerNone => '담당 트레이너가 아직 없어요. 운동 탭에서 헬스장·트레이너를 연결해 보세요';

  @override
  String get alertCategoryReminder => '리마인더';

  @override
  String get alertCategoryHealth => '건강';

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
  String get alertSimulatedTitle => '시뮬레이션 알림';

  @override
  String get alertSimulatedBody => '지금 막 가상 푸시가 도착했어요.';

  @override
  String get alertJustNow => '방금';

  @override
  String get exPtLogTitle => '오늘 완료한 PT';

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
  String get a11yOpenCalendar => '일정 달력 열기';

  @override
  String get a11yPrevWeek => '지난 주';

  @override
  String get a11yNextWeek => '다음 주';
}
