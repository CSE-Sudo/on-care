import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';
import 'package:oncare_trainer/features/my/presentation/pages/my_page.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

class _GymFailureRepository implements TrainerProfileRepository {
  final MockTrainerProfileRepository _delegate = MockTrainerProfileRepository();

  @override
  Future<TrainerProfile> fetch() => _delegate.fetch();

  @override
  Future<List<TrainerGymChoice>> listGyms() => _delegate.listGyms();

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) =>
      _delegate.update(update);

  @override
  Future<TrainerProfile> setGym(String gymId) {
    throw const ServerError(message: '헬스장 연결 요청이 실패했습니다.');
  }

  @override
  Future<TrainerProfile> clearGym() => _delegate.clearGym();
}

class _UpdateFailureRepository implements TrainerProfileRepository {
  @override
  Future<TrainerProfile> fetch() async => seedTrainerProfile;

  @override
  Future<List<TrainerGymChoice>> listGyms() async => const <TrainerGymChoice>[];

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) {
    throw const ValidationError(message: '프로필 입력값을 확인해 주세요.');
  }

  @override
  Future<TrainerProfile> setGym(String gymId) => throw UnimplementedError();

  @override
  Future<TrainerProfile> clearGym() => throw UnimplementedError();
}

void main() {
  group('MyPage', () {
    Future<void> openTab(WidgetTester tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
      );
    }

    /// 로그아웃 moved into the 설정 section (it is an account action, not
    /// part of the profile).
    Future<void> openSettings(WidgetTester tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('settings'),
      );
    }

    testWidgets('renders profile, certs, stats, gym — and no 역할 전환', (
      tester,
    ) async {
      await openTab(tester);

      expect(find.text(kDemoTrainerName), findsWidgets);
      expect(find.text('trainer@oncare.com'), findsOneWidget);
      expect(find.text('퍼스널 트레이너 · 경력 7년'), findsOneWidget);
      // 기본 정보의 '경력' 칸에는 연수만 — 라벨과 같은 말을 되풀이하지 않는다.
      expect(find.text('7년'), findsOneWidget);
      expect(find.text('생활스포츠지도사 2급'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('담당 회원'), 150);
      expect(find.text('15 명'), findsOneWidget); // live client count
      expect(find.text('완료 세션'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('온케어짐 신촌점').last, 150);
      // 운영 시간으로 정한 값이 아니라 늘 붙던 '영업 중' 은 없앴다(#2264).
      expect(find.text('영업 중'), findsNothing);

      // 역할 전환은 계정 분리 정책상 존재하지 않는다.
      expect(find.textContaining('역할 전환'), findsNothing);
    });

    testWidgets('회원 삭제 전 이름과 데이터 보존 범위를 확인한다', (tester) async {
      // 회원 관리는 메뉴의 `내 정보` 묶음에 있다(#2264).
      await openSettings(tester);

      await tester.tap(find.text('회원 관리'));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), AppRoutes.mySection('clients'));

      final remove = find.byTooltip('회원 삭제').first;
      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(find.textContaining('회원을 삭제할까요?'), findsOneWidget);
      expect(find.textContaining('스케줄, 프로그램·루틴, 리포트, 메시지, 메모'), findsOneWidget);
      expect(find.textContaining('회원 앱의 기존 데이터는 삭제되지 않아요'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.textContaining('회원을 삭제할까요?'), findsNothing);
    });

    // ---- 회원 관리 검색 (#2564) ----

    Finder managedRows() => find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('managed-client-'),
    );

    Future<void> openClientManagement(WidgetTester tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('clients'),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('회원 관리 검색은 이름으로만 목록을 거르고 지우면 전체로 돌아간다', (
      tester,
    ) async {
      await openClientManagement(tester);
      final int all = managedRows().evaluate().length;
      expect(all, greaterThan(1));
      // 입력 전에는 지우기 버튼이 없다.
      expect(find.byTooltip('검색어 지우기'), findsNothing);

      await tester.enterText(find.byKey(clientManagementSearchFieldKey), '이지수');
      await tester.pumpAndSettle();
      expect(managedRows(), findsOneWidget);
      expect(find.text('이지수'), findsOneWidget);
      expect(find.text('김민수'), findsNothing);

      // 목표로는 찾지 않는다 — 정하윤의 목표는 `체력 강화 · 재활` 이다.
      await tester.enterText(find.byKey(clientManagementSearchFieldKey), '재활');
      await tester.pumpAndSettle();
      expect(managedRows(), findsNothing);

      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pumpAndSettle();
      expect(managedRows(), findsNWidgets(all));
      expect(find.byTooltip('검색어 지우기'), findsNothing);
    });

    testWidgets('회원 관리 검색 결과가 없으면 그렇다고 말한다', (tester) async {
      await openClientManagement(tester);

      await tester.enterText(find.byKey(clientManagementSearchFieldKey), 'zzz');
      await tester.pumpAndSettle();
      expect(managedRows(), findsNothing);
      expect(find.text('“zzz”와 일치하는 회원이 없어요'), findsOneWidget);
    });

    testWidgets('담당 종료한 회원은 관리 화면에서 완전히 사라진다', (tester) async {
      // 회원 관리는 메뉴의 `내 정보` 묶음에 있다(#2264).
      await openSettings(tester);

      await tester.tap(find.text('회원 관리'));
      await tester.pumpAndSettle();

      final before = find.byTooltip('회원 삭제').evaluate().length;
      expect(before, greaterThan(0));
      expect(find.text('김민수'), findsWidgets);

      await tester.tap(find.byTooltip('회원 삭제').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AppDialog), matching: find.text('삭제')),
      );
      await tester.pumpAndSettle();

      expect(find.text('회원을 삭제했어요'), findsOneWidget);
      // 미등록 상태로 목록에 남지 않는다 — 다시 잡으려면 회원 탭의
      // "신규 회원 등록"에서 회원 ID로 새로 찾아야 한다. 여기에는 그
      // 지름길(다시 등록 버튼, 미등록 표시)이 아예 없다.
      expect(find.byTooltip('회원 삭제'), findsNWidgets(before - 1));
      expect(find.textContaining('미등록'), findsNothing);
      expect(find.byTooltip('다시 등록'), findsNothing);
      expect(find.text('김민수'), findsNothing);
    });

    testWidgets('로그아웃 returns to the login screen', (tester) async {
      await openSettings(tester);

      await tester.scrollUntilVisible(find.text('로그아웃'), 150);
      await tester.ensureVisible(find.text('로그아웃'));
      await tester.pump();
      await tester.tap(find.text('로그아웃'));
      await settle(tester);

      // 회원 앱처럼 한 번 묻는다 — 취소하면 그대로 남는다.
      expect(find.text('이 브라우저에서 로그아웃할까요?'), findsOneWidget);
      await tester.tap(
        find
            .descendant(of: find.byType(AppDialog), matching: find.text('로그아웃'))
            .last,
      );
      await settle(tester);

      // 로그인 화면으로 돌아왔다 — 표식은 가입 링크(데모 진입은 감춤, #1526).
      expect(find.text('회원가입'), findsOneWidget);
    });

    testWidgets('edit mode saves changes with a confirmation flash', (
      tester,
    ) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
      );

      await tester.tap(find.text('프로필 수정'));
      await tester.pump();
      expect(find.text('저장'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '010-9999-0000',
      );
      await tester.tap(find.text('저장'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('변경사항이 저장됐어요'), findsOneWidget);
      expect(
        container.read(sessionControllerProvider).profile?.phone,
        '010-9999-0000',
      );

      // Flash expires (no pending timers at test end).
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('변경사항이 저장됐어요'), findsNothing);
    });

    testWidgets('career validation rejects a signed or embedded number', (
      tester,
    ) async {
      await openTab(tester);
      await tester.tap(find.text('프로필 수정'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-career')),
        '-1년',
      );
      await tester.tap(find.text('저장'));
      await tester.pump();

      expect(find.text('경력은 0~80 사이의 연수로 입력해 주세요.'), findsOneWidget);
    });

    // ---- 연락처 형식 (#1914) ----
    //
    // 서버가 회원 경로와 같은 기준으로 보므로, 화면이 보내기 전에 알려 준다.
    // 거기서 걸리면 이유를 알 수 없는 오류 토스트만 남는다.

    testWidgets('형식이 틀린 전화번호는 저장을 보내지 않고 칸 아래에 알린다', (tester) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
      );
      final String? before = container
          .read(sessionControllerProvider)
          .profile
          ?.phone;

      await tester.tap(find.text('프로필 수정'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '0101234',
      );
      await tester.tap(find.text('저장'));
      await tester.pump();

      expect(find.text('전화번호를 010-0000-0000 형식으로 입력해 주세요'), findsOneWidget);
      expect(find.text('변경사항이 저장됐어요'), findsNothing);
      expect(container.read(sessionControllerProvider).profile?.phone, before);
    });

    testWidgets('숫자만 쳐도 하이픈이 붙는다 — 가입 화면과 같은 서식이다', (tester) async {
      await openTab(tester);
      await tester.tap(find.text('프로필 수정'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '01098765432',
      );
      await tester.pump();

      // 키는 `AppTextField` 에 붙어 있으므로 그 안의 `TextField` 를 찾아 읽는다.
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey<String>('profile-phone')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '010-9876-5432',
      );
    });

    testWidgets('오류를 보인 뒤 고치면 문구가 사라진다', (tester) async {
      await openTab(tester);
      await tester.tap(find.text('프로필 수정'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '0101234',
      );
      await tester.tap(find.text('저장'));
      await tester.pump();
      expect(find.text('전화번호를 010-0000-0000 형식으로 입력해 주세요'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '01012345678',
      );
      await tester.pump();
      expect(find.text('전화번호를 010-0000-0000 형식으로 입력해 주세요'), findsNothing);
    });

    testWidgets('전화번호를 비워도 저장된다 — 트레이너 가입은 이 값을 받지 않는다', (tester) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
      );

      await tester.tap(find.text('프로필 수정'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '',
      );
      await tester.tap(find.text('저장'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('전화번호를 010-0000-0000 형식으로 입력해 주세요'), findsNothing);
      expect(container.read(sessionControllerProvider).profile?.phone, '');

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('고칠 수 없는 이름·이메일 칸은 회색 채움·흐린 글자다(#1776)', (tester) async {
      await openTab(tester);
      await tester.tap(find.text('프로필 수정'));
      await tester.pump();

      // 활성 칸은 흰 채움이라, 회색이 남은 칸만 입력칸이 아니라고 읽힌다.
      (Color, Color?) look(String text) {
        final Finder field = find.byWidgetPredicate(
          (widget) => widget is TextField && widget.controller?.text == text,
        );
        expect(tester.widget<TextField>(field).enabled, isFalse);
        final InputDecoration decoration = tester
            .widget<InputDecorator>(
              find.descendant(of: field, matching: find.byType(InputDecorator)),
            )
            .decoration;
        return (
          WidgetStateProperty.resolveAs<Color>(
            decoration.fillColor!,
            <WidgetState>{if (!decoration.enabled) WidgetState.disabled},
          ),
          tester
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .style
              .color,
        );
      }

      for (final String text in <String>[
        kDemoTrainerName,
        'trainer@oncare.com',
      ]) {
        expect(look(text), (
          OnCareColors.surfaceInput,
          OnCareColors.textDisabled,
        ));
      }
    });

    Future<void> openEdit(WidgetTester tester) async {
      await openTab(tester);
      await tester.tap(find.text('프로필 수정'));
      // 헬스장 목록은 수정 화면이 열려야 읽는다 — 목록이 올 때까지 기다린다.
      await settle(tester);
    }

    Future<void> unlinkGym(WidgetTester tester) async {
      final Finder unlink = find.byKey(const ValueKey<String>('gym-unlink'));
      await tester.ensureVisible(unlink);
      await tester.pump();
      await tester.tap(unlink);
      await tester.pump();
    }

    TextField gymField(WidgetTester tester, String text) =>
        tester.widget<TextField>(
          find.byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == text,
          ),
        );

    testWidgets('이름이 같은 등록 헬스장으로 열고, 풀고 검색해 고르면 정보가 채워진다 (#2264)', (
      tester,
    ) async {
      await openEdit(tester);

      // 데모 프로필은 글자만 있지만 이름이 목록과 같아 등록된 헬스장으로 연다.
      expect(find.text('등록된 헬스장'), findsOneWidget);
      expect(gymField(tester, '온케어짐 신촌점').enabled, isFalse);

      await unlinkGym(tester);
      expect(find.text('등록된 헬스장'), findsNothing);
      // 연결을 풀면 칸을 모두 비운다 — 앞 헬스장의 주소가 섞이지 않게.
      expect(find.text('서울 서대문구'), findsNothing);
      expect(find.text('06:00 – 23:00'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-name')),
        '강남',
      );
      await tester.pump();
      final Finder suggestion = find.byKey(
        const ValueKey<String>('gym-suggestion-gym-2'),
      );
      expect(suggestion, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('gym-suggestion-gym-1')),
        findsNothing,
      );

      await tester.ensureVisible(suggestion);
      await tester.pump();
      await tester.tap(suggestion);
      await tester.pump();
      expect(find.text('등록된 헬스장'), findsOneWidget);
      expect(gymField(tester, '서울 강남구').enabled, isFalse);
      expect(
        find.byKey(const ValueKey<String>('gym-suggestions')),
        findsNothing,
      );
    });

    testWidgets('목록은 칸 아래에 떠서 다른 칸을 밀지 않고, 키보드로 고른다', (tester) async {
      await openEdit(tester);
      await unlinkGym(tester);
      final Finder address = find.byKey(const ValueKey<String>('gym-address'));
      final double before = tester.getTopLeft(address).dy;

      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-name')),
        '온케어',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('gym-suggestions')),
        findsOneWidget,
      );
      expect(tester.getTopLeft(address).dy, before);

      // 두 번째 줄(강남점)로 내려 Enter.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('gym-suggestions')),
        findsNothing,
      );
      expect(find.text('등록된 헬스장'), findsOneWidget);
      expect(gymField(tester, '온케어짐 강남점').enabled, isFalse);
    });

    testWidgets('이름을 다 쓰고 다음 칸으로 가면 목록이 닫힌다', (tester) async {
      await openEdit(tester);
      await unlinkGym(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-name')),
        '온케어',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('gym-suggestions')),
        findsOneWidget,
      );

      // 주소 칸으로 포커스를 옮긴다(Tab 과 같은 효과).
      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-address')),
        '서울',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('gym-suggestions')),
        findsNothing,
      );
    });

    testWidgets('목록에 없는 곳은 직접 적어 저장한다', (tester) async {
      await openEdit(tester);
      await unlinkGym(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-name')),
        '동네 PT 스튜디오',
      );
      await tester.pump();
      // 맞는 등록 헬스장이 없다고 칸 아래 한 줄로 말한다 — 떠 있는 창은 없어
      // 주소 칸을 가리지 않는다. 주소·운영 시간은 비어 있다.
      expect(
        find.byKey(const ValueKey<String>('gym-suggestions')),
        findsNothing,
      );
      expect(find.text('목록에 없는 헬스장이에요. 주소와 운영 시간을 직접 적어 주세요.'), findsOneWidget);
      expect(find.text('서울 서대문구 신촌로 120'), findsNothing);

      await tester.tap(find.text('저장'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));
      expect(find.text('동네 PT 스튜디오'), findsWidgets);
    });

    testWidgets('소속 헬스장은 필수다 — 비우면 저장하지 않고 칸 아래에 알린다', (tester) async {
      await openEdit(tester);
      await unlinkGym(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-name')),
        '',
      );
      await tester.pump();

      await tester.tap(find.text('저장'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('edit'));
      expect(find.text('소속 헬스장을 입력해 주세요'), findsOneWidget);
    });

    testWidgets('gym-only failure reports that profile fields were saved', (
      tester,
    ) async {
      final repository = _GymFailureRepository();
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
        extraOverrides: <Override>[
          trainerProfileRepositoryProvider.overrideWithValue(repository),
        ],
      );

      await tester.tap(find.text('프로필 수정'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '010-9999-0000',
      );
      // 헬스장 목록이 오면 같은 이름의 등록 헬스장으로 연결된다 — 저장하면
      // 소속 설정(setGym)이 실패한다.
      await settle(tester);
      expect(find.text('등록된 헬스장'), findsOneWidget);

      await tester.tap(find.text('저장'));
      await settle(tester);

      expect(find.textContaining('소속 헬스장 변경에 실패했습니다'), findsOneWidget);
      expect(
        container.read(sessionControllerProvider).profile?.phone,
        '010-9999-0000',
      );
    });

    testWidgets('profile update failure restores the server snapshot', (
      tester,
    ) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
        extraOverrides: <Override>[
          trainerProfileRepositoryProvider.overrideWithValue(
            _UpdateFailureRepository(),
          ),
        ],
      );

      await tester.tap(find.text('프로필 수정'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-phone')),
        '010-0000-0000',
      );
      await tester.tap(find.text('저장'));
      await settle(tester);

      expect(find.text('프로필 입력값을 확인해 주세요.'), findsOneWidget);
      expect(
        container.read(sessionControllerProvider).profile?.phone,
        seedTrainerProfile.phone,
      );
      expect(find.text('프로필 수정'), findsOneWidget);
    });
  });
}
