/// 리포트 알림을 누르면 그 주 리포트가 바로 열린다 — #3344.
///
/// 예전에는 대화 맨 아래로만 갔다. 그 뒤로 메시지가 쌓였으면 회원이 리포트 카드를
/// 찾아 위로 올라가야 했다. 서버는 목적지 값을 메시지 알림과 같은 대화로 두고
/// (`coach_chat` — 옛 앱이 아는 값) 주·메시지를 따로 실어 준다. 여기서 보는 것:
///
/// - 그 값이 있으면 대화가 아니라 리포트를 연다
/// - 그 값이 없는 옛 리포트 알림과 메시지 알림은 지금처럼 대화로 간다
/// - 열 수 없으면(담당 해제·리포트 없음) 받은 리포트 화면으로 간다
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/data/repositories/chat_pdf_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_navigation.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_member_coach_repository.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

final DateTime _thisWeek = DateTime(2026, 10, 5);
final DateTime _lastWeek = DateTime(2026, 9, 28);

CoachAttachment _pdf(String id) => CoachAttachment(
  kind: CoachAttachmentKind.pdf,
  fileName: '$id.pdf',
  fileId: id,
  fileSize: 10,
  downloadPath: '/chat/attachments/$id',
);

CoachMessage _report(
  String id,
  DateTime week, {
  required DateTime sentAt,
  bool attached = true,
}) => CoachMessage(
  id: id,
  sender: CoachSender.trainer,
  body: '주간 리포트입니다.',
  timeLabel: '18:10',
  createdAt: sentAt,
  reportWeekStart: week,
  attachment: attached ? _pdf(id) : null,
);

CoachMessage _talk(String id, DateTime at) => CoachMessage(
  id: id,
  sender: CoachSender.trainer,
  body: '오늘 운동 어떠셨어요?',
  timeLabel: '19:00',
  createdAt: at,
);

/// 리포트 뒤로도 대화가 이어진 스레드 — 대화 맨 아래에는 리포트가 없다.
List<CoachMessage> _thread() => <CoachMessage>[
  _report('rep-last', _lastWeek, sentAt: DateTime(2026, 10, 4, 18)),
  _report('rep-first', _thisWeek, sentAt: DateTime(2026, 10, 9, 18)),
  // 같은 주 리포트를 다시 보냈다.
  _report('rep-again', _thisWeek, sentAt: DateTime(2026, 10, 10, 18)),
  _talk('talk-1', DateTime(2026, 10, 11, 9)),
  _talk('talk-2', DateTime(2026, 10, 11, 10)),
];

/// 대화를 읽는 길이 어떻게 끝나는지 고르는 대역.
class _ChatRepository extends FakeMemberCoachRepository {
  _ChatRepository({super.chat, this.unassigned = false, this.broken = false});

  /// 담당이 해제됐다 — 서버가 대화 조회를 404 로 답한다.
  final bool unassigned;

  /// 연결·서버 문제로 대화를 읽지 못한다.
  final bool broken;

  @override
  Future<MemberCoach?> fetchCoach() async => unassigned ? null : coach;

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async {
    if (unassigned) throw const CoachUnassignedException();
    if (broken) throw Exception('네트워크 실패');
    return super.fetchChat(before: before);
  }

  @override
  Stream<List<CoachMessage>> watchChat() => unassigned
      ? Stream<List<CoachMessage>>.error(const CoachUnassignedException())
      : super.watchChat();

  // 대화 화면이 열릴 때 함께 읽는 것들 — 옛 알림이 대화로 가는 길에서 쓴다.
  @override
  Future<List<CoachRoutine>> fetchRoutines() async => const <CoachRoutine>[];

  @override
  Future<List<CoachRoutine>> fetchRoutinesOn(DateTime day) async =>
      const <CoachRoutine>[];

  @override
  Future<List<CoachSession>> fetchSessions() async => const <CoachSession>[];
}

/// 받으라고 한 경로만 적어 두는 PDF 저장소.
class _PdfRepository extends ChatPdfRepository {
  _PdfRepository({this.fail = false}) : super(Dio());

  final bool fail;
  final List<String> paths = <String>[];

  @override
  Future<Uint8List> download(String path) async {
    paths.add(path);
    if (fail) throw Exception('다운로드 실패');
    return Uint8List.fromList(const <int>[37, 80, 68, 70]);
  }
}

AlertItem _alert({
  AlertReportRef? report,
  AlertCategory category = AlertCategory.coachReport,
}) => AlertItem(
  id: 'n1',
  title: '주간 리포트가 도착했어요',
  body: '이번 주 잘하셨어요',
  timeAgo: '방금',
  category: category,
  wireCategory: category == AlertCategory.coachReport
      ? 'coach_report'
      : 'coach_chat',
  // 서버가 주는 목적지 값은 리포트 알림도 대화다.
  action: const AlertAction(label: '리포트 보기', target: AlertTarget.coachChat),
  report: report,
);

void main() {
  group('findReportNotice', () {
    test('메시지 식별자가 가리키는 그 리포트를 고른다', () {
      final SentReportNotice? notice = findReportNotice(
        _thread(),
        weekStart: _thisWeek,
        messageId: 'rep-first',
      );

      // 같은 주를 다시 보냈어도 알림이 말한 한 건이다.
      expect(notice?.message.id, 'rep-first');
      expect(notice?.weekStart, _thisWeek);
    });

    test('식별자가 없으면 그 주의 마지막 리포트다', () {
      final SentReportNotice? notice = findReportNotice(
        _thread(),
        weekStart: _thisWeek,
      );

      expect(notice?.message.id, 'rep-again');
    });

    test('식별자를 대화에서 못 찾으면 그 주의 마지막 리포트다', () {
      final SentReportNotice? notice = findReportNotice(
        _thread(),
        weekStart: _lastWeek,
        messageId: 'gone',
      );

      expect(notice?.message.id, 'rep-last');
      expect(notice?.weekStart, _lastWeek);
    });

    test('식별자가 리포트가 아닌 메시지면 주로 찾는다', () {
      final SentReportNotice? notice = findReportNotice(
        _thread(),
        weekStart: _thisWeek,
        messageId: 'talk-1',
      );

      expect(notice?.message.id, 'rep-again');
    });

    test('메시지의 주가 알림의 주와 달라도 메시지의 주로 연다', () {
      // 문서는 메시지가 실어 온 주로 세운다 — 대화 안내·받은 리포트 목록과 같다.
      final SentReportNotice? notice = findReportNotice(
        _thread(),
        weekStart: _thisWeek,
        messageId: 'rep-last',
      );

      expect(notice?.weekStart, _lastWeek);
    });

    test('시각이 붙은 주도 날짜로 맞춘다', () {
      final SentReportNotice? notice = findReportNotice(
        _thread(),
        weekStart: DateTime(2026, 10, 5, 13, 30),
      );

      expect(notice?.message.id, 'rep-again');
    });

    test('그 주 리포트가 없으면 없다', () {
      expect(
        findReportNotice(_thread(), weekStart: DateTime(2026, 9, 21)),
        isNull,
      );
      expect(
        findReportNotice(const <CoachMessage>[], weekStart: _thisWeek),
        isNull,
      );
    });
  });

  group('리포트 알림 이동', () {
    late BuildContext ctx;
    late WidgetRef wref;

    Future<void> pumpApp(
      WidgetTester tester,
      MemberCoachRepository repo,
      _PdfRepository pdf,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/home',
        routes: <RouteBase>[
          GoRoute(
            path: '/home',
            builder: (_, _) => Consumer(
              builder: (BuildContext c, WidgetRef r, _) {
                ctx = c;
                wref = r;
                return const Text('home');
              },
            ),
          ),
          GoRoute(
            path: AppRoutes.myCoachReports,
            builder: (_, _) => const Text('받은 리포트'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_config),
            memberCoachRepositoryProvider.overrideWithValue(repo),
            chatPdfRepositoryProvider.overrideWithValue(pdf),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 알림 화면처럼 기다리지 않고 부른다 — 미리보기·대화를 여는 Future 는 창을
    /// 닫아야 끝난다.
    Future<void> tap(WidgetTester tester, AlertItem item) async {
      unawaited(openAlertTarget(ctx, wref, item));
      await tester.pump(); // 대화를 읽는 구간
      await tester.pump(); // 파일을 받는 구간
      await tester.pump(); // 이동 반영
      await tester.pump(const Duration(milliseconds: 400)); // 화면 전환
    }

    Future<void> drainToasts(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }

    testWidgets('알림이 가리킨 리포트를 대화 없이 바로 연다', (WidgetTester tester) async {
      final _PdfRepository pdf = _PdfRepository();
      await pumpApp(tester, _ChatRepository(chat: _thread()), pdf);

      await tap(
        tester,
        _alert(
          report: AlertReportRef(weekStart: _thisWeek, messageId: 'rep-first'),
        ),
      );

      // 트레이너가 보낸 그 파일을 받는다 — 같은 주를 다시 보낸 것이 아니라.
      expect(pdf.paths, <String>['/chat/attachments/rep-first']);
      expect(find.byKey(PdfPreviewPage.pageKey), findsOneWidget);
      expect(find.byType(TrainerChatPage), findsNothing);
    });

    testWidgets('식별자가 없으면 그 주의 마지막 리포트를 연다', (WidgetTester tester) async {
      final _PdfRepository pdf = _PdfRepository();
      await pumpApp(tester, _ChatRepository(chat: _thread()), pdf);

      await tap(tester, _alert(report: AlertReportRef(weekStart: _lastWeek)));

      expect(pdf.paths, <String>['/chat/attachments/rep-last']);
      expect(find.byKey(PdfPreviewPage.pageKey), findsOneWidget);
    });

    testWidgets('옛 리포트 알림은 지금처럼 대화로 간다', (WidgetTester tester) async {
      // 주·메시지가 실리기 전에 쌓인 알림 — 열 리포트를 정할 수 없다.
      final _PdfRepository pdf = _PdfRepository();
      await pumpApp(tester, _ChatRepository(chat: _thread()), pdf);

      await tap(tester, _alert());

      expect(find.byType(TrainerChatPage), findsOneWidget);
      expect(find.byKey(PdfPreviewPage.pageKey), findsNothing);
      expect(pdf.paths, isEmpty);
    });

    testWidgets('메시지 알림은 지금처럼 대화로 간다', (WidgetTester tester) async {
      final _PdfRepository pdf = _PdfRepository();
      await pumpApp(tester, _ChatRepository(chat: _thread()), pdf);

      await tap(tester, _alert(category: AlertCategory.coachChat));

      expect(find.byType(TrainerChatPage), findsOneWidget);
      expect(find.byKey(PdfPreviewPage.pageKey), findsNothing);
      expect(pdf.paths, isEmpty);
    });

    testWidgets('담당이 끊겼으면 받은 리포트 화면으로 간다', (WidgetTester tester) async {
      final _PdfRepository pdf = _PdfRepository();
      await pumpApp(tester, _ChatRepository(unassigned: true), pdf);

      await tap(
        tester,
        _alert(
          report: AlertReportRef(weekStart: _thisWeek, messageId: 'rep-first'),
        ),
      );

      expect(find.text('받은 리포트'), findsOneWidget);
      expect(pdf.paths, isEmpty);
      // 리포트 알림을 눌렀는데 대화를 열 수 없다는 안내는 띄우지 않는다.
      expect(
        find.text(AppLocalizations.of(ctx).alertCoachChatNoTrainer),
        findsNothing,
      );
    });

    testWidgets('그 리포트가 대화에 없으면 받은 리포트 화면으로 간다', (WidgetTester tester) async {
      final _PdfRepository pdf = _PdfRepository();
      await pumpApp(
        tester,
        _ChatRepository(
          chat: <CoachMessage>[_talk('talk-1', DateTime(2026, 10, 11, 9))],
        ),
        pdf,
      );

      await tap(
        tester,
        _alert(
          report: AlertReportRef(weekStart: _thisWeek, messageId: 'rep-first'),
        ),
      );

      expect(find.text('받은 리포트'), findsOneWidget);
      expect(pdf.paths, isEmpty);
    });

    testWidgets('대화를 읽지 못하면 제자리에서 사정을 알린다', (WidgetTester tester) async {
      final _PdfRepository pdf = _PdfRepository();
      await pumpApp(tester, _ChatRepository(broken: true), pdf);

      await tap(tester, _alert(report: AlertReportRef(weekStart: _thisWeek)));

      expect(find.text('home'), findsOneWidget);
      expect(
        find.text(AppLocalizations.of(ctx).coachReportsLoadFailed),
        findsOneWidget,
      );
      await drainToasts(tester);
    });

    testWidgets('파일을 받지 못하면 열지 못했다고 알린다', (WidgetTester tester) async {
      final _PdfRepository pdf = _PdfRepository(fail: true);
      await pumpApp(tester, _ChatRepository(chat: _thread()), pdf);

      await tap(
        tester,
        _alert(
          report: AlertReportRef(weekStart: _thisWeek, messageId: 'rep-first'),
        ),
      );

      expect(pdf.paths, <String>['/chat/attachments/rep-first']);
      expect(find.byKey(PdfPreviewPage.pageKey), findsNothing);
      expect(
        find.text(AppLocalizations.of(ctx).coachChatPdfOpenFailed),
        findsOneWidget,
      );
      await drainToasts(tester);
    });
  });
}
