/// 담당 해제·동의 철회 회원의 로스터 카드는 성별·나이·건강 목표를 적지 않는다.
/// (#2814)
///
/// 서버 로스터(`build_roster`)는 그 관계에서 세 값을 비워 보낸다. 화면이
/// 빈 성별을 `기타` 로 읽거나 id 로 성별을 지어내면, 가린 자리에 다시 값이
/// 보인다. 데모 로스터도 담당을 해제한 회원을 같은 규칙으로 그린다.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';

Map<String, Object?> _row({
  required bool registered,
  String gender = 'female',
  int? age = 41,
  String goal = '혈압 관리',
}) => <String, Object?>{
  'id': 'm-2814',
  'name': '가회원',
  'avatar': '가',
  'gender': gender,
  'age': age,
  'goal': goal,
  'active': true,
  'registered': registered,
};

Future<void> _pump(
  WidgetTester tester,
  TrainerClient client, {
  Locale locale = const Locale('ko'),
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ClientRow(client: client)),
  ),
);

void main() {
  group('trainerClientFromJson — 해제된 관계', () {
    test('담당 해제 행은 서버가 값을 실어 보내도 비운다', () {
      final TrainerClient c = trainerClientFromJson(_row(registered: false));

      expect(c.registered, isFalse);
      expect(c.gender, '');
      expect(c.age, isNull);
      expect(c.goal, '');
      expect(c.rosterGender, '');
      expect(c.rosterAge, isNull);
      // 이름은 관계 이력 식별용으로 남는다.
      expect(c.name, '가회원');
    });

    test('담당 중인 행은 서버 값을 그대로 쓴다', () {
      final TrainerClient c = trainerClientFromJson(_row(registered: true));

      expect(c.rosterGender, 'female');
      expect(c.rosterAge, 41);
      expect(c.goal, '혈압 관리');
    });

    test('동의 철회 행(담당 중·서버가 비움)은 빈 값 그대로다', () {
      final TrainerClient c = trainerClientFromJson(
        _row(registered: true, gender: '', age: null, goal: ''),
      );

      expect(c.rosterGender, '');
      expect(c.rosterAge, isNull);
      expect(c.goal, '');
    });
  });

  group('로스터 행 — 빈 성별·나이·목표', () {
    testWidgets('철회 회원 카드에는 성별·나이·목표가 없다', (tester) async {
      await _pump(
        tester,
        trainerClientFromJson(
          _row(registered: true, gender: '', age: null, goal: ''),
        ),
      );

      expect(find.text('가회원'), findsOneWidget);
      // 빈 값을 `기타` 로 읽지 않는다.
      expect(find.textContaining('기타'), findsNothing);
      expect(find.textContaining('여성'), findsNothing);
      expect(find.textContaining('남성'), findsNothing);
      expect(find.textContaining('세'), findsNothing);
      expect(find.textContaining('혈압'), findsNothing);
      // "기록 없음" 같은 오해 문구도 없다.
      expect(find.textContaining('없음'), findsNothing);
    });

    testWidgets('해제 회원 카드도 같다 (영어)', (tester) async {
      await _pump(
        tester,
        trainerClientFromJson(_row(registered: false)),
        locale: const Locale('en'),
      );

      expect(find.text('가회원'), findsOneWidget);
      expect(find.textContaining('Other'), findsNothing);
      expect(find.textContaining('Female'), findsNothing);
      expect(find.textContaining('Age'), findsNothing);
    });

    testWidgets('담당·동의 회원 카드는 지금과 같다', (tester) async {
      await _pump(tester, trainerClientFromJson(_row(registered: true)));

      expect(find.text('여성 · 41세'), findsOneWidget);
      expect(find.text('혈압 관리'), findsOneWidget);
    });
  });

  group('데모 로스터 — 담당 해제 회원', () {
    late AppDatabase db;
    late DriftClientRepository repository;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
      repository = DriftClientRepository(db);
    });

    tearDown(() => db.close());

    TrainerClient byId(List<TrainerClient> clients, String id) =>
        clients.firstWhere((TrainerClient c) => c.id == id);

    test('해제하면 성별·나이·목표가 비고, 되살리면 돌아온다', () async {
      final TrainerClient before = byId(
        await repository.watchClients().first,
        'seed-client-3',
      );
      expect(before.rosterGender, isNotEmpty);
      expect(before.goal, isNotEmpty);

      await repository.removeClient('seed-client-3');
      final TrainerClient released = byId(
        await repository.watchClients().first,
        'seed-client-3',
      );
      expect(released.registered, isFalse);
      expect(released.rosterGender, '');
      expect(released.rosterAge, isNull);
      expect(released.goal, '');
      expect(released.name, before.name);

      await repository.restoreClient('seed-client-3');
      final TrainerClient restored = byId(
        await repository.watchClients().first,
        'seed-client-3',
      );
      expect(restored.rosterGender, before.rosterGender);
      expect(restored.rosterAge, before.rosterAge);
      expect(restored.goal, before.goal);
    });

    test('다른 회원 카드는 그대로다', () async {
      await repository.removeClient('seed-client-3');
      final TrainerClient other = byId(
        await repository.watchClients().first,
        'seed-client-2',
      );
      expect(other.registered, isTrue);
      expect(other.rosterGender, isNotEmpty);
      expect(other.goal, isNotEmpty);
    });
  });
}
