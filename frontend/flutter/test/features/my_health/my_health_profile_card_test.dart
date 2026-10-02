import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/entities/profile_pet.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../benefits/fake_benefits_repository.dart';

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

  Future<void> pumpMyTab(WidgetTester tester, {ProfilePet? pet}) async {
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
          benefitsRepositoryProvider.overrideWithValue(
            FakeBenefitsRepository(pet: pet),
          ),
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

  testWidgets('동기화 행은 앞머리 아이콘 없이 제목·설명·화살표만 둔다 (#1785)', (tester) async {
    await pumpMyTab(tester);

    expect(find.byIcon(AppIcons.sync), findsNothing);
    expect(find.text('6자리 코드로 담당 트레이너와 연결해요'), findsOneWidget);
    // 아이콘 칸이 빠졌으니 제목이 프로필 아바타와 같은 왼쪽 선에서 시작한다.
    // 아래 헬스장 카드의 담당 트레이너도 성씨 프로필이라(#2599) 맨 위
    // 프로필 카드의 것을 짚는다.
    expect(
      tester.getTopLeft(find.text('트레이너와 데이터 동기화')).dx,
      tester.getTopLeft(find.byType(AppAvatar).first).dx,
    );
    // 행에 남는 아이콘은 오른쪽 화살표 하나뿐이다.
    final Finder row = find
        .ancestor(of: find.text('트레이너와 데이터 동기화'), matching: find.byType(Row))
        .first;
    final Finder icons = find.descendant(of: row, matching: find.byType(Icon));
    expect(icons, findsOneWidget);
    expect(tester.widget<Icon>(icons).icon, AppIcons.chevronRight);
  });

  testWidgets('공유 범위를 먼저 보여 주고, 동의해야 코드를 발급한다 (#2584)', (tester) async {
    await pumpMyTab(tester);

    await tester.tap(find.text('트레이너와 데이터 동기화'));
    await tester.pumpAndSettle();

    // 여는 것만으로는 발급하지 않는다 — 무엇에 동의하는지 읽기 전에 동의가
    // 끝나면 안 된다. 서버는 발급 시각을 동의 시각으로 적는다.
    expect(sync.issued, 0);
    expect(find.textContaining('식단 기록·운동 기록·신체 정보와 건강 목표'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sync-digit-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('trainer-sync-agree')));
    await tester.pumpAndSettle();

    expect(sync.issued, 1);
    expect(
      find.byKey(const ValueKey<String>('trainer-sync-agree')),
      findsNothing,
    );
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
    // 코드와 함께 공유 범위가 남아 있다 — 무엇에 동의했는지 계속 보인다.
    expect(find.textContaining('식단 기록·운동 기록·신체 정보와 건강 목표'), findsOneWidget);
  });

  testWidgets('동의하지 않고 닫으면 발급도 취소도 없다 (#2584)', (tester) async {
    await pumpMyTab(tester);
    await tester.tap(find.text('트레이너와 데이터 동기화'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    expect(sync.issued, 0);
    expect(sync.revoked, 0);
  });

  testWidgets('시트를 닫으면 코드를 버린다', (tester) async {
    await pumpMyTab(tester);
    await tester.tap(find.text('트레이너와 데이터 동기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('trainer-sync-agree')));
    await tester.pumpAndSettle();

    // 배경을 눌러 닫는다.
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    // 발급이 동의였으니 취소도 즉시 반영돼야 한다 — 만료를 기다리지 않는다.
    expect(sync.revoked, 1);
  });

  testWidgets('펫은 달고 있을 때만 이름 옆에 붙고, 빠져도 이름 줄이 흔들리지 않는다 (#2021)', (
    tester,
  ) async {
    Future<(double, double)> measure() async => (
      tester.getSize(find.byKey(const Key('profileNameLine'))).height,
      tester.getTopLeft(find.text('트레이너와 데이터 동기화')).dy,
    );

    await pumpMyTab(
      tester,
      pet: const ProfilePet(kind: 'dog', remainingSeconds: 5 * 86400),
    );
    expect(find.byKey(const Key('profilePet')), findsOneWidget);
    final (double, double) worn = await measure();

    // 기간이 끝나면 서버가 `pet` 을 비워 보낸다.
    expect(
      ProfilePet.fromStateJson(<String, Object?>{
        'pet': <String, Object?>{'kind': 'dog', 'remaining_seconds': 0},
      }),
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await pumpMyTab(tester);
    expect(find.byKey(const Key('profilePet')), findsNothing);
    expect(await measure(), worn);

    // 사용처 카드는 달고 있는 펫과 남은 기간을 적는다.
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    const ShopItem card = ShopItem(
      id: kProfilePetItem,
      title: '',
      benefit: '',
      description: '',
      cost: 200,
      validDays: 7,
      available: false,
      blockReason: ShopBlockReason.activePet,
      activeOption: 'cat',
      remainingSeconds: 5 * 86400 - 60,
    );
    expect(shopBlockLabel(l, card), '고양이 · 5일 남음');
  });
}
