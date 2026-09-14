/// 리포트 등록 안내 카드 (#1421).
///
/// 트레이너 앱은 같은 사건을 `ReportRegisteredCard` 로 그린다 — 상태 문구,
/// 대상 주, 다음 행동 한 줄. 짝은
/// `frontend/flutter_trainer/test/features/clients/client_detail_chat_test.dart`
/// 의 `리포트 전송 메시지는 …` 테스트다. 한쪽 문구만 고치면 여기서 깨진다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Widget child,
    String lang = 'ko',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpChat(WidgetTester tester, {String lang = 'ko'}) async {
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
          home: const TrainerChatPage(trainerName: '김트레이너'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('리포트 등록 카드 (#1421, #1600)', () {
    testWidgets('상태 문구·대상 주·다음 행동을 한 상자에 담는다', (WidgetTester tester) async {
      var opened = 0;
      await pumpCard(
        tester,
        child: CoachReportCard(
          weekStart: DateTime(2026, 8, 17),
          onOpenPdf: () => opened++,
        ),
      );

      expect(find.text('리포트가 등록되었어요'), findsOneWidget);
      expect(find.text('8월 17일 – 8월 23일'), findsOneWidget);
      expect(find.text('PDF 미리보기'), findsOneWidget);

      await tester.tap(find.text('PDF 미리보기'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('추천운동 수신 배너와 같은 안내 배너(info)에 동작 버튼 하나 (#1577)', (
      WidgetTester tester,
    ) async {
      await pumpCard(
        tester,
        child: CoachReportCard(
          weekStart: DateTime(2026, 8, 17),
          onOpenPdf: () {},
        ),
      );

      final AppBanner banner = tester.widget<AppBanner>(
        find.descendant(
          of: find.byType(CoachReportCard),
          matching: find.byType(AppBanner),
        ),
      );
      expect(banner.tone, AppBannerTone.info);
      final Container box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, OnCareBrand.member.surface);
      expect(decoration.border, Border.all(color: OnCareBrand.member.border));
      // 다음 행동은 하나뿐이다.
      expect(find.byType(AppButton), findsOneWidget);
    });

    testWidgets('영어 로케일도 같은 정보 구조다', (WidgetTester tester) async {
      await pumpCard(
        tester,
        lang: 'en',
        child: CoachReportCard(
          weekStart: DateTime(2026, 8, 17),
          onOpenPdf: () {},
        ),
      );

      expect(find.text('Weekly report added'), findsOneWidget);
      expect(find.text('8/17 – 8/23'), findsOneWidget);
      expect(find.text('Preview PDF'), findsOneWidget);
    });

    testWidgets('좁은 화면에서 글자를 키워도 넘치지 않는다', (WidgetTester tester) async {
      // `setSurfaceSize` 는 MediaQuery 를 바꾸지 않는다 — 카드가 화면 폭으로
      // 최대 너비를 잡으므로 뷰를 직접 세운다.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpCard(
        tester,
        child: CoachReportCard(
          weekStart: DateTime(2026, 8, 17),
          onOpenPdf: () {},
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  /// 데모에서 두 앱은 저장소를 공유하지 않는다(`oncare` vs `oncare_trainer`).
  /// 트레이너가 데모 중에 보낸 리포트는 트레이너 쪽 로컬 DB 에만 남으므로,
  /// 회원 쪽에서 이 안내가 보이려면 시드가 들고 있어야 한다. (#1605)
  group('데모 대화의 리포트 등록 안내 (#1605)', () {
    testWidgets('김민수 데모 스레드에 리포트 등록 카드가 있다', (
      WidgetTester tester,
    ) async {
      await pumpChat(tester);

      expect(find.byType(CoachReportCard), findsOneWidget);
      expect(find.text('리포트가 등록되었어요'), findsOneWidget);
      // 안내로 그리므로 본문은 말풍선으로 나타나지 않는다.
      expect(find.text('이번 주 리포트 등록해 뒀어요. 확인해 보세요'), findsNothing);
    });

    testWidgets('안내에는 미리보기 버튼이 있다', (WidgetTester tester) async {
      await pumpChat(tester);

      expect(find.text('PDF 미리보기'), findsOneWidget);
    });

    testWidgets('데모 리포트 메시지는 표시만 갖고 첨부는 없다', (
      WidgetTester tester,
    ) async {
      final List<CoachMessage> chat = await MockMemberCoachRepository()
          .fetchChat();
      final Iterable<CoachMessage> reports = chat.where(
        (CoachMessage m) => m.reportWeekStart != null,
      );

      expect(reports.length, 1);
      expect(
        chat.where((CoachMessage m) => m.attachment != null),
        isEmpty,
        reason: '데모에는 첨부 저장소가 없다 — 미리보기는 회원 기록으로 만든다',
      );
    });
  });
}
