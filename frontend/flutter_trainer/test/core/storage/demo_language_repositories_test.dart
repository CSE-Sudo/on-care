/// 데모 저장소들이 앱이 정한 데모 언어를 따르는가 (#2304).
///
/// 상담 신청 메시지, 등록 후보 회원의 목표, 대화에서 옮긴 감지 메모는 로컬 DB
/// 시드 밖에서 만들어진다. 시드만 영어로 심으면 이 자리들이 한국어로 남는다.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/demo_member_directory.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/storage/seed_insight_memos.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fixed_clock.dart';

final RegExp _hangul = RegExp(r'[가-힣]');

/// 이수아 — 명부에만 있고 아직 등록되지 않은 회원.
const String _suaId = 'user-8f2a41c9d6e3';

/// 박준서 — 같은 명부의 다른 회원.
const String _junseoId = 'user-1c7b93f04a58';

const AppConfig _demoConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

Future<AppDatabase> _seeded(DemoLanguage language) async {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await seedIfEmpty(db, clock: kMidWeekKst, language: language);
  return db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('상담 신청 (DemoConsultationRepository)', () {
    Future<List<ConsultationRequest>> requests(DemoLanguage language) =>
        DemoConsultationRepository(language: language).fetch(status: 'all');

    test('영어 메시지에는 한글이 없고 이름은 그대로다', () async {
      final en = await requests(DemoLanguage.en);
      expect(en, hasLength(2));
      for (final request in en) {
        expect(request.message, isNotEmpty);
        expect(request.message, isNot(matches(_hangul)));
      }
      expect(en.map((r) => r.memberName), <String>['김하늘', '김민수']);
      expect(
        en.first.message,
        "I'd like my first consultation at a time that works after work.",
      );
    });

    test('한국어는 지금까지의 문구 그대로다', () async {
      final ko = await requests(DemoLanguage.ko);
      expect(ko.map((r) => r.message), <String>[
        '퇴근 후 가능한 시간으로 첫 상담을 받고 싶어요.',
        '혈압 관리도 같이 봐주시면 좋겠어요.',
      ]);
      expect(
        (await DemoConsultationRepository().fetch(
          status: 'all',
        )).map((r) => r.message),
        ko.map((r) => r.message),
        reason: '언어를 넘기지 않으면 한국어다',
      );
    });

    test('언어와 상관없는 값은 두 언어가 같다', () async {
      useFixedKstDate();
      final ko = await requests(DemoLanguage.ko);
      final en = await requests(DemoLanguage.en);
      for (var i = 0; i < ko.length; i++) {
        expect(en[i].id, ko[i].id);
        expect(en[i].memberId, ko[i].memberId);
        expect(en[i].goalCode, ko[i].goalCode);
        expect(en[i].purposeCode, ko[i].purposeCode);
        expect(en[i].slotStartsAt, ko[i].slotStartsAt);
        expect(en[i].slotDurationMinutes, ko[i].slotDurationMinutes);
        expect(en[i].status, ko[i].status);
      }
    });

    test('프로바이더가 데모 언어를 넘긴다', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demoConfig),
          demoLanguageProvider.overrideWithValue(DemoLanguage.en),
        ],
      );
      addTearDown(container.dispose);
      final rows = await container
          .read(consultationRepositoryProvider)
          .fetch(status: 'all');
      expect(rows.map((r) => r.message), everyElement(isNot(matches(_hangul))));
    });
  });

  group('등록 후보 명부 (DemoProspectiveMember)', () {
    test('목표는 언어마다 하나씩 있다', () {
      final sua = findDemoProspectiveMemberById(_suaId)!;
      expect(sua.goalIn(DemoLanguage.ko), '체중 감량');
      expect(sua.goalIn(DemoLanguage.en), 'Weight loss');
      final junseo = findDemoProspectiveMemberById(_junseoId)!;
      expect(junseo.goalIn(DemoLanguage.ko), '근력 향상');
      expect(junseo.goalIn(DemoLanguage.en), 'Strength');
    });
  });

  group('회원 등록 (DemoClientInviteRepository)', () {
    test('영어 데모 — 조회한 후보의 목표가 영어다', () async {
      final db = await _seeded(DemoLanguage.en);
      final repo = DemoClientInviteRepository(db, language: DemoLanguage.en);
      final found = await repo.lookup(_suaId);
      expect(found.name, '이수아');
      expect(found.goal, 'Weight loss');
    });

    test('영어 데모 — 등록한 회원 행에 한국어 문구가 남지 않는다', () async {
      final db = await _seeded(DemoLanguage.en);
      final repo = DemoClientInviteRepository(db, language: DemoLanguage.en);
      await repo.invite(_junseoId);

      final row = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals(_junseoId))).getSingle();
      expect(row.name, '박준서');
      expect(row.goal, 'Strength');
      expect(row.lastMessage, isEmpty, reason: '대화 없음 문구는 화면이 로케일에 맞춰 그린다');
    });

    test('한국어 데모 — 목표는 한국어, 대화 미리보기는 비어 있다', () async {
      final db = await _seeded(DemoLanguage.ko);
      final repo = DemoClientInviteRepository(db);
      expect((await repo.lookup(_suaId)).goal, '체중 감량');
      await repo.invite(_suaId);
      final row = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals(_suaId))).getSingle();
      expect(row.goal, '체중 감량');
      expect(row.lastMessage, isEmpty);
    });

    test('프로바이더가 데모 언어를 넘긴다', () async {
      final db = await _seeded(DemoLanguage.en);
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demoConfig),
          appDatabaseProvider.overrideWithValue(db),
          demoLanguageProvider.overrideWithValue(DemoLanguage.en),
        ],
      );
      addTearDown(container.dispose);
      final repo =
          container.read(clientInviteRepositoryProvider)
              as DemoClientInviteRepository;
      expect(repo.language, DemoLanguage.en);
    });
  });

  group('감지 메모 시드 (seedDemoInsightMemos)', () {
    Future<List<String>> memoBodies(DemoLanguage language) async {
      useFixedKstDate();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final db = await _seeded(language);
      await seedDemoInsightMemos(
        db,
        prefs,
        lookupAppLocalizations(language.locale),
      );
      return <String>[
        for (final key in prefs.getKeys().toList()..sort())
          if (key.startsWith('trainer_memos:'))
            for (final Object? memo
                in jsonDecode(prefs.getString(key)!) as List<Object?>)
              (memo! as Map<String, Object?>)['body']! as String,
      ];
    }

    test('영어 데모의 메모는 영어이고, 한국어와 개수가 같다', () async {
      final ko = await memoBodies(DemoLanguage.ko);
      final en = await memoBodies(DemoLanguage.en);
      expect(ko, isNotEmpty);
      expect(en, hasLength(ko.length));
      for (final body in en) {
        expect(body, isNot(matches(_hangul)), reason: body);
      }
      for (final body in ko) {
        expect(body, matches(_hangul), reason: body);
      }
    });
  });
}
