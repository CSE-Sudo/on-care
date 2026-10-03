import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/not_found_page.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/admin/data/repositories/admin_trainer_repository.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';
import 'package:oncare_trainer/features/admin/presentation/pages/admin_trainers_page.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 트레이너 웹 운영 화면 — 승인·반려·정지 (#3008·#3009).
AdminTrainer _trainer({
  String id = 'trainer-1',
  String name = '김코치',
  TrainerVerificationStatus status = TrainerVerificationStatus.pending,
  bool isActive = true,
  bool hasGym = true,
  bool gymIsFitness = true,
  String note = '',
}) => AdminTrainer(
  trainerId: id,
  name: name,
  email: '$id@oncare.com',
  specialty: '체형 교정',
  careerYears: 4,
  certifications: const <String>['CPT'],
  gymName: hasGym ? '온케어짐 신촌점' : '',
  gymAddress: hasGym ? '서울 서대문구 신촌로 120' : '',
  gymIsFitness: gymIsFitness,
  hasGym: hasGym,
  status: status,
  note: note,
  isActive: isActive,
  createdAt: DateTime(2026, 10, 2),
);

class _FakeAdminRepo implements AdminTrainerRepository {
  _FakeAdminRepo(this.rows);

  List<AdminTrainer> rows;
  final List<AdminTrainerFilter> fetched = <AdminTrainerFilter>[];
  final List<String> calls = <String>[];
  int released = 0;
  AppError? failWith;

  @override
  Future<List<AdminTrainer>> fetch(AdminTrainerFilter filter) async {
    fetched.add(filter);
    return rows;
  }

  @override
  Future<AdminTrainer> approve(String trainerId) async {
    calls.add('approve:$trainerId');
    final AppError? error = failWith;
    if (error != null) throw error;
    return rows.first;
  }

  @override
  Future<AdminTrainer> reject(String trainerId, {String reason = ''}) async {
    calls.add('reject:$trainerId:$reason');
    return rows.first;
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
    at: AppRoutes.adminTrainers,
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

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
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

void main() {
  testWidgets('운영자가 아니면 주소로 열어도 찾을 수 없음 안내만 보인다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo, admin: false);

    expect(find.byKey(NotFoundPage.bodyKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('admin-trainers-page')),
      findsNothing,
    );
    expect(repo.fetched, isEmpty);
  });

  testWidgets('운영자는 승인 대기 목록을 카드로 본다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo);

    expect(
      find.byKey(const ValueKey<String>('admin-trainers-page')),
      findsOneWidget,
    );
    expect(repo.fetched, <AdminTrainerFilter>[AdminTrainerFilter.pending]);
    expect(
      find.byKey(const ValueKey<String>('admin-trainer-trainer-1')),
      findsOneWidget,
    );
    expect(find.text('김코치'), findsOneWidget);
    expect(find.text('trainer-1@oncare.com'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('admin-approve-trainer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-reject-trainer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-suspend-trainer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-gym-warning-trainer-1')),
      findsNothing,
    );
  });

  testWidgets('소속이 없거나 헬스장이 아니면 경고 배너가 붙는다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[
      _trainer(id: 'no-gym', hasGym: false),
      _trainer(id: 'not-fit', gymIsFitness: false),
    ]);
    await _pump(tester, repo);

    expect(
      find.byKey(const ValueKey<String>('admin-gym-warning-no-gym')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-gym-warning-not-fit')),
      findsOneWidget,
    );
  });

  testWidgets('승인은 확인창을 거쳐 저장소를 부르고 목록을 다시 읽는다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo);

    await _tapKey(tester, 'admin-approve-trainer-1');
    expect(find.byType(AppDialog), findsOneWidget);
    await _confirm(tester, '승인');

    expect(repo.calls, <String>['approve:trainer-1']);
    expect(find.text('김코치 트레이너를 승인했어요'), findsOneWidget);
    expect(repo.fetched.length, greaterThanOrEqualTo(2));
    await tester.pump(OnCareMotion.toastActionVisible);
  });

  testWidgets('확인창을 취소하면 아무것도 부르지 않는다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo);

    await _tapKey(tester, 'admin-approve-trainer-1');
    await _confirm(tester, '취소');

    expect(repo.calls, isEmpty);
  });

  testWidgets('승인 실패는 오류 안내를 띄운다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()])
      ..failWith = const NetworkError();
    await _pump(tester, repo);

    await _tapKey(tester, 'admin-approve-trainer-1');
    await _confirm(tester, '승인');

    expect(repo.calls, <String>['approve:trainer-1']);
    expect(find.text('김코치 트레이너를 승인했어요'), findsNothing);
    await tester.pump(OnCareMotion.toastActionVisible);
  });

  testWidgets('반려는 사유를 받아 그대로 보낸다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo);

    await _tapKey(tester, 'admin-reject-trainer-1');
    expect(find.byType(AdminRejectDialog), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('admin-reject-reason')),
        matching: find.byType(EditableText),
      ),
      '  소속 확인 불가  ',
    );
    await _tapKey(tester, 'admin-reject-confirm');

    expect(repo.calls, <String>['reject:trainer-1:소속 확인 불가']);
    expect(find.text('김코치 트레이너를 반려했어요'), findsOneWidget);
    await tester.pump(OnCareMotion.toastActionVisible);
  });

  testWidgets('반려 창을 취소하면 반려하지 않는다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo);

    await _tapKey(tester, 'admin-reject-trainer-1');
    await _tapKey(tester, 'admin-reject-cancel');

    expect(repo.calls, isEmpty);
    expect(find.byType(AdminRejectDialog), findsNothing);
  });

  testWidgets('정지는 해제한 담당 회원 수를 알려 준다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[
      _trainer(status: TrainerVerificationStatus.approved),
    ])..released = 2;
    await _pump(tester, repo);

    await _tapKey(tester, 'admin-suspend-trainer-1');
    await _confirm(tester, '계정 정지');

    expect(repo.calls, <String>['suspend:trainer-1']);
    expect(find.text('김코치 계정을 정지하고 담당 회원 2명의 연결을 해제했어요'), findsOneWidget);
    await tester.pump(OnCareMotion.toastActionVisible);
  });

  testWidgets('정지된 계정은 정지 태그와 해제 버튼만 있다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[
      _trainer(isActive: false),
    ]);
    await _pump(tester, repo);

    expect(
      find.byKey(const ValueKey<String>('admin-suspended-trainer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-approve-trainer-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-reject-trainer-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-suspend-trainer-1')),
      findsNothing,
    );

    await _tapKey(tester, 'admin-unsuspend-trainer-1');
    await _confirm(tester, '정지 해제');

    expect(repo.calls, <String>['unsuspend:trainer-1']);
    expect(find.text('김코치 계정 정지를 풀었어요'), findsOneWidget);
    await tester.pump(OnCareMotion.toastActionVisible);
  });

  testWidgets('반려된 카드는 사유를 보이고 재승인만 할 수 있다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[
      _trainer(status: TrainerVerificationStatus.rejected, note: '서류 보완'),
    ]);
    await _pump(tester, repo);

    expect(find.text('서류 보완'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('admin-reject-trainer-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-approve-trainer-1')),
      findsOneWidget,
    );
  });

  testWidgets('칩을 바꾸면 그 상태로 다시 읽는다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo);

    await _tapKey(tester, 'admin-filter-all');
    expect(repo.fetched.last, AdminTrainerFilter.all);

    await _tapKey(tester, 'admin-filter-rejected');
    expect(repo.fetched.last, AdminTrainerFilter.rejected);
  });

  testWidgets('목록이 비면 빈 상태를 보인다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[]);
    await _pump(tester, repo);

    expect(
      find.byKey(const ValueKey<String>('admin-trainers-empty')),
      findsOneWidget,
    );
  });

  testWidgets('영문 화면도 같은 동작을 보인다', (tester) async {
    final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[_trainer()]);
    await _pump(tester, repo, locale: const Locale('en'));

    expect(find.text('Trainer approvals'), findsWidgets);
    await _tapKey(tester, 'admin-approve-trainer-1');
    await _confirm(tester, 'Approve');
    expect(find.text('Approved 김코치'), findsOneWidget);
    await tester.pump(OnCareMotion.toastActionVisible);
  });

  group('사이드바', () {
    const ValueKey<String> item = ValueKey<String>('sidebar-/admin/trainers');

    testWidgets('운영자에게만 운영 메뉴가 보인다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeAdminRepo repo = _FakeAdminRepo(<AdminTrainer>[]);
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
        expect(
          find.byKey(const ValueKey<String>('admin-trainers-page')),
          findsOneWidget,
        );
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
