// 회원 상세 `식단 분석`(#2299 → #2379). 운동 AI 조언은 #2329 에서 걷어냈다.
//
// `식단 분석` 문장은 키·값으로 오고 화면이 ARB 로 그린다(#2379).
//
// - 실서버: 받은 `sentences` 를 읽는다.
// - 데모: 서버 규칙을 옮긴 규칙(`diet_analysis_rules.dart`)이 같은 키를 낸다 — 서버와
//   같은지는 `diet_analysis_rules_test.dart` 가 공유 사례 파일로 본다.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

final AppLocalizations _l = lookupAppLocalizations(const Locale('ko'));
final RegExp _hangul = RegExp('[가-힣]');

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

    test('시드 고객마다 기간별 분석이 비지 않고 한국어 문장이 된다', () async {
      final DriftClientRepository repo = DriftClientRepository(db);
      for (int i = 1; i <= 7; i++) {
        final String id = 'seed-client-$i';
        for (final ClientPeriod period in ClientPeriod.values) {
          final ClientDietAnalysis a = await repo.fetchDietAdvice(id, period);
          final String where = '$id ${period.name}';
          expect(a.isEmpty, isFalse, reason: where);
          final String text = clientDietAnalysisText(_l, a);
          expect(_hangul.hasMatch(text), isTrue, reason: '$where: $text');
        }
      }
    });
  });

  group('실서버 저장소 — 문장 키를 읽는다', () {
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

    test('식단 분석', () async {
      const String path = '/trainer/clients/m1/diet-advice';
      answer(path, serverBody);
      final ClientDietAnalysis a = await repo.fetchDietAdvice(
        'm1',
        ClientPeriod.week,
      );
      expect(a.sentences, const <ClientDietSentence>[
        ClientDietSentence('tr_week_over', <String, Object>{
          'scope': 'this',
          'logged': 4,
          'days': 3,
          'nutrient': 'sodium',
        }),
      ]);
    });

    test('기간 이름은 서버 이름이다', () async {
      const String path = '/trainer/clients/m1/diet-advice';
      answer(path, const <String, Object?>{});
      await repo.fetchDietAdvice('m1', ClientPeriod.month);
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
        (await repo.fetchDietAdvice('m1', ClientPeriod.today)).isEmpty,
        isTrue,
      );
    });

    test('실패는 AppError 로', () async {
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
        repo.fetchDietAdvice('m1', ClientPeriod.today),
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

    testWidgets('식단 분석 제목이 선다', (tester) async {
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
    });
  });
}
