// 트레이너가 운동을 보낸 자리에 대화 가운데 안내가 서는지 (#2672).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  test('서버 응답의 routine_delivery 를 읽고, 없거나 깨지면 일반 메시지다', () {
    Map<String, Object?> json(Object? delivery) => <String, Object?>{
      'id': 'chat-1',
      'sender': 'trainer',
      'body': '운동을 보냈어요: 스쿼트',
      'time_label': '10:00',
      'created_at': '2026-08-20T10:00:00+09:00',
      'routine_delivery': delivery,
    };

    final CoachMessage card = coachMessageFromJson(
      json(<String, Object?>{
        'kind': 'routine_only',
        'program_names': <Object?>[],
        'routine_names': <Object?>['걷기', '플랭크'],
      }),
    );
    expect(card.routineDelivery?.kind, 'routine_only');
    expect(card.routineDelivery?.routineNames, <String>['걷기', '플랭크']);

    expect(coachMessageFromJson(json(null)).routineDelivery, isNull);
    expect(coachMessageFromJson(json('broken')).routineDelivery, isNull);
  });

  testWidgets('안내는 종류별 제목과 운동 이름 셋까지를 적는다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: CoachRoutineDeliveryNotice(
            delivery: CoachRoutineDelivery(
              kind: 'pt_with_routine',
              programNames: <String>['스쿼트', '데드리프트'],
              routineNames: <String>['걷기', '플랭크'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('PT 프로그램과 개인운동을 받았어요'), findsOneWidget);
    expect(find.text('스쿼트 · 데드리프트 · 걷기 외 1개'), findsOneWidget);
  });
}
