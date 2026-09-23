import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../support/consultation_test_support.dart';

const Gym _gymWithTrainer = Gym(
  id: 'gym-test',
  name: '테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.7,
  rating: 4.8,
  tags: <String>['근력운동'],
  weekdayHours: '06:00 - 23:00',
  weekendHours: '08:00 - 20:00',
  phone: '02-0000-0000',
);

const Gym _gymWithoutTrainer = Gym(
  id: 'gym-no-trainer',
  name: '트레이너 없는 헬스장',
  address: '서울시 테스트구',
  distanceKm: 1.2,
  rating: 4.2,
  tags: <String>[],
);

const Trainer _trainer = Trainer(
  id: 'trainer-test',
  gymId: 'gym-test',
  name: '김테스트',
  role: '전담 트레이너',
);

/// 지금 데모 데이터에서 가장 긴 직함을 가진 트레이너 (#2082).
const Trainer _longRoleTrainer = Trainer(
  id: 'trainer-long-role',
  gymId: 'gym-test',
  name: '이지훈',
  role: '시니어 운동 트레이너',
  reasons: <String>['체력 향상'],
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<GoRouter> pumpRoute(
    WidgetTester tester, {
    required String location,
    List<Gym> gyms = const <Gym>[_gymWithTrainer, _gymWithoutTrainer],
    List<Trainer> trainers = const <Trainer>[_trainer],
    Gym? myGym,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          nearbyGymsProvider.overrideWith((ref) async => gyms),
          // 헬스장 상세·찾기는 제휴 + 카카오를 합친 provider 를 본다(#329).
          // gymRepositoryProvider 가 mock/실 API 를 이 값으로 고른다(#324).
          appConfigProvider.overrideWithValue(_config),
          gymFinderResultsProvider.overrideWith((ref) async => gyms),
          myGymProvider.overrideWith((ref) async => myGym),
          myTrainerProvider.overrideWith((ref) async => null),
          recommendedTrainersProvider.overrideWith((ref) async => trainers),
          for (final Gym gym in gyms)
            gymTrainersProvider(gym.id).overrideWith(
              (ref) async => trainers
                  .where((Trainer t) => t.gymId == gym.id)
                  .toList(growable: false),
            ),
          for (final Trainer trainer in trainers)
            trainerProvider(trainer.id).overrideWith((ref) async => trainer),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  // 트레이너로 가는 길은 헬스장을 거친다 — 트레이너만 따로 세우는 목록은 없다
  // (#1885). 헬스장 상세에서 트레이너 상세로 넘어가는 길은 아래 테스트가 본다.
  testWidgets('gym list rows open the gym detail route', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, location: AppRoutes.gyms);

    await tester.tap(find.text(_gymWithTrainer.name));
    await tester.pumpAndSettle();
    expect(find.text('헬스장 상세'), findsOneWidget);
  });

  testWidgets('detail pages link between the gym and its trainer', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath(_gymWithTrainer.id),
    );

    await tester.scrollUntilVisible(
      find.textContaining(_trainer.name),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.textContaining(_trainer.name));
    await tester.pumpAndSettle();
    expect(find.text('트레이너 상세'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(_gymWithTrainer.name),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(_gymWithTrainer.name));
    await tester.pumpAndSettle();
    expect(find.text('헬스장 상세'), findsOneWidget);
  });

  testWidgets('missing gym or trainer data shows a safe empty state', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath('missing'),
      gyms: const <Gym>[_gymWithoutTrainer],
      trainers: const <Trainer>[],
    );
    expect(find.text('헬스장 정보를 찾을 수 없어요.'), findsOneWidget);

    router.go(AppRoutes.trainerDetailPath('missing-trainer'));
    await tester.pumpAndSettle();
    expect(find.text('트레이너 정보를 찾을 수 없어요.'), findsOneWidget);
  });

  testWidgets('assigned trainer detail hides the consultation request action', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      location: AppRoutes.trainerDetailPath(_gymWithTrainer.id),
      myGym: _gymWithTrainer,
    );

    expect(find.text('트레이너 상세'), findsOneWidget);
    expect(find.text('트레이너 상담 요청하기'), findsNothing);
  });

  testWidgets('connected gym detail hides the consultation request action', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath(_gymWithTrainer.id),
      myGym: _gymWithTrainer,
    );

    expect(find.text('헬스장 상세'), findsOneWidget);
    expect(find.text('헬스장 상담 요청하기'), findsNothing);
  });

  // 트레이너를 고르는 자리와 눌러 들어간 트레이너 상세·채팅이 같은 얼굴이다
  // (#2154). 예전에는 사람 아이콘이라 줄마다 같은 그림이 반복됐다.
  testWidgets('소속 트레이너 행은 성씨 프로필로 선다 (#2154)', (WidgetTester tester) async {
    await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath(_gymWithTrainer.id),
      trainers: const <Trainer>[_trainer, _longRoleTrainer],
    );

    for (final Trainer trainer in <Trainer>[_trainer, _longRoleTrainer]) {
      final Finder avatar = find.byWidgetPredicate(
        (Widget w) => w is AppAvatar && w.name == trainer.name,
      );
      await tester.scrollUntilVisible(
        avatar,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(avatar, findsOneWidget);
      expect(tester.widget<AppAvatar>(avatar).size, AppAvatarSize.large);
      expect(
        find.descendant(
          of: avatar,
          matching: find.text(trainer.name.characters.first),
        ),
        findsOneWidget,
      );
    }
  });

  // 이름과 직함은 한 줄에 읽힌다 — 헬스장 찾기·내 헬스장 카드의 트레이너 줄과
  // 같은 규칙이다(#2038 · #2082). 두 줄은 `제목 + 설명` 행의 몫이다.
  testWidgets('소속 트레이너 행은 이름·직함 한 줄이다 (#2082)', (WidgetTester tester) async {
    await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath(_gymWithTrainer.id),
      trainers: const <Trainer>[_trainer, _longRoleTrainer],
    );

    for (final Trainer trainer in <Trainer>[_trainer, _longRoleTrainer]) {
      final Finder line = find.textContaining(trainer.name);
      await tester.scrollUntilVisible(
        line,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(line, findsOneWidget);
      final Text text = tester.widget<Text>(line);
      expect(text.maxLines, 1);
      expect(text.textSpan!.toPlainText(), contains(trainer.role!));
      // 직함만 따로 선 글줄(예전의 부제)이 없다.
      expect(find.text(trainer.role!), findsNothing);
    }
    // 360 폭에서 가장 긴 직함도 행을 넘치게 하지 않는다.
    expect(tester.takeException(), isNull);
  });

  testWidgets('상담 대기 중인 행도 직함이 먼저 줄고 넘치지 않는다 (#2082)', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      location: AppRoutes.gymDetailPath(_gymWithTrainer.id),
      trainers: const <Trainer>[_trainer, _longRoleTrainer],
    );
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    // 이미 대기 중이면 고르기 시트가 오른쪽 화살표 대신 상태 문구를 붙인다 —
    // 이름·직함 칸이 가장 좁아지는 경우다.
    expect(
      await seedPending(
        container.read(consultationRequestControllerProvider.notifier),
        ConsultationRequest(
          id: 'request-long-role',
          trainerId: _longRoleTrainer.id,
          trainerName: _longRoleTrainer.name,
          trainerRole: _longRoleTrainer.role,
          exerciseGoal: ExerciseGoal.fitness,
          healthPurposeType: HealthPurposeType.general,
          healthPurposeDetail: null,
          preferredDate: DateTime(2026, 7, 28),
          preferredTimeSlot: const PreferredTime.at(
            TimeOfDay(hour: 14, minute: 0),
          ),
          message: null,
          status: ConsultationStatus.pending,
          createdAt: DateTime(2026, 7, 26),
        ),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(l.exGymConsultRequest),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(l.exGymConsultRequest));
    await tester.pumpAndSettle();

    final Finder row = find.byKey(
      Key('gym-consult-trainer-${_longRoleTrainer.id}'),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text(l.exConsultPendingCta)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final Finder line = find.descendant(
      of: row,
      matching: find.textContaining(_longRoleTrainer.name),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      line,
    );
    expect(paragraph.didExceedMaxLines, isTrue);
    // 줄 끝에 걸린 글자가 이름 뒤다 — 이름은 온전하고 직함이 잘렸다.
    final TextPosition end = paragraph.getPositionForOffset(
      Offset(paragraph.size.width - 1, paragraph.size.height / 2),
    );
    expect(end.offset, greaterThan(_longRoleTrainer.name.length));
  });
}
