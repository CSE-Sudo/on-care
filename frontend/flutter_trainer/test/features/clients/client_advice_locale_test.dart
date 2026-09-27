// 회원 상세 식단·운동 AI 조언의 언어(#2299).
//
// 트레이너웹은 서버 조언 문장을 그대로 보여 준다. 영어 화면에서도 한국어로만
// 나오던 조언을 화면 언어로 맞춘다.
//
// - 실서버: 조언 요청에 화면 언어를 `Accept-Language` 로 싣는다.
// - 데모: 서버 규칙을 흉내 내는 문장을 ARB 번역으로 만든다. 한국어 번역은
//   예전에 코드에 박혀 있던 문장과 **글자까지 같다**(아래 `_legacy…` 가 그 문장).
// - provider 는 화면 언어가 바뀌면 조언을 다시 읽는다.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/interceptors/accept_language_interceptor.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

const Locale _ko = Locale('ko');
const Locale _en = Locale('en');
final RegExp _hangul = RegExp('[가-힣]');
final RegExp _digits = RegExp(r'\d+');

AppLocalizations _l(Locale locale) => lookupAppLocalizations(locale);

/// 문장 속 수를 모은다 — 언어가 바뀌어도 같은 규칙이면 같은 수를 말한다.
List<String> _numbers(String text) =>
    _digits.allMatches(text).map((Match m) => m.group(0)!).toList()..sort();

// ---------------------------------------------------------------------------
// 예전 데모 문장 — 이 PR 전에 client_repository.dart 에 박혀 있던 그대로다.
// ---------------------------------------------------------------------------

String _legacyTodayOver(int over) =>
    '나트륨이 목표치를 ${over}mg 초과했어요. '
    '오늘 운동 프로그램에 유산소를 추가하면 도움이 돼요.';
const String _legacyTodayBalanced = '오늘 식단은 균형이 잘 맞아요. 현재 프로그램을 유지하세요.';
const String _legacyWeekEmpty = '이번 주 식단 기록이 아직 없어요. 한 끼만 남겨도 흐름이 보여요.';
const String _legacyAllEmpty = '기록이 쌓이면 나트륨·칼로리 흐름을 짚어 드릴게요.';
String _legacyWeekManyOver(int over) =>
    '이번 주 $over일이나 나트륨을 넘겼어요. 국물은 건더기 위주로 드세요.';
const String _legacyWeekWeekend = '주중엔 잘 지키다 주말에 나트륨이 올라요. 주말 외식은 한 끼만 정해요.';
String _legacyWeekSomeOver(int over) =>
    '이번 주 $over일만 권장량을 넘었어요. 나머지 날의 균형은 좋았어요.';
String _legacyWeekAllUnder(int days) => '이번 주 $days일 모두 나트륨을 권장량 안에서 지켰어요!';
String _legacyAllWeekend(int weeks) =>
    '최근 $weeks주 주말마다 나트륨이 올라요. 주말 한 끼만 담백하게 바꿔요.';
String _legacyAllRatio(int weeks, int pct) =>
    '최근 $weeks주 중 $pct%가 '
    '나트륨 권장량을 넘었어요. 국물부터 남겨 봐요.';
String _legacyAllMostlyUnder(int weeks, int days) =>
    '최근 $weeks주 기록한 $days일 대부분이 권장량 안이에요. '
    '지금 흐름이 좋아요.';
const String _legacyExWeekEmpty = '이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';
const String _legacyExAllEmpty = '기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.';
const String _legacyExTodayEmpty = '오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';
String _legacyExToday(String label, int minutes, int calories) =>
    '오늘 $label 위주로 $minutes분, '
    '${calories}kcal 썼어요. 스트레칭으로 마무리해요.';
String _legacyExOneDay(int minutes) =>
    '이번 주는 $minutes분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.';
String _legacyExCardioSkew(int days, int minutes) =>
    '이번 주 $days일 $minutes분이 유산소에 몰렸어요. '
    '근력도 섞어 볼까요?';
String _legacyExStrengthSkew(int days, int minutes) =>
    '이번 주 $days일 $minutes분이 근력에 몰렸어요. '
    '유산소도 섞어 볼까요?';
String _legacyExBalanced(int days, int minutes) =>
    '이번 주 $days일 $minutes분, 유형도 고르게 섞였어요.';
const String _legacyExAllUp = '최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요.';
const String _legacyExAllDown = '최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요.';
String _legacyExSteady(int days, int minutes) =>
    '12주 동안 $days일 $minutes분, 기복 없이 이어가고 있어요.';

// ---------------------------------------------------------------------------
// 합성 데이터로 규칙의 모든 갈래를 여는 데모 저장소
// ---------------------------------------------------------------------------

/// 식단 기간(이번 주·전체)과 운동 주간을 테스트가 준 값으로 돌려준다.
class _ScriptedRepository extends DriftClientRepository {
  _ScriptedRepository(
    super.db, {
    this.dietDays = const <ClientDietDay>[],
    this.exercise = const <String, _Ex>{},
  });

  final List<ClientDietDay> dietDays;

  /// `yyyy-MM-dd` → 그날 운동.
  final Map<String, _Ex> exercise;

  @override
  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  ) async => ClientDietPeriod(range: range, days: dietDays);

  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) async {
    final DateTime monday = weekStart!;
    List<int> pick(int Function(_Ex) f) => <int>[
      for (int d = 0; d < 7; d++)
        f(
          exercise[_ymd(DateTime(monday.year, monday.month, monday.day + d))] ??
              const _Ex(),
        ),
    ];
    final List<int> minutes = pick((_Ex e) => e.total);
    return ClientExerciseWeek(
      dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
      dailyMinutes: minutes,
      dailyCalories: pick((_Ex e) => e.total * 7),
      totalMinutes: minutes.fold<int>(0, (int a, int b) => a + b),
      totalCalories: minutes.fold<int>(0, (int a, int b) => a + b * 7),
      cardioMinutes: pick((_Ex e) => e.cardio),
      strengthMinutes: pick((_Ex e) => e.strength),
      stretchingMinutes: pick((_Ex e) => e.stretching),
      otherMinutes: pick((_Ex e) => e.other),
    );
  }
}

class _Ex {
  const _Ex({
    this.cardio = 0,
    this.strength = 0,
    this.stretching = 0,
    this.other = 0,
  });

  final int cardio;
  final int strength;
  final int stretching;
  final int other;

  int get total => cardio + strength + stretching + other;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 2026-08-20(목) — 주중이라 `이번 주` 가 주말 분기로 먼저 빠지지 않는다.
final DateTime _thursday = DateTime(2026, 8, 20, 13);

DateTime _daysAgo(int n) =>
    DateTime(_thursday.year, _thursday.month, _thursday.day - n);

ClientDietDay _diet(int back, int sodium) =>
    ClientDietDay(date: _daysAgo(back), calories: 1800, sodiumMg: sodium);

class _MockDio extends Mock implements Dio {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ARB — 한국어는 예전 데모 문장 그대로', () {
    final AppLocalizations ko = _l(_ko);

    test('식단 조언', () {
      for (final int n in <int>[0, 1, 2, 3, 12, 250, 1840]) {
        expect(ko.clientDietAdviceTodayOver(n), _legacyTodayOver(n));
        expect(ko.clientDietAdviceWeekManyOver(n), _legacyWeekManyOver(n));
        expect(ko.clientDietAdviceWeekSomeOver(n), _legacyWeekSomeOver(n));
        expect(ko.clientDietAdviceWeekAllUnder(n), _legacyWeekAllUnder(n));
        expect(ko.clientDietAdviceAllWeekend(n), _legacyAllWeekend(n));
        expect(ko.clientDietAdviceAllRatio(12, n), _legacyAllRatio(12, n));
        expect(
          ko.clientDietAdviceAllMostlyUnder(12, n),
          _legacyAllMostlyUnder(12, n),
        );
      }
      expect(ko.clientDietAdviceTodayBalanced, _legacyTodayBalanced);
      expect(ko.clientDietAdviceWeekEmpty, _legacyWeekEmpty);
      expect(ko.clientDietAdviceAllEmpty, _legacyAllEmpty);
      expect(ko.clientDietAdviceWeekWeekend, _legacyWeekWeekend);
    });

    test('운동 조언', () {
      const Map<String, String> labels = <String, String>{
        'cardio': '유산소',
        'strength': '근력',
        'stretching': '스트레칭',
        'other': '기타',
      };
      for (final MapEntry<String, String> e in labels.entries) {
        expect(
          ko.clientExerciseAdviceToday(e.key, 45, 310),
          _legacyExToday(e.value, 45, 310),
        );
      }
      for (final int n in <int>[1, 2, 7, 60]) {
        expect(ko.clientExerciseAdviceWeekOneDay(n), _legacyExOneDay(n));
        expect(
          ko.clientExerciseAdviceWeekSkew(n, 90, 'cardio', 'strength'),
          _legacyExCardioSkew(n, 90),
        );
        expect(
          ko.clientExerciseAdviceWeekSkew(n, 90, 'strength', 'cardio'),
          _legacyExStrengthSkew(n, 90),
        );
        expect(
          ko.clientExerciseAdviceWeekBalanced(n, 90),
          _legacyExBalanced(n, 90),
        );
        expect(
          ko.clientExerciseAdviceAllSteady(12, n, 90),
          _legacyExSteady(n, 90),
        );
      }
      expect(ko.clientExerciseAdviceEmptyToday, _legacyExTodayEmpty);
      expect(ko.clientExerciseAdviceEmptyWeek, _legacyExWeekEmpty);
      expect(ko.clientExerciseAdviceEmptyAll, _legacyExAllEmpty);
      expect(ko.clientExerciseAdviceAllUp, _legacyExAllUp);
      expect(ko.clientExerciseAdviceAllDown, _legacyExAllDown);
    });
  });

  group('ARB — 영어', () {
    final AppLocalizations en = _l(_en);

    test('식단 조언은 서버 영어 문장과 같은 말투다', () {
      expect(
        en.clientDietAdviceTodayOver(640),
        'Sodium is 640mg over the target. '
        "Adding cardio to today's program would help.",
      );
      expect(
        en.clientDietAdviceTodayBalanced,
        "Today's meals are well balanced. Keep the current program.",
      );
      expect(
        en.clientDietAdviceWeekEmpty,
        'No meals logged this week yet. Even one meal shows the trend.',
      );
      expect(
        en.clientDietAdviceAllEmpty,
        "Once you log more, we'll show how your sodium and calories are trending.",
      );
      expect(
        en.clientDietAdviceWeekManyOver(4),
        'Sodium went over on 4 days this week. '
        'With soups, eat the solids and leave the broth.',
      );
      expect(
        en.clientDietAdviceWeekWeekend,
        'Sodium stays in check on weekdays but rises on weekends. '
        'Limit eating out to one weekend meal.',
      );
      expect(
        en.clientDietAdviceAllWeekend(12),
        'Over the last 12 weeks, sodium rises every weekend. '
        'Make one weekend meal lighter.',
      );
      expect(
        en.clientDietAdviceAllRatio(12, 45),
        '45% of days in the last 12 weeks went over the sodium limit. '
        'Start by leaving the broth.',
      );
    });

    test('식단 조언 단·복수', () {
      expect(
        en.clientDietAdviceWeekSomeOver(1),
        'Only 1 day went over the sodium limit this week. '
        'The other days were well balanced.',
      );
      expect(
        en.clientDietAdviceWeekSomeOver(2),
        'Only 2 days went over the sodium limit this week. '
        'The other days were well balanced.',
      );
      expect(
        en.clientDietAdviceWeekAllUnder(1),
        'You kept sodium within the limit on the 1 day you logged this week!',
      );
      expect(
        en.clientDietAdviceWeekAllUnder(5),
        'You kept sodium within the limit on all 5 days this week!',
      );
      expect(
        en.clientDietAdviceAllMostlyUnder(12, 1),
        'Your 1 logged day in the last 12 weeks stayed within the sodium '
        'limit. Nice trend.',
      );
      expect(
        en.clientDietAdviceAllMostlyUnder(12, 30),
        'Most of your 30 logged days in the last 12 weeks stayed within the '
        'sodium limit. Nice trend.',
      );
    });

    test('운동 조언은 회원 앱 영어 조언과 같은 문장이다', () {
      expect(
        en.clientExerciseAdviceEmptyToday,
        'No workout logged today yet. How about a 10-minute walk to start?',
      );
      expect(
        en.clientExerciseAdviceEmptyWeek,
        'No workouts logged this week yet. How about a 10-minute walk to start?',
      );
      expect(
        en.clientExerciseAdviceEmptyAll,
        "Once you log more, we'll show how your workout volume and types are "
        'trending.',
      );
      expect(
        en.clientExerciseAdviceToday('cardio', 30, 210),
        'Today: 30 min and 210 kcal, mostly cardio. Wrap up with a stretch.',
      );
      expect(
        en.clientExerciseAdviceToday('other', 30, 210),
        'Today: 30 min and 210 kcal, mostly other exercise. '
        'Wrap up with a stretch.',
      );
      expect(
        en.clientExerciseAdviceWeekOneDay(40),
        'Just one day this week (40 min). One more session keeps the flow '
        'going.',
      );
      expect(
        en.clientExerciseAdviceWeekSkew(2, 60, 'cardio', 'strength'),
        "This week's 2 days and 60 min leaned on cardio. "
        'Mix in some strength?',
      );
      expect(
        en.clientExerciseAdviceWeekBalanced(1, 30),
        '1 day and 30 min this week, with a good mix of types.',
      );
      expect(
        en.clientExerciseAdviceWeekBalanced(3, 90),
        '3 days and 90 min this week, with a good mix of types.',
      );
      expect(
        en.clientExerciseAdviceAllUp,
        "You've done more over the last 4 weeks than before. "
        'This approach suits you.',
      );
      expect(
        en.clientExerciseAdviceAllDown,
        'Your last 4 weeks are trending down. '
        'Try to keep 3 days a week, even short ones.',
      );
      expect(
        en.clientExerciseAdviceAllSteady(12, 20, 600),
        '20 days and 600 min over 12 weeks — nice and steady.',
      );
      expect(
        en.clientExerciseAdviceAllSteady(1, 1, 30),
        '1 day and 30 min over 1 week — nice and steady.',
      );
    });

    test('영어 문장에 한국어가 남지 않는다', () {
      final List<String> all = <String>[
        en.clientDietAdviceTodayOver(1),
        en.clientDietAdviceTodayBalanced,
        en.clientDietAdviceWeekEmpty,
        en.clientDietAdviceAllEmpty,
        en.clientDietAdviceWeekManyOver(3),
        en.clientDietAdviceWeekWeekend,
        en.clientDietAdviceWeekSomeOver(1),
        en.clientDietAdviceWeekAllUnder(2),
        en.clientDietAdviceAllWeekend(12),
        en.clientDietAdviceAllRatio(12, 40),
        en.clientDietAdviceAllMostlyUnder(12, 3),
        en.clientExerciseAdviceEmptyToday,
        en.clientExerciseAdviceEmptyWeek,
        en.clientExerciseAdviceEmptyAll,
        for (final String t in <String>[
          'cardio',
          'strength',
          'stretching',
          'other',
        ])
          en.clientExerciseAdviceToday(t, 10, 70),
        en.clientExerciseAdviceWeekOneDay(10),
        en.clientExerciseAdviceWeekSkew(2, 60, 'strength', 'cardio'),
        en.clientExerciseAdviceWeekBalanced(2, 60),
        en.clientExerciseAdviceAllUp,
        en.clientExerciseAdviceAllDown,
        en.clientExerciseAdviceAllSteady(12, 2, 60),
      ];
      for (final String text in all) {
        expect(_hangul.hasMatch(text), isFalse, reason: text);
        expect(text, isNot(contains('{')), reason: text);
      }
    });
  });

  group('데모 저장소 — 식단 조언의 갈래마다 두 언어', () {
    late AppDatabase db;

    setUp(() {
      useFixedKstDate(_thursday);
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    Future<(String, String)> both(
      List<ClientDietDay> days,
      ClientPeriod period,
    ) async {
      final _ScriptedRepository repo = _ScriptedRepository(db, dietDays: days);
      return (
        await repo.fetchDietAdvice('c', period, locale: _ko),
        await repo.fetchDietAdvice('c', period, locale: _en),
      );
    }

    final Map<String, (List<ClientDietDay>, ClientPeriod, String, String)>
    cases = <String, (List<ClientDietDay>, ClientPeriod, String, String)>{
      '이번 주 기록 없음': (
        const <ClientDietDay>[],
        ClientPeriod.week,
        _legacyWeekEmpty,
        'No meals logged this week yet. Even one meal shows the trend.',
      ),
      '전체 기록 없음': (
        const <ClientDietDay>[],
        ClientPeriod.month,
        _legacyAllEmpty,
        "Once you log more, we'll show how your sodium and calories are trending.",
      ),
      '이번 주 사흘 넘김': (
        <ClientDietDay>[_diet(3, 3000), _diet(2, 3000), _diet(1, 3000)],
        ClientPeriod.week,
        _legacyWeekManyOver(3),
        'Sodium went over on 3 days this week. '
            'With soups, eat the solids and leave the broth.',
      ),
      '이번 주 하루 넘김': (
        <ClientDietDay>[_diet(2, 3000), _diet(1, 1000)],
        ClientPeriod.week,
        _legacyWeekSomeOver(1),
        'Only 1 day went over the sodium limit this week. '
            'The other days were well balanced.',
      ),
      '이번 주 모두 지킴': (
        <ClientDietDay>[_diet(2, 1000), _diet(1, 1200)],
        ClientPeriod.week,
        _legacyWeekAllUnder(2),
        'You kept sodium within the limit on all 2 days this week!',
      ),
      '이번 주 주말만 높음': (
        // 8/15(토)·8/16(일) 이 높고 평일은 낮다.
        <ClientDietDay>[
          _diet(5, 1900),
          _diet(4, 1900),
          _diet(3, 800),
          _diet(2, 800),
        ],
        ClientPeriod.week,
        _legacyWeekWeekend,
        'Sodium stays in check on weekdays but rises on weekends. '
            'Limit eating out to one weekend meal.',
      ),
      '전체 넘긴 날 비율': (
        <ClientDietDay>[
          // 8/14(금)~8/20(목) 중 평일만 — 주말 분기로 빠지지 않게.
          _diet(6, 1000),
          _diet(3, 3000),
          _diet(2, 3000),
          _diet(1, 1000),
          _diet(0, 1000),
        ],
        ClientPeriod.month,
        _legacyAllRatio(12, 40),
        '40% of days in the last 12 weeks went over the sodium limit. '
            'Start by leaving the broth.',
      ),
      '전체 대부분 지킴': (
        <ClientDietDay>[_diet(2, 3000), _diet(1, 1000), _diet(0, 1000)],
        ClientPeriod.month,
        _legacyAllMostlyUnder(12, 3),
        'Most of your 3 logged days in the last 12 weeks stayed within the '
            'sodium limit. Nice trend.',
      ),
      '전체 주말마다 높음': (
        <ClientDietDay>[_diet(5, 1900), _diet(4, 1900), _diet(1, 800)],
        ClientPeriod.month,
        _legacyAllWeekend(12),
        'Over the last 12 weeks, sodium rises every weekend. '
            'Make one weekend meal lighter.',
      ),
    };

    cases.forEach((
      String name,
      (List<ClientDietDay>, ClientPeriod, String, String) c,
    ) {
      test(name, () async {
        final (String ko, String en) = await both(c.$1, c.$2);
        expect(ko, c.$3);
        expect(en, c.$4);
      });
    });

    test('오늘 끼니가 없으면 균형 문장 — 두 언어', () async {
      final _ScriptedRepository repo = _ScriptedRepository(db);
      expect(
        await repo.fetchDietAdvice('c', ClientPeriod.today, locale: _ko),
        _legacyTodayBalanced,
      );
      expect(
        await repo.fetchDietAdvice('c', ClientPeriod.today, locale: _en),
        "Today's meals are well balanced. Keep the current program.",
      );
    });
  });

  group('데모 저장소 — 운동 조언의 갈래마다 두 언어', () {
    late AppDatabase db;

    setUp(() {
      useFixedKstDate(_thursday);
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    Future<(String, String)> both(
      Map<String, _Ex> exercise,
      ClientPeriod period,
    ) async {
      final _ScriptedRepository repo = _ScriptedRepository(
        db,
        exercise: exercise,
      );
      return (
        await repo.fetchExerciseAdvice('c', period, locale: _ko),
        await repo.fetchExerciseAdvice('c', period, locale: _en),
      );
    }

    String day(int back) => _ymd(_daysAgo(back));

    test('기록 없음 — 기간마다', () async {
      expect(await both(const <String, _Ex>{}, ClientPeriod.today), (
        _legacyExTodayEmpty,
        'No workout logged today yet. How about a 10-minute walk to start?',
      ));
      expect(await both(const <String, _Ex>{}, ClientPeriod.week), (
        _legacyExWeekEmpty,
        'No workouts logged this week yet. How about a 10-minute walk to start?',
      ));
      expect(await both(const <String, _Ex>{}, ClientPeriod.month), (
        _legacyExAllEmpty,
        "Once you log more, we'll show how your workout volume and types are "
            'trending.',
      ));
    });

    test('오늘 — 가장 오래 한 유형을 두 언어로', () async {
      expect(
        await both(<String, _Ex>{
          day(0): const _Ex(strength: 40, cardio: 10),
        }, ClientPeriod.today),
        (
          _legacyExToday('근력', 50, 350),
          'Today: 50 min and 350 kcal, mostly strength. Wrap up with a stretch.',
        ),
      );
      expect(
        await both(<String, _Ex>{
          day(0): const _Ex(stretching: 20),
        }, ClientPeriod.today),
        (
          _legacyExToday('스트레칭', 20, 140),
          'Today: 20 min and 140 kcal, mostly stretching. '
              'Wrap up with a stretch.',
        ),
      );
      expect(
        await both(<String, _Ex>{
          day(0): const _Ex(other: 15),
        }, ClientPeriod.today),
        (
          _legacyExToday('기타', 15, 105),
          'Today: 15 min and 105 kcal, mostly other exercise. '
              'Wrap up with a stretch.',
        ),
      );
    });

    test('이번 주 — 하루뿐', () async {
      expect(
        await both(<String, _Ex>{
          day(1): const _Ex(cardio: 40),
        }, ClientPeriod.week),
        (
          _legacyExOneDay(40),
          'Just one day this week (40 min). '
              'One more session keeps the flow going.',
        ),
      );
    });

    test('이번 주 — 유산소 쏠림·근력 쏠림·고르게', () async {
      expect(
        await both(<String, _Ex>{
          day(2): const _Ex(cardio: 30),
          day(1): const _Ex(cardio: 30),
        }, ClientPeriod.week),
        (
          _legacyExCardioSkew(2, 60),
          "This week's 2 days and 60 min leaned on cardio. "
              'Mix in some strength?',
        ),
      );
      expect(
        await both(<String, _Ex>{
          day(2): const _Ex(strength: 45),
          day(1): const _Ex(strength: 45),
        }, ClientPeriod.week),
        (
          _legacyExStrengthSkew(2, 90),
          "This week's 2 days and 90 min leaned on strength. "
              'Mix in some cardio?',
        ),
      );
      expect(
        await both(<String, _Ex>{
          day(2): const _Ex(cardio: 30),
          day(1): const _Ex(strength: 30),
        }, ClientPeriod.week),
        (
          _legacyExBalanced(2, 60),
          '2 days and 60 min this week, with a good mix of types.',
        ),
      );
    });

    test('전체 — 꾸준하다', () async {
      // 데모의 `전체` 운동 구간은 이번 주 월요일부터다(`clientRangeFor`) —
      // 4주 전과 견주는 늘었다·줄었다 문장은 ARB 테스트가 두 언어로 본다.
      final Map<String, _Ex> steady = <String, _Ex>{
        for (int b = 0; b < 3; b++) day(b): const _Ex(cardio: 20),
      };
      expect(await both(steady, ClientPeriod.month), (
        _legacyExSteady(3, 60),
        '3 days and 60 min over 12 weeks — nice and steady.',
      ));
    });
  });

  group('데모 저장소 — 시드 고객 전체', () {
    late AppDatabase db;

    setUp(() async {
      useFixedKstDate(_thursday);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: _thursday);
    });
    tearDown(() => db.close());

    test('두 언어가 같은 규칙·같은 수를 말하고, 영어엔 한국어가 없다', () async {
      final DriftClientRepository repo = DriftClientRepository(db);
      final List<String> ids = <String>[
        for (int i = 1; i <= 7; i++) 'seed-client-$i',
      ];
      for (final String id in ids) {
        for (final ClientPeriod period in ClientPeriod.values) {
          for (final bool diet in <bool>[true, false]) {
            final String ko = diet
                ? await repo.fetchDietAdvice(id, period, locale: _ko)
                : await repo.fetchExerciseAdvice(id, period, locale: _ko);
            final String en = diet
                ? await repo.fetchDietAdvice(id, period, locale: _en)
                : await repo.fetchExerciseAdvice(id, period, locale: _en);
            final String where = '$id ${period.name} ${diet ? '식단' : '운동'}';
            expect(_hangul.hasMatch(ko), isTrue, reason: '$where: $ko');
            expect(_hangul.hasMatch(en), isFalse, reason: '$where: $en');
            expect(_numbers(en), _numbers(ko), reason: '$where: $ko / $en');
          }
        }
      }
    });

    test('김민수 오늘 식단 — 넘긴 양을 두 언어가 같게 말한다', () async {
      final DriftClientRepository repo = DriftClientRepository(db);
      final String ko = await repo.fetchDietAdvice(
        'seed-client-1',
        ClientPeriod.today,
        locale: _ko,
      );
      final String en = await repo.fetchDietAdvice(
        'seed-client-1',
        ClientPeriod.today,
        locale: _en,
      );
      expect(ko, startsWith('나트륨이 목표치를 '));
      expect(en, startsWith('Sodium is '));
      expect(en, endsWith("Adding cardio to today's program would help."));
      expect(_numbers(en), _numbers(ko));
    });

    test('지원하지 않는 언어 코드는 영어 번역으로 떨어지지 않고 오류를 낸다', () {
      // lookupAppLocalizations 는 지원 언어만 받는다 — provider 는 항상
      // 해석된 지원 언어(`trainerResolvedLocaleProvider`)를 넘긴다.
      expect(
        () => DriftClientRepository(db).fetchDietAdvice(
          'seed-client-1',
          ClientPeriod.today,
          locale: const Locale('fr'),
        ),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  group('provider — 화면 언어를 넘기고, 바뀌면 다시 읽는다', () {
    late AppDatabase db;

    setUp(() async {
      useFixedKstDate(_thursday);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: _thursday);
    });
    tearDown(() => db.close());

    ProviderContainer container(_RecordingRepository repo) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          clientRepositoryProvider.overrideWithValue(repo),
          platformLocalesProvider.overrideWith(
            (ref) => _FixedPlatformLocales(const <Locale>[_ko]),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('식단 조언', () async {
      final _RecordingRepository repo = _RecordingRepository(db);
      final ProviderContainer c = container(repo);
      const ({String clientId, ClientPeriod period}) key = (
        clientId: 'seed-client-1',
        period: ClientPeriod.today,
      );
      final ProviderSubscription<AsyncValue<String>> sub = c.listen(
        clientDietAdviceProvider(key),
        (_, _) {},
      );
      addTearDown(sub.close);

      final String ko = await c.read(clientDietAdviceProvider(key).future);
      expect(ko, startsWith('나트륨이 목표치를'));
      expect(repo.dietLocales, <Locale>[_ko]);

      await c
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.english);
      final String en = await c.read(clientDietAdviceProvider(key).future);
      expect(en, startsWith('Sodium is '));
      expect(repo.dietLocales, <Locale>[_ko, _en]);
    });

    test('운동 조언', () async {
      final _RecordingRepository repo = _RecordingRepository(db);
      final ProviderContainer c = container(repo);
      const ({String clientId, ClientPeriod period}) key = (
        clientId: 'seed-client-7',
        period: ClientPeriod.week,
      );
      final ProviderSubscription<AsyncValue<String>> sub = c.listen(
        clientExerciseAdviceProvider(key),
        (_, _) {},
      );
      addTearDown(sub.close);

      await c.read(clientExerciseAdviceProvider(key).future);
      expect(repo.exerciseLocales, <Locale>[_ko]);

      await c
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.english);
      final String en = await c.read(clientExerciseAdviceProvider(key).future);
      expect(_hangul.hasMatch(en), isFalse, reason: en);
      expect(repo.exerciseLocales, <Locale>[_ko, _en]);
    });

    test('고른 언어가 없으면 브라우저 언어를 따른다', () async {
      final _RecordingRepository repo = _RecordingRepository(db);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          clientRepositoryProvider.overrideWithValue(repo),
          platformLocalesProvider.overrideWith(
            (ref) => _FixedPlatformLocales(const <Locale>[Locale('en', 'US')]),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(
        clientDietAdviceProvider((
          clientId: 'seed-client-2',
          period: ClientPeriod.week,
        )).future,
      );
      expect(repo.dietLocales.single.languageCode, 'en');
    });
  });

  group('실서버 저장소 — 조언 요청에 언어를 싣는다', () {
    late _MockDio dio;
    late DioClientRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioClientRepository(dio);
    });

    void answer(String path, String message) {
      when(
        () => dio.get<Map<String, Object?>>(
          path,
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: <String, Object?>{'message': message},
        ),
      );
    }

    Options sentOptions(String path) {
      final VerificationResult result = verify(
        () => dio.get<Map<String, Object?>>(
          path,
          queryParameters: any(named: 'queryParameters'),
          options: captureAny(named: 'options'),
        ),
      );
      return result.captured.last as Options;
    }

    for (final (Locale locale, String header) in <(Locale, String)>[
      (_ko, 'ko'),
      (_en, 'en'),
      (const Locale('en', 'US'), 'en'),
    ]) {
      test('식단 조언 — $locale → $header', () async {
        const String path = '/trainer/clients/m1/diet-advice';
        answer(path, 'server says');
        expect(
          await repo.fetchDietAdvice('m1', ClientPeriod.week, locale: locale),
          'server says',
        );
        expect(
          sentOptions(path).headers?[AcceptLanguageInterceptor.headerName],
          header,
        );
      });

      test('운동 조언 — $locale → $header', () async {
        const String path = '/trainer/clients/m1/exercise-advice';
        answer(path, 'server says');
        expect(
          await repo.fetchExerciseAdvice(
            'm1',
            ClientPeriod.month,
            locale: locale,
          ),
          'server says',
        );
        expect(
          sentOptions(path).headers?[AcceptLanguageInterceptor.headerName],
          header,
        );
      });
    }

    test('기간 이름은 언어와 상관없이 서버 이름이다', () async {
      const String path = '/trainer/clients/m1/diet-advice';
      answer(path, '');
      await repo.fetchDietAdvice('m1', ClientPeriod.month, locale: _en);
      final VerificationResult result = verify(
        () => dio.get<Map<String, Object?>>(
          path,
          queryParameters: captureAny(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      );
      expect(result.captured.single, <String, Object?>{'period': 'all'});
    });

    test('메시지가 없으면 빈 문장 — 카드를 세우지 않는다', () async {
      const String path = '/trainer/clients/m1/exercise-advice';
      when(
        () => dio.get<Map<String, Object?>>(
          path,
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: <String, Object?>{},
        ),
      );
      expect(
        await repo.fetchExerciseAdvice('m1', ClientPeriod.today, locale: _en),
        '',
      );
    });

    test('실패는 AppError 로 — 언어를 실어도 오류 경로는 같다', () async {
      const String path = '/trainer/clients/m1/diet-advice';
      when(
        () => dio.get<Map<String, Object?>>(
          path,
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: path),
            statusCode: 404,
          ),
        ),
      );
      await expectLater(
        repo.fetchDietAdvice('m1', ClientPeriod.today, locale: _en),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('회원 상세 화면', () {
    Finder detailScrollable(String clientId) => find
        .descendant(
          of: find.byKey(ValueKey<String>('client-detail-tabs-$clientId')),
          matching: find.byType(Scrollable),
        )
        .first;

    testWidgets('영어 화면의 식단 AI 분석은 영어다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        locale: _en,
        seedClock: _thursday,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Sodium is '),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.textContaining('Sodium is '), findsOneWidget);
      expect(find.textContaining('나트륨이 목표치를'), findsNothing);
    });

    testWidgets('한국어 화면의 식단 AI 분석은 예전 문장 그대로다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        seedClock: _thursday,
      );
      await tester.scrollUntilVisible(
        find.textContaining('나트륨이 목표치를'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.textContaining('나트륨이 목표치를'), findsOneWidget);
      expect(find.textContaining('Sodium is '), findsNothing);
    });

    testWidgets('영어 화면의 운동 AI 분석은 영어다', (tester) async {
      final ProviderContainer container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
        locale: _en,
        seedClock: _thursday,
      );
      final String expected = await container.read(
        clientExerciseAdviceProvider((
          clientId: 'seed-client-1',
          period: ClientPeriod.today,
        )).future,
      );
      expect(_hangul.hasMatch(expected), isFalse, reason: expected);
      await tester.scrollUntilVisible(
        find.text(expected),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text(expected), findsOneWidget);
    });
  });
}

/// 조언을 부를 때 받은 언어를 적어 두는 데모 저장소.
class _RecordingRepository extends DriftClientRepository {
  _RecordingRepository(super.db);

  final List<Locale> dietLocales = <Locale>[];
  final List<Locale> exerciseLocales = <Locale>[];

  @override
  Future<String> fetchDietAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  }) {
    dietLocales.add(locale);
    return super.fetchDietAdvice(clientId, period, locale: locale);
  }

  @override
  Future<String> fetchExerciseAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  }) {
    exerciseLocales.add(locale);
    return super.fetchExerciseAdvice(clientId, period, locale: locale);
  }
}

/// 테스트가 정한 '브라우저 언어'.
class _FixedPlatformLocales extends PlatformLocalesNotifier {
  _FixedPlatformLocales(List<Locale> locales) {
    state = locales;
  }
}
