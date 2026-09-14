import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/features/schedule/domain/repositories/schedule_repository.dart';
import 'package:oncare/features/schedule/domain/schedule_format.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/add_event_dialog.dart';

/// 저장된 값을 그대로 붙잡아 둔다 — 일정 추가 시트가 서버에 무엇을 보내는지가
/// 이 테스트의 관심사다.
class _CapturingRepository implements ScheduleRepository {
  String? date;
  String? time;
  String? title;

  @override
  Future<ScheduleEvent> createEvent({
    required String date,
    required String title,
    String time = '',
    ScheduleCategory category = ScheduleCategory.other,
  }) async {
    this.date = date;
    this.time = time;
    this.title = title;
    return ScheduleEvent(
      id: 'evt-1',
      date: date,
      time: time,
      title: title,
      category: category,
    );
  }

  @override
  Future<List<ScheduleEvent>> fetchByDate(String date) async =>
      const <ScheduleEvent>[];

  @override
  Future<List<ScheduleEvent>> fetchByMonth(String month) async =>
      const <ScheduleEvent>[];

  /// 이 파일은 새로 만드는 흐름만 본다. 수정은 하루 시트 테스트가 맡는다.
  @override
  Future<ScheduleEvent> updateEvent(
    String id, {
    String? date,
    String? time,
    String? title,
    ScheduleCategory? category,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteEvent(String id) async {
    throw UnimplementedError();
  }
}

void main() {
  late _CapturingRepository repo;

  Future<void> openDialog(WidgetTester tester) async {
    // 실제 폰 크기로 잡는다. 시간 피커는 다이얼로그라서 열릴 때의 MediaQuery 를
    // 그대로 쓰는데, `setSurfaceSize` 는 한 번 정착(settle)한 뒤에야 반영되어
    // 피커가 이전 크기로 그려진다. `view` 는 첫 프레임부터 적용된다.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    repo = _CapturingRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          scheduleRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showAddEventDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('날짜·시간을 직접 칠 수 없다', (WidgetTester tester) async {
    await openDialog(tester);

    // 예전에는 세 칸 모두 자유 입력이라 계약을 벗어난 값이 그대로 나갔다(#785).
    // 이제 편집 가능한 칸은 제목 하나뿐이다.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('addEventDate')), findsOneWidget);
    expect(find.byKey(const Key('addEventTime')), findsOneWidget);
  });

  testWidgets('저장하면 계약 형식으로 나간다', (WidgetTester tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), '병원 정기검진');
    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(repo.title, '병원 정기검진');
    // 형식을 직접 비교하지 않고 계약 검사기에 물어본다 — 저장 경로와 조회
    // 경로가 같은 규칙을 쓰는지가 핵심이다.
    expect(isScheduleDate(repo.date!), isTrue);
    expect(isScheduleTime(repo.time!), isTrue);
    // 시간은 고르지 않았으므로 빈 값이다(계약이 허용한다).
    expect(repo.time, '');
  });

  testWidgets('제목이 비면 저장하지 않고 알린다', (WidgetTester tester) async {
    await openDialog(tester);

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(repo.title, isNull);
    expect(find.text('일정 제목을 입력해 주세요'), findsOneWidget);
  });

  testWidgets('시간을 고르면 HH:mm 으로 나가고 지울 수 있다', (WidgetTester tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), '운동');

    await tester.tap(find.byKey(const Key('addEventTime')));
    await tester.pumpAndSettle();
    // 다이얼에서 특정 시각을 집기는 어렵고 이 테스트의 관심사도 아니다. 확인만
    // 눌러 초기값(현재 시각)을 그대로 받고, 그 값이 계약 형식으로 나가는지를 본다.
    await tester.tap(find.widgetWithText(TextButton, '확인'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(isScheduleTime(repo.time!), isTrue);
    expect(repo.time, isNot(''));
  });
}
