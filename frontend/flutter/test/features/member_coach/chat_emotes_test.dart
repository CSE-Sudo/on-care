/// 트레이너 채팅의 이모티콘 — 버튼·하나씩 사기·전송·말풍선. (#2020, #2153)
///
/// 이모티콘은 하나씩 사서 7일 동안 쓴다. 한 판에 늘어놓되 산 것이 맨 앞에 오고, 안 산
/// 것도 **무엇인지는 보인다** — 가려 두면 무엇을 사는지 모른 채 사야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/domain/repositories/emote_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

/// 산 이모티콘을 마음대로 정할 수 있는 대역.
class _FakeEmoteRepository implements EmoteRepository {
  _FakeEmoteRepository({Set<String>? owned, this.balance = 1000})
    : owned = owned ?? <String>{};

  final Set<String> owned;
  int balance;
  final List<String> bought = <String>[];

  EmoteState get _state => EmoteState(
    cost: 50,
    days: 7,
    balance: balance,
    unlocked: <String, Duration>{
      for (final String id in owned) id: const Duration(days: 6, hours: 3),
    },
  );

  @override
  Future<EmoteState> fetchState() async => _state;

  @override
  Future<EmoteState> unlock(String emoteId) async {
    bought.add(emoteId);
    owned.add(emoteId);
    balance -= 50;
    return _state;
  }
}

/// 보낸 것을 적어 두는 채팅 대역.
class _RecordingCoachRepository extends MockMemberCoachRepository {
  String? sentEmote;
  String? sentText;

  @override
  Future<void> sendMessage(String text, {String? emoteId}) async {
    sentText = text;
    sentEmote = emoteId;
    await super.sendMessage(text, emoteId: emoteId);
  }
}

Future<AppLocalizations> _pumpChat(
  WidgetTester tester, {
  required _FakeEmoteRepository emotes,
  _RecordingCoachRepository? coach,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_demo),
        emoteRepositoryProvider.overrideWithValue(emotes),
        memberCoachRepositoryProvider.overrideWithValue(
          coach ?? MockMemberCoachRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrainerChatPage(trainerName: '김트레이너'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(TrainerChatPage)));
}

Future<void> _openSheet(WidgetTester tester, AppLocalizations l) async {
  await tester.tap(find.byTooltip(l.a11yOpenEmotes));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('입력칸과 보내기 사이에 같은 높이의 이모티콘 버튼이 있다', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await _pumpChat(
      tester,
      emotes: _FakeEmoteRepository(),
    );

    final Finder button = find.byTooltip(l.a11yOpenEmotes);
    expect(button, findsOneWidget);
    // 보내기 버튼과 한 변이 같다 — 입력줄에서 셋의 높이가 어긋나면 줄이 뒤뚱거린다.
    expect(
      tester.getSize(button).height,
      tester.getSize(find.byTooltip(l.a11ySendMessage)).height,
    );
    // 자리도 입력칸과 보내기 사이다.
    expect(
      tester.getCenter(button).dx,
      lessThan(tester.getCenter(find.byTooltip(l.a11ySendMessage)).dx),
    );
  });

  testWidgets('안 산 이모티콘도 보이고, 누르면 보내지 않고 사기를 묻는다', (
    WidgetTester tester,
  ) async {
    final _FakeEmoteRepository emotes = _FakeEmoteRepository();
    final _RecordingCoachRepository coach = _RecordingCoachRepository();
    final AppLocalizations l = await _pumpChat(
      tester,
      emotes: emotes,
      coach: coach,
    );

    await _openSheet(tester, l);

    expect(find.byKey(const Key('emote-oni_owoon')), findsOneWidget);

    await tester.tap(find.byKey(const Key('emote-oni_owoon')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emoteBuyDialog')), findsOneWidget);
    expect(find.text(l.emoteBuyConfirm(50, 7)), findsOneWidget);
    await tester.tap(find.text(l.myCancel));
    await tester.pumpAndSettle();

    // 취소하면 아무것도 사지도 보내지도 않는다 — 창도 그대로다.
    expect(emotes.bought, isEmpty);
    expect(coach.sentEmote, isNull);
    expect(find.byKey(const Key('emoteSheet')), findsOneWidget);
  });

  testWidgets('사면 창은 그대로이고 그 이모티콘이 맨 앞으로 온다', (WidgetTester tester) async {
    final _FakeEmoteRepository emotes = _FakeEmoteRepository();
    final _RecordingCoachRepository coach = _RecordingCoachRepository();
    final AppLocalizations l = await _pumpChat(
      tester,
      emotes: emotes,
      coach: coach,
    );
    await _openSheet(tester, l);

    await tester.tap(find.byKey(const Key('emote-oni_gains')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('emoteBuyConfirm')));
    await tester.pumpAndSettle();

    expect(emotes.bought, <String>['oni_gains']);
    // 사기만 한다 — 보내는 것은 다시 눌러서다.
    expect(coach.sentEmote, isNull);
    expect(find.byKey(const Key('emoteSheet')), findsOneWidget);
    // 원래 두 번째였던 이모티콘이 첫 번째 자리로 온다.
    expect(
      tester.getTopLeft(find.byKey(const Key('emote-oni_gains'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('emote-oni_owoon'))).dx),
    );
  });

  testWidgets('산 이모티콘은 맨 앞에 오고, 누르면 바로 나간다', (WidgetTester tester) async {
    final _RecordingCoachRepository coach = _RecordingCoachRepository();
    final AppLocalizations l = await _pumpChat(
      tester,
      emotes: _FakeEmoteRepository(owned: <String>{'dog_love'}),
      coach: coach,
    );

    await _openSheet(tester, l);
    // 강아지는 원래 목록 아래쪽이지만, 산 것은 맨 앞이라 끌어 올리지 않아도 보인다.
    final Offset dog = tester.getTopLeft(find.byKey(const Key('emote-dog_love')));
    final Offset first = tester.getTopLeft(
      find.byKey(const Key('emote-oni_owoon')),
    );
    expect(dog.dy, first.dy);
    expect(dog.dx, lessThan(first.dx));

    await tester.tap(find.byKey(const Key('emote-dog_love')));
    await tester.pumpAndSettle();

    // 고르면 바로 보낸다 — 전송을 다시 누르게 하면 글보다 느려진다.
    expect(coach.sentEmote, 'dog_love');
    expect(find.byKey(const Key('emoteSheet')), findsNothing);
  });

  testWidgets('포인트가 모자라면 사기를 묻지 않고 부족하다고 알린다', (WidgetTester tester) async {
    final _FakeEmoteRepository emotes = _FakeEmoteRepository(balance: 30);
    final AppLocalizations l = await _pumpChat(tester, emotes: emotes);
    await _openSheet(tester, l);

    await tester.tap(find.byKey(const Key('emote-oni_owoon')));
    await tester.pump();

    expect(find.byKey(const Key('emoteBuyDialog')), findsNothing);
    expect(find.text(l.emoteShortfall), findsOneWidget);
    expect(emotes.bought, isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('이모티콘 말풍선은 그림만 그린다', (WidgetTester tester) async {
    final _RecordingCoachRepository coach = _RecordingCoachRepository();
    await coach.sendMessage('', emoteId: 'cat_knead');
    final AppLocalizations l = await _pumpChat(
      tester,
      emotes: _FakeEmoteRepository(),
      coach: coach,
    );

    expect(find.byType(AppEmote), findsWidgets);
    // 본문 `(이모티콘)` 은 알림·목록이 읽는 글이라 말풍선에는 나오지 않는다.
    expect(find.text('(이모티콘)'), findsNothing);
    expect(l.emoteSheetTitle, isNotEmpty);
  });
}
