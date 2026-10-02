/// 트레이너 데모 프로필의 영어판과 숫자로 옮긴 경력 (#2304).
///
/// 경력은 `'7년'` 같은 문구가 아니라 연수(숫자)로 들고, 화면이 로케일에 맞는
/// 단위를 붙인다. 데모 프로필은 앱이 켜질 때 정한 데모 언어를 따른다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/features/auth/data/dtos/trainer_me_dto.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/data/repositories/mock_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

import '../../helpers/pump_app.dart';

final RegExp _hangul = RegExp(r'[가-힣]');

/// 이름을 뺀, 화면에 글로 뜨는 프로필 값.
List<String> _profileText(TrainerProfile p) => <String>[
  p.specialty,
  p.intro,
  ...p.certifications,
  p.gym.name,
  p.gym.address,
  p.gym.hours,
];

/// 경력 1년 트레이너로 로그인한 데모.
class _OneYearAuthRepository extends MockTrainerAuthRepository {
  const _OneYearAuthRepository() : super(language: DemoLanguage.en);

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      seedTrainerProfileEn.copyWith(careerYears: 1);
}

const AppConfig _demoConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

void main() {
  group('seedTrainerProfileFor', () {
    test('한국어는 지금까지의 데모 프로필 그대로다', () {
      final p = seedTrainerProfileFor(DemoLanguage.ko);
      expect(identical(p, seedTrainerProfile), isTrue);
      expect(p.specialty, '퍼스널 트레이너');
      expect(p.gym.name, '온케어짐 신촌점');
    });

    test('영어는 이름 밖에 한글이 없다', () {
      final p = seedTrainerProfileFor(DemoLanguage.en);
      for (final text in _profileText(p)) {
        expect(text, isNot(matches(_hangul)), reason: text);
      }
      expect(p.specialty, 'Personal trainer');
      expect(p.gym.name, 'OnCare Gym Sinchon');
    });

    test('이름·연락처·경력·자격 개수는 두 언어가 같다', () {
      final ko = seedTrainerProfileFor(DemoLanguage.ko);
      final en = seedTrainerProfileFor(DemoLanguage.en);
      expect(en.name, ko.name);
      expect(en.name, kDemoTrainerName);
      expect(en.email, ko.email);
      expect(en.phone, ko.phone);
      expect(en.careerYears, ko.careerYears);
      expect(en.careerYears, 7);
      expect(en.certifications, hasLength(ko.certifications.length));
      expect(en.gym.phone, ko.gym.phone);
      expect(en.gym.hours, ko.gym.hours);
    });

    test('copyWith 는 경력 연수를 바꾸고, 안 주면 그대로 둔다', () {
      expect(seedTrainerProfile.copyWith(careerYears: 12).careerYears, 12);
      expect(seedTrainerProfile.copyWith(phone: '010').careerYears, 7);
    });
  });

  group('careerYearsFromJson', () {
    test('숫자 career_years 가 먼저다', () {
      expect(
        careerYearsFromJson(<String, Object?>{
          'career_years': 9,
          'career': '7년',
        }),
        9,
      );
      expect(careerYearsFromJson(<String, Object?>{'career_years': 3.0}), 3);
    });

    test('없으면 career 문구의 앞 숫자를 읽고 단위는 버린다', () {
      expect(careerYearsFromJson(<String, Object?>{'career': '7년'}), 7);
      expect(careerYearsFromJson(<String, Object?>{'career': ' 12 years'}), 12);
      expect(careerYearsFromJson(<String, Object?>{'career': '0년'}), 0);
    });

    test('숫자가 없거나 앞에 오지 않으면 비운다', () {
      expect(careerYearsFromJson(const <String, Object?>{}), isNull);
      expect(careerYearsFromJson(<String, Object?>{'career': ''}), isNull);
      expect(careerYearsFromJson(<String, Object?>{'career': '신입'}), isNull);
      expect(careerYearsFromJson(<String, Object?>{'career': '경력 7년'}), isNull);
      expect(careerYearsFromJson(<String, Object?>{'career': 7}), isNull);
      expect(
        careerYearsFromJson(<String, Object?>{'career_years': '7'}),
        isNull,
        reason: '문자열 career_years 는 계약 밖이다',
      );
    });

    test('/trainers/me 응답의 career 문구가 연수로 들어온다', () {
      final profile = trainerProfileFromJson(<String, Object?>{
        'name': kDemoTrainerName,
        'email': 'trainer@oncare.com',
        'career': '5년',
      });
      expect(profile.careerYears, 5);
    });
  });

  group('경력 문구 (ARB)', () {
    test('한국어', () {
      final l = lookupAppLocalizations(const Locale('ko'));
      expect(l.myCareerYears(7), '경력 7년');
      expect(l.myCareerYears(1), '경력 1년');
      expect(l.myCareerYears(0), '경력 0년');
    });

    test('영어는 단수·복수를 가린다', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(l.myCareerYears(7), '7 years of experience');
      expect(l.myCareerYears(1), '1 year of experience');
      expect(l.myCareerYears(0), '0 years of experience');
    });
  });

  group('데모 저장소', () {
    test('프로필 저장소는 데모 언어의 프로필·헬스장 검색 결과를 준다', () async {
      final en = MockTrainerProfileRepository(language: DemoLanguage.en);
      final profile = await en.fetch();
      expect(profile.specialty, 'Personal trainer');
      final List<TrainerGymCandidate> gyms = await en.searchGyms('gym');
      expect(gyms.map((TrainerGymCandidate g) => g.name), <String>[
        'OnCare Gym Sinchon',
        'OnCare Gym Gangnam',
        'OnCare Yeonhui Studio',
      ]);
      for (final TrainerGymCandidate gym in gyms) {
        expect(gym.address, isNot(matches(_hangul)));
      }

      final ko = MockTrainerProfileRepository();
      expect((await ko.fetch()).specialty, '퍼스널 트레이너');
      final List<TrainerGymCandidate> koGyms = await ko.searchGyms('헬스');
      expect(koGyms.first.name, '온케어짐 신촌점');
      expect(
        koGyms.map((TrainerGymCandidate g) => g.id),
        gyms.map((TrainerGymCandidate g) => g.id),
        reason: '헬스장 id 는 언어와 상관없다',
      );
    });

    test('프로필 수정은 경력 연수를 숫자로 저장한다', () async {
      final repo = MockTrainerProfileRepository(language: DemoLanguage.en);
      final updated = await repo.update(
        const TrainerProfileUpdate(
          phone: '010-0000-0000',
          specialty: 'Strength coach',
          careerYears: 1,
          intro: 'Hi',
          certifications: <String>[],
        ),
      );
      expect(updated.careerYears, 1);
      expect((await repo.fetch()).careerYears, 1);
    });

    test('로그인 목 저장소도 데모 언어의 프로필을 붙인다', () async {
      const en = MockTrainerAuthRepository(language: DemoLanguage.en);
      expect((await en.fetchProfile('t')).specialty, 'Personal trainer');
      const ko = MockTrainerAuthRepository();
      expect((await ko.fetchProfile('t')).specialty, '퍼스널 트레이너');
    });

    test('프로바이더가 데모 언어를 저장소에 넘긴다', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demoConfig),
          appDatabaseProvider.overrideWithValue(_memoryDb()),
          demoLanguageProvider.overrideWithValue(DemoLanguage.en),
        ],
      );
      addTearDown(container.dispose);

      final profiles = container.read(trainerProfileRepositoryProvider);
      expect((await profiles.fetch()).gym.name, 'OnCare Gym Sinchon');
      final auth = container.read(trainerAuthRepositoryProvider);
      expect((await auth.fetchProfile('t')).gym.name, 'OnCare Gym Sinchon');
    });

    test('데모 언어를 덮어쓰지 않으면 한국어다', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demoConfig),
          appDatabaseProvider.overrideWithValue(_memoryDb()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(demoLanguageProvider), DemoLanguage.ko);
      final profiles = container.read(trainerProfileRepositoryProvider);
      expect((await profiles.fetch()).gym.name, '온케어짐 신촌점');
    });
  });

  // 전문 분야·경력은 프로필 카드의 한 줄 글이다(#2264) — `분야 · 경력`.
  group('MyPage 경력 표기', () {
    testWidgets('한국어 — 경력 7년', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
      );
      expect(find.text('퍼스널 트레이너 · 경력 7년'), findsOneWidget);
      expect(find.textContaining('7 years of experience'), findsNothing);
    });

    testWidgets('영어 — 7 years of experience, 프로필도 영어', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
        locale: const Locale('en'),
        extraOverrides: <Override>[
          demoLanguageProvider.overrideWithValue(DemoLanguage.en),
        ],
      );
      expect(
        find.text('Personal trainer · 7 years of experience'),
        findsOneWidget,
      );
      expect(find.text('Sports Instructor Level 2'), findsOneWidget);
      expect(find.text(kDemoTrainerName), findsWidgets);
      expect(find.textContaining('경력'), findsNothing);
      expect(find.text('퍼스널 트레이너'), findsNothing);
    });

    testWidgets('영어 — 1년이면 단수', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
        locale: const Locale('en'),
        extraOverrides: <Override>[
          demoLanguageProvider.overrideWithValue(DemoLanguage.en),
          trainerAuthRepositoryProvider.overrideWithValue(
            const _OneYearAuthRepository(),
          ),
        ],
      );
      expect(
        find.text('Personal trainer · 1 year of experience'),
        findsOneWidget,
      );
    });
  });
}

/// 데모 저장소가 바꾼 값을 적는 메모리 DB(#2669). 테스트가 끝나면 닫는다.
AppDatabase _memoryDb() {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}
