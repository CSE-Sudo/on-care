import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const MemberCoach _coach = MemberCoach(
  trainerId: 'coach-1',
  name: '김트레이너',
  specialty: '체형 교정',
  career: '5년',
  intro: '',
  gymName: '신촌 짐',
  goal: '',
);

/// 버튼의 아이콘 색으로 활성/비활성을 읽는다 — 화면에서 사용자가 구별하는 근거와
/// 같은 것을 본다. 아이콘 버튼은 색을 아이콘 테마로 내려 주므로 그것을 읽는다.
Color _iconColor(WidgetTester tester) {
  return IconTheme.of(
    tester.element(find.byIcon(Icons.chat_bubble_outline_rounded)),
  ).color!;
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Override coachOverride,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          coachOverride,
          coachUnreadProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: TrainerChatHeaderButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('담당 트레이너가 있으면 활성으로 그린다', (WidgetTester tester) async {
    await pump(
      tester,
      coachOverride: memberCoachProvider.overrideWith((ref) async => _coach),
    );

    expect(_iconColor(tester), OnCareBrand.member.primary);
  });

  testWidgets('담당 트레이너가 없으면 흐리게 그린다', (WidgetTester tester) async {
    await pump(
      tester,
      coachOverride: memberCoachProvider.overrideWith((ref) async => null),
    );

    // 예전에는 색이 그대로여서 눌리는 버튼과 구별되지 않았다(#786).
    expect(_iconColor(tester), OnCareColors.textDisabled);
  });

  testWidgets('담당 트레이너가 없을 때 누르면 이유를 알린다', (WidgetTester tester) async {
    await pump(
      tester,
      coachOverride: memberCoachProvider.overrideWith((ref) async => null),
    );

    await tester.tap(find.byKey(const Key('trainerChatHeaderButton')));
    await tester.pumpAndSettle();

    // 흐리게 그리되 아무 반응도 없지는 않다 — 왜 못 쓰는지 말해 준다.
    expect(
      find.text('담당 트레이너가 아직 없어요. 운동 탭에서 헬스장·트레이너를 연결해 보세요'),
      findsOneWidget,
    );
  });

  testWidgets('조회 중에는 없다고 단정하지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // 끝나지 않는 Future — 로딩 상태로 붙잡아 둔다.
          memberCoachProvider.overrideWith(
            (ref) => Completer<MemberCoach?>().future,
          ),
          coachUnreadProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: TrainerChatHeaderButton()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('trainerChatHeaderButton')));
    await tester.pump();

    // 로딩 중에 "트레이너가 없다" 고 말하면 거짓이 된다.
    expect(find.text('담당 트레이너를 불러오는 중이에요'), findsOneWidget);
  });
}
