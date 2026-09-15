import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  group('브랜드', () {
    test('앱마다 다른 것은 브랜드 색뿐이다', () {
      expect(OnCareBrand.member.primary, const Color(0xFF3EAFDF));
      expect(OnCareBrand.trainer.primary, const Color(0xFF2E7DAB));
      expect(OnCareBrand.member.surface, const Color(0xFFEDF7FC));
      expect(OnCareBrand.trainer.surface, const Color(0xFFEAF2F9));
    });

    test('차트 주색과 목표 안쪽은 각 앱의 메인 색이다(#1070, #1239)', () {
      for (final OnCareBrand brand in <OnCareBrand>[
        OnCareBrand.member,
        OnCareBrand.trainer,
      ]) {
        expect(brand.statusWithinGoal, brand.primary);
        expect(brand.dietChart, brand.primary);
        expect(brand.exerciseChart, brand.primary);
        expect(brand.macroCarbs, brand.primary);
      }
    });

    test('탄단지는 메인 색을 흰 바탕에 65·35% 로 얹은 불투명 색이다(#953)', () {
      expect(OnCareBrand.trainer.macroProtein.a, 1.0);
    });
  });

  group('상태색은 두 앱이 같다', () {
    test('위험 동작·초과 빨강은 하나다', () {
      expect(OnCareColors.danger, const Color(0xFFF04438));
    });

    test('완료 초록은 #34C759 다', () {
      expect(OnCareColors.success, const Color(0xFF34C759));
    });
  });

  group('대비', () {
    test('제목·보조 텍스트는 카드와 페이지 배경 모두에서 4.5:1 이상이다', () {
      for (final Color bg in <Color>[
        OnCareColors.surfaceCard,
        OnCareColors.surfacePage,
      ]) {
        expect(_contrast(OnCareColors.textPrimary, bg), greaterThan(4.5));
        expect(_contrast(OnCareColors.textSecondary, bg), greaterThan(4.5));
      }
    });

    test('힌트는 카드 위에서 4.5:1, 비활성은 3:1 이상이다', () {
      expect(
        _contrast(OnCareColors.textTertiary, OnCareColors.surfaceCard),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(OnCareColors.textDisabled, OnCareColors.surfaceCard),
        greaterThanOrEqualTo(3),
      );
    });

    test('토스트 글자는 오버레이 바탕에서 4.5:1 이상이다', () {
      expect(
        _contrast(OnCareColors.textOnFill, OnCareColors.overlayInk),
        greaterThan(4.5),
      );
      expect(
        _contrast(OnCareColors.overlayAction, OnCareColors.overlayInk),
        greaterThan(4.5),
      );
      // 적립 표시(★ +50P)는 밝은 바탕에 어두운 글자다.
      expect(
        _contrast(OnCareColors.overlayInk, OnCareColors.overlayReward),
        greaterThan(4.5),
      );
    });
  });

  group('글자 역할', () {
    test('9단계 크기·굵기가 규격과 같다', () {
      final Map<String, (double, FontWeight)> expected =
          <String, (double, FontWeight)>{
            'display': (28, FontWeight.w700),
            'titleLarge': (22, FontWeight.w700),
            'titleMedium': (18, FontWeight.w700),
            'titleSmall': (16, FontWeight.w700),
            'bodyLarge': (16, FontWeight.w500),
            'body': (15, FontWeight.w500),
            'bodySmall': (14, FontWeight.w500),
            'label': (14, FontWeight.w600),
            'caption': (12, FontWeight.w500),
          };
      expect(OnCareTypography.roles.keys, expected.keys);
      for (final MapEntry<String, TextStyle> role
          in OnCareTypography.roles.entries) {
        expect(role.value.fontSize, expected[role.key]!.$1, reason: role.key);
        expect(role.value.fontWeight, expected[role.key]!.$2, reason: role.key);
        expect(role.value.fontFamily, OnCareTypography.fontFamily);
      }
    });

    test('반 포인트 크기와 굵기 800 이 없다', () {
      for (final TextStyle style in <TextStyle>[
        ...OnCareTypography.roles.values,
        OnCareTypography.buttonLarge,
        OnCareTypography.buttonMedium,
        OnCareTypography.buttonSmall,
      ]) {
        expect(style.fontSize! % 1, 0);
        expect(style.fontWeight!.value, lessThanOrEqualTo(700));
      }
    });

    test('버튼 라벨은 16/15/13, 굵기 600 이다', () {
      expect(OnCareTypography.buttonLarge.fontSize, 16);
      expect(OnCareTypography.buttonMedium.fontSize, 15);
      expect(OnCareTypography.buttonSmall.fontSize, 13);
    });

    test('기기 배율은 1.0 ~ 1.3 으로 묶인다', () {
      expect(
        OnCareTypography.scaler(const TextScaler.linear(2)).scale(10),
        closeTo(13, 1e-9),
      );
      expect(
        OnCareTypography.scaler(const TextScaler.linear(0.8)).scale(10),
        closeTo(10, 1e-9),
      );
    });
  });

  group('밀도', () {
    test('버튼 높이 — 모바일 52/44/32, 웹 44/36/28(확정)', () {
      expect(
        OnCareButtonSize.values.map(OnCareDensity.mobile.buttonHeight),
        <double>[52, 44, 32],
      );
      expect(
        OnCareButtonSize.values.map(OnCareDensity.web.buttonHeight),
        <double>[44, 36, 28],
      );
    });

    test('페이지 좌우 여백 — 모바일 20, 웹 16', () {
      expect(OnCareDensity.mobile.pagePadding, 20);
      expect(OnCareDensity.web.pagePadding, 16);
    });
  });

  group('모양·간격', () {
    test('조작 요소 반경은 12, 카드·창은 20 이다', () {
      expect(OnCareRadius.md, const Radius.circular(12));
      expect(OnCareRadius.xl, const Radius.circular(20));
    });

    test('간격은 4의 배수(선·점 사이 2 제외)다', () {
      for (final double s in OnCareSpacing.scale.where((s) => s != 2)) {
        expect(s % 4, 0, reason: '$s');
      }
    });

    test('아이콘은 16/20/24 와 빈 화면 40 뿐이다', () {
      expect(OnCareSize.iconScale, <double>[16, 20, 24, 40]);
    });

    test('창 폭 — 웹 S400/M560/L800, 모바일 확인창 400(확정)', () {
      expect(OnCareLayout.dialogSmall, 400);
      expect(OnCareLayout.dialogMedium, 560);
      expect(OnCareLayout.dialogLarge, 800);
      expect(OnCareLayout.mobileDialogMaxWidth, 400);
      expect(OnCareLayout.dialogMaxHeightFactor, 0.85);
      expect(OnCareLayout.sheetMaxHeightFactor, 0.9);
    });
  });
}

double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
