import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const Gym _gym = Gym(
  id: 'gym-profile',
  name: '프로필 헬스장',
  address: '서울 서대문구 테스트로 1',
  distanceKm: 0.4,
  rating: 4.6,
  tags: <String>['PT'],
);

const Trainer _withProfile = Trainer(
  id: 'trainer-profile',
  gymId: 'gym-profile',
  name: '김테스트',
  role: '퍼스널 트레이너',
  career: '7년',
  intro: '혈압 관리와 체중 감량을 주로 담당합니다.',
  certifications: <String>['생활스포츠지도사 2급', '스포츠 영양사'],
);

/// 이름·직함만 있고 소개/경력/자격증이 없는 트레이너.
const Trainer _withoutProfile = Trainer(
  id: 'trainer-bare',
  gymId: 'gym-profile',
  name: '박테스트',
  role: '퍼스널 트레이너',
);

/// 값은 있지만 공백뿐이라 실제로는 보여줄 게 없는 트레이너.
const Trainer _withWhitespaceOnlyProfile = Trainer(
  id: 'trainer-whitespace',
  gymId: 'gym-profile',
  name: '공백테스트',
  role: '퍼스널 트레이너',
  career: '  ',
  intro: '\n ',
  certifications: <String>['', '  '],
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<void> pumpTrainerDetail(WidgetTester tester, Trainer trainer) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.trainerDetailPath(trainer.id));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // gymRepository·consultationRepository 가 이 값으로 mock/실 API 를 고른다.
          appConfigProvider.overrideWithValue(_config),
          nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
          // 헬스장 상세·찾기는 제휴 + 카카오를 합친 provider 를 본다(#329).
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_gym],
          ),
          myGymProvider.overrideWith((ref) async => null),
          myTrainerProvider.overrideWith((ref) async => null),
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
  }

  testWidgets('트레이너 상세가 소개·경력·자격증을 보여준다', (WidgetTester tester) async {
    await pumpTrainerDetail(tester, _withProfile);

    expect(find.text('트레이너 소개'), findsOneWidget);
    expect(find.text(_withProfile.intro!), findsOneWidget);
    expect(find.text('경력 7년'), findsOneWidget);
    expect(find.text('자격증 · 인증'), findsOneWidget);
    for (final String cert in _withProfile.certifications) {
      expect(find.text(cert), findsOneWidget);
    }
  });

  testWidgets('프로필 정보가 없으면 소개 섹션을 그리지 않는다', (WidgetTester tester) async {
    await pumpTrainerDetail(tester, _withoutProfile);

    // 트레이너 자체는 존재하므로 이름은 보이되, 소개 섹션만 빠진다.
    expect(find.text(_withoutProfile.name), findsOneWidget);
    expect(find.text('트레이너 소개'), findsNothing);
    expect(find.text('자격증 · 인증'), findsNothing);
  });

  testWidgets('공백뿐인 프로필 정보는 소개 섹션과 빈 칩을 만들지 않는다', (WidgetTester tester) async {
    await pumpTrainerDetail(tester, _withWhitespaceOnlyProfile);

    expect(find.text(_withWhitespaceOnlyProfile.name), findsOneWidget);
    expect(find.text('트레이너 소개'), findsNothing);
    expect(find.text('자격증 · 인증'), findsNothing);
  });

  group('MockGymRepository 트레이너 디렉터리', () {
    // 트레이너 앱은 별도 패키지라 seedTrainerProfile 을 import 할 수 없다.
    // 기대값을 여기 고정해 두어, 사용자 앱 목 데이터가 바뀌면 실패하도록 한다.
    // 값을 고칠 때는 frontend/flutter_trainer/lib/shared/models/trainer_profile.dart
    // 의 seedTrainerProfile 과 함께 맞춰야 한다.
    test('연결된 트레이너가 트레이너 앱 seedTrainerProfile 과 같은 값을 쓴다', () async {
      final MockGymRepository repo = MockGymRepository();
      final Gym? gym = await repo.fetchMyGym();
      final Trainer? trainer = await repo.fetchMyTrainer();

      expect(gym, isNotNull);
      expect(gym!.name, '온케어짐 신촌점');
      expect(gym.address, '서울 서대문구 신촌로 120');
      expect(gym.phone, '02-1234-5678');
      expect(gym.weekdayHours, '06:00 – 23:00');

      expect(trainer, isNotNull);
      expect(trainer!.name, '김트레이너');
      expect(trainer.role, '퍼스널 트레이너');
      expect(trainer.gymId, gym.id);
      expect(trainer.career, '7년');
      expect(
        trainer.intro,
        '혈압 관리와 체중 감량을 함께 다루는 퍼스널 트레이너입니다. 회원 상태에 맞춘 AI 추천 프로그램을 활용해 안전한 강도부터 시작합니다.',
      );
      expect(trainer.certifications, <String>[
        '생활스포츠지도사 2급',
        '퍼스널트레이닝 CPT',
        '스포츠 영양사',
      ]);
    });

    test('한 헬스장이 트레이너 여러 명을 가질 수 있다', () async {
      final MockGymRepository repo = MockGymRepository();
      final List<Trainer> sinchon = await repo.fetchTrainersByGym(
        'gym-oncare-sinchon',
      );

      expect(sinchon.length, greaterThan(1));
      expect(
        sinchon.every((Trainer t) => t.gymId == 'gym-oncare-sinchon'),
        isTrue,
      );
      // id 는 서로 겹치지 않아야 상세 라우팅이 정확히 한 명을 가리킨다.
      expect(sinchon.map((Trainer t) => t.id).toSet().length, sinchon.length);
    });

    test('트레이너를 id 로 조회하고, 없으면 null 이다', () async {
      final MockGymRepository repo = MockGymRepository();

      expect((await repo.fetchTrainer('trainer-kim'))?.name, '김트레이너');
      expect(await repo.fetchTrainer('trainer-nope'), isNull);
    });

    test('추천 트레이너는 추천 사유가 있는 사람만 나온다', () async {
      final MockGymRepository repo = MockGymRepository();
      final List<Trainer> recommended = await repo.fetchRecommendedTrainers();

      expect(recommended, isNotEmpty);
      expect(
        recommended.every((Trainer t) => t.reason?.isNotEmpty ?? false),
        isTrue,
      );
    });
  });

  test('트레이너 연결 해제 후에도 같은 헬스장의 운영시간을 유지한다', () async {
    final MockGymRepository repository = MockGymRepository();
    final Gym? before = await repository.fetchMyGym();

    await repository.disconnectMyTrainer();
    final Gym? after = await repository.fetchMyGym();

    expect(after, isNotNull);
    expect(after!.id, before!.id);
    expect(after.weekdayHours, before.weekdayHours);
    expect(await repository.fetchMyTrainer(), isNull);
  });
}
