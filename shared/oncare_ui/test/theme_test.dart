import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

ThemeData _member() => OnCareTheme.light(
  brand: OnCareBrand.member,
  density: OnCareDensity.mobile,
);

ThemeData _trainer() =>
    OnCareTheme.light(brand: OnCareBrand.trainer, density: OnCareDensity.web);

void main() {
  group('테마에 실린 토큰', () {
    test('브랜드·밀도가 extension 으로 들어 있다', () {
      final OnCareTokens? member = _member().extension<OnCareTokens>();
      final OnCareTokens? trainer = _trainer().extension<OnCareTokens>();
      expect(member?.brand, OnCareBrand.member);
      expect(member?.density, OnCareDensity.mobile);
      expect(trainer?.brand, OnCareBrand.trainer);
      expect(trainer?.density, OnCareDensity.web);
    });

    test('두 앱의 다른 점은 브랜드 색과 밀도에서 오는 값뿐이다', () {
      final ThemeData m = _member();
      final ThemeData t = _trainer();
      expect(m.colorScheme.primary, OnCareBrand.member.primary);
      expect(t.colorScheme.primary, OnCareBrand.trainer.primary);
      expect(m.scaffoldBackgroundColor, t.scaffoldBackgroundColor);
      expect(m.textTheme.bodyMedium!.fontSize, t.textTheme.bodyMedium!.fontSize);
      expect(m.dialogTheme.shape, t.dialogTheme.shape);
      expect(m.snackBarTheme.backgroundColor, t.snackBarTheme.backgroundColor);
    });

    testWidgets('context.oncare 는 테마 밖에서 조용히 기본값을 쓰지 않는다', (tester) async {
      late Object error;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              try {
                context.oncare;
              } catch (e) {
                error = e;
              }
              return const SizedBox();
            },
          ),
        ),
      );
      expect(error, isA<FlutterError>());
    });
  });

  group('M3 기본값이 튀어나오지 않는다', () {
    test('배경 — 페이지는 연회색, 다이얼로그·시트는 흰색이다', () {
      final ThemeData theme = _member();
      expect(theme.scaffoldBackgroundColor, OnCareColors.surfacePage);
      expect(theme.dialogTheme.backgroundColor, OnCareColors.surfaceCard);
      expect(theme.bottomSheetTheme.backgroundColor, OnCareColors.surfaceCard);
      expect(theme.colorScheme.surfaceTint, Colors.transparent);
    });

    test('버튼은 반경 12 이고 기본 높이가 밀도를 따른다', () {
      for (final (ThemeData theme, OnCareDensity density)
          in <(ThemeData, OnCareDensity)>[
            (_member(), OnCareDensity.mobile),
            (_trainer(), OnCareDensity.web),
          ]) {
        for (final ButtonStyle? style in <ButtonStyle?>[
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
        ]) {
          final OutlinedBorder? shape = style!.shape!.resolve(
            <WidgetState>{},
          );
          expect(
            (shape! as RoundedRectangleBorder).borderRadius,
            OnCareRadius.mdAll,
          );
          expect(
            style.minimumSize!.resolve(<WidgetState>{})!.height,
            density.buttonMedium,
          );
          expect(
            style.textStyle!.resolve(<WidgetState>{})!.fontSize,
            OnCareTypography.buttonMedium.fontSize,
          );
        }
      }
    });

    test('다이얼로그 — 반경 20, 제목 18, 웹은 위 여백 100', () {
      final ThemeData web = _trainer();
      expect(
        (web.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
        OnCareRadius.xlAll,
      );
      expect(web.dialogTheme.titleTextStyle!.fontSize, 18);
      expect(web.dialogTheme.insetPadding!.top, OnCareLayout.dialogTopClearance);
      expect(_member().dialogTheme.insetPadding!.left, OnCareSpacing.s20);
    });

    test('입력창은 외곽선·반경 12 이고 밑줄이 아니다', () {
      final InputDecorationThemeData input = _member().inputDecorationTheme;
      expect(input.filled, isTrue);
      expect(input.enabledBorder, isA<OutlineInputBorder>());
      expect(
        (input.enabledBorder! as OutlineInputBorder).borderRadius,
        OnCareRadius.mdAll,
      );
      expect(input.border, isNot(isA<UnderlineInputBorder>()));
    });

    test('칩은 체크 표시 없이 반경 12 이다', () {
      final ChipThemeData chip = _member().chipTheme;
      expect(chip.showCheckmark, isFalse);
      expect(
        (chip.shape! as RoundedRectangleBorder).borderRadius,
        OnCareRadius.mdAll,
      );
    });

    test('스낵바는 떠 있는 오버레이 모양이다', () {
      final SnackBarThemeData snack = _trainer().snackBarTheme;
      expect(snack.behavior, SnackBarBehavior.floating);
      expect(snack.backgroundColor, OnCareColors.overlayInk);
    });

    test('모바일 바텀시트는 콘텐츠 최대 폭까지 넓어진다', () {
      expect(
        _member().bottomSheetTheme.constraints!.maxWidth,
        OnCareLayout.mobileContentMaxWidth,
      );
    });

    test('구분선·카드 테두리는 옅은 선 한 가지다', () {
      final ThemeData theme = _member();
      expect(theme.dividerTheme.color, OnCareColors.lineSubtle);
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).side.color,
        OnCareColors.lineSubtle,
      );
    });
  });

  group('글자', () {
    test('TextTheme 슬롯이 역할 크기를 따른다', () {
      final TextTheme text = _member().textTheme;
      expect(text.titleLarge!.fontSize, 22);
      expect(text.titleMedium!.fontSize, 18);
      expect(text.titleSmall!.fontSize, 16);
      expect(text.bodyLarge!.fontSize, 16);
      expect(text.bodyMedium!.fontSize, 15);
      expect(text.bodySmall!.fontSize, 14);
      expect(text.labelLarge!.fontSize, 14);
      expect(text.labelSmall!.fontSize, 12);
      expect(text.bodyMedium!.color, OnCareColors.textPrimary);
    });

    test('옛 전역 배율을 넘기면 그만큼 나눠 보이는 크기를 지킨다', () {
      final ThemeData theme = OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
        legacyTextScale: 1.10,
      );
      expect(theme.textTheme.bodyMedium!.fontSize! * 1.10, closeTo(15, 1e-9));
      expect(theme.dialogTheme.titleTextStyle!.fontSize! * 1.10, closeTo(18, 1e-9));
    });

    testWidgets('AlertDialog 제목이 22px 기본값이 아니라 18 로 그려진다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _member(),
          home: const AlertDialog(title: Text('제목'), content: Text('본문')),
        ),
      );
      final RichText title = tester.widget<RichText>(
        find.descendant(of: find.text('제목'), matching: find.byType(RichText)),
      );
      expect(title.text.style!.fontSize, 18);
    });
  });

  testWidgets('웹 밀도 FilledButton 은 높이 36 으로 그려진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _trainer(),
        home: Scaffold(
          body: Center(
            child: FilledButton(onPressed: () {}, child: const Text('저장')),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(FilledButton)).height, 36);
  });

  testWidgets('토큰 카탈로그가 두 테마에서 그려진다', (tester) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final ThemeData theme in <ThemeData>[_member(), _trainer()]) {
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const OnCareTokenCatalog()),
      );
      expect(find.byType(OnCareTokenCatalog), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
