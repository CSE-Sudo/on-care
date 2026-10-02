import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/app.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/ai_advice_text.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/locale_provider.dart';
import 'package:oncare_ui/oncare_ui.dart' show keepWords;

import '../../helpers/fake_dashboard_repository.dart';
import '../../helpers/fake_diet_repository.dart';

final RegExp _hangul = RegExp('[가-힣]');

/// 조언 필드만 다르게 둔 최소 요약.
DashboardSummary _summary({
  String? adviceKey,
  String? sodiumWarning,
  Map<String, Object> adviceParams = const <String, Object>{},
}) => DashboardSummary(
  indicators: const <HealthIndicator>[],
  macros: const DietMacros.zero(),
  dietEntries: 0,
  exerciseMinutes: 0,
  sodiumWarning: sodiumWarning,
  aiAdviceKey: adviceKey,
  aiAdviceParams: adviceParams,
);

/// 홈 '오늘의 AI 통합 조언'은 예전에 데모 소스가 둘(목 요약, 시드 KV)이라 한쪽만
/// 고치면 조용히 갈라졌다. 지금 데모 홈은 시드 KV 를 읽는 로컬 인터셉터 하나다
/// (#2645). 게다가 예전에는 양쪽이 한국어 **문장**을 실어
/// 보내, 홈이 그 값을 ARB 보다 우선하는 바람에 영어 로케일에서도 한국어가
/// 나왔다(#435). 이제 둘 다 키만 싣고 문장은 ARB 가 갖는다.
void main() {
  test('테스트 대역 요약도 문구가 아니라 키를 싣는다', () async {
    final DashboardSummary summary = await FakeDashboardRepository(
      FakeDietRepository(),
    ).fetchSummary();

    expect(summary.aiAdviceKey, kDailyCombinedAdviceKey);
    // 표시 문자열을 실으면 로케일과 무관하게 그 값이 이긴다.
    expect(summary.sodiumWarning, isNull);
    expect(summary.exerciseFeedback, isNull);
  });

  test('시드 KV 도 같은 키를 쓴다 — 두 경로가 갈라지지 않는다', () async {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await seedIfEmpty(db);

    expect(await db.readValue('dashboard_ai_advice'), kDailyCombinedAdviceKey);
  });

  group('aiAdviceBody', () {
    test('키가 있으면 로케일에 맞는 ARB 문장으로 푼다', () {
      final DashboardSummary summary = _summary(
        adviceKey: kDailyCombinedAdviceKey,
      );

      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

      expect(aiAdviceBody(ko, summary), ko.homeAiAdviceBody);
      expect(aiAdviceBody(en, summary), en.homeAiAdviceBody);
      expect(aiAdviceBody(en, summary), isNot(matches(_hangul)));
    });

    test('키가 없으면 서버 문장을 그대로 쓴다', () {
      final DashboardSummary summary = _summary(
        sodiumWarning: '오늘 나트륨이 3,000mg 으로 권장량을 넘었어요.',
      );

      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

      expect(aiAdviceBody(ko, summary), summary.sodiumWarning);
    });

    // 음식 이름이 든 나트륨 경고(#2644). 예전에는 키 없이 한국어 문장만 와서
    // 영어 화면이 그 문장을 그대로 그렸다.
    group('sodium_over_sources', () {
      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

      test('두 음식을 언어에 맞게 이어 문장 틀에 끼운다', () {
        final DashboardSummary summary = _summary(
          adviceKey: 'sodium_over_sources',
          adviceParams: const <String, Object>{
            'foods': <String>['라면', '김밥'],
          },
          sodiumWarning: '라면·김밥 섭취로 나트륨이 높아요.',
        );

        expect(aiAdviceBody(ko, summary), '라면·김밥 섭취로 나트륨이 높아요.');
        expect(aiAdviceBody(en, summary), 'Sodium is high from 라면 and 김밥.');
      });

      test('음식이 하나면 잇지 않는다', () {
        final DashboardSummary summary = _summary(
          adviceKey: 'sodium_over_sources',
          adviceParams: const <String, Object>{
            'foods': <String>['Ramen'],
          },
        );

        expect(aiAdviceBody(ko, summary), 'Ramen 섭취로 나트륨이 높아요.');
        expect(aiAdviceBody(en, summary), 'Sodium is high from Ramen.');
      });

      test('영어 문장에서 음식 이름을 빼면 한글이 없다', () {
        final DashboardSummary summary = _summary(
          adviceKey: 'sodium_over_sources',
          adviceParams: const <String, Object>{
            'foods': <String>['김치찌개', '배추김치'],
          },
          sodiumWarning: '김치찌개·배추김치 섭취로 나트륨이 높아요.',
        );

        final String body = aiAdviceBody(en, summary);
        expect(
          body.replaceAll('김치찌개', '').replaceAll('배추김치', ''),
          isNot(matches(_hangul)),
        );
        expect(body, isNot(summary.sodiumWarning));
      });

      test('세 개 이상 와도 앞의 두 개만 쓴다', () {
        final DashboardSummary summary = _summary(
          adviceKey: 'sodium_over_sources',
          adviceParams: const <String, Object>{
            'foods': <String>['A', 'B', 'C'],
          },
        );

        expect(aiAdviceBody(en, summary), 'Sodium is high from A and B.');
      });

      test('이름이 빈 문자열뿐이면 받은 문장으로 넘긴다', () {
        final DashboardSummary summary = _summary(
          adviceKey: 'sodium_over_sources',
          adviceParams: const <String, Object>{
            'foods': <String>['  ', ''],
          },
          sodiumWarning: 'Sodium is high from your meals.',
        );

        expect(aiAdviceBody(en, summary), summary.sodiumWarning);
      });

      test('인자가 없거나 모양이 틀리면 받은 문장, 그것도 없으면 ARB 기본값', () {
        final DashboardSummary missing = _summary(
          adviceKey: 'sodium_over_sources',
          sodiumWarning: 'Sodium is high from 라면.',
        );
        final DashboardSummary wrongShape = _summary(
          adviceKey: 'sodium_over_sources',
          adviceParams: const <String, Object>{'foods': '라면'},
        );

        expect(aiAdviceBody(en, missing), missing.sodiumWarning);
        expect(aiAdviceBody(en, wrongShape), en.homeAiAdviceBody);
      });
    });

    test('ai_advice_params 를 응답에서 읽는다', () {
      final DashboardSummary summary = DashboardSummary.fromJson(
        <String, Object?>{
          'indicators': <Object?>[],
          'diet_entries': 1,
          'exercise_minutes': 0,
          'sodium_warning': '라면 섭취로 나트륨이 높아요.',
          'ai_advice_key': 'sodium_over_sources',
          'ai_advice_params': <String, Object?>{
            'foods': <Object?>['라면'],
            'ignored': null,
          },
        },
      );

      expect(summary.aiAdviceParams, <String, Object>{
        'foods': <Object?>['라면'],
      });
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      expect(aiAdviceBody(en, summary), 'Sodium is high from 라면.');
    });

    test('ai_advice_params 가 없는 옛 응답은 빈 값이다', () {
      final DashboardSummary summary =
          DashboardSummary.fromJson(<String, Object?>{
            'indicators': <Object?>[],
            'diet_entries': 0,
            'exercise_minutes': 0,
            'sodium_warning': null,
          });

      expect(summary.aiAdviceParams, isEmpty);
    });

    test('모르는 키는 서버 문장·ARB 기본값으로 넘긴다', () {
      final DashboardSummary summary = _summary(
        adviceKey: 'server_shipped_a_new_key',
      );

      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

      expect(aiAdviceBody(ko, summary), ko.homeAiAdviceBody);
    });
  });

  // 위 검사들은 조각을 본다. 실제로 홈 카드에 올라오는지는 앱을 데모로 띄워
  // 확인한다 — 저장소 분기가 또 바뀌면 화면에는 다른 값이 나올 수 있다.
  group('데모 홈 화면', () {
    /// [width] 기본값(390)은 폰 폭이다. **영어만 넓게 돌린다** — 위젯 테스트의
    /// 기본 폰트는 모든 글자를 `fontSize` 크기의 정사각형으로 그려서 라틴
    /// 문자의 폭이 실제의 약 2배로 잡힌다(측정: `Exercise`@12px 가 96px,
    /// 실제 폰트는 ~48px. 한글은 전각이라 오차가 거의 없다).
    ///
    /// 그래서 영어를 폰 폭에 두면 하단 내비 라벨이 실제 기기에서는 접히지 않을
    /// 자리에서 접혀 오버플로 예외가 난다. 여기서 볼 것은 조언 문구가 로케일을
    /// 따르는지이지 레이아웃이 아니므로, 그 아티팩트를 피해 넓은 폭으로 돌린다.
    /// 레이아웃 자체는 `dashboard_content_state_test` 가 따로 본다.
    Future<void> pumpDemoHome(
      WidgetTester tester,
      Locale locale, {
      double width = 390,
    }) async {
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const AppConfig config = AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
        // 데모 진입은 기본 빌드에서 감춰 뒀다 — 이 테스트는 그 경로로 화면에
        // 들어가므로 플래그를 켜고 편다. (#1526)
        showDemoEntry: true,
      );
      // 데모 홈은 실서버와 같은 Dio 저장소 → 로컬 인터셉터 경로다(#2645).
      // 인터셉터가 읽는 DB 를 앱이 켤 때처럼 시드해 둔 인메모리로 준다 — 파일
      // DB 를 열면 테스트가 기기 저장소에 기댄다.
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() => seedIfEmpty(db));

      // 저장된 세션이 없다고 답해 준다 — 없으면 복구가 끝나지 않아 시작
      // 화면(#1944)에 머문다.
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(config),
            appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
            appDatabaseProvider.overrideWithValue(db),
            dietRepositoryProvider.overrideWithValue(
              FakeDietRepository() as DietRepository,
            ),
            // 운동도 앱의 데모처럼 위 DB 를 읽는 로컬 목업 API 를 탄다(#2724).
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
            // dashboardRepositoryProvider 는 일부러 덮지 않는다 — 데모 홈이
            // 실제로 타는 경로(Dio → 로컬 인터셉터)가 이 테스트의 핵심이다.
            localeProvider.overrideWith((ref) => locale),
          ],
          child: const OncareApp(),
        ),
      );
      await tester.pumpAndSettle();

      final Finder demoButton = find.byKey(const Key('demoEnterButton'));
      await tester.ensureVisible(demoButton);
      await tester.pumpAndSettle();
      await tester.tap(demoButton);
      await tester.pumpAndSettle();
    }

    testWidgets('한국어 로케일은 한국어 조언을 렌더한다', (WidgetTester tester) async {
      await pumpDemoHome(tester, const Locale('ko'));

      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
      expect(find.text(ko.homeAiAdviceTitle), findsOneWidget);
      expect(find.text(keepWords(ko.homeAiAdviceBody)), findsOneWidget);
    });

    testWidgets('영어 로케일 조언 본문에 한글이 없다 (#435)', (WidgetTester tester) async {
      await pumpDemoHome(tester, const Locale('en'), width: 800);

      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.homeAiAdviceTitle), findsOneWidget);
      expect(find.text(keepWords(en.homeAiAdviceBody)), findsOneWidget);

      // 제목 아래 본문이 한국어로 새지 않는지 — 카드 전체를 훑는다.
      final Finder card = find.ancestor(
        of: find.text(en.homeAiAdviceTitle),
        matching: find.byType(Column),
      );
      final Iterable<Text> texts = tester.widgetList<Text>(
        find.descendant(of: card.first, matching: find.byType(Text)),
      );
      for (final Text t in texts) {
        expect(
          t.data ?? '',
          isNot(matches(_hangul)),
          reason: '영어 로케일 조언 카드에 한글이 남아 있다: ${t.data}',
        );
      }
    });
  });
}
