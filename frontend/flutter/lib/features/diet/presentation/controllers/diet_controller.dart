import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/data/sources/image_picker_meal_photo_picker.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';

/// 식단 저장소 — 빌드와 무관하게 **항상** 네트워크 구현이다.
///
/// 데모 응답은 `LocalApiInterceptor` 가 drift 에서 만들어 준다. AI 코치가 이미 쓰는
/// 구조이고, 식단만 저장소 단에서 갈라져 있던 것이 `REAL_API=diet` 를 죽은 스위치로
/// 만들었다 — 인메모리 구현은 Dio 를 타지 않으니 인터셉터의 통과 규칙에 닿을 일이
/// 없었다(#616).
///
/// 이제 분석 요청만 실 백엔드로 흘려보낼 수 있고, 나머지 조회·수정·삭제는 그대로
/// 로컬이 답하므로 데모 화면이 움직이지 않는다.
final dietRepositoryProvider = Provider<DietRepository>((ref) {
  return DioDietRepository(ref.watch(dioProvider));
}, name: 'dietRepository');

/// Camera / photo-library access for 식단 추가. Overridden in tests to play
/// back a capture, a cancel, or a denied permission without the plugin.
final mealPhotoPickerProvider = Provider<MealPhotoPicker>((ref) {
  return ImagePickerMealPhotoPicker();
}, name: 'mealPhotoPicker');

/// 식단 추가 시트의 사진 갈래 배치 — 웹은 시스템 메뉴 하나, 네이티브는 둘.
/// 테스트가 웹 배치를 VM 에서 확인할 수 있게 provider 로 둔다. (#1433)
final mealPhotoChoiceLayoutProvider = Provider<MealPhotoChoiceLayout>((ref) {
  return MealPhotoChoiceLayout.forPlatform(isWeb: kIsWeb);
}, name: 'mealPhotoChoiceLayout');

final dietTodayProvider = FutureProvider<DietDay>((ref) {
  return ref.watch(dietRepositoryProvider).fetchToday();
}, name: 'dietToday');

/// 날짜별 식단 캐시의 원본. 화면은 [dietByDateProvider] 로 읽는다 — 이 이름은
/// **덮어쓰기용**이다(사용 가이드가 예시 하루로 갈아 끼운다, #1857). 함수는
/// override 의 대상이 될 수 없어 family 자체가 공개돼 있어야 한다.
final dietByDateFamily = FutureProvider.family<DietDay, DateTime>((ref, date) {
  return ref.watch(dietRepositoryProvider).fetchByDate(date);
}, name: 'dietByDate');

FutureProvider<DietDay> dietByDateProvider(DateTime date) {
  return dietByDateFamily(DateTime(date.year, date.month, date.day));
}

/// 기간 조회의 키. 양끝을 포함한다(from ≤ 날짜 ≤ to).
typedef DietDateRange = ({DateTime from, DateTime to});

/// 기간에 든 날짜들(양끝 포함).
///
/// 일수는 **UTC 로 환산해** 센다. 로컬 자정끼리 빼면 서머타임이 있는 지역에서
/// 3월 한 달이 29일 23시간이 되고, `inDays` 가 29 로 잘려 말일이 통째로
/// 빠진다.
List<DateTime> dietRangeDates(DietDateRange range) {
  final DateTime from = DateTime(
    range.from.year,
    range.from.month,
    range.from.day,
  );
  final DateTime to = DateTime(range.to.year, range.to.month, range.to.day);
  final int span = DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
  return <DateTime>[
    for (int i = 0; i <= span; i++)
      DateTime(from.year, from.month, from.day + i),
  ];
}

/// 이번 주·`전체` 식단 집계 — `GET /diet/days?from=&to=` **한 번**이다. (#2236)
///
/// 예전에는 하루 조회를 날짜 수만큼 모았다. `전체` 가 모든 기록을 그리게 되면서
/// (#2079) 해가 바뀐 회원에게 수백 번의 왕복이 됐다.
///
/// 하루 뷰(`오늘`)는 그대로 [dietTodayProvider]·[dietByDateProvider] 다 — 끼니
/// 목록과 사진이 필요하고, 이 응답에는 없다. 끼니를 더하거나 지울 때 비워야 할
/// 캐시가 그만큼 늘었다(`diet_flows.dart`).
final dietPeriodProvider = FutureProvider.family<DietPeriod, DietDateRange>((
  ref,
  DietDateRange range,
) {
  return ref
      .watch(dietRepositoryProvider)
      .fetchPeriod(from: range.from, to: range.to);
}, name: 'dietPeriod');

/// 기간에 맞는 식단 조언 — GET /diet/advice. (#1017)
///
/// 기간을 바꾸는 것은 "무엇을 볼지" 를 바꾸는 일이다. 그래프만 갈아 끼우고
/// 조언이 오늘 이야기로 남으면, 이번 주를 보고 있는데 "오늘 점심이 짰어요" 를
/// 읽게 된다.
///
/// 구간 경계는 서버가 정한다 — 앱이 따로 계산해 넘기지 않는다.
final dietAdviceProvider = FutureProvider.family<String, String>((
  ref,
  String period,
) async {
  return ref.watch(dietRepositoryProvider).fetchAdvice(period);
}, name: 'dietAdvice');

/// 홈 "AI 추천 식단" — GET /diet/recommendations.
///
/// 홈 진입을 막지 않는 게 요구사항이라, 소비하는 쪽은 이 provider 가 값을 내기
/// 전이나 실패했을 때 [MealRecommendations.fallback] 을 그린다. 그래서 여기서
/// 로딩/에러 상태를 따로 표현하지 않는다(스켈레톤 없음 = 화면 깜빡임 없음).
final dietRecommendationsProvider = FutureProvider<MealRecommendations>((ref) {
  return ref.watch(dietRepositoryProvider).fetchRecommendations();
}, name: 'dietRecommendations');
