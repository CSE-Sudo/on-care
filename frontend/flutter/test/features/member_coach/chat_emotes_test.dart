/// 트레이너 채팅의 이모티콘 — 버튼·이용권·전송·말풍선. (#2020)
///
/// 이용권은 24시간 전체 사용이고 포인트로 산다. 이용권이 없으면 고를 수 없지만
/// **무엇이 있는지는 보인다** — 가려 두면 무엇을 사는지 모른 채 사야 한다.
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

/// 이용권을 마음대로 켜고 끌 수 있는 대역.
class _FakeEmoteRepository implements EmoteRepository {
  _FakeEmoteRepository({this.active = false});

  bool active;
  int balance = 1000;
  int buys = 0;

  EmoteState get _state => EmoteState(
    cost: 300,
    hours: 24,
    balance: balance,
    remaining: active ? const Duration(hours: 3, minutes: 12) : null,
  );

  @override
  Future<EmoteState> fetchState() async => _state;

  @override
  Future<EmoteState> buyPass() async {
    buys++;
    active = true;
    balance -= 300;
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

  testWidgets('이용권이 없으면 값과 사는 버튼이 보이고 고를 수 없다', (
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

    expect(find.byKey(const Key('emotePassBuy')), findsOneWidget);
    expect(find.byKey(const Key('emotePassActive')), findsNothing);
    // 무엇이 있는지는 보인다.
    expect(find.byKey(const Key('emote-oni_owoon')), findsOneWidget);

    await tester.tap(find.byKey(const Key('emote-oni_owoon')));
    await tester.pumpAndSettle();

    // 눌러도 아무것도 보내지 않는다 — 창도 그대로다.
    expect(coach.sentEmote, isNull);
    expect(find.byKey(const Key('emoteSheet')), findsOneWidget);
  });

  testWidgets('이용권을 사면 그 자리에서 남은 시간이 보인다', (WidgetTester tester) async {
    final _FakeEmoteRepository emotes = _FakeEmoteRepository();
    final AppLocalizations l = await _pumpChat(tester, emotes: emotes);
    await _openSheet(tester, l);

    await tester.tap(find.byKey(const Key('emoteBuyButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.emoteBuyAction).last);
    await tester.pumpAndSettle();

    expect(emotes.buys, 1);
    expect(find.byKey(const Key('emotePassActive')), findsOneWidget);
    // 남은 시간을 말한다 — 24시간이 언제 끝나는지 모르면 다시 살 때를 알 수 없다.
    expect(find.text(l.emotePassRemaining(l.emoteRemainingHm(3, 12))), findsOneWidget);
  });

  testWidgets('이용 중이면 고른 이모티콘이 바로 나간다', (WidgetTester tester) async {
    final _RecordingCoachRepository coach = _RecordingCoachRepository();
    final AppLocalizations l = await _pumpChat(
      tester,
      emotes: _FakeEmoteRepository(active: true),
      coach: coach,
    );

    await _openSheet(tester, l);
    // 강아지 묶음은 목록 아래쪽이라 화면 안으로 끌어 올린 뒤 누른다.
    await tester.scrollUntilVisible(
      find.byKey(const Key('emote-dog_love')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('emote-dog_love')));
    await tester.pumpAndSettle();

    // 고르면 바로 보낸다 — 전송을 다시 누르게 하면 글보다 느려진다.
    expect(coach.sentEmote, 'dog_love');
    expect(find.byKey(const Key('emoteSheet')), findsNothing);
  });

  testWidgets('이모티콘 말풍선은 그림만 그린다', (WidgetTester tester) async {
    final _RecordingCoachRepository coach = _RecordingCoachRepository();
    await coach.sendMessage('', emoteId: 'cat_knead');
    final AppLocalizations l = await _pumpChat(
      tester,
      emotes: _FakeEmoteRepository(active: true),
      coach: coach,
    );

    expect(find.byType(AppEmote), findsWidgets);
    // 본문 `(이모티콘)` 은 알림·목록이 읽는 글이라 말풍선에는 나오지 않는다.
    expect(find.text('(이모티콘)'), findsNothing);
    expect(l.emoteSheetTitle, isNotEmpty);
  });
}
