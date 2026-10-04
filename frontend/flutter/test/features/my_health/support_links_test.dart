/// 고객 지원 → 카카오톡 채널. (#507)
///
/// 전에는 FAQ·1:1 문의를 누르면 "준비 중" 스낵바만 떴다. 같은 화면의 약관·개인정보
/// 처리방침은 실제 문서로 이동하는데 두 항목만 막다른 길이었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/app_version/app_version.dart';
import 'package:oncare/features/my_health/domain/support_links.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';

/// `url_launcher` 플랫폼 호출을 가로채 어떤 URL 로 나갔는지 기록한다.
class _LaunchRecorder {
  final List<String> urls = <String>[];
  bool canLaunch = true;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (MethodCall call) async {
        if (call.method == 'canLaunch') return canLaunch;
        if (call.method == 'launch') {
          if (!canLaunch) return false;
          final args = call.arguments as Map<Object?, Object?>;
          urls.add(args['url']! as String);
          return true;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      );
    });
  }
}

Future<void> _pumpSupport(
  WidgetTester tester, {
  Locale locale = const Locale('ko'),
  String? version = '0.4.0',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // 버전 줄은 빌드 정보에서 읽는다(#3047). 테스트에는 플랫폼이 없어 값을 준다.
      overrides: <Override>[
        appVersionProvider.overrideWith((ref) async => version),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SupportPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FAQ 는 카카오톡 채널 홈을 연다', (WidgetTester tester) async {
    final recorder = _LaunchRecorder()..install(tester);
    await _pumpSupport(tester);

    await tester.tap(find.text('자주 묻는 질문'));
    await tester.pumpAndSettle();

    expect(recorder.urls, <String>[kSupportChannelUrl]);
  });

  testWidgets('1:1 문의는 채널 채팅을 연다', (WidgetTester tester) async {
    final recorder = _LaunchRecorder()..install(tester);
    await _pumpSupport(tester);

    await tester.tap(find.text('1:1 문의'));
    await tester.pumpAndSettle();

    expect(recorder.urls, <String>[kSupportChatUrl]);
  });

  testWidgets('열지 못하면 사유를 알린다', (WidgetTester tester) async {
    final recorder = _LaunchRecorder()..install(tester);
    recorder.canLaunch = false;
    await _pumpSupport(tester);

    await tester.tap(find.text('1:1 문의'));
    await tester.pumpAndSettle();

    // 조용히 아무 일도 안 일어나면 사용자는 앱이 고장 난 것으로 읽는다.
    expect(find.textContaining('열지 못했어요'), findsOneWidget);
  });

  testWidgets('"준비 중" 안내가 남지 않는다', (WidgetTester tester) async {
    _LaunchRecorder().install(tester);
    await _pumpSupport(tester);

    await tester.tap(find.text('자주 묻는 질문'));
    await tester.pumpAndSettle();

    expect(find.textContaining('준비 중'), findsNothing);
  });

  testWidgets('앱 밖으로 나가는 행임을 미리 알린다', (WidgetTester tester) async {
    _LaunchRecorder().install(tester);
    await _pumpSupport(tester);

    // 아이콘과 안내 문구 둘 다 — 누르기 전에 무엇이 일어나는지 보이게.
    expect(find.byIcon(AppIcons.external), findsNWidgets(2));
    expect(find.text('카카오톡 채널로 연결돼요'), findsNWidgets(2));
  });

  test('채널 주소는 https 다', () {
    // 평문으로 외부 링크를 여는 것을 남길 이유가 없다.
    expect(kSupportChannelUrl.startsWith('https://'), isTrue);
    expect(kSupportChatUrl.startsWith('https://'), isTrue);
    expect(kSupportChatUrl.startsWith(kSupportChannelUrl), isTrue);
  });

  group('버전 줄 (#3047)', () {
    final AppLocalizationsKo ko = AppLocalizationsKo();
    final AppLocalizationsEn en = AppLocalizationsEn();

    testWidgets('빌드 버전을 그대로 보인다', (WidgetTester tester) async {
      await _pumpSupport(tester, version: '1.2.3');

      expect(find.text('On-Care · 버전 1.2.3'), findsOneWidget);
      expect(find.text(ko.myAppVersion('1.2.3')), findsOneWidget);
    });

    testWidgets('영어 화면도 빌드 버전을 보인다', (WidgetTester tester) async {
      await _pumpSupport(tester, locale: const Locale('en'), version: '1.2.3');

      expect(find.text(en.myAppVersion('1.2.3')), findsOneWidget);
    });

    testWidgets('읽지 못하면 앱 이름만 보인다', (WidgetTester tester) async {
      await _pumpSupport(tester, version: null);

      expect(find.text(ko.myAppName), findsOneWidget);
      expect(find.textContaining('버전'), findsNothing);
    });

    testWidgets('예전 고정 버전이 남지 않았다', (WidgetTester tester) async {
      await _pumpSupport(tester, version: '2.3.4');

      expect(find.textContaining('1.0.0'), findsNothing);
      expect(find.text(ko.myAppVersion('2.3.4')), findsOneWidget);
    });
  });
}
