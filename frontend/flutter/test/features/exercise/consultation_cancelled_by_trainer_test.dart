/// 트레이너가 상담 일정을 취소·삭제해 신청이 철회되면, 회원 카드가 "확정" 으로
/// 남지 않고 트레이너가 취소했다는 안내를 보여 준다 (#2758).
///
/// 같은 `cancelled` 상태라도 회원이 스스로 취소한 신청에는 이 안내가 붙지
/// 않는다 — 서버가 `cancelled_by_trainer` 로 둘을 가른다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/widgets/consultation_request_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// `GET /consultations/me` 한 줄.
Map<String, Object?> _row({
  String status = 'cancelled',
  Object? cancelledByTrainer,
  String slotStartsAt = '2031-04-13T22:00:00Z',
}) => <String, Object?>{
  'id': 'consult-1',
  'member_id': 'user-1',
  'target_type': 'trainer',
  'trainer_id': 'trainer-1',
  'trainer_name': '김태오',
  'exercise_goal': 'strength',
  'health_purpose_type': 'general',
  'preferred_date': '2031-04-14',
  'preferred_time_slot': '07:00',
  'slot_id': null,
  'slot_starts_at': slotStartsAt,
  'slot_duration_minutes': 30,
  'status': status,
  'decision_note': null,
  'decided_at': '2031-04-10T01:00:00Z',
  'created_at': '2031-04-09T10:00:00Z',
  'updated_at': '2031-04-10T01:00:00Z',
  'cancelled_by_trainer': ?cancelledByTrainer,
};

Map<String, Object?> _slotJson({int remaining = 1, Object? overlapped}) =>
    <String, Object?>{
      'id': 'slot-1',
      'trainer_id': 'trainer-1',
      'starts_at': '2031-04-13T22:00:00Z',
      'duration_minutes': 60,
      'capacity': 1,
      'remaining': remaining,
      'is_closed': false,
      'session_type': '1:1 PT',
      'overlapped': ?overlapped,
    };

Future<void> _pumpCard(WidgetTester tester, ConsultationRequest request) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConsultationRequestCard(request: request),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const Key _trainerCancelNote = Key('consult-outcome-cancelled-by-trainer');

void main() {
  group('consultationFromJson', () {
    test('트레이너가 철회한 신청을 읽는다', () {
      final ConsultationRequest request = consultationFromJson(
        _row(cancelledByTrainer: true),
      );

      expect(request.status, ConsultationStatus.cancelled);
      expect(request.cancelledByTrainer, isTrue);
    });

    test('회원이 취소한 신청은 트레이너 철회가 아니다', () {
      final ConsultationRequest request = consultationFromJson(
        _row(cancelledByTrainer: false),
      );

      expect(request.status, ConsultationStatus.cancelled);
      expect(request.cancelledByTrainer, isFalse);
    });

    test('필드가 없는 예전 응답은 트레이너 철회가 아니다', () {
      expect(consultationFromJson(_row()).cancelledByTrainer, isFalse);
    });

    test('copyWith 가 트레이너 철회 표시를 잃지 않는다', () {
      final ConsultationRequest request = consultationFromJson(
        _row(cancelledByTrainer: true),
      ).copyWith(id: 'server-id');

      expect(request.id, 'server-id');
      expect(request.cancelledByTrainer, isTrue);
    });

    test('일정을 옮긴 상담은 옮긴 시각을 그대로 읽는다', () {
      // 서버는 일정이 옮겨지면 slot_starts_at 을 일정 시각으로 준다.
      final ConsultationRequest request = consultationFromJson(
        _row(status: 'accepted', slotStartsAt: '2031-04-14T01:00:00Z'),
      );

      // 01:00Z 는 KST 10:00 이다 — 엔티티는 KST 벽시계를 든다(#2876).
      expect(request.slotStartsAt, DateTime(2031, 4, 14, 10));
    });
  });

  group('trainerSlotFromJson (#2761)', () {
    test('트레이너 일정과 겹친 자리는 마감이다', () {
      expect(trainerSlotFromJson(_slotJson(overlapped: true)).booked, isTrue);
    });

    test('겹치지 않은 빈 자리는 예약할 수 있다', () {
      expect(trainerSlotFromJson(_slotJson()).booked, isFalse);
      expect(trainerSlotFromJson(_slotJson(overlapped: false)).booked, isFalse);
    });

    test('남은 자리가 없으면 겹침과 무관하게 마감이다', () {
      expect(trainerSlotFromJson(_slotJson(remaining: 0)).booked, isTrue);
    });
  });

  group('ConsultationRequestCard', () {
    testWidgets('트레이너가 취소한 신청에는 안내를 보여 준다', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        consultationFromJson(_row(cancelledByTrainer: true)),
      );

      expect(find.byKey(_trainerCancelNote), findsOneWidget);
      expect(find.textContaining('트레이너가 상담 일정을 취소했어요'), findsOneWidget);
    });

    testWidgets('회원이 취소한 신청에는 안내가 없다', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        consultationFromJson(_row(cancelledByTrainer: false)),
      );

      expect(find.byKey(_trainerCancelNote), findsNothing);
      expect(find.textContaining('트레이너가 상담 일정을 취소했어요'), findsNothing);
    });

    testWidgets('확정된 신청에는 안내가 없다', (WidgetTester tester) async {
      await _pumpCard(tester, consultationFromJson(_row(status: 'accepted')));

      expect(find.byKey(_trainerCancelNote), findsNothing);
    });
  });
}
