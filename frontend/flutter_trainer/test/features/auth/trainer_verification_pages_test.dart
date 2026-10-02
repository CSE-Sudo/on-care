import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/widgets/trainer_verification_banner.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 승인 대기·반려 트레이너에게 화면마다 이유를 보이고 회원 연결을 끈다 (#2825).
const TrainerVerification _pending = TrainerVerification(
  status: TrainerVerificationStatus.pending,
);

List<Override> _as(TrainerVerification v) => <Override>[
  trainerVerificationProvider.overrideWithValue(v),
];

const ValueKey<String> _overview = ValueKey<String>(
  'trainer-verification-overview',
);
const ValueKey<String> _connect = ValueKey<String>(
  'trainer-verification-connect',
);
const ValueKey<String> _consult = ValueKey<String>(
  'trainer-verification-consultations',
);
const ValueKey<String> _newClient = ValueKey<String>('clients-new');

void main() {
  group('dashboard', () {
    testWidgets('pending shows the overview banner', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.dashboard,
        extraOverrides: _as(_pending),
      );
      expect(find.byKey(_overview), findsOneWidget);
    });

    testWidgets('the demo trainer is approved — no banner', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.dashboard,
      );
      expect(find.byKey(_overview), findsNothing);
    });
  });

  group('clients', () {
    testWidgets('pending disables new-client and says why', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
        extraOverrides: _as(_pending),
      );

      final AppButton button = tester.widget<AppButton>(find.byKey(_newClient));
      expect(button.onPressed, isNull);
      expect(find.byKey(_connect), findsOneWidget);
    });

    testWidgets('rejected also keeps new-client off', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
        extraOverrides: _as(
          const TrainerVerification(
            status: TrainerVerificationStatus.rejected,
            note: '자격 확인 불가',
          ),
        ),
      );

      expect(
        tester.widget<AppButton>(find.byKey(_newClient)).onPressed,
        isNull,
      );
      expect(find.byKey(_connect), findsOneWidget);
    });

    testWidgets('approved keeps new-client on with no banner', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clients,
      );

      expect(
        tester.widget<AppButton>(find.byKey(_newClient)).onPressed,
        isNotNull,
      );
      expect(find.byKey(_connect), findsNothing);
    });
  });

  group('consultations', () {
    testWidgets('pending explains why no requests arrive', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.consultations,
        extraOverrides: _as(_pending),
      );
      expect(find.byKey(_consult), findsOneWidget);
    });

    testWidgets('approved shows no banner in the inbox', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.consultations,
      );
      expect(find.byKey(_consult), findsNothing);
    });
  });
}
