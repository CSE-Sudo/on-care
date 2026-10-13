/// 트레이너가 탈퇴해 이름이 없는 상담 카드는 빈칸 대신 대체 문구를 보여 준다 (#3360).
///
/// 트레이너 행이 지워지면 서버는 요청을 남기되 `trainer_name` 을 비워 준다. 카드
/// 제목 줄이 빈칸이면 누구에게 낸 상담이었는지 읽을 수 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_complete_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/consultation_request_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// `GET /consultations/me` 한 줄. 탈퇴한 트레이너의 요청은 `trainer_id`·
/// `trainer_name` 이 null 로 온다.
Map<String, Object?> _row({
  Object? trainerName,
  Object? trainerGymName,
  String status = 'cancelled',
}) => <String, Object?>{
  'id': 'consult-1',
  'member_id': 'user-1',
  'target_type': 'trainer',
  'trainer_id': trainerName == null ? null : 'trainer-1',
  'trainer_name': trainerName,
  'trainer_gym_name': trainerGymName,
  'exercise_goal': 'strength',
  'health_purpose_type': 'general',
  'preferred_date': '2031-04-14',
  'preferred_time_slot': '07:00',
  'slot_id': null,
  'slot_starts_at': null,
  'slot_duration_minutes': null,
  'status': status,
  'decision_note': null,
  'decided_at': '2031-04-10T01:00:00Z',
  'created_at': '2031-04-09T10:00:00Z',
  'updated_at': '2031-04-10T01:00:00Z',
  'cancelled_by_trainer': false,
};

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _card(ConsultationRequest request) => Scaffold(
  body: SingleChildScrollView(child: ConsultationRequestCard(request: request)),
);

void main() {
  group('consultationFromJson', () {
    test('탈퇴한 트레이너의 요청은 이름 없이 읽힌다', () {
      final ConsultationRequest request = consultationFromJson(_row());

      expect(request.trainerId, isNull);
      expect(request.trainerName, isNull);
      expect(request.status, ConsultationStatus.cancelled);
    });
  });

  group('ConsultationRequestCard', () {
    testWidgets('이름이 없으면 대체 문구를 제목으로 적는다', (WidgetTester tester) async {
      await _pump(tester, _card(consultationFromJson(_row())));

      expect(find.text('트레이너 정보 없음'), findsOneWidget);
      // 소속도 모르면 둘째 줄은 종류 문구다 — 대체 문구를 두 번 적지 않는다.
      expect(find.text('트레이너 상담'), findsOneWidget);
    });

    testWidgets('빈 문자열 이름도 대체 문구로 바꾼다', (WidgetTester tester) async {
      await _pump(tester, _card(consultationFromJson(_row(trainerName: '  '))));

      expect(find.text('트레이너 정보 없음'), findsOneWidget);
    });

    testWidgets('수락된 채 남은 지난 상담도 이름 칸이 비지 않는다', (WidgetTester tester) async {
      await _pump(
        tester,
        _card(consultationFromJson(_row(status: 'accepted'))),
      );

      expect(find.text('트레이너 정보 없음'), findsOneWidget);
    });

    testWidgets('이름이 있으면 그 이름을 그대로 적는다', (WidgetTester tester) async {
      await _pump(
        tester,
        _card(
          consultationFromJson(
            _row(trainerName: '김태오', trainerGymName: '온케어짐 신촌점'),
          ),
        ),
      );

      expect(find.text('김태오'), findsOneWidget);
      expect(find.text('온케어짐 신촌점'), findsOneWidget);
      expect(find.text('트레이너 정보 없음'), findsNothing);
    });

    testWidgets('소속을 모르면 예전처럼 이름을 둘째 줄에도 적는다', (WidgetTester tester) async {
      await _pump(
        tester,
        _card(consultationFromJson(_row(trainerName: '김태오'))),
      );

      expect(find.text('김태오'), findsNWidgets(2));
      expect(find.text('트레이너 상담'), findsNothing);
    });
  });

  group('ConsultationCompletePage', () {
    testWidgets('이름이 없으면 요약 줄에 대체 문구를 적는다', (WidgetTester tester) async {
      await _pump(
        tester,
        ConsultationCompletePage(
          request: consultationFromJson(_row(status: 'pending')),
        ),
      );

      expect(find.text('트레이너 정보 없음'), findsOneWidget);
    });
  });
}
