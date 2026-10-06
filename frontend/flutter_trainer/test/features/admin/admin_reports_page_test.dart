import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/not_found_page.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/admin/data/repositories/admin_trainer_repository.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_report.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';
import 'package:oncare_trainer/features/admin/presentation/pages/admin_reports_page.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 트레이너 웹 운영 화면 `신고·계정 관리` — 신고 처리·트레이너 찾기·정지 (#3008).
AdminTrainerReport _report({
  String id = 'report-1',
  String trainerId = 'trainer-1',
  AdminReportReason reason = AdminReportReason.impersonation,
  String memo = '',
  AdminReportStatus status = AdminReportStatus.open,
  bool trainerIsActive = true,
}) => AdminTrainerReport(
  id: id,
  trainerId: trainerId,
  trainerName: '김코치',
  trainerEmail: '$trainerId@oncare.com',
  trainerIsActive: trainerIsActive,
  reason: reason,
  memo: memo,
  status: status,
  createdAt: DateTime(2026, 10, 2),
  resolvedAt: status == AdminReportStatus.open ? null : DateTime(2026, 10, 3),
);

AdminTrainer _trainer({
  String id = 'trainer-1',
  bool isActive = true,
  int openReports = 0,
  bool hasGym = true,
}) => AdminTrainer(
  trainerId: id,
  name: '김코치',
  email: '$id@oncare.com',
  gymName: hasGym ? '온케어짐 신촌점' : '',
  gymAddress: hasGym ? '서울 서대문구 신촌로 120' : '',
  isActive: isActive,
  openReports: openReports,
  createdAt: DateTime(2026, 10, 2),
);

class _FakeAdminRepo implements AdminTrainerRepository {
  _FakeAdminRepo({
    this.reports = const <AdminTrainerReport>[],
    this.trainers = const <AdminTrainer>[],
  });

  List<AdminTrainerReport> reports;
  List<AdminTrainer> trainers;
  final List<AdminReportFilter> reportFetches = <AdminReportFilter>[];
  final List<String> trainerFetches = <String>[];
  final List<String> calls = <String>[];
  int released = 0;

  /// 처리 응답 대신 던질 예외. [AppError] 가 아닌 것도 된다(#3262).
  Object? failWith;

  /// 있으면 끝날 때까지 처리 응답을 잡아 둔다 — 처리 중 화면을 바꾸는 자리(#3248).
  Completer<void>? gate;

  @override
  Future<List<AdminTrainerReport>> fetchReports(
    AdminReportFilter filter,
  ) async {
    reportFetches.add(filter);
    return reports;
  }

  @override
  Future<AdminTrainerReport> closeReport(
    String reportId,
    AdminReportOutcome outcome,
  ) async {
    calls.add('close:$reportId:${outcome.wire}');
    final Completer<void>? wait = gate;
    if (wait != null) await wait.future;
    final Object? error = failWith;
    if (error != null) throw error;
    return reports.first;
  }

  @override
  Future<List<AdminTrainer>> fetchTrainers({
    String query = '',
    AdminTrainerState state = AdminTrainerState.all,
  }) async {
    trainerFetches.add('$query|${state.wire}');
    return trainers;
  }

  @override
  Future<AdminUserStatus> suspend(String userId) async {
    calls.add('suspend:$userId');
    return AdminUserStatus(
      userId: userId,
      isActive: false,
      releasedClients: released,
    );
  }

  @override
  Future<AdminUserStatus> unsuspend(String userId) async {
    calls.add('unsuspend:$userId');
    return AdminUserStatus(userId: userId, isActive: true);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminRepo repo, {
  bool admin = true,
  Locale locale = const Locale('ko'),
}) async {
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.adminReports,
    locale: locale,
    extraOverrides: <Override>[
      adminConsoleEnabledProvider.overrideWithValue(admin),
      adminTrainerRepositoryProvider.overrideWithValue(repo),
    ],
  );
  await tester.pump();
}

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(text));

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder target = _key(key);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _confirm(WidgetTester tester, String label) async {
  await tester.tap(_inDialog(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openTrainers(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _key('admin-section'), matching: find.text('트레이너')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('운영자가 아니면 주소로 열어도 찾을 수 없음 안내만 보인다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(
      reports: <AdminTrainerReport>[_report()],
    );
    await _pump(tester, repo, admin: false);

    expect(find.byKey(NotFoundPage.bodyKey), findsOneWidget);
    expect(_key('admin-reports-page'), findsNothing);
    expect(repo.reportFetches, isEmpty);
  });

  group('신고', () {
    testWidgets('처리 전 신고를 대상·사유·내용과 함께 카드로 본다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[
          _report(reason: AdminReportReason.other, memo: '다른 헬스장 소속이에요'),
        ],
      );
      await _pump(tester, repo);

      expect(_key('admin-reports-page'), findsOneWidget);
      expect(find.text('신고·계정 관리'), findsWidgets);
      expect(repo.reportFetches, <AdminReportFilter>[AdminReportFilter.open]);
      expect(_key('admin-report-report-1'), findsOneWidget);
      expect(find.text('김코치'), findsOneWidget);
      expect(find.text('trainer-1@oncare.com'), findsOneWidget);
      expect(find.text('기타'), findsOneWidget);
      expect(find.text('다른 헬스장 소속이에요'), findsOneWidget);
      expect(_key('admin-report-resolve-report-1'), findsOneWidget);
      expect(_key('admin-report-dismiss-report-1'), findsOneWidget);
      expect(_key('admin-suspend-report-report-1'), findsOneWidget);
    });

    testWidgets('사유 라벨이 세 가지로 갈린다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[
          _report(id: 'a'),
          _report(id: 'b', reason: AdminReportReason.inappropriateMessage),
        ],
      );
      await _pump(tester, repo);

      expect(find.text('소속·신원 사칭'), findsOneWidget);
      expect(find.text('부적절한 메시지'), findsOneWidget);
    });

    testWidgets('조치함은 확인창을 거쳐 닫고 목록을 다시 읽는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
      );
      await _pump(tester, repo);

      await _tapKey(tester, 'admin-report-resolve-report-1');
      expect(find.byType(AppDialog), findsOneWidget);
      await _confirm(tester, '조치함');

      expect(repo.calls, <String>['close:report-1:resolved']);
      expect(find.text('신고를 조치함으로 닫았어요'), findsOneWidget);
      expect(repo.reportFetches.length, greaterThanOrEqualTo(2));
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    testWidgets('처리하는 사이 카드가 사라져도 오류 없이 목록을 다시 읽는다 (#3248)', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
        trainers: <AdminTrainer>[_trainer()],
      )..gate = Completer<void>();
      await _pump(tester, repo);

      await _tapKey(tester, 'admin-report-resolve-report-1');
      await _confirm(tester, '조치함');
      // 응답이 오기 전에 트레이너 갈래로 옮겨 신고 카드를 내린다.
      await _openTrainers(tester);
      expect(_key('admin-report-report-1'), findsNothing);
      final int trainerFetches = repo.trainerFetches.length;

      repo.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(repo.trainerFetches.length, greaterThan(trainerFetches));
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    testWidgets('넘김은 dismissed 로 닫는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
      );
      await _pump(tester, repo);

      await _tapKey(tester, 'admin-report-dismiss-report-1');
      await _confirm(tester, '넘김');

      expect(repo.calls, <String>['close:report-1:dismissed']);
      expect(find.text('신고를 넘겼어요'), findsOneWidget);
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    testWidgets('확인창을 취소하면 아무것도 부르지 않는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
      );
      await _pump(tester, repo);

      await _tapKey(tester, 'admin-report-resolve-report-1');
      await _confirm(tester, '취소');

      expect(repo.calls, isEmpty);
    });

    testWidgets('처리 실패는 성공 안내를 띄우지 않는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
      )..failWith = const NetworkError();
      await _pump(tester, repo);

      await _tapKey(tester, 'admin-report-resolve-report-1');
      await _confirm(tester, '조치함');

      expect(repo.calls, <String>['close:report-1:resolved']);
      expect(find.text('신고를 조치함으로 닫았어요'), findsNothing);
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    // 저장소가 AppError 로 감싸지 못한 예외는 안내 없이 비동기 오류로 샜다(#3262).
    testWidgets('AppError 가 아닌 예외도 실패 안내를 띄우고 목록을 다시 읽는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
      )..failWith = StateError('unexpected');
      await _pump(tester, repo);
      final int reportFetches = repo.reportFetches.length;

      await _tapKey(tester, 'admin-report-resolve-report-1');
      await _confirm(tester, '조치함');

      expect(tester.takeException(), isNull);
      expect(repo.calls, <String>['close:report-1:resolved']);
      expect(find.text('처리하지 못했어요. 잠시 뒤 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('신고를 조치함으로 닫았어요'), findsNothing);
      expect(repo.reportFetches.length, greaterThan(reportFetches));
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    testWidgets('처리한 신고는 상태와 처리일만 보이고 처리 버튼이 없다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[
          _report(status: AdminReportStatus.dismissed),
        ],
      );
      await _pump(tester, repo);

      expect(find.text('넘김'), findsOneWidget);
      expect(find.text('처리일'), findsOneWidget);
      expect(_key('admin-report-resolve-report-1'), findsNothing);
      expect(_key('admin-report-dismiss-report-1'), findsNothing);
    });

    testWidgets('신고 카드에서 대상 계정을 정지한다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
      )..released = 2;
      await _pump(tester, repo);

      await _tapKey(tester, 'admin-suspend-report-report-1');
      await _confirm(tester, '계정 정지');

      expect(repo.calls, <String>['suspend:trainer-1']);
      expect(find.text('김코치 계정을 정지하고 담당 회원 2명의 연결을 해제했어요'), findsOneWidget);
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    testWidgets('정지된 대상은 정지 태그와 해제 버튼을 보인다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report(trainerIsActive: false)],
      );
      await _pump(tester, repo);

      expect(_key('admin-report-suspended-report-1'), findsOneWidget);
      expect(_key('admin-suspend-report-report-1'), findsNothing);
      await _tapKey(tester, 'admin-unsuspend-report-report-1');
      await _confirm(tester, '정지 해제');

      expect(repo.calls, <String>['unsuspend:trainer-1']);
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    testWidgets('칩을 바꾸면 그 상태로 다시 읽는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        reports: <AdminTrainerReport>[_report()],
      );
      await _pump(tester, repo);

      await _tapKey(tester, 'admin-report-filter-closed');
      expect(repo.reportFetches.last, AdminReportFilter.closed);

      await _tapKey(tester, 'admin-report-filter-all');
      expect(repo.reportFetches.last, AdminReportFilter.all);
    });

    testWidgets('처리할 신고가 없으면 빈 상태를 보인다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo();
      await _pump(tester, repo);

      expect(_key('admin-reports-empty'), findsOneWidget);
      expect(find.text('처리할 신고가 없어요'), findsOneWidget);
    });
  });

  group('트레이너', () {
    testWidgets('갈래를 바꾸면 트레이너 목록을 읽어 카드로 본다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        trainers: <AdminTrainer>[_trainer(openReports: 3)],
      );
      await _pump(tester, repo);
      expect(repo.trainerFetches, isEmpty);

      await _openTrainers(tester);

      expect(repo.trainerFetches, <String>['|all']);
      expect(_key('admin-trainer-trainer-1'), findsOneWidget);
      expect(_key('admin-open-reports-trainer-1'), findsOneWidget);
      expect(find.text('3건'), findsWidgets);
      expect(find.textContaining('온케어짐 신촌점'), findsOneWidget);
      expect(_key('admin-suspend-trainer-1'), findsOneWidget);
    });

    testWidgets('검색은 보내기를 누를 때 서버에 묻는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        trainers: <AdminTrainer>[_trainer()],
      );
      await _pump(tester, repo);
      await _openTrainers(tester);

      await tester.enterText(
        find.descendant(
          of: _key('admin-trainer-search'),
          matching: find.byType(EditableText),
        ),
        ' 김코치 ',
      );
      await tester.pump();
      expect(repo.trainerFetches, <String>['|all']);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(repo.trainerFetches.last, '김코치|all');
    });

    testWidgets('상태 칩은 state 로 다시 읽는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        trainers: <AdminTrainer>[_trainer()],
      );
      await _pump(tester, repo);
      await _openTrainers(tester);

      await _tapKey(tester, 'admin-trainer-state-suspended');
      expect(repo.trainerFetches.last, '|suspended');
    });

    testWidgets('정지·해제는 확인창을 거친다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        trainers: <AdminTrainer>[
          _trainer(),
          _trainer(id: 'trainer-2', isActive: false),
        ],
      );
      await _pump(tester, repo);
      await _openTrainers(tester);

      await _tapKey(tester, 'admin-suspend-trainer-1');
      await _confirm(tester, '계정 정지');
      await tester.pump(OnCareMotion.toastActionVisible);
      await _tapKey(tester, 'admin-unsuspend-trainer-2');
      await _confirm(tester, '정지 해제');

      expect(repo.calls, <String>['suspend:trainer-1', 'unsuspend:trainer-2']);
      expect(find.text('김코치 계정 정지를 풀었어요'), findsOneWidget);
      await tester.pump(OnCareMotion.toastActionVisible);
    });

    testWidgets('소속이 없으면 없다고 적는다', (tester) async {
      final _FakeAdminRepo repo = _FakeAdminRepo(
        trainers: <AdminTrainer>[_trainer(hasGym: false)],
      );
      await _pump(tester, repo);
      await _openTrainers(tester);

      expect(find.text('소속 헬스장이 없어요'), findsOneWidget);
    });
  });

  testWidgets('영문 화면도 같은 동작을 보인다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(
      reports: <AdminTrainerReport>[_report()],
    );
    await _pump(tester, repo, locale: const Locale('en'));

    expect(find.text('Reports & accounts'), findsWidgets);
    expect(find.text('Impersonation'), findsOneWidget);
    await _tapKey(tester, 'admin-report-dismiss-report-1');
    await _confirm(tester, 'Dismiss');
    expect(find.text('Report dismissed'), findsOneWidget);
    await tester.pump(OnCareMotion.toastActionVisible);
  });

  group('사이드바', () {
    const ValueKey<String> item = ValueKey<String>('sidebar-/admin/reports');

    testWidgets('운영자에게만 신고·계정 관리 메뉴가 보인다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeAdminRepo repo = _FakeAdminRepo();
        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.dashboard,
          extraOverrides: <Override>[
            adminConsoleEnabledProvider.overrideWithValue(true),
            adminTrainerRepositoryProvider.overrideWithValue(repo),
          ],
        );
        expect(find.byKey(item), findsOneWidget);

        await tester.tap(find.byKey(item));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_key('admin-reports-page'), findsOneWidget);
      });
    });

    testWidgets('운영자가 아니면 메뉴가 없다', (tester) async {
      await withWideSurface(tester, () async {
        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.dashboard,
        );
        expect(find.byKey(item), findsNothing);
      });
    });
  });
}
