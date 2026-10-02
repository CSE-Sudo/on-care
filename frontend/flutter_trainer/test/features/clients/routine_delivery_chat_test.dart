// 운동을 보낸 일이 채팅 가운데 안내로 남는지 (#2672).
//
// 실서버는 운동을 보내면 알림과 함께 채팅에 전송 안내 메시지를 남기고
// (`routine_delivery`), 두 앱이 그것을 리포트 안내처럼 가운데 카드로 그린다.
// 데모에는 날이 바뀔 때마다 실제와 상관없이 `루틴 전송됨` 배너가 붙었는데,
// 이제 실제로 보낸 자리에만 같은 카드가 선다.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/dtos/chat_dtos.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  test('서버 응답의 routine_delivery 를 안내로 읽고, 없으면 일반 메시지다', () {
    final ClientChatMessage card = chatMessageFromJson(<String, Object?>{
      'id': 'chat-1',
      'sender': 'trainer',
      'body': '운동을 보냈어요: 스쿼트',
      'time_label': '10:00',
      'created_at': '2026-08-20T10:00:00+09:00',
      'routine_delivery': <String, Object?>{
        'kind': 'pt_with_routine',
        'program_names': <String>['스쿼트'],
        'routine_names': <String>['걷기'],
      },
    });
    expect(card.routineDelivery?.kind, 'pt_with_routine');
    expect(card.routineDelivery?.programNames, <String>['스쿼트']);
    expect(card.routineDelivery?.routineNames, <String>['걷기']);

    final ClientChatMessage plain = chatMessageFromJson(<String, Object?>{
      'id': 'chat-2',
      'sender': 'client',
      'body': '네',
      'time_label': '10:01',
      'created_at': '2026-08-20T10:01:00+09:00',
    });
    expect(plain.routineDelivery, isNull);
  });

  group('데모', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test('시드 대화에는 첫 배정을 보낸 안내가 한 건 있다 — 김민수는 없다', () async {
      final repo = DriftChatRepository(db);
      final jisu = await repo.watchThread('seed-client-2').first;
      final cards = jisu.where((m) => m.routineDelivery != null).toList();
      expect(cards, hasLength(1));
      expect(cards.single.routineDelivery!.kind, 'routine_only');
      expect(cards.single.routineDelivery!.routineNames, contains('스쿼트'));
      // 대화가 시작되기 전이라 마지막 메시지는 그대로 회원의 말이다.
      expect(jisu.last.routineDelivery, isNull);

      // 김민수 대화는 회원 앱 데모와 같아야 해 안내를 심지 않는다.
      final minsu = await repo.watchThread('seed-client-1').first;
      expect(minsu.where((m) => m.routineDelivery != null), isEmpty);
    });

    test('개인운동을 보내면 대화 끝에 안내가 서고 목록 미리보기도 바뀐다', () async {
      final routines = MockTrainerRoutineRepository(db: db);
      addTearDown(routines.dispose);
      await routines.assignProgram('seed-client-3', <String, Object?>{
        'name': '개인운동',
        'delivery_kind': 'routine_only',
        'sessions': <Object?>[
          <String, Object?>{
            'id': 's1',
            'name': '',
            'exercises': <Object?>[
              <String, Object?>{'id': 'e1', 'name': '실내 자전거', 'duration': 20},
            ],
          },
        ],
      });

      final thread = await DriftChatRepository(
        db,
      ).watchThread('seed-client-3').first;
      expect(thread.last.routineDelivery?.kind, 'routine_only');
      expect(thread.last.routineDelivery?.routineNames, <String>['실내 자전거']);
      final client = await (db.select(
        db.trainerClients,
      )..where((c) => c.id.equals('seed-client-3'))).getSingle();
      expect(client.lastMessage, ChatPreviewCode.routineDelivered);
    });

    test('단건 배정(AI 제안 승인)도 안내를 남긴다', () async {
      final routines = MockTrainerRoutineRepository(db: db);
      addTearDown(routines.dispose);
      await routines.assignRoutine(
        'seed-client-4',
        const AssignedRoutine(
          id: '',
          name: '버드독',
          minutes: 10,
          type: '근력',
          reason: '',
          source: 'ai',
        ),
      );
      final thread = await DriftChatRepository(
        db,
      ).watchThread('seed-client-4').first;
      expect(thread.last.routineDelivery?.kind, 'routine');
      expect(thread.last.routineDelivery?.routineNames, <String>['버드독']);
    });
  });

  testWidgets('안내 카드는 종류별 제목과 운동 이름 셋까지를 적는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: RoutineDeliveryCard(
            notice: RoutineDeliveryNotice(
              kind: 'pt_with_routine',
              programNames: <String>['스쿼트', '데드리프트'],
              routineNames: <String>['걷기', '플랭크'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('PT 프로그램과 개인운동을 보냈어요'), findsOneWidget);
    expect(find.text('스쿼트 · 데드리프트 · 걷기 외 1개'), findsOneWidget);
  });
}
