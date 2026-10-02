/// 트레이너 채팅의 빈 대화 안내·조회 실패 재시도·글 없는 사진 말풍선. (#2880)
///
/// 연결만 되고 메시지가 없으면 입력줄 위가 통째로 비었고, 조회가 실패하면 다음
/// 폴링까지 할 수 있는 것이 없었다. 글 없이 보낸 사진은 위쪽에 빈 글줄만큼
/// 여백이 생겼다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

/// 1×1 투명 PNG.
final Uint8List _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, //
  0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
  13, 10, 45, 180,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

/// KST 고정 시각.
final DateTime _at = DateTime(2026, 9, 28, 9, 30);

CoachMessage _photoMessage(String id, {String body = ''}) => CoachMessage(
  id: id,
  sender: CoachSender.me,
  body: body,
  timeLabel: '09:30',
  createdAt: _at,
  attachment: CoachAttachment(
    kind: CoachAttachmentKind.image,
    fileName: 'photo.png',
    fileId: 'file-$id',
    fileSize: _png.length,
    downloadPath: '/chat/attachments/file-$id',
    localBytes: _png,
  ),
);

/// 대화 조회를 테스트가 정하는 저장소. [failures] 만큼 먼저 실패한다.
class _ChatRepository extends MockMemberCoachRepository {
  _ChatRepository({this.messages = const <CoachMessage>[], this.failures = 0});

  List<CoachMessage> messages;
  int failures;
  int calls = 0;

  @override
  Stream<List<CoachMessage>> watchChat() {
    calls++;
    if (failures > 0) {
      failures -= 1;
      return Stream<List<CoachMessage>>.error(StateError('network down'));
    }
    return Stream<List<CoachMessage>>.value(messages);
  }

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async =>
      before == null ? messages : const <CoachMessage>[];
}

Future<AppLocalizations> _pumpChat(
  WidgetTester tester,
  _ChatRepository repo, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_demo),
        memberCoachRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrainerChatPage(trainerName: '김트레이너'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(TrainerChatPage)));
}

/// 말풍선 안의 빈 글줄.
Finder _blankTextIn(String id) => find.descendant(
  of: find.byKey(ValueKey<String>('coach-message-bubble-$id')),
  matching: find.byWidgetPredicate(
    (Widget w) => w is Text && (w.data?.trim().isEmpty ?? false),
  ),
);

void main() {
  group('빈 대화', () {
    testWidgets('메시지가 없으면 트레이너 이름과 보낼 것을 안내한다', (tester) async {
      final AppLocalizations l = await _pumpChat(tester, _ChatRepository());

      expect(
        find.byKey(const ValueKey<String>('coach-chat-empty')),
        findsOneWidget,
      );
      expect(find.text(l.coachChatEmptyTitle('김트레이너')), findsOneWidget);
      expect(find.text(l.coachChatEmptyBody), findsOneWidget);
      // 입력줄은 그대로 있어 바로 보낼 수 있다.
      expect(
        find.byKey(const ValueKey<String>('member-chat-input')),
        findsOneWidget,
      );
    });

    testWidgets('영어 화면에서도 안내가 나온다', (tester) async {
      final AppLocalizations l = await _pumpChat(
        tester,
        _ChatRepository(),
        locale: const Locale('en'),
      );

      expect(find.text(l.coachChatEmptyTitle('김트레이너')), findsOneWidget);
      expect(find.text(l.coachChatEmptyBody), findsOneWidget);
    });

    testWidgets('메시지가 있으면 안내가 없다', (tester) async {
      await _pumpChat(
        tester,
        _ChatRepository(
          messages: <CoachMessage>[_photoMessage('m1', body: '안녕하세요')],
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('coach-chat-empty')),
        findsNothing,
      );
    });
  });

  group('조회 실패', () {
    testWidgets('오류와 다시 시도를 보이고 누르면 다시 받는다', (tester) async {
      final _ChatRepository repo = _ChatRepository(
        messages: <CoachMessage>[_photoMessage('m1', body: '안녕하세요')],
        failures: 1,
      );
      final AppLocalizations l = await _pumpChat(tester, repo);

      expect(
        find.byKey(const ValueKey<String>('coach-chat-error')),
        findsOneWidget,
      );
      expect(find.text(l.coachChatLoadFailed), findsOneWidget);
      final int before = repo.calls;

      await tester.tap(find.byKey(const ValueKey<String>('coach-chat-retry')));
      await tester.pumpAndSettle();

      expect(repo.calls, greaterThan(before));
      expect(
        find.byKey(const ValueKey<String>('coach-chat-error')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('coach-message-bubble-m1')),
        findsOneWidget,
      );
    });
  });

  group('사진 말풍선', () {
    testWidgets('글 없이 보낸 사진에는 빈 글줄이 없다', (tester) async {
      await _pumpChat(
        tester,
        _ChatRepository(messages: <CoachMessage>[_photoMessage('p1')]),
      );

      expect(
        find.byKey(const ValueKey<String>('coach-message-bubble-p1')),
        findsOneWidget,
      );
      expect(_blankTextIn('p1'), findsNothing);
    });

    testWidgets('글과 함께 보낸 사진은 글을 그대로 그린다', (tester) async {
      await _pumpChat(
        tester,
        _ChatRepository(
          messages: <CoachMessage>[_photoMessage('p2', body: '오늘 점심이에요')],
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('coach-message-bubble-p2')),
          matching: find.text('오늘 점심이에요'),
        ),
        findsOneWidget,
      );
    });
  });
}
