import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/app_sidebar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/release_update_banner.dart';

import '../../helpers/fake_release_probe.dart';
import '../../helpers/pump_app.dart';

/// 새 배포 안내 배너가 콘솔 콘텐츠 영역 맨 위에 서는지(#3023).
void main() {
  late FakeReleaseProbe probe;

  setUp(() => probe = FakeReleaseProbe(latest: kNextSha));
  tearDown(() => probe.close());

  Finder banner() => find.byKey(ReleaseUpdateBanner.bannerKey);

  Future<void> pumpConsole(
    WidgetTester tester, {
    String sha = kCurrentSha,
    Locale locale = const Locale('ko'),
  }) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token-existing',
      locale: locale,
      extraOverrides: releaseOverrides(probe, sha: sha),
      at: AppRoutes.dashboard,
    );
  }

  testWidgets('새 배포가 있으면 대시보드 위에 정보 배너가 뜬다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
      expect(banner(), findsOneWidget);
      expect(
        find.descendant(
          of: banner(),
          matching: find.text(l.releaseUpdateTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner(),
          matching: find.text(l.releaseUpdateMessage),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('같은 SHA 면 배너가 없다', (tester) async {
    probe.latest = kCurrentSha;
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      expect(probe.fetchCount, greaterThanOrEqualTo(1));
      expect(banner(), findsNothing);
    });
  });

  testWidgets('읽기가 실패하면 배너가 없다', (tester) async {
    probe.error = StateError('offline');
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      expect(banner(), findsNothing);
    });
  });

  testWidgets('내장 SHA 가 없는 빌드는 확인하지 않는다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester, sha: '');
      expect(probe.fetchCount, 0);
      expect(banner(), findsNothing);
    });
  });

  testWidgets('새로고침 버튼은 페이지를 다시 읽는다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
      await tester.tap(
        find.descendant(
          of: banner(),
          matching: find.text(l.releaseUpdateReload),
        ),
      );
      await tester.pump();
      expect(probe.reloadCount, 1);
    });
  });

  testWidgets('새로고침을 누르면 배너가 바로 사라지고 받으러 간 배포를 남긴다(#3204)', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
      await tester.tap(
        find.descendant(
          of: banner(),
          matching: find.text(l.releaseUpdateReload),
        ),
      );
      await tester.pump();
      expect(banner(), findsNothing);
      expect(probe.reloadedShaAtReload, <String?>[kNextSha]);

      // 페이지가 아직 남아 있는 동안 확인이 와도 같은 배포로는 다시 뜨지 않는다.
      probe.visible.add(null);
      await settle(tester);
      expect(banner(), findsNothing);
    });
  });

  testWidgets('새로고침 뒤 옛 번들이 다시 떠도 같은 배포 안내가 돌아오지 않는다(#3204)', (tester) async {
    probe.reloadedSha = kNextSha;
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      expect(probe.fetchCount, greaterThanOrEqualTo(1));
      expect(banner(), findsNothing);
      expect(probe.reloadCount, 0);

      probe
        ..latest = kLaterSha
        ..visible.add(null);
      await settle(tester);
      expect(banner(), findsOneWidget);
    });
  });

  testWidgets('새로고침해서 새 배포가 뜨면 기록을 지우고 배너가 없다(#3204)', (tester) async {
    probe.reloadedSha = kNextSha;
    await withWideSurface(tester, () async {
      await pumpConsole(tester, sha: kNextSha);
      expect(banner(), findsNothing);
      expect(probe.reloadedSha, isNull);
    });
  });

  testWidgets('안내 문구는 배포 용어 없이 업데이트로 말한다(#3204)', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      expect(
        find.descendant(of: banner(), matching: find.text('앱이 업데이트되었어요')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner(),
          matching: find.text('새로고침하면 최신 버전으로 바뀌어요. 작성 중인 내용이 있으면 먼저 저장해 주세요.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: banner(), matching: find.text('새로고침')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: banner(), matching: find.textContaining('배포')),
        findsNothing,
      );
    });
  });

  testWidgets('닫으면 사라지고 같은 배포로는 다시 뜨지 않는다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      await tester.tap(find.byKey(ReleaseUpdateBanner.dismissKey));
      await tester.pump();
      expect(banner(), findsNothing);

      probe.visible.add(null);
      await settle(tester);
      expect(banner(), findsNothing);

      probe
        ..latest = kLaterSha
        ..visible.add(null);
      await settle(tester);
      expect(banner(), findsOneWidget);
    });
  });

  testWidgets('다른 화면으로 옮겨도 배너가 그대로 위에 있다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester);
      await goTo(tester, AppRoutes.clients);
      expect(banner(), findsOneWidget);
    });
  });

  for (final ({String name, Size size, bool sidebar}) form
      in <({String name, Size size, bool sidebar})>[
        (name: '펼친 사이드바', size: const Size(1440, 900), sidebar: true),
        (name: '아이콘 레일', size: const Size(1100, 800), sidebar: true),
        (name: '드로어', size: const Size(900, 800), sidebar: false),
      ]) {
    testWidgets('${form.name} 폭에서 배너는 콘텐츠 영역 위쪽에 선다', (tester) async {
      await withWideSurface(tester, size: form.size, () async {
        await pumpConsole(tester);
        expect(banner(), findsOneWidget);
        final Rect rect = tester.getRect(banner());
        if (form.sidebar) {
          final Rect side = tester.getRect(find.byType(AppSidebar));
          expect(rect.left, greaterThanOrEqualTo(side.right));
          expect(rect.top, lessThan(form.size.height / 3));
        } else {
          expect(find.byType(AppSidebar), findsNothing);
          // 위쪽 막대(메뉴·워드마크) 아래다.
          expect(rect.top, greaterThan(0));
          expect(rect.top, lessThan(form.size.height / 3));
        }
        expect(rect.right, lessThanOrEqualTo(form.size.width));
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('영어 화면은 영어 문구다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpConsole(tester, locale: const Locale('en'));
      final AppLocalizations l = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l.releaseUpdateTitle), findsOneWidget);
      expect(find.text(l.releaseUpdateReload), findsOneWidget);
      expect(find.byTooltip(l.releaseUpdateDismiss), findsOneWidget);
      expect(l.releaseUpdateTitle, 'The app has been updated');
      expect(l.releaseUpdateReload, 'Refresh');
    });
  });
}
