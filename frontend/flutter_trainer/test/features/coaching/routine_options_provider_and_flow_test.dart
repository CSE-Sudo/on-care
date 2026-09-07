import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/design_system/tokens/spacing.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/presentation/pages/ai_routine_options_flow.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

const _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

const _client = TrainerClient(
  id: 'm1',
  name: '김민수',
  avatar: '김',
  goal: '혈압 관리 · 체중 감량',
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

class _CapturingRoutineRepository implements TrainerRoutineRepository {
  @override
  Future<void> assignProgram(
    String memberId,
    Map<String, Object?> payload,
  ) async {}

  @override
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    String? type,
    String? reason,
  }) async {}

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {}

  AssignedRoutine? assigned;
  String? memberId;
  String? lastClientRequestId;

  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async {
    this.memberId = memberId;
    assigned = routine;
    lastClientRequestId = clientRequestId;
  }

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) =>
      Stream<List<AssignedRoutine>>.value(const <AssignedRoutine>[]);
}

/// Always throws [error] from `assignRoutine`, to exercise the send
/// button's failure-message branching (network vs. other).
class _ThrowingRoutineRepository implements TrainerRoutineRepository {
  @override
  Future<void> assignProgram(
    String memberId,
    Map<String, Object?> payload,
  ) async {
    // `assignRoutine` 과 같은 규칙 — 실제 프로그램 배정 경로가 이걸 부르면
    // 시도가 기록되고 던져야, 아래 회귀 테스트의 `attempts` 어서션이
    // "이 경로는 안 불렸다"를 실제로 검증한다.
    attempts.add(payload['client_request_id'] as String?);
    throw error;
  }

  @override
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    String? type,
    String? reason,
  }) async {}

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {}

  _ThrowingRoutineRepository(this.error);

  final Object error;

  /// 시도마다 넘어온 멱등키 — 재시도가 같은 키인지 확인한다(#581).
  final List<String?> attempts = <String?>[];

  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async {
    attempts.add(clientRequestId);
    throw error;
  }

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) =>
      Stream<List<AssignedRoutine>>.value(const <AssignedRoutine>[]);
}

/// Drives the flow from the initial analysis stage to the `템플릿에 반영`
/// button being visible and tappable, without actually tapping it — mirrors
/// the setup half of the "inline flow" test above.
Future<void> _driveToApplyReady(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('generate-routine-options')),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('generate-routine-options')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey<String>('routine-option-B')));
  await tester.pumpAndSettle();

  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('complete-routine-review')),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('complete-routine-review')),
  );
  await tester.pumpAndSettle();

  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('apply-routine-to-template')),
  );
}

void main() {
  group('생성 실패 문구 분기', _rateLimitMessageTests);

  group('trainerRoutineOptionsRepositoryProvider', () {
    test('mock when USE_MOCK_API=true', () {
      final c = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(_mockConfig)],
      );
      addTearDown(c.dispose);
      expect(
        c.read(trainerRoutineOptionsRepositoryProvider),
        isA<MockTrainerRoutineOptionsRepository>(),
      );
    });

    test('mock generator produces a shorter A and a stronger B', () async {
      const repo = MockTrainerRoutineOptionsRepository();
      final o = await repo.generate(
        'm1',
        availableMinutes: 40,
        intensityPreference: 'moderate',
        trainerNote: '무릎',
      );
      expect(o.planA.key, 'A');
      expect(o.planB.key, 'B');
      expect(o.planA.totalMinutes, lessThan(o.planB.totalMinutes));
      expect(o.planA.rationale, contains('2100mg'));
      expect(o.planA.rationale, contains('무릎')); // trainer note reflected
    });

    test('mock generator respects the requested time at both limits', () async {
      const repo = MockTrainerRoutineOptionsRepository();

      // 5 는 RoutineMinutesSlider 의 실제 최소값이다 — 예전엔 A안 하한이 10 이라
      // `clamp(10, 5)`로 죽었다.
      for (final minutes in <int>[5, 10, 180]) {
        final options = await repo.generate(
          'm1',
          availableMinutes: minutes,
          intensityPreference: 'low',
          trainerNote: '',
        );
        expect(options.planA.totalMinutes, lessThanOrEqualTo(minutes));
        expect(options.planB.totalMinutes, minutes);
        expect(
          options.planB.exercises.fold<int>(
            0,
            (sum, exercise) => sum + exercise.minutes,
          ),
          minutes,
        );
      }
    });

    test('#776 — demo member has no real history, so the mock reports '
        'template (never claims to be personalized)', () async {
      const repo = MockTrainerRoutineOptionsRepository();
      final options = await repo.generate(
        'm1',
        availableMinutes: 40,
        intensityPreference: 'moderate',
        trainerNote: '',
      );
      expect(
        options.analysis.recommendationStatus,
        RecommendationStatus.template,
      );
      expect(options.analysis.frequentExercises, isEmpty);
    });

    test('#776 — null conditions fall back to the same default as the backend '
        '(30 minutes / moderate)', () async {
      const repo = MockTrainerRoutineOptionsRepository();
      final options = await repo.generate(
        'm1',
        availableMinutes: null,
        intensityPreference: null,
        trainerNote: '',
      );
      expect(options.planB.totalMinutes, 30);
    });
  });

  group('#1028 단계 이름 · 자연어 요청 · 데모', () {
    const realConfig = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'http://localhost/v1',
      useMockApi: false,
    );

    Future<_CapturingOptionsRepository> pumpFlow(
      WidgetTester tester, {
      AppConfig config = _mockConfig,
      RoutineOptions? response,
      List<RoutineHistoryEntry> history = const <RoutineHistoryEntry>[],
      List<TrainerMemo> memos = const <TrainerMemo>[],
    }) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _CapturingOptionsRepository(
        response ?? _personalizedOptions(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(config),
            trainerRoutineOptionsRepositoryProvider.overrideWithValue(repo),
            // 분석 박스가 읽는 두 자리(#1655). 실제 저장소를 붙이면 이
            // 위젯 테스트가 열지도 않는 드리프트 DB 의 타이머에 매인다.
            clientHistoryProvider(
              _client.id,
            ).overrideWith((Ref ref) => Stream.value(history)),
            trainerMemoRepositoryProvider.overrideWithValue(
              _StaticMemoRepository(memos),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AiRoutineOptionsFlow(client: _client),
          ),
        ),
      );
      return repo;
    }

    Future<void> generate(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('generate-routine-options')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('generate-routine-options')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
    }

    // #1655 — 분석 박스는 왼쪽에 사실, 오른쪽에 최근 7일 AI 감지 메모를 둔다.
    TrainerMemo memo(String id, String body, int daysAgo, TrainerMemoSource source) {
      final DateTime today = nowKst();
      final DateTime at = DateTime(
        today.year,
        today.month,
        today.day - daysAgo,
        9,
      );
      return TrainerMemo(
        id: id,
        body: body,
        source: source,
        createdAt: at,
        updatedAt: at,
      );
    }

    testWidgets('#1655 최근 운동은 날짜가 아니라 마친 운동 이름을 말한다', (tester) async {
      await pumpFlow(
        tester,
        history: <RoutineHistoryEntry>[
          const RoutineHistoryEntry(
            id: 'h1',
            dateLabel: '9/1 (오늘)',
            label: 'PT 세션',
            completionRate: 80,
            exercises: <String>['런지 ✗', '스쿼트 ✓', '레그프레스 ✓'],
            clientFeedback: '',
            trainerNote: '',
          ),
        ],
      );
      await tester.pumpAndSettle();

      // 하지 않은 운동(✗)은 "최근 운동" 이 아니다.
      expect(find.text('스쿼트 외 1개'), findsOneWidget);
      expect(find.text('오늘'), findsNothing);
    });

    testWidgets('#1655 오른쪽 칸은 최근 7일 채팅 감지 메모만 최신순으로 보여 준다', (
      tester,
    ) async {
      await pumpFlow(
        tester,
        memos: <TrainerMemo>[
          memo('a', '무릎 불편 감지', 0, TrainerMemoSource.chatInsight),
          memo('b', '어깨 불편 감지', 3, TrainerMemoSource.chatInsight),
          // 8일 전은 창 밖이고, 손으로 쓴 메모는 이 칸의 대상이 아니다.
          memo('c', '허리 불편 감지', 8, TrainerMemoSource.chatInsight),
          memo('d', '수업 시간 조정 요청', 0, TrainerMemoSource.trainer),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('무릎 불편 감지'), findsOneWidget);
      expect(find.text('어깨 불편 감지'), findsOneWidget);
      expect(find.text('허리 불편 감지'), findsNothing);
      expect(find.text('수업 시간 조정 요청'), findsNothing);
    });

    testWidgets('#1655 메모가 늘어도 감지 칸의 높이는 그대로다', (tester) async {
      await pumpFlow(
        tester,
        memos: <TrainerMemo>[
          memo('a', '무릎 불편 감지', 0, TrainerMemoSource.chatInsight),
        ],
      );
      await tester.pumpAndSettle();
      final Size one = tester.getSize(
        find.byKey(const ValueKey<String>('ai-chat-insight-memos')),
      );

      await pumpFlow(
        tester,
        memos: <TrainerMemo>[
          for (int i = 0; i < 8; i++)
            memo('m$i', '무릎 불편 감지 $i', i, TrainerMemoSource.chatInsight),
        ],
      );
      await tester.pumpAndSettle();

      // 아래로 자라면 생성 버튼이 눌리던 자리에서 밀린다 — 넘치는 메모는
      // 칸 안에서 스크롤한다.
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('ai-chat-insight-memos')))
            .height,
        one.height,
      );
    });

    testWidgets('세 단계는 조건 설정 → 프로그램 선택 → 최종 검토다', (tester) async {
      await pumpFlow(tester);

      expect(find.text('조건 설정'), findsOneWidget);
      expect(find.text('프로그램 선택'), findsOneWidget);
      expect(find.text('최종 검토'), findsOneWidget);
      // 예전 이름이 남아 있으면 흐름이 두 이름으로 불린다.
      expect(find.text('후보 검토'), findsNothing);
      expect(find.text('추천 완료'), findsNothing);
    });

    testWidgets('자연어 요청은 trainer_note 로 그대로 나가고, 직접 작성 경로는 '
        '`운동 직접 추가하기` 로 불린다', (tester) async {
      final repo = await pumpFlow(tester);

      const prompt = '하체 부담 적고 유산소 비중 높은 40분 프로그램 만들어줘';
      await tester.enterText(
        find.byKey(const ValueKey<String>('ai-natural-language-prompt')),
        prompt,
      );
      await tester.pump();
      await generate(tester);

      // 지어낸 새 필드가 아니라 백엔드가 실제로 읽는 자유 텍스트로 나간다.
      expect(repo.lastTrainerNote, prompt);

      expect(find.text('운동 직접 추가하기'), findsOneWidget);
      expect(find.text('운동 직접 등록'), findsNothing);
    });

    testWidgets('데모에서는 목표 기반 기본 추천 안내가 보이지 않는다', (tester) async {
      // 데모 회원은 기록이 없어 생성기가 늘 template 상태를 돌려준다.
      await pumpFlow(tester, response: _templateOptions());
      await generate(tester);

      expect(find.text('목표 기반 기본 추천'), findsNothing);
      expect(find.text('목표 기반 추천안 생성'), findsNothing);

      // 데이터 기반 흐름의 문구만 남는다.
      await tester.tap(find.byKey(const ValueKey<String>('routine-stage-0')));
      await tester.pumpAndSettle();
      expect(find.text('맞춤 추천안 후보 생성'), findsOneWidget);
    });

    testWidgets('실 API 모드에서는 기록이 적은 회원에게 그 사실을 그대로 말한다', (tester) async {
      await pumpFlow(tester, config: realConfig, response: _templateOptions());
      await generate(tester);

      expect(find.text('목표 기반 기본 추천'), findsOneWidget);
    });
  });

  group('#776 recommendation status', () {
    testWidgets(
      'first generation sends no explicit conditions, and the personalized '
      'banner + pattern-based labels show once the server responds',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _CapturingOptionsRepository(_personalizedOptions());
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              appConfigProvider.overrideWithValue(_mockConfig),
              trainerRoutineOptionsRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              locale: Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AiRoutineOptionsFlow(client: _client),
            ),
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('generate-routine-options')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        // 트레이너가 조건을 건드리지 않았으니 서버가 알아서 채우도록 둘 다
        // 비워 보낸다 — 슬라이더 기본값(30/moderate)을 그대로 보냈다면
        // 서버의 자동 설정 분기가 아예 실행되지 않는다.
        expect(repo.lastAvailableMinutes, isNull);
        expect(repo.lastIntensityPreference, isNull);

        // 개인화 분석 배너와, 반복 패턴 기반 A/B 라벨이 그대로 보인다.
        expect(find.text('최근 패턴 분석 완료'), findsOneWidget);
        expect(find.textContaining('스쿼트'), findsWidgets);
        expect(find.textContaining('기존 패턴 유지형'), findsOneWidget);
        expect(find.textContaining('점진적 강화형'), findsOneWidget);

        // 서버가 실제로 쓴 조건(45분/높음)이 화면에도 반영돼, 되돌아가면
        // 그 값에서 바로 수정할 수 있다.
        await tester.tap(find.byKey(const ValueKey<String>('routine-stage-0')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey<String>('generation-minutes-field')),
              )
              .controller!
              .text,
          '45',
        );
        final highIntensityLabel = tester.widget<Text>(find.text('높음'));
        expect(highIntensityLabel.style?.color, AppColors.accent);
      },
    );

    testWidgets(
      'once the trainer edits a condition, that explicit value is sent '
      'instead of letting the server auto-fill',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _CapturingOptionsRepository(_personalizedOptions());
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              appConfigProvider.overrideWithValue(_mockConfig),
              trainerRoutineOptionsRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              locale: Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AiRoutineOptionsFlow(client: _client),
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('generation-minutes-field')),
          '60',
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey<String>('generate-routine-options')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(repo.lastAvailableMinutes, 60);
        // 시간만 건드렸다 — 강도는 여전히 서버가 이력에서 계산하도록 비워
        // 보낸다. 한쪽을 고쳤다고 다른 쪽까지 트레이너 입력값으로 굳으면 안
        // 된다.
        expect(repo.lastIntensityPreference, isNull);
      },
    );

    testWidgets(
      'touching only intensity leaves minutes for the server to derive',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _CapturingOptionsRepository(_personalizedOptions());
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              appConfigProvider.overrideWithValue(_mockConfig),
              trainerRoutineOptionsRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              locale: Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AiRoutineOptionsFlow(client: _client),
            ),
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('routine-intensity-high')),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey<String>('generate-routine-options')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        // 강도만 건드렸다 — 시간은 여전히 서버가 이력에서 계산하도록 비워
        // 보낸다.
        expect(repo.lastAvailableMinutes, isNull);
        expect(repo.lastIntensityPreference, 'high');
      },
    );
  });

  testWidgets(
    'inline flow: analyse → horizontal options → edit/apply to template',
    (tester) async {
      // Tall viewport so every step's content fits (buttons sit at the bottom
      // of a scrolling list otherwise, and taps miss off-screen).
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final assigned = _CapturingRoutineRepository();
      List<RoutineExercise>? reviewed;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_mockConfig),
            trainerRoutineRepositoryProvider.overrideWithValue(assigned),
          ],
          child: MaterialApp(
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AiRoutineOptionsFlow(
              client: _client,
              recommendedExercises: const <RoutineExercise>[
                RoutineExercise(name: '실내 자전거', minutes: 20, type: '유산소'),
              ],
              recommendedReason: '기존 회원 데이터 기반 추천',
              onReviewCompleted: (exercises) => reviewed = exercises,
            ),
          ),
        ),
      );

      // 조건 설정 단계에는 자연어 요청 칸이 있고(#1028), 예시 문구는 입력 전
      // 참고용이라 흐린 placeholder 로 남는다.
      expect(find.text('운동 목표와 최근 활동, 오늘의 식단 정보를 확인했어요'), findsOneWidget);
      // 분석 제목과 생성 버튼의 AI 아이콘은 유지하되 요청 제목 아이콘만 뺀다.
      expect(find.byIcon(Icons.auto_awesome), findsNWidgets(2));
      expect(find.text('요청 내용'), findsOneWidget);
      final promptBlurb = tester.widget<Text>(
        find.textContaining('요청은 회원 데이터와 함께 AI에 전달돼요'),
      );
      expect(promptBlurb.maxLines, 1);
      expect(promptBlurb.overflow, TextOverflow.ellipsis);
      final promptField = find.byKey(
        const ValueKey<String>('ai-natural-language-prompt'),
      );
      final initialPrompt = tester.widget<TextField>(promptField);
      expect(
        initialPrompt.decoration?.hintStyle?.color,
        AppColors.mutedForeground,
      );
      expect(initialPrompt.decoration?.fillColor, AppColors.card);
      expect(
        (initialPrompt.decoration?.enabledBorder! as OutlineInputBorder)
            .borderSide
            .color,
        AppColors.borderStrong,
      );
      expect(initialPrompt.buildCounter, isNotNull);
      expect(
        find.byKey(const ValueKey<String>('ai-prompt-counter')),
        findsOneWidget,
      );
      // 서버 상한(`trainer_note`, 500자)을 화면에서 먼저 막는다.
      expect(initialPrompt.maxLength, 500);
      expect(
        initialPrompt.decoration?.hintText,
        '예: 하체 부담 적고 유산소 비중 높은 40분 프로그램 만들어줘',
      );
      final generationMinutes = find.byKey(
        const ValueKey<String>('generation-minutes'),
      );
      expect(
        find.descendant(of: generationMinutes, matching: find.text('총 운동시간')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: generationMinutes, matching: find.text('운동 시간')),
        findsNothing,
      );
      await tester.enterText(promptField, '무릎 부담 적게, 유산소 위주로 만들어줘');

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('generate-routine-options')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('generate-routine-options')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // A/B + the existing recommendation are shown together. The layout
      // adapts — side by side when the column is wide enough, stacked
      // vertically when it isn't — so this asserts the three options
      // themselves rather than which of the two layouts rendered them.
      expect(find.textContaining('회복안 · 회복·지속 중심'), findsOneWidget);
      expect(find.textContaining('강화안 · 강도·운동량 중심'), findsOneWidget);
      expect(find.textContaining('기존안 · 기존 AI 추천'), findsOneWidget);
      // 세 번째 후보의 key 는 선택 식별자다 — 화면 문구가 아니라서 로케일과
      // 무관하게 'recommended' 로 고정돼 있다(#501).
      final optionHeights = <String>['A', 'B', 'recommended']
          .map(
            (key) => tester
                .getSize(find.byKey(ValueKey<String>('routine-option-$key')))
                .height,
          )
          .toSet();
      expect(optionHeights, hasLength(1));

      // Select B and edit its first exercise in the common inline editor.
      await tester.tap(find.byKey(const ValueKey<String>('routine-option-B')));
      await tester.pumpAndSettle();
      final categoryNameGap = tester.widget<SizedBox>(
        find.byKey(const ValueKey<String>('routine-category-name-gap-0')),
      );
      expect(categoryNameGap.height, AppSpacing.md);
      // 시간 칸은 스테퍼가 아니라 라벨 없는 compact 입력이다(#1489) — 값
      // 오른쪽의 단위(suffixText)로 무엇을 재는 칸인지 구분한다.
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('routine-minutes-0-field')),
            )
            .decoration
            ?.suffixText,
        '분',
      );

      final showAddExerciseForm = find.byKey(
        const ValueKey<String>('show-add-exercise-form'),
      );
      await tester.ensureVisible(showAddExerciseForm);
      await tester.tap(showAddExerciseForm);
      await tester.pumpAndSettle();
      // 기본 유형이 근력이라 시간 슬라이더 대신 세트·횟수 칸이 보인다(#1029).
      expect(
        find.byKey(const ValueKey<String>('new-exercise-sets')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('new-exercise-minutes')),
        findsNothing,
      );
      // 근력이 아닌 유형으로 바꾸면 시간 슬라이더로 바뀐다.
      await tester.tap(
        find.byKey(const ValueKey<String>('new-exercise-category-유산소')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('routine-minutes-field')),
            )
            .decoration
            ?.suffixText,
        '분',
      );
      expect(
        find.byKey(const ValueKey<String>('new-exercise-sets')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('hide-add-exercise-form')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '인터벌 걷기');
      final minutesField = find.byKey(
        const ValueKey<String>('routine-minutes-0-field'),
      );
      await tester.enterText(minutesField, '20');
      await tester.pump();
      expect(tester.widget<TextField>(minutesField).controller!.text, '20');
      // 유형은 네 가지다 (#996, #1276).
      for (final category in <String>['유산소', '근력', '스트레칭', '기타']) {
        expect(
          find.byKey(ValueKey<String>('routine-category-B-0-$category')),
          findsOneWidget,
        );
      }
      await tester.pump();

      // 회원에게 함께 보낼 메모는 AI 요청과 **다른 칸**이다 (#1028) — 여기 적은
      // 것만 회원이 받는 루틴 사유로 나간다.
      final clientNote = find.byKey(
        const ValueKey<String>('final-trainer-memo'),
      );
      await tester.ensureVisible(clientNote);
      await tester.enterText(clientNote, '무릎 충격 주의');
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('complete-routine-review')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('complete-routine-review')),
      );
      await tester.pumpAndSettle();
      // 최종 검토에 들어온 것만으로는 아직 아무 데도 반영되지 않는다 (#1028
      // 후속) — `템플릿에 반영`을 눌러야 [onReviewCompleted] 가 호출된다.
      expect(reviewed, isNull);
      expect(
        find.byKey(const ValueKey<String>('reviewed-routine-list')),
        findsOneWidget,
      );
      expect(assigned.memberId, isNull);
      expect(assigned.assigned, isNull);
      // 이 화면에는 회원에게 직접 보내는 버튼이 없다 — `템플릿에 반영` 뿐이다.
      expect(
        find.byKey(const ValueKey<String>('send-selected-routine')),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('apply-routine-to-template')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('apply-routine-to-template')),
      );
      await tester.pumpAndSettle();

      // 템플릿(편집기)로만 반영된다 — 서버에는 여전히 아무것도 나가지 않는다.
      expect(reviewed, isNotNull);
      expect(reviewed!.first.name, '인터벌 걷기');
      expect(assigned.memberId, isNull);
      expect(assigned.assigned, isNull);
    },
  );

  testWidgets('템플릿에 반영은 회원에게 보내는 API를 호출하지 않는다 (#1028 후속)', (tester) async {
    // AI 3단계 최종 검토는 더 이상 여기서 곧바로 전송하지 않는다 — `템플릿에
    // 반영`은 [onReviewCompleted] 로 편집기에 넘길 뿐이다. 실수로라도 회원
    // 전송 API 가 호출되면 곧바로 던지도록 만들어 회귀를 잡는다.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _ThrowingRoutineRepository(const NetworkError());
    List<RoutineExercise>? reviewed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_mockConfig),
          trainerRoutineRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiRoutineOptionsFlow(
            client: _client,
            recommendedExercises: const <RoutineExercise>[
              RoutineExercise(name: '실내 자전거', minutes: 20, type: '유산소'),
            ],
            recommendedReason: '기존 회원 데이터 기반 추천',
            onReviewCompleted: (exercises) => reviewed = exercises,
          ),
        ),
      ),
    );

    await _driveToApplyReady(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('apply-routine-to-template')),
    );
    await tester.pumpAndSettle();

    expect(reviewed, isNotNull);
    expect(repository.attempts, isEmpty);
    expect(find.text('전송에 실패했어요. 다시 시도해 주세요'), findsNothing);
  });
}

/// Records what conditions the flow actually sent, and returns a fixed
/// [RoutineOptions] regardless — used to check the "leave it blank, let the
/// server decide" contract (#776) without a real backend.
class _CapturingOptionsRepository implements TrainerRoutineOptionsRepository {
  _CapturingOptionsRepository(this._response);

  final RoutineOptions _response;
  int? lastAvailableMinutes;
  String? lastIntensityPreference;
  String? lastTrainerNote;

  @override
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
  }) async {
    lastAvailableMinutes = availableMinutes;
    lastIntensityPreference = intensityPreference;
    lastTrainerNote = trainerNote;
    return _response;
  }
}

/// 기록이 거의 없는 회원의 응답 — 서버가 [RecommendationStatus.template] 을
/// 돌려주는 상태 (#776). 데모는 언제나 이 상태다.
RoutineOptions _templateOptions() {
  const analysis = MemberAnalysis(
    goal: '체중 감량',
    sodiumTodayMg: 1800,
    sodiumOverTarget: false,
    avgCompletionRate: 40,
    latestRoutine: '-',
    note: '',
  );
  return const RoutineOptions(
    analysis: analysis,
    planA: RoutinePlan(
      key: 'A',
      label: '회복·지속 중심',
      totalMinutes: 20,
      intensity: '낮음',
      exercises: <RoutineExercise>[
        RoutineExercise(name: '걷기', minutes: 20, type: '유산소'),
      ],
      reason: '가볍게 시작',
      rationale: '목표 기준 기본 구성',
    ),
    planB: RoutinePlan(
      key: 'B',
      label: '강도·운동량 중심',
      totalMinutes: 30,
      intensity: '보통',
      exercises: <RoutineExercise>[
        RoutineExercise(name: '스쿼트', minutes: 30, type: '근력'),
      ],
      reason: '조금 더',
      rationale: '목표 기준 기본 구성',
    ),
    generatedBy: 'rule',
  );
}

/// A settled-history response: repeated squats over several weeks, so the
/// candidates read as "keep the pattern" / "grow it a little" (#776).
RoutineOptions _personalizedOptions() {
  const analysis = MemberAnalysis(
    goal: '체중 감량',
    sodiumTodayMg: 1800,
    sodiumOverTarget: false,
    avgCompletionRate: 70,
    latestRoutine: '스쿼트',
    note: '',
    recommendationStatus: RecommendationStatus.personalized,
    historySessionCount: 6,
    analysisPeriodDays: 42,
    frequentExercises: <String>['스쿼트'],
    suggestedAvailableMinutes: 45,
    suggestedIntensity: 'high',
  );
  const planA = RoutinePlan(
    key: 'A',
    label: '기존 패턴 유지형',
    totalMinutes: 45,
    intensity: '높음',
    exercises: <RoutineExercise>[
      RoutineExercise(name: '스쿼트', minutes: 45, type: '근력'),
    ],
    reason: '최근 자주 수행한 운동을 그대로 유지',
    rationale: '최근 기록에서 반복 확인된 운동(스쿼트)을 유지',
  );
  const planB = RoutinePlan(
    key: 'B',
    label: '점진적 강화형',
    totalMinutes: 45,
    intensity: '높음',
    exercises: <RoutineExercise>[
      RoutineExercise(name: '스쿼트', minutes: 30, type: '근력'),
      RoutineExercise(name: '인터벌 러닝', minutes: 15, type: '유산소'),
    ],
    reason: '기존 핵심 운동을 유지하며 운동량을 소폭 확대',
    rationale: '기존 핵심 운동(스쿼트)은 유지하고 인터벌 러닝을 더함',
  );
  return const RoutineOptions(
    analysis: analysis,
    planA: planA,
    planB: planB,
    generatedBy: 'rule',
  );
}

/// Always throws [error] from `generate`, to exercise the generate button's
/// failure-message branching (한도 초과 vs. 그 외).
class _ThrowingOptionsRepository implements TrainerRoutineOptionsRepository {
  _ThrowingOptionsRepository(this.error);

  final Object error;

  @override
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
  }) async {
    throw error;
  }
}

Future<void> _pumpFlowWithOptionsError(
  WidgetTester tester,
  Object error,
) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        trainerRoutineOptionsRepositoryProvider.overrideWithValue(
          _ThrowingOptionsRepository(error),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiRoutineOptionsFlow(
          client: _client,
          recommendedExercises: <RoutineExercise>[
            RoutineExercise(name: '실내 자전거', minutes: 20, type: '유산소'),
          ],
          recommendedReason: '기존 회원 데이터 기반 추천',
        ),
      ),
    ),
  );

  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('generate-routine-options')),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('generate-routine-options')),
  );
  await tester.pumpAndSettle();
}

void _rateLimitMessageTests() {
  testWidgets('한도 초과(429)는 고장이 아니라 기다리라고 안내한다 (#582)', (tester) async {
    // 429 를 다른 오류와 뭉뚱그리면 트레이너가 기능이 깨진 것으로 읽는다.
    await _pumpFlowWithOptionsError(tester, const RateLimitedError());

    expect(find.text('AI 생성을 너무 자주 요청했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
    expect(find.text('AI 생성에 실패했어요. 잠시 후 다시 시도해 주세요'), findsNothing);
  });

  testWidgets('그 밖의 실패는 기존 문구를 그대로 쓴다 (#582)', (tester) async {
    await _pumpFlowWithOptionsError(tester, const ServerError(statusCode: 500));

    expect(find.text('AI 생성에 실패했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
    expect(find.text('AI 생성을 너무 자주 요청했어요. 잠시 후 다시 시도해 주세요'), findsNothing);
  });
}

/// 분석 박스가 읽을 메모만 들고 있는 저장소 — 쓰기는 이 흐름에서 쓰지 않는다.
class _StaticMemoRepository implements TrainerMemoRepository {
  const _StaticMemoRepository(this._memos);

  final List<TrainerMemo> _memos;

  @override
  Future<List<TrainerMemo>> fetch(String clientId) async => _memos;

  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
  }) async => throw UnsupportedError('not used');

  @override
  Future<TrainerMemo> update(String clientId, String memoId, String body) =>
      throw UnsupportedError('not used');

  @override
  Future<void> delete(String clientId, String memoId) async =>
      throw UnsupportedError('not used');
}
