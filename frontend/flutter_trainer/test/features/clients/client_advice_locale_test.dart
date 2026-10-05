// 회원 상세 `식단 분석`의 언어(#2299 → #2379). 운동 AI 조언은 #2329 에서 걷어냈다.
//
// `식단 분석` 문장은 로케일과 무관한 키·값으로 오고 화면이 ARB 로 그린다(#2379).
//
// - 실서버: 요청에 화면 언어를 `Accept-Language` 로 싣고, 받은 `sentences` 를 읽는다.
// - 데모: 서버 규칙을 옮긴 규칙(`diet_analysis_rules.dart`)이 같은 키를 낸다 — 서버와
//   같은지는 `diet_analysis_rules_test.dart` 가 공유 사례 파일로 본다.
// - provider 는 화면 언어가 바뀌면 다시 읽는다.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_core/network/accept_language_interceptor.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/presentation/diet_analysis_text.dart';
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

/// 음식 이름은 회원이 기록한 말 그대로라 번역하지 않는다 — 영어 문장에서 뺀다.
String _withoutFoods(String text, ClientDietAnalysis a) {
  String out = text;
  for (final ClientDietSentence s in a.sentences) {
    for (final MapEntry<String, Object> e in s.params.entries) {
      if (e.key.startsWith('food') && e.value is String) {
        out = out.replaceAll(e.value as String, '');
      }
    }
  }
  return out;
}

/// 2026-08-20(목) 13시.
final DateTime _thursday = DateTime(2026, 8, 20, 13);

class _MockDio extends Mock implements Dio {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('데모 저장소 — 시드 고객 전체', () {
    late AppDatabase db;

    setUp(() async {
      useFixedKstDate(_thursday);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: _thursday);
    });
    tearDown(() => db.close());

    test('두 언어가 같은 규칙·같은 수를 말하고, 영어엔 음식 이름 밖의 한국어가 없다', () async {
      final DriftClientRepository repo = DriftClientRepository(db);
      for (int i = 1; i <= 7; i++) {
        final String id = 'seed-client-$i';
        for (final ClientPeriod period in ClientPeriod.values) {
          final ClientDietAnalysis ko = await repo.fetchDietAdvice(
            id,
            period,
            locale: _ko,
          );
          final ClientDietAnalysis en = await repo.fetchDietAdvice(
            id,
            period,
            locale: _en,
          );
          final String where = '$id ${period.name}';
          // 문장 키는 언어와 무관하다.
          expect(en.sentences, ko.sentences, reason: where);
          expect(ko.isEmpty, isFalse, reason: where);
          final String koText = clientDietAnalysisText(_l(_ko), ko);
          final String enText = clientDietAnalysisText(_l(_en), en);
          expect(_hangul.hasMatch(koText), isTrue, reason: '$where: $koText');
          expect(
            _hangul.hasMatch(_withoutFoods(enText, en)),
            isFalse,
            reason: '$where: $enText',
          );
          expect(
            _numbers(_withoutFoods(enText, en)),
            _numbers(_withoutFoods(koText, ko)),
            reason: '$where: $koText / $enText',
          );
        }
      }
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

    test('식단 분석', () async {
      final _RecordingRepository repo = _RecordingRepository(db);
      final ProviderContainer c = container(repo);
      final ClientDietAdviceKey key = clientDietAdviceKey(
        'seed-client-1',
        ClientPeriod.today,
      );
      final ProviderSubscription<AsyncValue<ClientDietAnalysis>> sub = c.listen(
        clientDietAdviceProvider(key),
        (_, _) {},
      );
      addTearDown(sub.close);

      await c.read(clientDietAdviceProvider(key).future);
      expect(repo.dietLocales, <Locale>[_ko]);

      await c
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.english);
      await c.read(clientDietAdviceProvider(key).future);
      expect(repo.dietLocales, <Locale>[_ko, _en]);
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
        clientDietAdviceProvider(
          clientDietAdviceKey('seed-client-2', ClientPeriod.week),
        ).future,
      );
      expect(repo.dietLocales.single.languageCode, 'en');
    });
  });

  group('실서버 저장소 — 요청에 언어를 싣고 문장 키를 읽는다', () {
    late _MockDio dio;
    late DioClientRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioClientRepository(dio);
    });

    void answer(String path, Map<String, Object?> data) {
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
          data: data,
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

    const Map<String, Object?> serverBody = <String, Object?>{
      'message': '이번 주 식단 기록이 아직 없어요.',
      'sentences': <Object?>[
        <String, Object?>{
          'key': 'tr_week_over',
          'params': <String, Object?>{
            'scope': 'this',
            'logged': 4,
            'days': 3,
            'nutrient': 'sodium',
          },
        },
      ],
    };

    for (final (Locale locale, String header) in <(Locale, String)>[
      (_ko, 'ko'),
      (_en, 'en'),
      (const Locale('en', 'US'), 'en'),
    ]) {
      test('식단 분석 — $locale → $header', () async {
        const String path = '/trainer/clients/m1/diet-advice';
        answer(path, serverBody);
        final ClientDietAnalysis a = await repo.fetchDietAdvice(
          'm1',
          ClientPeriod.week,
          locale: locale,
        );
        expect(a.sentences, const <ClientDietSentence>[
          ClientDietSentence('tr_week_over', <String, Object>{
            'scope': 'this',
            'logged': 4,
            'days': 3,
            'nutrient': 'sodium',
          }),
        ]);
        expect(
          sentOptions(path).headers?[AcceptLanguageInterceptor.headerName],
          header,
        );
      });
    }

    test('기간 이름은 언어와 상관없이 서버 이름이다', () async {
      const String path = '/trainer/clients/m1/diet-advice';
      answer(path, const <String, Object?>{});
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

    test('문장이 없으면 빈 분석 — 카드를 세우지 않는다', () async {
      const String path = '/trainer/clients/m1/diet-advice';
      answer(path, const <String, Object?>{'message': '옛 서버 문장'});
      expect(
        (await repo.fetchDietAdvice(
          'm1',
          ClientPeriod.today,
          locale: _en,
        )).isEmpty,
        isTrue,
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

    testWidgets('영어 화면의 식단 분석은 영어 제목·문장이다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        locale: _en,
        seedClock: _thursday,
      );
      await tester.scrollUntilVisible(
        find.text('Diet analysis'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('Diet analysis'), findsOneWidget);
      expect(find.text('식단 분석'), findsNothing);
    });

    testWidgets('한국어 화면의 식단 분석은 한국어 제목이다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        seedClock: _thursday,
      );
      await tester.scrollUntilVisible(
        find.text('식단 분석'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('식단 분석'), findsOneWidget);
      expect(find.text('Diet analysis'), findsNothing);
    });
  });
}

/// 분석을 부를 때 받은 언어를 적어 두는 데모 저장소.
class _RecordingRepository extends DriftClientRepository {
  _RecordingRepository(super.db);

  final List<Locale> dietLocales = <Locale>[];

  @override
  Future<ClientDietAnalysis> fetchDietAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  }) {
    dietLocales.add(locale);
    return super.fetchDietAdvice(clientId, period, locale: locale);
  }
}

/// 테스트가 정한 '브라우저 언어'.
class _FixedPlatformLocales extends PlatformLocalesNotifier {
  _FixedPlatformLocales(List<Locale> locales) {
    state = locales;
  }
}
