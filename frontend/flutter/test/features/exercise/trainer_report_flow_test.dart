import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_trainer_report_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/repositories/trainer_report_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/trainer_report_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/trainer_detail_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/connected_gym_card.dart';
import 'package:oncare/features/exercise/presentation/widgets/trainer_report_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const Gym _gym = Gym(
  id: 'gym-test',
  name: '테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.7,
  rating: 4.8,
  tags: <String>['근력운동'],
);

const Trainer _trainer = Trainer(
  id: 'trainer-test',
  gymId: 'gym-test',
  name: '김테스트',
  role: '전담 트레이너',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 보낸 신고를 적어 두고, 정해 둔 실패를 던지는 저장소.
class _RecordingRepository implements TrainerReportRepository {
  _RecordingRepository({this.failWith});

  Object? failWith;
  final List<({String trainerId, TrainerReportReason reason, String memo})>
  sent = <({String trainerId, TrainerReportReason reason, String memo})>[];

  @override
  Future<void> report(
    String trainerId, {
    required TrainerReportReason reason,
    String memo = '',
  }) async {
    final Object? failure = failWith;
    if (failure != null) throw failure;
    sent.add((trainerId: trainerId, reason: reason, memo: memo));
  }
}

void main() {
  Future<GoRouter> pumpRoute(
    WidgetTester tester, {
    required String location,
    required TrainerReportRepository repository,
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          nearbyGymsProvider.overrideWith((ref) async => <Gym>[_gym]),
          gymFinderResultsProvider.overrideWith((ref) async => <Gym>[_gym]),
          myGymProvider.overrideWith((ref) async => null),
          myTrainerProvider.overrideWith((ref) async => null),
          gymTrainersProvider(
            _gym.id,
          ).overrideWith((ref) async => <Trainer>[_trainer]),
          trainerProvider(_trainer.id).overrideWith((ref) async => _trainer),
          trainerReportRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  AppLocalizations lOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  Finder submit() => find.byKey(const Key('trainer-report-submit'));

  bool submitEnabled(WidgetTester tester) =>
      tester.widget<AppButton>(submit()).onPressed != null;

  /// 토스트 타이머를 흘려 보낸다 — 남은 타이머가 있으면 테스트가 끝나지 않는다.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  Future<void> openFromDetail(WidgetTester tester) async {
    final Finder report = find.byKey(const Key('trainer-detail-report'));
    await tester.ensureVisible(report);
    await tester.pumpAndSettle();
    await tester.tap(report);
    await tester.pumpAndSettle();
  }

  group('트레이너 상세 (#3008)', () {
    testWidgets('신고 버튼과 직접 등록한 소속 안내가 보인다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: _RecordingRepository(),
      );
      final AppLocalizations l = lOf(tester);

      final Finder report = find.byKey(const Key('trainer-detail-report'));
      expect(report, findsOneWidget);
      final AppButton button = tester.widget<AppButton>(
        find.descendant(of: report, matching: find.byType(AppButton)),
      );
      // 상담·연결 동작보다 앞서지 않는 작은 빨간 글자 버튼이다.
      expect(button.variant, AppButtonVariant.destructiveText);
      expect(button.size, OnCareButtonSize.small);
      expect(button.label, l.exTrainerReport);

      final Finder note = find.byKey(
        const Key('trainer-detail-self-registered'),
      );
      expect(note, findsOneWidget);
      expect(
        find.descendant(of: note, matching: find.text('트레이너가 직접 등록한 소속이에요')),
        findsOneWidget,
      );
      // 안내는 소속 헬스장 줄 아래에 선다.
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(find.text(_gym.name)).dy),
      );
    });

    testWidgets('신고 버튼은 화면 맨 아래, 상담 버튼보다 뒤에 선다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: _RecordingRepository(),
      );
      final Finder report = find.byKey(const Key('trainer-detail-report'));
      await tester.ensureVisible(report);
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(report).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const Key('consult-start'))).dy,
        ),
      );
    });

    testWidgets('사유를 고르기 전에는 보낼 수 없다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: _RecordingRepository(),
      );
      await openFromDetail(tester);

      expect(find.byKey(const Key('trainer-report-sheet')), findsOneWidget);
      // 시트는 누구를 신고하는지 부제로 밝힌다.
      expect(
        find.descendant(
          of: find.byKey(const Key('trainer-report-sheet')),
          matching: find.text(_trainer.name),
        ),
        findsOneWidget,
      );
      expect(submitEnabled(tester), isFalse);
      for (final TrainerReportReason reason in TrainerReportReason.values) {
        expect(
          find.byKey(Key('trainer-report-reason-${reason.wire}')),
          findsOneWidget,
        );
      }
    });

    testWidgets('사칭을 골라 보내면 접수되고 시트가 닫힌다', (WidgetTester tester) async {
      final _RecordingRepository repository = _RecordingRepository();
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: repository,
      );
      final AppLocalizations l = lOf(tester);
      await openFromDetail(tester);

      await tester.tap(
        find.byKey(const Key('trainer-report-reason-impersonation')),
      );
      await tester.pump();
      expect(submitEnabled(tester), isTrue);
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(repository.sent, hasLength(1));
      expect(repository.sent.single.trainerId, _trainer.id);
      expect(repository.sent.single.reason, TrainerReportReason.impersonation);
      expect(find.byKey(const Key('trainer-report-sheet')), findsNothing);
      expect(find.text(l.exTrainerReportSubmitted), findsOneWidget);
      // 신고해도 상세 화면은 그대로다.
      expect(find.byType(TrainerDetailPage), findsOneWidget);
      await drainToast(tester);
    });

    testWidgets('기타는 내용을 적어야 보낼 수 있고, 적은 내용이 함께 간다', (
      WidgetTester tester,
    ) async {
      final _RecordingRepository repository = _RecordingRepository();
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: repository,
      );
      final AppLocalizations l = lOf(tester);
      await openFromDetail(tester);

      await tester.tap(find.byKey(const Key('trainer-report-reason-other')));
      await tester.pump();
      expect(submitEnabled(tester), isFalse);
      expect(find.text(l.exTrainerReportMemoRequired), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('trainer-report-memo')),
          matching: find.byType(EditableText),
        ),
        '   ',
      );
      await tester.pump();
      // 공백만으로는 내용이 아니다.
      expect(submitEnabled(tester), isFalse);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('trainer-report-memo')),
          matching: find.byType(EditableText),
        ),
        '다른 헬스장 소속이라고 했어요',
      );
      await tester.pump();
      expect(submitEnabled(tester), isTrue);

      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(repository.sent.single.reason, TrainerReportReason.other);
      expect(repository.sent.single.memo, '다른 헬스장 소속이라고 했어요');
      await drainToast(tester);
    });

    testWidgets('메모 칸은 서버와 같은 200 자 상한과 글자 수를 보인다', (
      WidgetTester tester,
    ) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: _RecordingRepository(),
      );
      await openFromDetail(tester);

      final AppTextField memo = tester.widget<AppTextField>(
        find.byKey(const Key('trainer-report-memo')),
      );
      expect(memo.maxLength, kTrainerReportMemoMax);
      expect(memo.showCounter, isTrue);
    });

    testWidgets('이미 처리 전 신고가 있으면 시트를 닫고 그 사실을 알린다', (
      WidgetTester tester,
    ) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: _RecordingRepository(
          failWith: const TrainerReportAlreadyOpen(),
        ),
      );
      final AppLocalizations l = lOf(tester);
      await openFromDetail(tester);

      await tester.tap(
        find.byKey(const Key('trainer-report-reason-inappropriate_message')),
      );
      await tester.pump();
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('trainer-report-sheet')), findsNothing);
      expect(find.text(l.exTrainerReportAlreadyOpen), findsOneWidget);
      await drainToast(tester);
    });

    testWidgets('그 밖의 실패는 시트를 남겨 적은 내용으로 다시 보내게 한다', (
      WidgetTester tester,
    ) async {
      final _RecordingRepository repository = _RecordingRepository(
        failWith: StateError('network'),
      );
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: repository,
      );
      final AppLocalizations l = lOf(tester);
      await openFromDetail(tester);

      await tester.tap(find.byKey(const Key('trainer-report-reason-other')));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('trainer-report-memo')),
          matching: find.byType(EditableText),
        ),
        '설명',
      );
      await tester.pump();
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('trainer-report-sheet')), findsOneWidget);
      expect(find.text(l.errorUnknown), findsOneWidget);
      expect(find.text('설명'), findsOneWidget);
      expect(submitEnabled(tester), isTrue);

      repository.failWith = null;
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(repository.sent, hasLength(1));
      expect(find.byKey(const Key('trainer-report-sheet')), findsNothing);
      await drainToast(tester);
    });

    testWidgets('영어 로케일에서 시트 문구가 영어다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.trainerDetailPath(_trainer.id),
        repository: _RecordingRepository(),
        locale: const Locale('en'),
      );
      expect(
        find.text('Affiliation registered by the trainer'),
        findsOneWidget,
      );
      await openFromDetail(tester);

      expect(find.text('Report trainer'), findsWidgets);
      expect(find.text('Impersonation'), findsOneWidget);
      expect(find.text('Inappropriate message'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Submit report'), findsOneWidget);
    });
  });

  group('헬스장 상세의 소속 트레이너 (#3008)', () {
    testWidgets('줄마다 신고 버튼이 있고, 섹션 아래에 직접 등록한 소속 안내가 선다', (
      WidgetTester tester,
    ) async {
      await pumpRoute(
        tester,
        location: AppRoutes.gymDetailPath(_gym.id),
        repository: _RecordingRepository(),
      );
      final AppLocalizations l = lOf(tester);

      final Finder report = find.byKey(
        Key('gym-detail-trainer-report-${_trainer.id}'),
      );
      expect(report, findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.descendant(of: report, matching: find.byType(AppButton)),
            )
            .label,
        l.exTrainerReportShort,
      );

      final Finder note = find.byKey(const Key('gym-detail-self-registered'));
      expect(note, findsOneWidget);
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(find.text(_trainer.name)).dy),
      );
    });

    testWidgets('신고 버튼은 상세로 가지 않고 시트를 연다', (WidgetTester tester) async {
      final _RecordingRepository repository = _RecordingRepository();
      await pumpRoute(
        tester,
        location: AppRoutes.gymDetailPath(_gym.id),
        repository: repository,
      );

      final Finder report = find.byKey(
        Key('gym-detail-trainer-report-${_trainer.id}'),
      );
      await tester.ensureVisible(report);
      await tester.pumpAndSettle();
      await tester.tap(report);
      await tester.pumpAndSettle();

      expect(find.byType(TrainerDetailPage), findsNothing);
      expect(find.byKey(const Key('trainer-report-sheet')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('trainer-report-reason-impersonation')),
      );
      await tester.pump();
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(repository.sent.single.trainerId, _trainer.id);
      await drainToast(tester);
    });

    testWidgets('줄의 나머지를 누르면 여전히 트레이너 상세로 간다', (WidgetTester tester) async {
      await pumpRoute(
        tester,
        location: AppRoutes.gymDetailPath(_gym.id),
        repository: _RecordingRepository(),
      );

      // 이름과 직함은 한 문단(Text.rich)으로 그려진다.
      final Finder name = find
          .textContaining(_trainer.name, findRichText: true)
          .first;
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.tap(name);
      await tester.pumpAndSettle();

      expect(find.byType(TrainerDetailPage), findsOneWidget);
    });
  });

  group('연결된 내 트레이너 카드 (#3008)', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required Trainer? trainer,
      required TrainerReportRepository repository,
      bool showTrainerReport = true,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            trainerReportRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ConnectedGymCard(
                  gym: _gym,
                  trainer: trainer,
                  onGymTap: () {},
                  onTrainerDetail: () {},
                  showTrainerReport: showTrainerReport,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('담당 트레이너가 있으면 그 줄 아래에 신고 버튼이 선다', (WidgetTester tester) async {
      await pumpCard(
        tester,
        trainer: _trainer,
        repository: _RecordingRepository(),
      );

      final Finder report = find.byKey(const Key('my-trainer-report'));
      expect(report, findsOneWidget);
      expect(
        tester.getTopLeft(report).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(find.byKey(const Key('gym-trainer-line-mine')))
              .dy,
        ),
      );
    });

    testWidgets('담당 트레이너가 없으면 신고할 대상도 없다', (WidgetTester tester) async {
      await pumpCard(tester, trainer: null, repository: _RecordingRepository());

      expect(find.byKey(const Key('my-trainer-report')), findsNothing);
    });

    testWidgets('끄면 신고 버튼을 두지 않는다', (WidgetTester tester) async {
      await pumpCard(
        tester,
        trainer: _trainer,
        repository: _RecordingRepository(),
        showTrainerReport: false,
      );

      expect(find.byKey(const Key('my-trainer-report')), findsNothing);
    });

    testWidgets('데모 저장소로 보내면 같은 트레이너 두 번째 신고는 이미 접수됨이다', (
      WidgetTester tester,
    ) async {
      final MockTrainerReportRepository repository =
          MockTrainerReportRepository();
      await pumpCard(tester, trainer: _trainer, repository: repository);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(ConnectedGymCard)),
      );

      for (int i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('my-trainer-report')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('trainer-report-reason-impersonation')),
        );
        await tester.pump();
        await tester.tap(submit());
        await tester.pumpAndSettle();
        expect(
          find.text(
            i == 0 ? l.exTrainerReportSubmitted : l.exTrainerReportAlreadyOpen,
          ),
          findsOneWidget,
        );
        await drainToast(tester);
      }
      expect(repository.openReports.keys, <String>[_trainer.id]);
    });
  });

  test('TrainerReportOutcome 은 접수·이미 접수 둘이다', () {
    expect(TrainerReportOutcome.values, hasLength(2));
  });
}
