import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../helpers/client_factory.dart';

/// 트레이너 웹 회원 행은 공용 컴포넌트 한 벌로 그린다. (#2467)
///
/// 같은 회원의 이름이 탭마다 14·15·16 에 굵기까지 갈려 있었다.
void main() {
  const String goal = '혈압 관리 · 체중 감량';

  Future<void> pumpBlock(
    WidgetTester tester,
    Widget child) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ko'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Text textOf(WidgetTester tester, String data) =>
      tester.widget<Text>(find.text(data));

  testWidgets('밀도가 이름 글씨·아바타 크기를 정한다', (tester) async {
    // 성별·나이를 모두 모르면 그 글자를 그리지 않으므로(#2870) 성별을 준다.
    final TrainerClient client = makeClient(
      name: '가회원',
      goal: goal,
      gender: 'female',
    );
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

  // 줄 수를 세는 테스트라 성별을 준다 — 성별·나이를 모두 모르면 그 글자는
  // 그리지 않는다(#2870).
  testWidgets('둘째 줄은 바꾸거나 숨길 수 있고, 비면 줄을 만들지 않는다', (tester) async {
    await pumpBlock(
      tester,
      Column(
        children: <Widget>[
          ClientIdentityBlock(
            key: const ValueKey<String>('detail'),
            client: makeClient(
              id: 'a',
              name: '가회원',
              goal: goal,
              gender: 'female',
            ),
            detail: '9월 28일 전송',
          ),
          ClientIdentityBlock(
            key: const ValueKey<String>('hidden'),
            client: makeClient(
              id: 'b',
              name: '나회원',
              goal: goal,
              gender: 'male',
            ),
            showDetail: false,
          ),
          ClientIdentityBlock(
            key: const ValueKey<String>('empty'),
            client: makeClient(
              id: 'c',
              name: '다회원',
              goal: '',
              gender: 'female',
            ),
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
}
