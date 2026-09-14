import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 상담 요청 인박스로 가는 헤더 액션. (#858, #882, #987)
///
/// 처음에는 화면 폭 전체를 쓰는 남색 그라디언트 카드였다. 면적은 제일 큰데
/// 정작 몇 건 밀렸는지가 눈에 꽂히지 않았고 — 알림이 아니라 배너로 읽혔다 —
/// 타임라인에서 세로 공간까지 빼앗았다.
///
/// 지금은 아이콘 버튼 위에 **빨간 배지**를 얹은 헤더 액션이다. 알림을 알림으로
/// 읽히게 하는 가장 익숙한 표현이고, 헤더 액션 줄에서 가장 적은 폭을 쓴다.
/// 라벨을 함께 두면 영어 로케일·큰 글자 배율에서 줄 전체가 넘친다 — #849
/// 관문이 폭 1024·en·배율 1.3 에서 그것을 잡았다. 이름은 툴팁으로 남는다.
///
/// 배지는 **아이콘이 아니라 버튼 네모의 오른쪽 위 모서리**에 걸친다(#987).
/// 아이콘 위에 얹으면 빨간 원이 아이콘의 절반 가까이를 덮어 무슨 버튼인지
/// 형태로 알아볼 수 없었다. 네모 밖으로 나가는 만큼은 자리를 비우지 않는다 —
/// `Clip.none` 으로 그리므로 잘리지 않고, 옆 버튼과 같은 높이를 지킨다(#1013).
///
/// 빨강은 처리할 것이 있을 때만 뜬다: 0건이거나 아직 못 읽었으면([pending] 이
/// null) 배지 없이 조용한 버튼으로 남는다.
class ConsultationInboxAction extends StatelessWidget {
  const ConsultationInboxAction({
    super.key,
    required this.pending,
    required this.onTap,
  });

  /// 대기 중인 상담 요청 수. 아직 불러오지 못했으면 null.
  final int? pending;

  final VoidCallback onTap;

  /// 배지가 버튼 네모 밖으로 나가는 양. 배지(최소 20)의 가운데가 네모의 위
  /// 모서리 근처에 오고, 왼쪽 끝이 아이콘 오른쪽 끝에 닿는 값이다.
  static const double _badgeOverflowTop = OnCareSpacing.s8;
  static const double _badgeOverflowRight = OnCareSpacing.s12;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int count = pending ?? 0;

    return Stack(
      // 키는 액션 전체에 둔다 — 배지가 탭 대상(아이콘 버튼)의 바깥이라, 키가
      // 안쪽에 있으면 배지를 이 액션의 자손으로 찾을 수 없다.
      key: const Key('consult-inbox-entry'),
      clipBehavior: Clip.none,
      children: <Widget>[
        AppIconButton(
          icon: Icons.mark_email_unread_rounded,
          tooltip: l.consultTitle,
          variant: AppIconButtonVariant.tonal,
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            top: -_badgeOverflowTop,
            right: -_badgeOverflowRight,
            // 배지는 숫자를 더하는 표시일 뿐 누르는 대상이 아니다 — 탭이
            // 배지에 걸려 버튼에 닿지 않는 일이 없게 한다.
            child: IgnorePointer(child: AppCountBadge(count: count)),
          ),
      ],
    );
  }
}
