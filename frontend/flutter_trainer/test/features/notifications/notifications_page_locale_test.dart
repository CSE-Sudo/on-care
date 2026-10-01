/// 알림함은 알림 문장을 화면 언어로 보여 준다(#2302).
///
/// 서버가 틀 코드와 인자를 주면 ARB 로 조립하고, 틀이 없는 옛 알림은 저장된
/// 문장을 그대로 보여 준다. 한국어 화면의 문장은 틀 이전과 같다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

import '../../helpers/pump_app.dart';

class _Repo implements TrainerNotificationRepository {
  _Repo(this._rows);

  final List<TrainerNotification> _rows;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => TrainerNotificationPage(items: _rows);

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async =>
      _rows.where((TrainerNotification r) => !r.read).length;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

TrainerNotification _row(
  String id, {
  required String title,
  required String body,
  String? template,
  Map<String, Object?> args = const <String, Object?>{},
  TrainerNotificationKind kind = TrainerNotificationKind.other,
}) => TrainerNotification(
  id: id,
  title: title,
  body: body,
  kind: kind,
  read: false,
  createdAt: DateTime.utc(2026, 10, 2),
  timeAgo: '',
  template: template,
  args: args,
);

/// 서버가 한국어로 저장한 알림 세 건 — 틀이 있는 두 건과 틀 이전의 한 건.
final List<TrainerNotification> _rows = <TrainerNotification>[
  _row(
    'goal',
    title: '회원 건강 목표 변경',
    body: '지수 회원이 건강 목표를 바꿨어요: 근력 향상 · 재활',
    template: 'trainer_health_goal',
    args: <String, Object?>{
      'member_name': '지수',
      'focus': <String>['근력 향상', '재활'],
    },
    kind: TrainerNotificationKind.healthGoal,
  ),
  _row(
    'message',
    title: '지수 회원의 메시지',
    body: '오늘 수업 시간 조정 가능할까요?',
    template: 'trainer_member_message',
    args: <String, Object?>{'member_name': '지수'},
    kind: TrainerNotificationKind.message,
  ),
  _row('legacy', title: '예전 알림 제목', body: '예전 알림 본문'),
];

Future<void> _pump(WidgetTester tester, {required Locale locale}) async {
  await pumpTrainerApp(
    tester,
    token: 'demo-token',
    at: AppRoutes.notifications,
    locale: locale,
    extraOverrides: <Override>[
      trainerNotificationRepositoryProvider.overrideWithValue(_Repo(_rows)),
    ],
  );
}

void main() {
  testWidgets('영어 화면은 틀로 조립한 영어 문장을 보여 준다', (tester) async {
    await _pump(tester, locale: const Locale('en'));

    expect(find.text('Member goals changed'), findsOneWidget);
    expect(
      find.text('지수 changed their health goals: Build strength · Rehab'),
      findsOneWidget,
    );
    expect(find.text('Message from 지수'), findsOneWidget);
    // 메시지 본문은 회원이 쓴 문장 그대로다.
    expect(find.text('오늘 수업 시간 조정 가능할까요?'), findsOneWidget);
    expect(find.text('회원 건강 목표 변경'), findsNothing);
    expect(find.text('지수 회원의 메시지'), findsNothing);
  });

  testWidgets('틀이 없는 옛 알림은 저장된 문장을 보여 준다', (tester) async {
    await _pump(tester, locale: const Locale('en'));

    expect(find.text('예전 알림 제목'), findsOneWidget);
    expect(find.text('예전 알림 본문'), findsOneWidget);
  });

  testWidgets('한국어 화면의 문장은 틀 이전과 같다', (tester) async {
    await _pump(tester, locale: const Locale('ko'));

    expect(find.text('회원 건강 목표 변경'), findsOneWidget);
    expect(find.text('지수 회원이 건강 목표를 바꿨어요: 근력 향상 · 재활'), findsOneWidget);
    expect(find.text('지수 회원의 메시지'), findsOneWidget);
    expect(find.text('오늘 수업 시간 조정 가능할까요?'), findsOneWidget);
    expect(find.text('예전 알림 제목'), findsOneWidget);
    expect(find.text('Member goals changed'), findsNothing);
  });
}
