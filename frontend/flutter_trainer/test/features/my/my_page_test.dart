import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/my/data/trainer_location_service.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';
import 'package:oncare_trainer/features/my/presentation/pages/my_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

class _GymFailureRepository implements TrainerProfileRepository {
  final MockTrainerProfileRepository _delegate = MockTrainerProfileRepository();

  @override
  Future<TrainerProfile> fetch() => _delegate.fetch();

  @override
  Future<List<TrainerGymCandidate>> searchGyms(
    String query, {
    double? lat,
    double? lng,
  }) => _delegate.searchGyms(query, lat: lat, lng: lng);

  @override
  Future<List<TrainerGymCandidate>> nearbyGyms({
    required double lat,
    required double lng,
  }) => _delegate.nearbyGyms(lat: lat, lng: lng);

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) =>
      _delegate.update(update);

  @override
  Future<TrainerProfile> selectGym(TrainerGymCandidate gym) {
    throw const ServerError(message: '헬스장 연결 요청이 실패했습니다.');
  }

  @override
  Future<TrainerGymInfo> fetchGymInfo() => _delegate.fetchGymInfo();

  @override
  Future<TrainerGymInfo> updateGymInfo(TrainerGymInfoUpdate update) =>
      _delegate.updateGymInfo(update);
}

class _UpdateFailureRepository implements TrainerProfileRepository {
  @override
  Future<TrainerProfile> fetch() async => seedTrainerProfile;

  @override
  Future<List<TrainerGymCandidate>> searchGyms(
    String query, {
    double? lat,
    double? lng,
  }) async => const <TrainerGymCandidate>[];

  @override
  Future<List<TrainerGymCandidate>> nearbyGyms({
    required double lat,
    required double lng,
  }) async => const <TrainerGymCandidate>[];

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) {
    throw const ValidationError(message: '프로필 입력값을 확인해 주세요.');
  }

  @override
  Future<TrainerProfile> selectGym(TrainerGymCandidate gym) =>
      throw UnimplementedError();

  @override
  Future<TrainerGymInfo> fetchGymInfo() => throw UnimplementedError();

  @override
  Future<TrainerGymInfo> updateGymInfo(TrainerGymInfoUpdate update) =>
      throw UnimplementedError();
}

/// 검색·주변 찾기가 늘 빈 목록인 저장소 — 서버가 맞는 헬스장을 못 찾은 경우.
class _EmptySearchRepository implements TrainerProfileRepository {
  final MockTrainerProfileRepository _delegate = MockTrainerProfileRepository();

  @override
  Future<TrainerProfile> fetch() => _delegate.fetch();

  @override
  Future<List<TrainerGymCandidate>> searchGyms(
    String query, {
    double? lat,
    double? lng,
  }) async => const <TrainerGymCandidate>[];

  @override
  Future<List<TrainerGymCandidate>> nearbyGyms({
    required double lat,
    required double lng,
  }) async => const <TrainerGymCandidate>[];

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) =>
      _delegate.update(update);

  @override
  Future<TrainerProfile> selectGym(TrainerGymCandidate gym) =>
      _delegate.selectGym(gym);

  @override
  Future<TrainerGymInfo> fetchGymInfo() => _delegate.fetchGymInfo();

  @override
  Future<TrainerGymInfo> updateGymInfo(TrainerGymInfoUpdate update) =>
      _delegate.updateGymInfo(update);
}

/// 브라우저 위치 대신 정해 둔 결과를 주는 위치 서비스(#3223).
class _FakeLocationService implements TrainerLocationService {
  _FakeLocationService.at(TrainerPosition this._position) : _failure = null;
  _FakeLocationService.failing(TrainerLocationFailure this._failure)
    : _position = null;

  final TrainerPosition? _position;
  final TrainerLocationFailure? _failure;
  int calls = 0;

  @override
  Future<TrainerPosition> locate() async {
    calls++;
    final TrainerLocationFailure? failure = _failure;
    if (failure != null) throw failure;
    return _position!;
  }
}

/// 헬스메이트 신촌점 자리 — 데모 신촌점이 가장 가깝고, 강남점이 가장 멀다.
const TrainerPosition _sinchon = TrainerPosition(lat: 37.5548, lng: 126.9385);

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
      expect(find.text('완료 PT'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('온케어짐 신촌점').last, 150);
      // 운영 시간으로 정한 값이 아니라 늘 붙던 '영업 중' 은 없앴다(#2264).
      expect(find.text('영업 중'), findsNothing);

      // 역할 전환은 계정 분리 정책상 존재하지 않는다.
      expect(find.textContaining('역할 전환'), findsNothing);
    });

    testWidgets('연결 해제 전 이름과 데이터 보존 범위를 확인한다', (tester) async {
      // 회원 관리는 메뉴의 `내 정보` 묶음에 있다(#2264).
      await openSettings(tester);

      await tester.tap(find.text('회원 관리'));
      await tester.pumpAndSettle();
      expect(currentLocation(tester), AppRoutes.mySection('clients'));

      final remove = find.byTooltip('연결 해제').first;
      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(find.textContaining('회원과 연결을 해제할까요?'), findsOneWidget);
      expect(
        find.textContaining(keepWords('스케줄, 프로그램·개인운동, 리포트, 메시지, 메모')),
        findsOneWidget,
      );
      expect(
        find.textContaining(keepWords('회원 계정과 회원 앱의 기록은 그대로 남아요')),
        findsOneWidget,
      );
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.textContaining('회원과 연결을 해제할까요?'), findsNothing);
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

    testWidgets('회원 관리 검색은 이름으로만 목록을 거르고 지우면 전체로 돌아간다', (tester) async {
      await openClientManagement(tester);
      final int all = managedRows().evaluate().length;
      expect(all, greaterThan(1));
      // 입력 전에는 지우기 버튼이 없다.
      expect(find.byTooltip('검색어 지우기'), findsNothing);

      await tester.enterText(find.byKey(clientManagementSearchFieldKey), '이지수');
      await tester.pumpAndSettle();
      expect(managedRows(), findsOneWidget);
      // 입력칸에도 같은 글자가 있으니 목록 카드 안에서만 본다.
      expect(
        find.descendant(of: managedRows(), matching: find.text('이지수')),
        findsOneWidget,
      );
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

      final before = find.byTooltip('연결 해제').evaluate().length;
      expect(before, greaterThan(0));
      expect(find.text('김민수'), findsWidgets);

      await tester.tap(find.byTooltip('연결 해제').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.text('해제'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('회원과 연결을 해제했어요'), findsOneWidget);
      // 미등록 상태로 목록에 남지 않는다 — 다시 잡으려면 회원 탭의
      // "신규 회원 등록"에서 회원 ID로 새로 찾아야 한다. 여기에는 그
      // 지름길(다시 등록 버튼, 미등록 표시)이 아예 없다.
      expect(find.byTooltip('연결 해제'), findsNWidgets(before - 1));
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
      // 직접 로그아웃이라 방금 있던 MY 를 다음 로그인으로 잇지 않는다(#2765).
      final String location = currentLocation(tester);
      expect(Uri.parse(location).path, AppRoutes.signIn);
      expect(AppRoutes.resumeTarget(location), isNull);
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

      // 저장 완료는 공용 토스트다 — 시간이 지나면 사라진다.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
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

    /// 헬스장 검색 칸에 [query] 를 치고 결과가 올 때까지 기다린다(치는 동안은
    /// 잠깐 기다렸다 찾는다).
    Future<void> searchGym(WidgetTester tester, String query) async {
      final Finder field = find.byKey(const ValueKey<String>('gym-search'));
      await tester.ensureVisible(field);
      await tester.pump();
      await tester.enterText(field, query);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    Future<void> tapResult(WidgetTester tester, String id) async {
      final Finder row = find.byKey(ValueKey<String>('gym-result-$id'));
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();
    }

    /// 소속이 없는 트레이너로 내 정보를 연다 — 예전에 이름만 직접 적어 둔 경우다.
    Future<void> openWithoutGym(WidgetTester tester) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.dashboard,
      );
      final notifier = container.read(sessionControllerProvider.notifier);
      notifier.replaceProfile(
        seedTrainerProfile.copyWith(
          gym: const TrainerGym(
            name: '직접 적은 헬스장',
            address: '',
            hours: '',
            phone: '',
          ),
        ),
      );
      await goTo(tester, AppRoutes.my);
    }

    testWidgets('이름으로 찾아 고르면 저장할 때 소속이 바뀐다 (#2543)', (tester) async {
      await openEdit(tester);
      expect(find.text('현재 소속'), findsOneWidget);
      expect(find.text('온케어짐 신촌점'), findsWidgets);

      await searchGym(tester, '강남');
      expect(
        find.byKey(const ValueKey<String>('gym-result-gym-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('gym-result-$kDemoTrainerGymId')),
        findsNothing,
      );

      await tapResult(tester, 'gym-2');
      expect(find.text('저장하면 이 헬스장으로 바뀌어요'), findsOneWidget);

      await tester.tap(find.text('저장'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));
      expect(find.text('온케어짐 강남점'), findsWidgets);
      expect(find.text('온케어짐 신촌점'), findsNothing);
    });

    testWidgets('카카오에서 찾은 헬스장도 같은 방법으로 고른다', (tester) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
      );
      await tester.tap(find.text('프로필 수정'));
      await settle(tester);

      await searchGym(tester, '연희');
      await tapResult(tester, 'gym-demo-yeonhui');
      await tester.tap(find.text('저장'));
      await settle(tester);

      final TrainerGym gym = container
          .read(sessionControllerProvider)
          .profile!
          .gym;
      expect(gym.id, 'gym-demo-yeonhui');
      expect(gym.name, '온케어 연희 스튜디오');
      expect(gym.address, '서울 서대문구 연희로 25');
    });

    testWidgets('Enter 를 누르면 기다리지 않고 바로 찾는다', (tester) async {
      await openEdit(tester);
      final Finder field = find.byKey(const ValueKey<String>('gym-search'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '강남');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('gym-result-gym-2')),
        findsOneWidget,
      );
      // 남은 디바운스 타이머를 흘려 보낸다.
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('찾는 헬스장이 없으면 그렇다고 말한다 — 직접 적는 칸은 없다', (tester) async {
      // 데모 저장소는 빈 목록을 주지 않는다(#3223) — 서버가 빈 목록을 준 경우다.
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
        extraOverrides: <Override>[
          trainerProfileRepositoryProvider.overrideWithValue(
            _EmptySearchRepository(),
          ),
        ],
      );
      await tester.tap(find.text('프로필 수정'));
      await settle(tester);
      await searchGym(tester, '없는 스튜디오');
      expect(
        find.text('찾는 헬스장이 없어요. 이름을 다르게 적거나 동네 이름을 붙여 보세요.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('gym-address')), findsNothing);
    });

    testWidgets('데모에서 실제 헬스장 이름을 쳐도 고를 헬스장이 나온다 (#3223)', (tester) async {
      await openEdit(tester);
      await searchGym(tester, '스포애니 신림점');

      expect(
        find.text('찾는 헬스장이 없어요. 이름을 다르게 적거나 동네 이름을 붙여 보세요.'),
        findsNothing,
      );
      for (final String id in <String>[
        kDemoTrainerGymId,
        'gym-2',
        'gym-demo-yeonhui',
      ]) {
        expect(find.byKey(ValueKey<String>('gym-result-$id')), findsOneWidget);
      }

      // 나온 헬스장을 골라 저장할 수 있다 — 가입 직후 막히지 않는다.
      await tapResult(tester, 'gym-2');
      await tester.tap(find.text('저장'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));
      expect(find.text('온케어짐 강남점'), findsWidgets);
    });

    testWidgets('붙여 쓴 이름으로도 데모 헬스장을 찾는다 (#3223)', (tester) async {
      await openEdit(tester);
      await searchGym(tester, '온케어짐강남');
      expect(
        find.byKey(const ValueKey<String>('gym-result-gym-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('gym-result-$kDemoTrainerGymId')),
        findsNothing,
      );
    });

    /// 위치 서비스를 [service] 로 바꿔 프로필 수정 화면을 연다.
    Future<void> openEditWithLocation(
      WidgetTester tester,
      TrainerLocationService service, {
      TrainerProfileRepository? repository,
    }) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.my,
        extraOverrides: <Override>[
          trainerLocationServiceProvider.overrideWithValue(service),
          if (repository != null)
            trainerProfileRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await tester.tap(find.text('프로필 수정'));
      await settle(tester);
    }

    Future<void> tapLocate(WidgetTester tester) async {
      final Finder button = find.byKey(const ValueKey<String>('gym-locate'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
    }

    double topOf(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(ValueKey<String>(key))).dy;

    testWidgets('현재 위치로 찾으면 주변 헬스장이 가까운 순으로 나온다 (#3223)', (tester) async {
      final service = _FakeLocationService.at(_sinchon);
      await openEditWithLocation(tester, service);
      // 버튼을 누르기 전에는 위치를 읽지 않는다.
      expect(service.calls, 0);
      expect(find.text('현재 위치로 찾기'), findsOneWidget);

      await tapLocate(tester);
      expect(service.calls, 1);
      expect(find.text('현재 위치에서 가까운 헬스장이에요. 위치는 저장하지 않아요.'), findsOneWidget);
      final double sinchon = topOf(tester, 'gym-result-$kDemoTrainerGymId');
      final double yeonhui = topOf(tester, 'gym-result-gym-demo-yeonhui');
      final double gangnam = topOf(tester, 'gym-result-gym-2');
      expect(sinchon, lessThan(yeonhui));
      expect(yeonhui, lessThan(gangnam));
      // 결과 줄에 주소와 거리가 함께 나온다.
      expect(find.textContaining('km'), findsWidgets);
      expect(find.textContaining('서울 강남구 강남대로 396 · '), findsOneWidget);
    });

    testWidgets('주변 결과에서 고른 헬스장도 저장하면 소속이 된다 (#3223)', (tester) async {
      await openEditWithLocation(tester, _FakeLocationService.at(_sinchon));
      await tapLocate(tester);
      await tapResult(tester, 'gym-demo-yeonhui');
      expect(find.text('저장하면 이 헬스장으로 바뀌어요'), findsOneWidget);

      await tester.tap(find.text('저장'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));
      expect(find.text('온케어 연희 스튜디오'), findsWidgets);
    });

    testWidgets('위치를 얻은 뒤 이름으로 찾으면 거리가 붙고, 지우면 주변으로 돌아간다', (tester) async {
      await openEditWithLocation(tester, _FakeLocationService.at(_sinchon));
      await tapLocate(tester);

      await searchGym(tester, '강남');
      expect(
        find.byKey(const ValueKey<String>('gym-result-gym-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('gym-result-$kDemoTrainerGymId')),
        findsNothing,
      );
      // 이름 검색 결과에는 주변 안내를 달지 않는다.
      expect(
        find.byKey(const ValueKey<String>('gym-nearby-caption')),
        findsNothing,
      );
      expect(find.textContaining('서울 강남구 강남대로 396 · '), findsOneWidget);

      await searchGym(tester, '');
      expect(
        find.byKey(const ValueKey<String>('gym-nearby-caption')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('gym-result-$kDemoTrainerGymId')),
        findsOneWidget,
      );
    });

    testWidgets('위치를 얻기 전 이름 검색에는 거리가 없다', (tester) async {
      await openEditWithLocation(tester, _FakeLocationService.at(_sinchon));
      await searchGym(tester, '강남');
      expect(find.text('서울 강남구 강남대로 396'), findsOneWidget);
      expect(find.textContaining('서울 강남구 강남대로 396 · '), findsNothing);
    });

    for (final ({TrainerLocationFailure failure, String message}) scenario
        in <({TrainerLocationFailure failure, String message})>[
          (
            failure: TrainerLocationFailure.denied,
            message: '위치 사용을 허용하면 주변 헬스장을 찾을 수 있어요.',
          ),
          (
            failure: TrainerLocationFailure.blocked,
            message: '브라우저 사이트 설정에서 위치 사용을 허용한 뒤 다시 눌러 주세요.',
          ),
          (
            failure: TrainerLocationFailure.disabled,
            message: '기기의 위치 서비스를 켠 뒤 다시 눌러 주세요.',
          ),
          (
            failure: TrainerLocationFailure.unavailable,
            message: '현재 위치를 가져오지 못했어요. 다시 시도하거나 이름으로 찾아 보세요.',
          ),
        ]) {
      testWidgets('위치를 못 얻으면(${scenario.failure.name}) 까닭을 알린다 (#3223)', (
        tester,
      ) async {
        final service = _FakeLocationService.failing(scenario.failure);
        await openEditWithLocation(tester, service);
        await tapLocate(tester);

        expect(find.text(scenario.message), findsOneWidget);
        // 결과도, 주변 안내도 없다 — 이름 검색은 그대로 쓸 수 있다.
        expect(
          find.byKey(const ValueKey<String>('gym-nearby-caption')),
          findsNothing,
        );
        await searchGym(tester, '강남');
        expect(
          find.byKey(const ValueKey<String>('gym-result-gym-2')),
          findsOneWidget,
        );
        // 다시 누르면 다시 묻는다.
        await tapLocate(tester);
        expect(service.calls, 2);
      });
    }

    testWidgets('주변에 헬스장이 없으면 이름으로 찾으라고 알린다', (tester) async {
      await openEditWithLocation(
        tester,
        _FakeLocationService.at(_sinchon),
        repository: _EmptySearchRepository(),
      );
      await tapLocate(tester);
      expect(
        find.text('현재 위치 2km 안에서 헬스장을 찾지 못했어요. 이름으로 찾아 보세요.'),
        findsOneWidget,
      );
    });

    testWidgets('현재 위치 버튼은 검색 칸 바로 아래, 결과 목록 위에 있다', (tester) async {
      await openEditWithLocation(tester, _FakeLocationService.at(_sinchon));
      await tapLocate(tester);
      final double search = topOf(tester, 'gym-search');
      final double locate = topOf(tester, 'gym-locate');
      final double firstResult = topOf(tester, 'gym-result-$kDemoTrainerGymId');
      expect(search, lessThan(locate));
      expect(locate, lessThan(firstResult));
      // 테스트 빌드에는 카카오 키가 없어 지도 자리를 비워 둔다.
      expect(find.byKey(const ValueKey<String>('gym-map')), findsNothing);
    });

    test('현재 위치 찾기 문구는 영어로도 있다', () async {
      final AppLocalizations en = await AppLocalizations.delegate.load(
        const Locale('en'),
      );
      expect(en.myGymLocateAction, 'Find near my location');
      expect(
        en.myGymLocationBlocked,
        'Allow location access in your browser site settings, then try again.',
      );
      expect(
        en.myGymNearbyCaption,
        'Gyms near your current location. Your location is not saved.',
      );
      expect(
        en.myGymNearbyEmpty,
        'No gyms found within 2 km of your location. Try searching by name.',
      );
    });

    testWidgets('소속이 없으면 내 정보에 회원에게 보이지 않는다고 알린다', (tester) async {
      await openWithoutGym(tester);
      expect(
        find.byKey(const ValueKey<String>('my-gym-hidden')),
        findsOneWidget,
      );
      expect(find.text('회원에게 아직 보이지 않아요'), findsOneWidget);

      await tester.tap(find.text('헬스장 설정'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('edit'));
    });

    testWidgets('소속이 있으면 안내하지 않는다', (tester) async {
      await openTab(tester);
      expect(find.byKey(const ValueKey<String>('my-gym-hidden')), findsNothing);
    });

    /// 소속 헬스장 카드의 `헬스장 정보 수정` 으로 들어가 값이 올 때까지 기다린다.
    Future<void> openGymInfo(WidgetTester tester) async {
      await openTab(tester);
      final Finder button = find.byKey(
        const ValueKey<String>('my-gym-info-edit'),
      );
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
    }

    testWidgets('소속 헬스장 정보를 고치면 내 정보 카드에 반영된다 (#2700)', (tester) async {
      await openGymInfo(tester);
      expect(currentLocation(tester), AppRoutes.mySection('gymInfo'));
      expect(
        find.byKey(const ValueKey<String>('gym-info-weekday')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-info-weekday')),
        '05:00 - 24:00',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('gym-info-phone')),
        '02-332-1720',
      );
      final Finder tagInput = find.byKey(
        const ValueKey<String>('gym-tag-input'),
      );
      await tester.ensureVisible(tagInput);
      await tester.enterText(tagInput, '샤워실');
      await tester.tap(find.byKey(const ValueKey<String>('gym-tag-add')));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('gym-tag-샤워실')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('gym-info-save')));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));
      expect(find.text('05:00 - 24:00'), findsOneWidget);
      expect(find.text('02-332-1720'), findsOneWidget);
      // 태그는 수정 화면이 아니라 카드의 헬스장 이름 옆에도 보인다.
      expect(
        find.byKey(const ValueKey<String>('my-gym-tag-샤워실')),
        findsOneWidget,
      );
    });

    testWidgets('태그는 지울 수 있고, 같은 태그는 한 번만 들어간다', (tester) async {
      await openGymInfo(tester);
      final Finder tagInput = find.byKey(
        const ValueKey<String>('gym-tag-input'),
      );
      final Finder add = find.byKey(const ValueKey<String>('gym-tag-add'));
      await tester.ensureVisible(tagInput);
      await tester.enterText(tagInput, '24시간');
      await tester.tap(add);
      await tester.pump();
      await tester.enterText(tagInput, ' 24시간 ');
      // 태그 줄이 생기며 버튼이 아래로 밀려, 다시 화면으로 올린 뒤 누른다.
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('gym-tag-24시간')),
        findsOneWidget,
      );

      // 태그 줄이 상단 바 아래로 밀려 있을 수 있어, 누르기 전에 화면으로 올린다.
      final Finder remove = find.byTooltip('태그 지우기');
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('gym-tag-24시간')), findsNothing);
      expect(find.text('아직 태그가 없어요.'), findsOneWidget);
    });

    testWidgets('소속이 없으면 헬스장 정보 수정 버튼이 없다', (tester) async {
      await openWithoutGym(tester);
      expect(
        find.byKey(const ValueKey<String>('my-gym-info-edit')),
        findsNothing,
      );
    });

    testWidgets('소속 헬스장은 필수다 — 고르지 않으면 저장하지 않고 칸 아래에 알린다', (tester) async {
      await openWithoutGym(tester);
      await tester.tap(find.text('헬스장 설정'));
      await settle(tester);

      await tester.tap(find.text('저장'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('edit'));
      expect(find.text('검색 결과에서 소속 헬스장을 골라 주세요'), findsOneWidget);

      // 골라서 저장하면 안내가 사라진다.
      await searchGym(tester, '신촌');
      await tapResult(tester, kDemoTrainerGymId);
      await tester.tap(find.text('저장'));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));
      expect(find.byKey(const ValueKey<String>('my-gym-hidden')), findsNothing);
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
      // 다른 헬스장을 고른다 — 저장하면 소속 설정(selectGym)이 실패한다.
      await searchGym(tester, '강남');
      await tapResult(tester, 'gym-2');

      await tester.tap(find.text('저장'));
      await settle(tester);

      expect(find.textContaining('소속 헬스장을 바꾸지 못했어요'), findsOneWidget);
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
