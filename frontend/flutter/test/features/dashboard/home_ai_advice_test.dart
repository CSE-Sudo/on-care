import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:oncare/features/dashboard/data/repositories/mock_dashboard_repository.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/ai_advice_text.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/locale_provider.dart';

import '../../helpers/fake_diet_repository.dart';

final RegExp _hangul = RegExp('[가-힣]');

/// 조언 필드만 다르게 둔 최소 요약.
DashboardSummary _summary({String? adviceKey, String? sodiumWarning}) =>
    DashboardSummary(
      indicators: const <HealthIndicator>[],
      macros: const DietMacros.zero(),
      dietEntries: 0,
      exerciseMinutes: 0,
      weekScore: 0,
      weekScoreDelta: 0,
      sodiumWarning: sodiumWarning,
      aiAdviceKey: adviceKey,
    );

/// 홈 '오늘의 AI 통합 조언'은 데모 소스가 둘(목 요약, 시드 KV)이라 한쪽만
/// 고치면 조용히 갈라진다. 게다가 예전에는 양쪽이 한국어 **문장**을 실어
/// 보내, 홈이 그 값을 ARB 보다 우선하는 바람에 영어 로케일에서도 한국어가
/// 나왔다(#435). 이제 둘 다 키만 싣고 문장은 ARB 가 갖는다.
void main() {
  test('데모 mock 요약은 문구가 아니라 키를 싣는다', () async {
    final DashboardSummary summary = await MockDashboardRepository(
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(config),
            appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
            dietRepositoryProvider.overrideWithValue(
              FakeDietRepository() as DietRepository,
            ),
            exerciseRepositoryProvider.overrideWithValue(
              MockExerciseRepository() as ExerciseRepository,
            ),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
            // dashboardRepositoryProvider 는 일부러 덮지 않는다 — 데모에서
            // 어떤 저장소가 뽑히는지가 이 테스트의 핵심이다.
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
      expect(find.text(ko.homeAiAdviceBody), findsOneWidget);
    });

    testWidgets('영어 로케일 조언 본문에 한글이 없다 (#435)', (WidgetTester tester) async {
      await pumpDemoHome(tester, const Locale('en'), width: 800);

      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.homeAiAdviceTitle), findsOneWidget);
      expect(find.text(en.homeAiAdviceBody), findsOneWidget);

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
