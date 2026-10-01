import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_generate_limits.dart';
import 'package:oncare_trainer/features/coaching/presentation/pages/ai_routine_options_flow.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// AI 루틴 생성 조건의 총 시간 범위가 서버(10~180분)와 같은지. (#2871)
///
/// 칸·데모·실서버 세 층이 같은 범위를 쓰고, 범위 밖 요청은 일시 장애가
/// 아니라 입력 범위 안내로 끝나야 한다.

class _MockDio extends Mock implements Dio {}

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

/// 받은 총 시간을 적어 두고 [error] 를 던지는 생성 저장소.
class _RecordingOptionsRepository implements TrainerRoutineOptionsRepository {
  _RecordingOptionsRepository(this.error);

  final Object error;
  final List<int?> requestedMinutes = <int?>[];

  @override
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
    Set<RoutineContextSource>? sources,
  }) async {
    requestedMinutes.add(availableMinutes);
    throw error;
  }
}

Widget _host(Widget child, {Locale locale = const Locale('ko')}) => MaterialApp(
  locale: locale,
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// 값을 들고 있다가 [RoutineMinutesField] 에 다시 넘기는 칸 — 실제 화면처럼
/// 부모가 값을 쥔다.
class _MinutesHost extends StatefulWidget {
  const _MinutesHost({
    super.key,
    required this.initial,
    required this.values,
    this.min,
    this.max,
    this.helper,
  });

  final int initial;
  final List<int> values;
  final int? min;
  final int? max;
  final String? helper;

  @override
  State<_MinutesHost> createState() => _MinutesHostState();
}

class _MinutesHostState extends State<_MinutesHost> {
  late int _minutes = widget.initial;

  @override
  Widget build(BuildContext context) {
    void onChanged(int v) {
      widget.values.add(v);
      setState(() => _minutes = v);
    }

    if (widget.min == null) {
      return RoutineMinutesField(
        keyPrefix: 'm',
        minutes: _minutes,
        onChanged: onChanged,
      );
    }
    return RoutineMinutesField(
      keyPrefix: 'm',
      minutes: _minutes,
      min: widget.min!,
      max: widget.max!,
      helper: widget.helper,
      onChanged: onChanged,
    );
  }
}

Future<void> _pumpFlow(
  WidgetTester tester,
  TrainerRoutineOptionsRepository repository,
) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        trainerRoutineSuggestionRepositoryProvider.overrideWithValue(
          MockTrainerRoutineSuggestionRepository(),
        ),
        trainerRoutineOptionsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AiRoutineOptionsFlow(
          client: _client,
          recommendedExercises: <RoutineExercise>[
            RoutineExercise(name: '실내 자전거', minutes: 20, type: '유산소'),
          ],
          recommendedReason: '기존 회원 데이터 기반 추천',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapGenerate(WidgetTester tester) async {
  final Finder button = find.byKey(
    const ValueKey<String>('generate-routine-options'),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  final TestPlatformDispatcher dispatcher =
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
  setUp(() => dispatcher.localesTestValue = const <Locale>[Locale('ko')]);
  tearDown(dispatcher.clearLocalesTestValue);

  group('생성 조건 범위 상수', () {
    test('서버 RoutineOptionsRequest.available_minutes 와 같은 10~180분이다', () {
      expect(kRoutineGenerateMinMinutes, 10);
      expect(kRoutineGenerateMaxMinutes, 180);
    });

    test('경계값은 받고 그 밖은 받지 않는다', () {
      expect(isRoutineGenerateMinutesInRange(10), isTrue);
      expect(isRoutineGenerateMinutesInRange(180), isTrue);
      expect(isRoutineGenerateMinutesInRange(9), isFalse);
      expect(isRoutineGenerateMinutesInRange(181), isFalse);
      expect(isRoutineGenerateMinutesInRange(5), isFalse);
      expect(isRoutineGenerateMinutesInRange(600), isFalse);
    });

    test('서버 추천값은 범위로 당겨 칸에 채운다', () {
      expect(clampRoutineGenerateMinutes(5), 10);
      expect(clampRoutineGenerateMinutes(45), 45);
      expect(clampRoutineGenerateMinutes(240), 180);
    });
  });

  group('데모 생성은 실서버와 같은 범위를 쓴다', () {
    const repo = MockTrainerRoutineOptionsRepository();

    for (final int minutes in <int>[5, 9, 181, 200]) {
      test('$minutes분은 실서버 422 와 같은 ValidationError 로 거절한다', () async {
        await expectLater(
          repo.generate(
            'm1',
            availableMinutes: minutes,
            intensityPreference: null,
            trainerNote: '',
          ),
          throwsA(isA<ValidationError>()),
        );
      });
    }

    for (final int minutes in <int>[10, 180]) {
      test('경계값 $minutes분은 정상 생성하고 그 시간을 넘지 않는다', () async {
        final RoutineOptions options = await repo.generate(
          'm1',
          availableMinutes: minutes,
          intensityPreference: null,
          trainerNote: '',
        );
        expect(options.planB.totalMinutes, minutes);
        expect(options.planA.totalMinutes, lessThanOrEqualTo(minutes));
      });
    }

    test('조건을 비워 두면(null) 범위 검사 없이 서버 기본값으로 만든다', () async {
      final RoutineOptions options = await repo.generate(
        'm1',
        availableMinutes: null,
        intensityPreference: null,
        trainerNote: '',
      );
      expect(options.planB.totalMinutes, 30);
    });
  });

  group('실서버 저장소', () {
    test('422 는 일시 장애가 아니라 ValidationError 로 올라온다', () async {
      final dio = _MockDio();
      final RequestOptions request = RequestOptions(
        path: '/trainer/clients/m1/routine-options',
      );
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/m1/routine-options',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: request,
            statusCode: 422,
            data: <String, Object?>{'detail': 'available_minutes'},
          ),
        ),
      );

      await expectLater(
        DioTrainerRoutineOptionsRepository(dio).generate(
          'm1',
          availableMinutes: 200,
          intensityPreference: null,
          trainerNote: '',
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('RoutineMinutesField 범위', () {
    testWidgets('생성 조건 칸은 10 미만·180 초과를 경계값으로 당긴다', (tester) async {
      final values = <int>[];
      await tester.pumpWidget(
        _host(
          _MinutesHost(
            initial: 30,
            values: values,
            min: kRoutineGenerateMinMinutes,
            max: kRoutineGenerateMaxMinutes,
            helper: '10~180분 사이로 입력해 주세요',
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('m-field')),
        '5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(values.last, 10);

      await tester.enterText(
        find.byKey(const ValueKey<String>('m-field')),
        '200',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(values.last, 180);
      expect(values.where((v) => v < 10 || v > 180), isEmpty);
    });

    testWidgets('경계에 닿으면 −/+ 가 잠긴다', (tester) async {
      final values = <int>[];
      await tester.pumpWidget(
        _host(
          _MinutesHost(
            initial: 10,
            values: values,
            min: kRoutineGenerateMinMinutes,
            max: kRoutineGenerateMaxMinutes,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('m-minus')));
      await tester.pump();
      expect(values, isEmpty);

      await tester.pumpWidget(
        _host(
          _MinutesHost(
            key: const ValueKey<String>('max-host'),
            initial: 180,
            values: values,
            min: kRoutineGenerateMinMinutes,
            max: kRoutineGenerateMaxMinutes,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('m-plus')));
      await tester.pump();
      expect(values, isEmpty);
    });

    testWidgets('도움말은 칸 아래에 선다', (tester) async {
      await tester.pumpWidget(
        _host(
          const _MinutesHost(
            initial: 30,
            values: <int>[],
            min: kRoutineGenerateMinMinutes,
            max: kRoutineGenerateMaxMinutes,
            helper: '10~180분 사이로 입력해 주세요',
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('m-helper')), findsOneWidget);
      expect(find.text('10~180분 사이로 입력해 주세요'), findsOneWidget);
    });

    testWidgets('개별 운동 시간 칸은 기존 범위(1~600분) 그대로다', (tester) async {
      final values = <int>[];
      await tester.pumpWidget(_host(_MinutesHost(initial: 30, values: values)));

      await tester.enterText(
        find.byKey(const ValueKey<String>('m-field')),
        '5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(values.last, 5);

      await tester.enterText(
        find.byKey(const ValueKey<String>('m-field')),
        '200',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(values.last, 200);
      expect(find.byKey(const ValueKey<String>('m-helper')), findsNothing);
    });
  });

  group('마법사 총 시간 칸', () {
    testWidgets('범위 도움말이 보이고, 범위 밖 값은 요청에 실리지 않는다', (tester) async {
      final repo = _RecordingOptionsRepository(
        const ServerError(statusCode: 500),
      );
      await _pumpFlow(tester, repo);

      expect(find.text('10~180분 사이로 입력해 주세요'), findsOneWidget);

      final Finder field = find.byKey(
        const ValueKey<String>('generation-minutes-field'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '200');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await _tapGenerate(tester);

      expect(repo.requestedMinutes, <int?>[180]);
    });

    testWidgets('422 는 재시도 문구가 아니라 입력 범위 안내로 뜬다', (tester) async {
      final repo = _RecordingOptionsRepository(const ValidationError());
      await _pumpFlow(tester, repo);
      await _tapGenerate(tester);

      expect(
        find.text('생성 조건을 확인해 주세요. 총 운동 시간은 10~180분 사이여야 해요'),
        findsOneWidget,
      );
      expect(find.text('AI 생성에 실패했어요. 잠시 후 다시 시도해 주세요'), findsNothing);
    });
  });
}
