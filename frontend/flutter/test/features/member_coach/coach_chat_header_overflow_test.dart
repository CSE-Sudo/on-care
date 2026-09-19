/// 트레이너 채팅 헤더가 넘치지 않는지 (#840).
///
/// 영어 부제(`Personal trainer`)가 한국어보다 길어도 헤더가 넘치지 않아야
/// 한다. #1235에서 불필요한 상태 점과 메뉴도 함께 걷어냈고, #2089 에서 부제의
/// `상담 가능`(`Available`)도 뺐다 — 뒷받침하는 상태가 없는 약속이었다.
///
/// 430px 는 iPhone 15 Pro Max 의 논리 폭이다. E2E 로그에는
/// `RenderFlex overflowed by 59 pixels on the right` 로 남아 있었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<void> pumpChat(
    WidgetTester tester, {
    required String lang,
    required Size size,
    String trainerName = '김트레이너',
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TrainerChatPage(trainerName: trainerName),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('트레이너 채팅 헤더 레이아웃 (#840)', () {
    for (final String lang in <String>['ko', 'en']) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets('폭 430 · $lang · 글자 배율 $scale 에서 넘치지 않는다', (
          WidgetTester tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await pumpChat(tester, lang: lang, size: const Size(430, 932));

          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('아주 긴 트레이너 이름에도 헤더가 넘치지 않는다', (WidgetTester tester) async {
      await pumpChat(
        tester,
        lang: 'ko',
        size: const Size(430, 932),
        trainerName: '아주아주긴이름을가진트레이너선생님입니다정말로깁니다',
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('부제는 잘려도 트레이너 이름은 그대로 보인다', (WidgetTester tester) async {
      await pumpChat(tester, lang: 'en', size: const Size(430, 932));

      expect(find.text('김트레이너'), findsOneWidget);
    });

    // 트레이너가 지금 답할 수 있는지는 앱이 모른다. 부제는 관계만 적고
    // `상담 가능` 같은 상태를 약속하지 않는다 (#2089).
    for (final (String lang, String subtitle, String promise)
        in <(String, String, String)>[
          ('ko', '담당 트레이너', '상담 가능'),
          ('en', 'Personal trainer', 'Available'),
        ]) {
      testWidgets('부제는 관계만 적고 상태를 약속하지 않는다 · $lang (#2089)', (
        WidgetTester tester,
      ) async {
        await pumpChat(tester, lang: lang, size: const Size(430, 932));

        expect(find.text(subtitle), findsOneWidget);
        expect(find.textContaining(promise), findsNothing);
      });
    }

    testWidgets('상태 점과 동작하지 않는 메뉴가 없다', (WidgetTester tester) async {
      await pumpChat(tester, lang: 'ko', size: const Size(430, 932));

      expect(find.byIcon(Symbols.more_vert_rounded), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 7 && widget.height == 7,
        ),
        findsNothing,
      );
    });

    testWidgets('날짜 구분선과 말풍선 가장자리 시간이 보인다', (WidgetTester tester) async {
      await pumpChat(tester, lang: 'ko', size: const Size(430, 932));

      // 규격 안내 배너가 예전 알약보다 커서, 맨 아래에서 열린 화면에는 구분선이
      // 뷰포트 밖(목록 캐시 영역)에 있을 수 있다 — 화면 밖 자식까지 센다.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(
                r'^\d{4}년 \d{1,2}월 \d{1,2}일 [월화수목금토일]요일$',
              ).hasMatch(widget.data ?? ''),
          skipOffstage: false,
        ),
        findsAtLeastNWidgets(1),
      );

      final sentBubble = find.byKey(
        const ValueKey<String>('coach-message-bubble-seed-m17'),
      );
      // 시간은 규격 말풍선(AppChatBubble)이 옆에 붙이는 AppChatTimestamp 다.
      final sentTime = find.descendant(
        of: find.byKey(const ValueKey<String>('coach-message-seed-m17')),
        matching: find.byType(AppChatTimestamp),
      );
      expect(
        tester.getTopLeft(sentTime).dx,
        lessThan(tester.getTopLeft(sentBubble).dx),
      );
      expect(find.text('18:16'), findsOneWidget);
      expect(find.text('금 18:16'), findsNothing);

      final receivedBubble = find.byKey(
        const ValueKey<String>('coach-message-bubble-seed-m18'),
      );
      final receivedTime = find.descendant(
        of: find.byKey(const ValueKey<String>('coach-message-seed-m18')),
        matching: find.byType(AppChatTimestamp),
      );
      expect(
        tester.getTopLeft(receivedTime).dx,
        greaterThan(tester.getTopRight(receivedBubble).dx),
      );
    });

    testWidgets('새 메시지는 루틴 수신 배너 아래에 쌓인다', (WidgetTester tester) async {
      await pumpChat(tester, lang: 'ko', size: const Size(430, 932));
      await tester.enterText(find.byType(TextField), '확인했습니다');
      await tester.tap(find.byIcon(AppIcons.send));
      await tester.pumpAndSettle();

      final banner = find.textContaining('추천운동을 받았어요').last;
      final sent = find.text('확인했습니다');
      expect(banner, findsOneWidget);
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester.getTopLeft(sent).dy),
      );
    });
  });
}
