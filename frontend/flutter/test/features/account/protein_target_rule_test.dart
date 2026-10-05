/// 목표 없는 회원의 단백질 분모 — 식단 분석과 같은 규칙. (#2898)
///
/// 영양 카드는 100g, 식단 분석·조언은 체중 × 1.2g(없으면 60g)을 써서, 하루 70g 을
/// 먹은 날 카드는 모자라다고 하고 분석은 채웠다고 했다. 이제 서버가 계산한
/// `effective_daily_protein_g` 를 쓰고, 옛 응답이면 같은 규칙을 앱에서 계산한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/demo/diet_advice.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/mock_account_repository.dart';

UserProfile _profile({int? protein, double? weight, int? server}) =>
    UserProfile(
      id: 'member',
      name: '회원',
      email: 'member@example.com',
      dailyProteinG: protein,
      weightKg: weight,
      serverEffectiveDailyProteinG: server,
    );

void main() {
  group('규칙', () {
    test('개인 목표가 먼저다', () {
      expect(
        _profile(protein: 130, weight: 70, server: 84).effectiveDailyProteinG,
        130,
      );
    });

    test('개인 목표가 없으면 서버가 계산한 값', () {
      expect(_profile(weight: 70, server: 84).effectiveDailyProteinG, 84);
    });

    test('옛 응답이면 체중 × 1.2g', () {
      expect(_profile(weight: 72).effectiveDailyProteinG, 86); // 86.4
      expect(_profile(weight: 55.5).effectiveDailyProteinG, 67); // 66.6
    });

    test('체중도 없으면 60g — 서버 DEFAULT_PROTEIN_G 와 같다', () {
      expect(_profile().effectiveDailyProteinG, 60);
      expect(UserProfile.defaultDailyProteinG, 60);
      expect(UserProfile.proteinGPerKg, 1.2);
    });

    test('데모 식단 조언과 같은 수를 낸다', () {
      for (final double? weight in <double?>[null, 50, 62.5, 72, 88.8]) {
        expect(
          _profile(weight: weight).effectiveDailyProteinG,
          demoDietTargets(<String, Object?>{'weight_kg': weight}).proteinG,
          reason: '체중 $weight',
        );
      }
    });
  });

  group('응답 파싱', () {
    test('effective_daily_protein_g 를 읽는다', () {
      final UserProfile p = UserProfile.fromJson(<String, Object?>{
        'id': 'm',
        'weight_kg': 70,
        'daily_protein_g': null,
        'effective_daily_protein_g': 84,
      });
      expect(p.dailyProteinG, isNull, reason: '개인 목표 칸은 그대로 비어 있다');
      expect(p.serverEffectiveDailyProteinG, 84);
      expect(p.effectiveDailyProteinG, 84);
    });

    test('없거나 0 이하면 없는 것과 같다', () {
      for (final Object? v in <Object?>[null, 0, -5, '84']) {
        final UserProfile p = UserProfile.fromJson(<String, Object?>{
          'id': 'm',
          'effective_daily_protein_g': v,
        });
        expect(p.serverEffectiveDailyProteinG, isNull, reason: '$v');
        expect(p.effectiveDailyProteinG, 60, reason: '$v');
      }
    });
  });

  testWidgets('목표 없이 체중만 있는 회원의 식단 카드 분모는 체중 × 1.2g 이다', (
    WidgetTester tester,
  ) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(profile: _profile(weight: 72)),
          ),
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DietRecordPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 오늘 4끼 단백질 합계 45g.
    expect(find.textContaining('45 / 86g'), findsOneWidget);
    expect(find.textContaining('45 / 100g'), findsNothing);
  });
}
