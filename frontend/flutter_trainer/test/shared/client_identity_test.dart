import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../helpers/client_factory.dart';
import '../helpers/pump_app.dart';

/// 트레이너 웹 회원 행은 공용 컴포넌트 한 벌로 그린다. (#2467)
///
/// 같은 회원의 이름이 탭마다 14·15·16 에 굵기까지 갈려 있었고, 목표는 어떤
/// 탭에서만 번역돼 영어 화면에서 탭마다 다른 말로 보였다.
void main() {
  const String goal = '혈압 관리 · 체중 감량';

  Future<void> pumpBlock(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('ko'),
  }) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Text textOf(WidgetTester tester, String data) =>
      tester.widget<Text>(find.text(data));

  testWidgets('밀도가 이름 글씨·아바타 크기를 정한다', (tester) async {
    final TrainerClient client = makeClient(name: '가회원', goal: goal);
    for (final ClientRowDensity density in ClientRowDensity.values) {
      await pumpBlock(tester, ClientRow(client: client, density: density));
      final BuildContext context = tester.element(find.byType(ClientRow));
      final OnCareTokens tokens = context.oncare;
      final TextStyle expected = tokens.text(switch (density) {
        ClientRowDensity.list => OnCareTypography.strong(
          OnCareTypography.bodyLarge,
        ),
        ClientRowDensity.compact => OnCareTypography.strong(
          OnCareTypography.bodySmall,
        ),
        ClientRowDensity.header => OnCareTypography.titleSmall,
      });
      final TextStyle name = textOf(tester, '가회원').style!;
      expect(name.fontSize, expected.fontSize, reason: density.name);
      expect(name.fontWeight, expected.fontWeight, reason: density.name);
      expect(name.color, OnCareColors.textPrimary, reason: density.name);
      expect(
        tester.widget<ClientAvatar>(find.byType(ClientAvatar)).size,
        density.avatarSize,
        reason: density.name,
      );
      // 성별·나이는 밀도와 상관없이 이름보다 작고 흐리다.
      final TextStyle demographics = textOf(
        tester,
        clientDemographicsLabel(context, client),
      ).style!;
      expect(demographics.fontSize!, lessThan(name.fontSize!));
      expect(demographics.color, OnCareColors.textTertiary);
    }
  });

  testWidgets('목표는 늘 로케일 문구로 적는다', (tester) async {
    final TrainerClient client = makeClient(name: 'Alex', goal: goal);
    await pumpBlock(
      tester,
      ClientIdentityBlock(client: client),
      locale: const Locale('en'),
    );
    expect(find.text('Blood pressure care · Weight loss'), findsOneWidget);
    expect(find.text(goal), findsNothing);
  });

  // 회원 관리 목록·상세·메시지 행이 함께 쓰는 자리다(#2744). 생년월일이 없는
  // 회원에게 id 해시로 지은 나이를 적지 않는다.
  testWidgets('회원 행은 서버가 준 나이만 적고, 없으면 성별만 적는다', (tester) async {
    await pumpBlock(
      tester,
      Column(
        children: <Widget>[
          ClientIdentityBlock(
            client: makeClient(
              id: 'user-a',
              name: '가회원',
              gender: 'female',
              age: 41,
            ),
          ),
          ClientIdentityBlock(
            client: makeClient(id: 'user-b', name: '나회원', gender: 'male'),
          ),
        ],
      ),
    );
    expect(find.text('여성 · 41세'), findsOneWidget);
    expect(find.text('남성'), findsOneWidget);
  });

  testWidgets('둘째 줄은 바꾸거나 숨길 수 있고, 비면 줄을 만들지 않는다', (tester) async {
    await pumpBlock(
      tester,
      Column(
        children: <Widget>[
          ClientIdentityBlock(
            key: const ValueKey<String>('detail'),
            client: makeClient(id: 'a', name: '가회원', goal: goal),
            detail: '9월 28일 전송',
          ),
          ClientIdentityBlock(
            key: const ValueKey<String>('hidden'),
            client: makeClient(id: 'b', name: '나회원', goal: goal),
            showDetail: false,
          ),
          ClientIdentityBlock(
            key: const ValueKey<String>('empty'),
            client: makeClient(id: 'c', name: '다회원', goal: ''),
          ),
        ],
      ),
    );
    int textsIn(String key) => find
        .descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
        )
        .evaluate()
        .length;
    expect(find.text('9월 28일 전송'), findsOneWidget);
    expect(find.text(goal), findsNothing);
    expect(textsIn('detail'), 3);
    expect(textsIn('hidden'), 2);
    expect(textsIn('empty'), 2);
  });

  // 회원 고르기 카드(프로그램 탭 왼쪽 목록)는 목표를 원문 그대로 적어, 영어
  // 화면에서 이 탭만 한국어 목표가 남았다.
  testWidgets('영어 화면의 프로그램 탭 회원 목록도 목표를 번역한다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.coaching,
      locale: const Locale('en'),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(id: 'type-a', name: 'Alex', goal: goal),
          ]),
        ),
      ],
    );
    await tester.pumpAndSettle();

    final Finder row = find.byKey(
      const ValueKey<String>('program-client-type-a'),
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text('Blood pressure care · Weight loss'),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: find.text(goal)), findsNothing);
  });
}
