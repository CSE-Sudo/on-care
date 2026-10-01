import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/presentation/pages/ai_routine_options_flow.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

/// 영어 화면의 운동 빼기·제외 문구에 한국어 조사가 붙지 않는다 (#2895).
const _client = TrainerClient(
  id: 'm1',
  name: '김민수',
  avatar: '김',
  goal: '체중 감량',
  lastMessage: '',
  lastTime: '',
  active: true,
  calories: 1800,
  sodiumMg: 2100,
  sugarG: 40,
  lastRoutine: '저강도 유산소',
  weekCompletion: <int>[100, 0, 60, 0, 0, 0, 0],
  sodiumWeek: <int>[],
);

const _suggestion = RoutineSuggestion(
  id: 'sug-1',
  name: '가벼운 인터벌 러닝',
  minutes: 30,
  type: '유산소',
  reason: '숨이 차면 속도를 낮추세요',
);

class _StaticSuggestionRepository
    implements TrainerRoutineSuggestionRepository {
  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async =>
      const <RoutineSuggestion>[_suggestion];

  @override
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  }) async {}

  @override
  Future<void> dismiss(String suggestionId) async {}
}

class _EmptyMemoRepository implements TrainerMemoRepository {
  @override
  Future<List<TrainerMemo>> fetch(String clientId) async =>
      const <TrainerMemo>[];

  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
    TrainerMemoRef? ref,
  }) async => throw UnsupportedError('not used');

  @override
  Future<TrainerMemo> update(String clientId, String memoId, String body) =>
      throw UnsupportedError('not used');

  @override
  Future<void> delete(String clientId, String memoId) async =>
      throw UnsupportedError('not used');
}

Future<void> _pumpFlow(WidgetTester tester, Locale locale) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost/v1',
            useMockApi: true,
          ),
        ),
        trainerRoutineOptionsRepositoryProvider.overrideWithValue(
          const MockTrainerRoutineOptionsRepository(),
        ),
        clientHistoryProvider(_client.id).overrideWith(
          (Ref ref) => Stream.value(const <RoutineHistoryEntry>[]),
        ),
        trainerMemoRepositoryProvider.overrideWithValue(_EmptyMemoRepository()),
        trainerRoutineSuggestionRepositoryProvider.overrideWithValue(
          _StaticSuggestionRepository(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AiRoutineOptionsFlow(client: _client),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // PT 후보를 건너뛰고 개인운동 단계로 — AI 제안이 첫 줄에 놓인다.
  await tester.tap(find.byKey(const ValueKey<String>('skip-pt-program')));
  await tester.pumpAndSettle();
}

void main() {
  final TestPlatformDispatcher dispatcher =
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
  tearDown(dispatcher.clearLocalesTestValue);

  testWidgets('영어 화면은 확인 창·토스트에 이름만 넣는다', (tester) async {
    dispatcher.localesTestValue = const <Locale>[Locale('en')];
    await _pumpFlow(tester, const Locale('en'));

    await tester.tap(
      find.byKey(const ValueKey<String>('personal-routine-remove-0')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('가벼운 인터벌 러닝 will be dropped'), findsOneWidget);
    expect(find.textContaining('러닝을'), findsNothing);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('가벼운 인터벌 러닝 will not be recommended'), findsOneWidget);
    expect(find.textContaining('러닝은'), findsNothing);
  });

  testWidgets('한국어 화면은 받침에 맞는 조사를 그대로 붙인다', (tester) async {
    dispatcher.localesTestValue = const <Locale>[Locale('ko')];
    await _pumpFlow(tester, const Locale('ko'));

    await tester.tap(
      find.byKey(const ValueKey<String>('personal-routine-remove-0')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('가벼운 인터벌 러닝을 이번 개인운동에서 빼요'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('가벼운 인터벌 러닝은 추천하지 않아요'), findsOneWidget);
  });
}
