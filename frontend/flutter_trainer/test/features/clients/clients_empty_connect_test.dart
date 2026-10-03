import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_connect_dialog.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/widgets/trainer_verification_banner.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 담당 회원 0명 빈 상태의 회원 연결 안내 (#3012).
///
/// 막 승인받은 트레이너의 첫 화면이 빈 카드 하나면 다음 행동을 모른다. 빈 상태가
/// 연결 방법을 적고, 툴바와 같은 연결 창을 여는 버튼을 단다.
const ValueKey<String> _empty = ValueKey<String>('clients-empty');
const ValueKey<String> _emptyConnect = ValueKey<String>(
  'clients-empty-connect',
);
const ValueKey<String> _connectBanner = ValueKey<String>(
  'trainer-verification-connect',
);

const String _hintKo = '연결 코드를 받거나 담당 요청을 보내 회원을 연결하세요.';
const String _hintEn = 'Connect members with the code they show you';

Future<void> _pumpEmpty(
  WidgetTester tester, {
  String at = AppRoutes.clients,
  List<Override> extra = const <Override>[],
  Locale locale = const Locale('ko'),
}) async {
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: at,
    locale: locale,
    extraOverrides: <Override>[stillRoster(), ...extra],
  );
}

void main() {
  testWidgets('승인 + 연결 가능 + 0명: 안내 문구와 신규 회원 등록 버튼', (tester) async {
    await _pumpEmpty(tester);

    expect(find.byKey(_empty), findsOneWidget);
    expect(find.text('아직 담당 회원이 없어요'), findsOneWidget);
    expect(find.textContaining(_hintKo), findsOneWidget);
    final AppButton button = tester.widget<AppButton>(
      find.byKey(_emptyConnect),
    );
    expect(button.onPressed, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(_emptyConnect),
        matching: find.text('신규 회원 등록'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('빈 상태 버튼은 툴바와 같은 연결 창을 연다', (tester) async {
    await _pumpEmpty(tester);

    await tester.tap(find.byKey(_emptyConnect));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ClientConnectDialog), findsOneWidget);
  });

  testWidgets('승인 대기: 버튼 없이 안내만, 이유는 승인 배너가 적는다', (tester) async {
    await _pumpEmpty(
      tester,
      extra: <Override>[
        trainerVerificationProvider.overrideWithValue(
          const TrainerVerification(status: TrainerVerificationStatus.pending),
        ),
      ],
    );

    expect(find.byKey(_empty), findsOneWidget);
    expect(find.byKey(_emptyConnect), findsNothing);
    expect(find.byKey(_connectBanner), findsOneWidget);
  });

  testWidgets('반려: 버튼 없이 안내만', (tester) async {
    await _pumpEmpty(
      tester,
      extra: <Override>[
        trainerVerificationProvider.overrideWithValue(
          const TrainerVerification(
            status: TrainerVerificationStatus.rejected,
            note: '자격 확인 불가',
          ),
        ),
      ],
    );

    expect(find.byKey(_emptyConnect), findsNothing);
    expect(find.byKey(_connectBanner), findsOneWidget);
  });

  testWidgets('연결 경로가 꺼진 빌드: 버튼도 안내 문구도 없다', (tester) async {
    await _pumpEmpty(
      tester,
      extra: <Override>[clientInvitesEnabledProvider.overrideWithValue(false)],
    );

    expect(find.byKey(_empty), findsOneWidget);
    expect(find.byKey(_emptyConnect), findsNothing);
    expect(find.textContaining(_hintKo), findsNothing);
  });

  testWidgets('필터로 걸러진 0명은 지금처럼 버튼 없는 빈 상태다', (tester) async {
    await _pumpEmpty(tester, at: AppRoutes.clientsFiltered('unread'));

    expect(find.byKey(_empty), findsOneWidget);
    expect(find.byKey(_emptyConnect), findsNothing);
    expect(find.textContaining(_hintKo), findsNothing);
  });

  testWidgets('회원이 있으면 빈 상태가 없다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clients,
    );

    expect(find.byKey(_empty), findsNothing);
    expect(find.byKey(_emptyConnect), findsNothing);
  });

  testWidgets('영문 화면도 안내 문구와 버튼을 보인다', (tester) async {
    await _pumpEmpty(tester, locale: const Locale('en'));

    expect(find.text('No members yet'), findsOneWidget);
    expect(find.textContaining(_hintEn), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_emptyConnect),
        matching: find.text('Register new member'),
      ),
      findsOneWidget,
    );
  });
}
