import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_program_section.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 유형마다 재는 단위가 다르다(#1276) — 근력은 세트·횟수·중량, 나머지는 시간.
///
/// 그 규칙이 값을 **받는·읽는** 자리에 없던 동안, 유산소 항목이 세트를 달고
/// 저장돼 상세 일정이 `저강도 유산소 (걷기) 3세트 · 30회` 라고 읽었다.
void main() {
  group('ProgramItem.byType', () {
    test('유산소는 세트·횟수·중량을 들지 않는다', () {
      const item = ProgramItem(
        name: '저강도 유산소 (걷기)',
        type: '유산소',
        duration: 30,
        sets: 3,
        reps: 30,
        weight: 12,
      );

      final normalised = item.byType;

      expect(normalised.duration, 30);
      expect(normalised.sets, isNull);
      expect(normalised.reps, isNull);
      expect(normalised.weight, isNull);
    });

    test('근력은 시간을 들지 않는다 — 세트로 재는 유형이다', () {
      const item = ProgramItem(
        name: '레그프레스',
        sets: 3,
        reps: 12,
        weight: 80,
        duration: 30,
      );

      final normalised = item.byType;

      expect(normalised.duration, isNull);
      expect(<Object?>[normalised.sets, normalised.reps, normalised.weight], <
        Object?
      >[3, 12, 80.0]);
    });
  });

  group('programItemFromJson', () {
    test('규칙이 서기 전에 저장된 행도 유형에 맞게 읽힌다', () {
      final item = programItemFromJson(<String, Object?>{
        'name': '하체 스트레칭',
        'type': '스트레칭',
        'duration': 10,
        'sets': 3,
        'reps': 15,
      });

      expect(item.duration, 10);
      expect(item.sets, isNull);
      expect(item.reps, isNull);
    });

    test('유형이 없던 예전 행은 근력으로 읽고 세트를 지킨다', () {
      final item = programItemFromJson(<String, Object?>{
        'name': '플랭크',
        'sets': '3세트',
        'reps': '3회',
      });

      expect(item.type, '근력');
      expect(<Object?>[item.sets, item.reps], <Object?>[3, 3]);
    });
  });

  group('SessionProgramRow', () {
    Future<void> pumpRow(WidgetTester tester, ProgramItem item) =>
        tester.pumpWidget(
          MaterialApp(
            // 행이 규격 토큰(`context.oncare`)을 읽는다 — 앱과 같은 테마를 준다.
            theme: OnCareTheme.light(
              brand: OnCareBrand.trainer,
              density: OnCareDensity.web,
            ),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SessionProgramRow(index: 1, item: item)),
          ),
        );

    testWidgets('맨몸 근력은 중량을 0kg 으로 적는다', (tester) async {
      // 중량 칸은 비울 수 없다(최솟값 0) — 근력을 고르면 언제나 값을 하나
      // 든다. 그래서 0 은 적지 않은 값이 아니라 트레이너가 적은 맨몸이다.
      await pumpRow(
        tester,
        const ProgramItem(name: '플랭크', sets: 3, reps: 3, weight: 0),
      );

      expect(find.text('3세트 · 3회 · 0kg'), findsOneWidget);
    });

    testWidgets('중량이 아예 없는 옛 행은 그 자리를 비운다', (tester) async {
      await pumpRow(tester, const ProgramItem(name: '플랭크', sets: 3, reps: 3));

      expect(find.text('3세트 · 3회'), findsOneWidget);
    });

    testWidgets('유산소는 시간만 적는다', (tester) async {
      await pumpRow(
        tester,
        const ProgramItem(name: '걷기', type: '유산소', duration: 30),
      );

      expect(find.text('30분'), findsOneWidget);
    });
  });

  group('programItemToJson', () {
    test('유형에 맞지 않는 칸은 아예 실어 보내지 않는다', () {
      final json = programItemToJson(
        const ProgramItem(
          name: '어깨 관절 보호 스트레칭',
          type: '스트레칭',
          duration: 8,
          sets: 3,
          reps: 8,
          weight: 5,
        ),
      );

      expect(json['duration'], 8);
      expect(json['sets'], isNull);
      expect(json['reps'], isNull);
      expect(json['weight'], isNull);
    });

    test('맨몸 근력의 0kg 는 값이라 그대로 싣는다', () {
      final json = programItemToJson(
        const ProgramItem(name: '플랭크', sets: 3, reps: 3, weight: 0),
      );

      expect(json['weight'], 0.0);
    });

    test('근력은 세트·횟수·중량을 그대로 싣는다', () {
      final json = programItemToJson(
        const ProgramItem(name: '데드리프트', sets: 4, reps: 8, weight: 55.5),
      );

      expect(<Object?>[json['sets'], json['reps'], json['weight']], <Object?>[
        4,
        8,
        55.5,
      ]);
      expect(json['duration'], isNull);
    });
  });
}
