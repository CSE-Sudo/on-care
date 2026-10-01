// 같은 탭에서 트레이너 A → 로그아웃 → 트레이너 B 로 넘어갈 때 provider 마다
// B 의 데이터만 보이는가. (#2285)
//
// 저장소 provider 는 override 하지 않는다. 실제 정의(실서버 모드의 Dio 저장소)를
// 그대로 쓰고, 맨 아래 HTTP 만 토큰으로 계정을 가르는 가짜 서버로 바꾼다 — 그래야
// 저장소가 들고 있던 메모리 캐시와 provider 가 붙잡아 둔 값까지 함께 검증된다.
//
// 앱의 실제 순서를 따른다: A 가 화면을 보고 있는 동안(구독 중) 로그아웃하고, 로그인
// 화면으로 넘어가며 구독이 끝나고, B 가 로그인해 같은 화면을 다시 연다.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/clients/data/repositories/chat_pdf_repository.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_coach_repository.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/clients/presentation/controllers/roster_view.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_meal_photo.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/my/data/trainer_account_repository.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings_repository.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_sender.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/follow_up_task_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

import '../../helpers/account_switch_backend.dart';
import '../../helpers/client_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late FakeTrainerBackend backend;
  late FakeTrainerAuthRepository auth;
  late SessionController session;

  setUp(() async {
    final setup = makeAccountSwitchContainer();
    container = setup.container;
    backend = setup.backend;
    auth = setup.auth;
    session = container.read(sessionControllerProvider.notifier);
    await settleAsync(); // 복구 → 로그아웃 상태
  });

  Future<void> signIn(TestTrainer t) async {
    await session.login(email: t.email, password: 'pw');
    await settleAsync();
  }

  /// 로그아웃하고 로그인 화면으로 넘어간다 — 열려 있던 화면의 구독이 끝난다.
  Future<void> signOutClosing(List<ProviderSubscription<Object?>> open) async {
    await session.signOut();
    for (final ProviderSubscription<Object?> sub in open) {
      sub.close();
    }
    await settleAsync();
  }

  /// [provider] 를 A 로 한 번, B 로 한 번 연다. B 가 여는 순간부터 본 모든
  /// 상태를 돌려준다 — 응답 전 로딩 상태까지 포함한다.
  Future<({AsyncValue<T> forA, List<AsyncValue<T>> seenByB})> switchAccounts<T>(
    ProviderListenable<AsyncValue<T>> provider,
  ) async {
    await signIn(TestTrainer.a);
    final ProviderSubscription<AsyncValue<T>> screenA = container.listen(
      provider,
      (_, _) {},
    );
    await waitUntil(() => screenA.read().hasValue);
    final AsyncValue<T> forA = screenA.read();

    await signOutClosing(<ProviderSubscription<Object?>>[screenA]);
    await signIn(TestTrainer.b);

    final List<AsyncValue<T>> seenByB = <AsyncValue<T>>[];
    final ProviderSubscription<AsyncValue<T>> screenB = container.listen(
      provider,
      (_, AsyncValue<T> next) => seenByB.add(next),
      fireImmediately: true,
    );
    addTearDown(screenB.close);
    await waitUntil(
      () =>
          seenByB.isNotEmpty &&
          seenByB.last.hasValue &&
          !seenByB.last.isLoading,
    );
    return (forA: forA, seenByB: seenByB);
  }

  /// B 가 본 어떤 상태에도 A 의 값이 실려 있지 않고, 마지막에는 B 의 값이다.
  void expectOnlyB<T>(
    List<AsyncValue<T>> seenByB,
    bool Function(T value, TestTrainer t) belongs,
  ) {
    expect(seenByB, isNotEmpty);
    for (final AsyncValue<T> state in seenByB) {
      final T? value = state.valueOrNull;
      if (value == null) continue;
      expect(
        belongs(value, TestTrainer.a),
        isFalse,
        reason: 'B 가 연 화면에 A 의 값이 보였다: $state',
      );
    }
    final T? last = seenByB.last.valueOrNull;
    expect(last, isNotNull, reason: 'B 의 응답이 도착해야 한다');
    expect(belongs(last as T, TestTrainer.b), isTrue);
  }

  bool rosterOf(List<TrainerClient> clients, TestTrainer t) =>
      clients.any((TrainerClient c) => c.name == t.memberName);

  group('회원 목록', () {
    test('managedClientsProvider — B 에게 B 의 회원만', () async {
      final result = await switchAccounts(managedClientsProvider);
      expect(rosterOf(result.forA.requireValue, TestTrainer.a), isTrue);
      expectOnlyB(result.seenByB, rosterOf);
    });

    test('clientsProvider — B 에게 B 의 회원만', () async {
      final result = await switchAccounts(clientsProvider);
      expect(rosterOf(result.forA.requireValue, TestTrainer.a), isTrue);
      expectOnlyB(result.seenByB, rosterOf);
    });

    test('prioritizedClientsProvider — 파생 목록도 A 를 싣지 않는다', () async {
      final result = await switchAccounts(prioritizedClientsProvider);
      expect(rosterOf(result.forA.requireValue, TestTrainer.a), isTrue);
      expectOnlyB(result.seenByB, rosterOf);
    });

    test('recentlyMessagedClientsProvider — 메시지 탭 목록도 B 의 것만', () async {
      final result = await switchAccounts(recentlyMessagedClientsProvider);
      expect(rosterOf(result.forA.requireValue, TestTrainer.a), isTrue);
      expectOnlyB(result.seenByB, rosterOf);
    });

    test('로그아웃 뒤에는 A 의 토큰으로 회원 목록을 부르지 않는다', () async {
      await switchAccounts(clientsProvider);
      final int signOutAt = backend.requests.indexWhere(
        (r) => r.account == TestTrainer.b,
      );
      expect(signOutAt, isNonNegative);
      expect(
        backend.requests
            .skip(signOutAt)
            .where((r) => r.account == TestTrainer.a),
        isEmpty,
      );
    });

    test('로그아웃하면 서버에서 A 의 세션을 폐기한다', () async {
      await switchAccounts(clientsProvider);
      expect(auth.revoked, <String>['refresh-a']);
    });
  });

  group('알림', () {
    bool inboxOf(TrainerNotificationPage page, TestTrainer t) => page.items.any(
      (TrainerNotification n) => n.title == t.notificationTitle,
    );

    test('trainerNotificationsProvider — B 에게 B 의 알림만', () async {
      final result = await switchAccounts(trainerNotificationsProvider);
      expect(inboxOf(result.forA.requireValue, TestTrainer.a), isTrue);
      expectOnlyB(result.seenByB, inboxOf);
    });
  });

  group('템플릿', () {
    bool templatesOf(List<ProgramTemplate> items, TestTrainer t) =>
        items.any((ProgramTemplate p) => p.name == t.templateName);

    test('programTemplatesProvider — B 에게 B 의 템플릿만', () async {
      final result = await switchAccounts(programTemplatesProvider);
      expect(templatesOf(result.forA.requireValue, TestTrainer.a), isTrue);
      expectOnlyB(result.seenByB, templatesOf);
    });

    test('구독 없이 읽어 둔 템플릿도 계정이 바뀌면 다시 읽는다', () async {
      await signIn(TestTrainer.a);
      final List<ProgramTemplate> forA = await container.read(
        programTemplatesProvider.future,
      );
      expect(templatesOf(forA, TestTrainer.a), isTrue);

      await signOutClosing(const <ProviderSubscription<Object?>>[]);
      await signIn(TestTrainer.b);

      final AsyncValue<List<ProgramTemplate>> first = container.read(
        programTemplatesProvider,
      );
      expect(first.hasValue, isFalse, reason: '버려진 뒤라 실어 둔 값이 없다');
      final List<ProgramTemplate> forB = await container.read(
        programTemplatesProvider.future,
      );
      expect(templatesOf(forB, TestTrainer.b), isTrue);
      expect(templatesOf(forB, TestTrainer.a), isFalse);
    });
  });

  group('주간 리포트', () {
    TrainerClient clientOf(TestTrainer t) =>
        makeClient(id: t.memberId, name: t.memberName);

    ReportKey keyOf(TestTrainer t) =>
        ReportKey(client: clientOf(t), weekStart: weekStartOf(nowKst()));

    test('weeklyReportProvider — B 에게 B 의 리포트만', () async {
      await signIn(TestTrainer.a);
      final WeeklyReport forA = await container.read(
        weeklyReportProvider(keyOf(TestTrainer.a)).future,
      );
      expect(forA.sessionsBooked, TestTrainer.a.sessionsBooked);

      await signOutClosing(const <ProviderSubscription<Object?>>[]);
      await signIn(TestTrainer.b);

      final WeeklyReport forB = await container.read(
        weeklyReportProvider(keyOf(TestTrainer.b)).future,
      );
      expect(forB.sessionsBooked, TestTrainer.b.sessionsBooked);
    });

    test('A 가 열어 둔 리포트 캐시는 계정이 바뀌면 사라진다', () async {
      await signIn(TestTrainer.a);
      final ReportKey keyA = keyOf(TestTrainer.a);
      await container.read(weeklyReportProvider(keyA).future);
      expect(container.exists(weeklyReportProvider(keyA)), isTrue);

      await signOutClosing(const <ProviderSubscription<Object?>>[]);
      expect(container.exists(weeklyReportProvider(keyA)), isFalse);
    });

    test('B 가 같은 열쇠로 읽어도 A 의 캐시가 아니라 서버의 거절을 받는다', () async {
      await signIn(TestTrainer.a);
      final ReportKey keyA = keyOf(TestTrainer.a);
      await container.read(weeklyReportProvider(keyA).future);

      await signOutClosing(const <ProviderSubscription<Object?>>[]);
      await signIn(TestTrainer.b);

      await expectLater(
        container.read(weeklyReportProvider(keyA).future),
        throwsA(anything),
      );
      expect(container.read(weeklyReportProvider(keyA)).valueOrNull, isNull);
    });

    test('reportSendLogProvider — A 의 전송 기록이 B 에게 남지 않는다', () async {
      await signIn(TestTrainer.a);
      final sub = container.listen(reportSendLogProvider, (_, _) {});
      container
          .read(reportSendLogProvider.notifier)
          .record(
            clientId: TestTrainer.a.memberId,
            weekStart: weekStartOf(nowKst()),
            message: 'A 가 보낸 리포트',
          );
      expect(container.read(reportSendLogProvider), hasLength(1));

      await signOutClosing(<ProviderSubscription<Object?>>[sub]);
      await signIn(TestTrainer.b);

      expect(container.read(reportSendLogProvider), isEmpty);
    });

    test('로그아웃 중에도 구독이 남아 있던 전송 기록은 비워진다', () async {
      // 상태를 가진 provider 는 다시 만들어질 때 이전 값을 싣지 않는다.
      await signIn(TestTrainer.a);
      final sub = container.listen(reportSendLogProvider, (_, _) {});
      addTearDown(sub.close);
      container
          .read(reportSendLogProvider.notifier)
          .record(
            clientId: TestTrainer.a.memberId,
            weekStart: weekStartOf(nowKst()),
            message: 'A',
          );

      await session.signOut();
      await settleAsync();
      expect(sub.read(), isEmpty);
    });
  });

  group('끼니 사진', () {
    test('같은 경로의 사진도 B 의 토큰으로 다시 받는다', () async {
      const String path = '/trainer/clients/shared/diet/photos/p1';
      await signIn(TestTrainer.a);
      final Uint8List? forA = await container.read(
        clientMealPhotoProvider(path).future,
      );
      expect(forA, TestTrainer.a.photoBytes);

      await signOutClosing(const <ProviderSubscription<Object?>>[]);
      await signIn(TestTrainer.b);

      final AsyncValue<Uint8List?> first = container.read(
        clientMealPhotoProvider(path),
      );
      expect(first.hasValue, isFalse);
      final Uint8List? forB = await container.read(
        clientMealPhotoProvider(path).future,
      );
      expect(forB, TestTrainer.b.photoBytes);
    });
  });

  group('설정·화면 상태', () {
    test('trainerSettingsProvider — B 의 알림 설정을 읽는다', () async {
      await signIn(TestTrainer.a);
      final sub = container.listen(trainerSettingsProvider, (_, _) {});
      // A 는 기본값(켜짐)과 다른 값을 저장해 두었다.
      await waitUntil(
        () =>
            sub.read().valueOrNull?.newMessageAlerts ==
            TestTrainer.a.newMessageAlerts,
      );

      await signOutClosing(<ProviderSubscription<Object?>>[sub]);
      await signIn(TestTrainer.b);

      final subB = container.listen(trainerSettingsProvider, (_, _) {});
      addTearDown(subB.close);
      // 새로 만든 컨트롤러는 A 의 값이 아니라 "아직 모름" 에서 출발해 B 의 값을
      // 읽는다(#2883).
      expect(subB.read().hasValue, isFalse);
      await waitUntil(
        () => backend.requests.any(
          (r) => r.account == TestTrainer.b && r.path == '/trainer/me/settings',
        ),
      );
      await settleAsync();
      expect(
        subB.read().valueOrNull?.newMessageAlerts,
        TestTrainer.b.newMessageAlerts,
      );
    });

    test('rosterViewProvider — A 가 고른 필터가 B 에게 남지 않는다', () async {
      await signIn(TestTrainer.a);
      final RosterView initial = container.read(rosterViewProvider);
      container.read(rosterViewProvider.notifier).state = initial.copyWith(
        sort: RosterSort.values.last == initial.sort
            ? RosterSort.values.first
            : RosterSort.values.last,
      );
      expect(container.read(rosterViewProvider).sort, isNot(initial.sort));

      await signOutClosing(const <ProviderSubscription<Object?>>[]);
      await signIn(TestTrainer.b);

      expect(container.read(rosterViewProvider).sort, initial.sort);
    });

    test('consultationFilterProvider — B 는 기본 필터에서 시작한다', () async {
      await signIn(TestTrainer.a);
      container.read(consultationFilterProvider.notifier).state = 'all';

      await signOutClosing(const <ProviderSubscription<Object?>>[]);
      await signIn(TestTrainer.b);

      expect(container.read(consultationFilterProvider), 'pending');
    });

    test('같은 계정의 프로필 편집은 화면 상태를 지우지 않는다', () async {
      await signIn(TestTrainer.a);
      container.read(consultationFilterProvider.notifier).state = 'all';

      final profile = container.read(sessionControllerProvider).profile!;
      session.replaceProfile(profile.copyWith(name: '고친 이름'));
      await settleAsync();

      expect(container.read(consultationFilterProvider), 'all');
    });
  });

  group('저장소 인스턴스', () {
    // 저장소가 들고 있는 메모리 상태(요청 id, 새로고침 스트림, 데모 배정 목록 등)
    // 는 인스턴스와 함께 버려져야 한다. 실서버 모드에서 상태 없는 `const`
    // 인스턴스를 돌려주는 AI 루틴 저장소는 같은 객체가 나오는 것이 정상이라 뺀다.
    final Map<String, ProviderListenable<Object>> repositories =
        <String, ProviderListenable<Object>>{
          'client': clientRepositoryProvider,
          'chat': chatRepositoryProvider,
          'followUp': followUpTaskRepositoryProvider,
          'memo': trainerMemoRepositoryProvider,
          'schedule': scheduleRepositoryProvider,
          'reservationSlot': reservationSlotRepositoryProvider,
          'consultation': consultationRepositoryProvider,
          'clientCoach': clientCoachRepositoryProvider,
          'clientInvite': clientInviteRepositoryProvider,
          'chatPdf': trainerChatPdfRepositoryProvider,
          'chatImage': trainerChatImageRepositoryProvider,
          'dailyTask': dailyTaskProgressStoreProvider,
          'account': trainerAccountRepositoryProvider,
          'profile': trainerProfileRepositoryProvider,
          'settings': trainerSettingsRepositoryProvider,
          'template': trainerProgramTemplateRepositoryProvider,
          'draft': trainerProgramDraftRepositoryProvider,
          'suggestion': trainerRoutineSuggestionRepositoryProvider,
          'options': trainerRoutineOptionsRepositoryProvider,
          'routine': trainerRoutineRepositoryProvider,
          'notification': trainerNotificationRepositoryProvider,
          'report': reportRepositoryProvider,
          'pdfSender': reportPdfSenderProvider,
        };

    for (final MapEntry<String, ProviderListenable<Object>> entry
        in repositories.entries) {
      test('${entry.key} — 계정이 바뀌면 새 인스턴스', () async {
        await signIn(TestTrainer.a);
        final Object forA = container.read(entry.value);

        await signOutClosing(const <ProviderSubscription<Object?>>[]);
        await signIn(TestTrainer.b);

        expect(identical(container.read(entry.value), forA), isFalse);
      });
    }

    test('같은 계정 안에서는 같은 인스턴스를 쓴다', () async {
      await signIn(TestTrainer.a);
      final Object first = container.read(clientRepositoryProvider);
      final profile = container.read(sessionControllerProvider).profile!;
      session.replaceProfile(profile.copyWith(name: '고친 이름'));
      await settleAsync();
      expect(
        identical(container.read(clientRepositoryProvider), first),
        isTrue,
      );
    });
  });
}
