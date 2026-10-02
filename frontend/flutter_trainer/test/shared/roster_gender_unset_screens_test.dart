import 'package:drift/drift.dart' show StringExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';

import '../helpers/client_factory.dart';
import '../helpers/pump_app.dart';

/// 성별을 적지 않은 회원에게 화면이 성별을 지어내지 않는다. (#2870)
///
/// 예전에는 회원 id 문자 코드 합의 짝홀로 `남성`/`여성` 을 골라, 회원 행·상세
/// 머리·대시보드·연결 카드·건강 프로필 기본값에 그대로 보였다.
void main() {
  final RegExp anyGender = RegExp(r'남성|여성|기타');

  Future<void> pumpBlock(WidgetTester tester, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  group('회원 행', () {
    testWidgets('성별·나이 둘 다 없으면 이름만 그린다', (tester) async {
      // 짝·홀 두 id 모두 — 예전 폴백은 이 둘에 서로 다른 성별을 지었다.
      await pumpBlock(
        tester,
        Column(
          children: <Widget>[
            ClientIdentityBlock(
              client: makeClient(id: 'seed-client-1', name: '가회원'),
            ),
            ClientIdentityBlock(
              client: makeClient(id: 'seed-client-2', name: '나회원'),
            ),
          ],
        ),
      );

      expect(find.text('가회원'), findsOneWidget);
      expect(find.text('나회원'), findsOneWidget);
      expect(find.textContaining(anyGender), findsNothing);
      // 빈 구분 문구 자리도 그리지 않는다.
      expect(find.text(''), findsNothing);
    });

    testWidgets('성별만 없으면 나이만 적는다', (tester) async {
      await pumpBlock(
        tester,
        ClientIdentityBlock(
          client: makeClient(id: 'seed-client-1', name: '가회원', age: 41),
        ),
      );

      expect(find.text('41세'), findsOneWidget);
      expect(find.textContaining(anyGender), findsNothing);
    });

    testWidgets('쌓은 모양에서도 같다', (tester) async {
      await pumpBlock(
        tester,
        ClientIdentityBlock(
          client: makeClient(id: 'seed-client-1', name: '가회원'),
          stacked: true,
        ),
      );

      expect(find.text('가회원'), findsOneWidget);
      expect(find.textContaining(anyGender), findsNothing);
      expect(find.text(''), findsNothing);
    });
  });

  testWidgets('회원 상세 머리는 성별을 지어내지 않는다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(id: 'seed-client-1', name: '김민수'),
          ]),
        ),
      ],
    );

    final Finder row = find.byKey(
      const ValueKey<String>('client-detail-name-row'),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('김민수')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('client-detail-demographics')),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining(anyGender)),
      findsNothing,
    );
  });

  testWidgets('회원 상세 머리는 아는 나이만 적는다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(id: 'seed-client-1', name: '김민수', age: 36),
          ]),
        ),
      ],
    );

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('client-detail-demographics')),
          )
          .data,
      '36세',
    );
  });

  group('데모 건강 프로필', () {
    test('저장된 성별이 없으면 지어낸 성별로 채우지 않는다', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await seedIfEmpty(db);
      await (db.delete(
        db.appKeyValues,
      )..where((t) => t.key.like('member_health_profile:%'))).go();
      // 시드는 성별을 저장하므로, 미입력 회원을 만들려고 비운다.
      await (db.update(db.trainerClients)..where(
            (t) => t.id.isIn(<String>['seed-client-1', 'seed-client-2']),
          ))
          .write(const TrainerClientsCompanion(gender: Value<String?>(null)));
      final repository = DriftClientRepository(db);

      for (final id in <String>['seed-client-1', 'seed-client-2']) {
        final profile = await repository.fetchHealthProfile(id);
        expect(profile.gender, '', reason: id);
      }
    });

    test('저장된 성별은 그대로 쓴다', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await seedIfEmpty(db);
      final repository = DriftClientRepository(db);
      final clients = await repository.watchClients().first;
      final withGender = clients.firstWhere((c) => c.gender.isNotEmpty);

      final profile = await repository.fetchHealthProfile(withGender.id);

      expect(profile.gender, isNotEmpty);
    });
  });
}
