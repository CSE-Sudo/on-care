/// 이모티콘 구매 응답을 못 받았을 때 — 같은 키로 다시 사고, 이미 열린 것은 실패가
/// 아니다. 잔액 부족·담당 없음은 각자의 문구다. 산 뒤 MY 잔액을 다시 읽는다. (#2845)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/domain/repositories/emote_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/emote_sheet.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const String _emote = 'oni_gains';

/// 서버처럼 키를 기억하는 대역. [loseNextResponse] 면 구매를 끝내고도 응답 대신
/// 망 오류를 던진다 — "서버는 샀는데 앱은 모르는" 상황이다.
class _ServerLikeEmotes implements EmoteRepository {
  int balance = 1000;
  final Set<String> owned = <String>{};
  final Set<String> seenKeys = <String>{};
  final List<String> keys = <String>[];
  bool loseNextResponse = false;
  bool failFetch = false;
  EmoteUnlockFailure? rejectWith;
  int spent = 0;

  EmoteState get _state => EmoteState(
    cost: 50,
    days: 7,
    balance: balance,
    unlocked: <String, Duration>{
      for (final String id in owned) id: const Duration(days: 7),
    },
  );

  @override
  Future<EmoteState> fetchState() async {
    if (failFetch) throw const NetworkError();
    return _state;
  }

  @override
  Future<EmoteState> unlock(
    String emoteId, {
    required String clientRequestId,
  }) async {
    keys.add(clientRequestId);
    final EmoteUnlockFailure? reject = rejectWith;
    if (reject != null) throw EmoteUnlockRejected(reject);
    if (seenKeys.contains(clientRequestId)) return _state;
    if (owned.contains(emoteId)) {
      throw const EmoteUnlockRejected(EmoteUnlockFailure.alreadyUnlocked);
    }
    owned.add(emoteId);
    seenKeys.add(clientRequestId);
    balance -= 50;
    spent++;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const NetworkError();
    }
    return _state;
  }
}

class _Harness {
  int healthBuilds = 0;
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _ServerLikeEmotes emotes,
  _Harness harness,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        emoteRepositoryProvider.overrideWithValue(emotes),
        // MY 잔액을 다시 읽었는지 센다. 값은 필요 없다.
        myHealthStateProvider.overrideWith((Ref ref) {
          harness.healthBuilds++;
          return Completer<MyHealthState>().future;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            // MY 탭이 잔액을 보고 있는 상태를 흉내 낸다.
            ref.watch(myHealthStateProvider);
            return Scaffold(
              body: Builder(
                builder: (BuildContext inner) => TextButton(
                  onPressed: () => showEmoteSheet(inner),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return AppLocalizations.of(
    tester.element(find.byKey(const Key('emoteSheet'))),
  );
}

Future<void> _buy(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('emote-$_emote')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('emoteBuyConfirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('응답을 못 받았어도 서버가 샀으면 성공으로 안내하고 한 번만 차감한다', (
    WidgetTester tester,
  ) async {
    final _ServerLikeEmotes emotes = _ServerLikeEmotes()
      ..loseNextResponse = true;
    final _Harness harness = _Harness();
    final AppLocalizations l = await _pump(tester, emotes, harness);
    final int before = harness.healthBuilds;

    await _buy(tester);

    expect(find.text(l.emoteBought), findsOneWidget);
    expect(find.text(l.emoteBuyFailed), findsNothing);
    expect(emotes.spent, 1);
    expect(emotes.balance, 950);
    // MY 잔액을 다시 읽는다.
    expect(harness.healthBuilds, greaterThan(before));
  });

  testWidgets('응답 유실 뒤 상태도 못 읽으면 실패 안내, 다시 사면 같은 키로 간다', (
    WidgetTester tester,
  ) async {
    final _ServerLikeEmotes emotes = _ServerLikeEmotes()
      ..loseNextResponse = true;
    final _Harness harness = _Harness();
    final AppLocalizations l = await _pump(tester, emotes, harness);

    emotes.failFetch = true;
    await _buy(tester);
    expect(find.text(l.emoteBuyFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    emotes.failFetch = false;
    await _buy(tester);

    expect(emotes.keys, hasLength(2));
    expect(emotes.keys.first, emotes.keys.last);
    expect(emotes.spent, 1);
    expect(find.text(l.emoteBought), findsOneWidget);
  });

  testWidgets('성공한 뒤의 다음 구매는 새 키를 쓴다', (WidgetTester tester) async {
    final _ServerLikeEmotes emotes = _ServerLikeEmotes();
    final _Harness harness = _Harness();
    await _pump(tester, emotes, harness);

    await _buy(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // 산 것이 맨 앞으로 오며 목록이 밀린다 — 화면 밖이면 시트를 굴려 보이게 한다.
    await tester.ensureVisible(find.byKey(const Key('emote-dog_love')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('emote-dog_love')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('emoteBuyConfirm')));
    await tester.pumpAndSettle();

    expect(emotes.keys, hasLength(2));
    expect(emotes.keys.first, isNot(emotes.keys.last));
  });

  testWidgets('이미 열린 이모티콘은 실패가 아니라 열려 있다고 안내한다', (WidgetTester tester) async {
    final _ServerLikeEmotes emotes = _ServerLikeEmotes()
      ..rejectWith = EmoteUnlockFailure.alreadyUnlocked;
    final _Harness harness = _Harness();
    final AppLocalizations l = await _pump(tester, emotes, harness);
    final int before = harness.healthBuilds;

    await _buy(tester);

    expect(find.text(l.emoteAlreadyUnlocked), findsOneWidget);
    expect(find.text(l.emoteBuyFailed), findsNothing);
    expect(harness.healthBuilds, greaterThan(before));
  });

  testWidgets('담당 없음과 잔액 부족은 서로 다른 문구다', (WidgetTester tester) async {
    final _ServerLikeEmotes emotes = _ServerLikeEmotes()
      ..rejectWith = EmoteUnlockFailure.trainerRequired;
    final _Harness harness = _Harness();
    final AppLocalizations l = await _pump(tester, emotes, harness);

    await _buy(tester);
    expect(find.text(l.emoteTrainerRequired), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    emotes.rejectWith = EmoteUnlockFailure.insufficientPoints;
    await _buy(tester);
    expect(find.text(l.emoteShortfall), findsOneWidget);
    expect(l.emoteShortfall, isNot(l.emoteTrainerRequired));
  });

  group('EmoteUnlockRejected.fromResponse', () {
    test('409 의 code 로 이미 열림·담당 없음을 나눈다', () {
      expect(
        EmoteUnlockRejected.fromResponse(409, <String, Object?>{
          'detail': <String, Object?>{'code': 'already_unlocked'},
        })?.reason,
        EmoteUnlockFailure.alreadyUnlocked,
      );
      expect(
        EmoteUnlockRejected.fromResponse(409, <String, Object?>{
          'detail': <String, Object?>{'code': 'trainer_required'},
        })?.reason,
        EmoteUnlockFailure.trainerRequired,
      );
    });

    test('400 은 잔액 부족, 코드 없는 409·5xx 는 모름(null)', () {
      expect(
        EmoteUnlockRejected.fromResponse(400, <String, Object?>{
          'detail': 'x',
        })?.reason,
        EmoteUnlockFailure.insufficientPoints,
      );
      expect(
        EmoteUnlockRejected.fromResponse(409, <String, Object?>{
          'detail': '이미 쓰고 있는 이모티콘이에요.',
        }),
        isNull,
      );
      expect(EmoteUnlockRejected.fromResponse(500, null), isNull);
      expect(EmoteUnlockRejected.fromResponse(null, null), isNull);
    });
  });
}
