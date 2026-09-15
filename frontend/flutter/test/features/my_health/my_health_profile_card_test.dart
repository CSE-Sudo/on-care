import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show OnCareColors;

/// MY 탭 프로필 카드의 "트레이너와 데이터 동기화" — 트레이너가 신규 고객
/// 등록에서 입력하는 6자리 코드가 여기서 나온다. (#1634)
///
/// 예전에는 이 자리가 "내 회원 ID"(`User.id`)를 보여 주고 복사 버튼을 뒀다.
/// `user-<12자리 hex>` 는 마주 앉아 불러 주거나 받아 적을 수 있는 형태가
/// 아니었다.
///
/// 코드를 카드에 바로 띄우지 않고 한 단계 두는 것은 **코드를 띄우는 것이 곧
/// 데이터 공유 동의**이기 때문이다 — 스스로 누른 것이어야 한다.
class _FakeTrainerSyncRepository implements TrainerSyncRepository {
  int issued = 0;
  int revoked = 0;

  @override
  Future<PairingCode> issue() async {
    issued += 1;
    return const PairingCode(code: '979030', expiresInSeconds: 300);
  }

  @override
  Future<void> revoke() async {
    revoked += 1;
  }
}

void main() {
  late _FakeTrainerSyncRepository sync;

  setUp(() => sync = _FakeTrainerSyncRepository());

  Future<void> pumpMyTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          myHealthRepositoryProvider.overrideWithValue(
            const MockMyHealthRepository(),
          ),
          trainerSyncRepositoryProvider.overrideWithValue(sync),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MyHealthPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('프로필 카드가 트레이너 동기화 진입점을 보여준다', (tester) async {
    await pumpMyTab(tester);

    expect(find.text('트레이너와 데이터 동기화'), findsOneWidget);
    // 누르기 전에는 코드를 받지 않는다 — 발급이 곧 동의라서다.
    expect(sync.issued, 0);
  });

  testWidgets('누르면 6자리 코드와 공유 범위 안내가 뜬다', (tester) async {
    await pumpMyTab(tester);

    await tester.tap(find.text('트레이너와 데이터 동기화'));
    await tester.pumpAndSettle();

    expect(sync.issued, 1);
    // 한 자리씩 상자에 담긴다 — 마주 앉아 불러 주는 값이라 글자가 갈려야 한다.
    final String shown = <String>[
      for (int i = 0; i < 6; i++)
        tester
                .widget<Text>(
                  find.descendant(
                    of: find.byKey(ValueKey<String>('sync-digit-$i')),
                    matching: find.byType(Text),
                  ),
                )
                .data ??
            '',
    ].join();
    expect(shown, '979030');
    // 자리 상자는 입력칸과 같은 흰 채움 + 회색 테두리다(#1776).
    for (int i = 0; i < 6; i++) {
      final BoxDecoration box =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byKey(ValueKey<String>('sync-digit-$i')),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(box.color, OnCareColors.surfaceCard);
      expect((box.border! as Border).top.color, OnCareColors.lineStrong);
    }
    // 코드보다 먼저 무엇이 공유되는지 말해야 한다 — 이 시트를 여는 것이 동의다.
    expect(find.textContaining('식단·운동·건강 기록이 공유돼요'), findsOneWidget);
  });

  testWidgets('시트를 닫으면 코드를 버린다', (tester) async {
    await pumpMyTab(tester);
    await tester.tap(find.text('트레이너와 데이터 동기화'));
    await tester.pumpAndSettle();

    // 배경을 눌러 닫는다.
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    // 발급이 동의였으니 취소도 즉시 반영돼야 한다 — 만료를 기다리지 않는다.
    expect(sync.revoked, 1);
  });
}
