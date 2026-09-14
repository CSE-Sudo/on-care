import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `[아이콘] 제목 … [기간 토글]` 한 줄, 그 아래 카드. — 회원 앱 `영양 요약`·
/// `운동 현황` 과 같은 구조다. (#943, #944)
///
/// 토글을 **카드 밖**에 두는 것이 요점이다. 카드 제목 줄 안에 넣었더니, 기간을
/// 바꿀 때 카드가 통째로 갈리면서 제목 길이가 달라져 토글이 좌우로 움직였다.
/// 방금 누른 자리가 옮겨 가 다음 기간을 누르려면 눈으로 다시 찾아야 했다.
/// 헤더는 기간과 무관하게 늘 같은 것을 그리므로 자리가 고정된다.
///
/// **이름은 여기가, 카드는 그림만.** 예전에는 식단 기간 카드만 자기 제목과
/// 아이콘을 들고 있어, 기간을 바꿀 때마다 제목이 나타났다 사라졌다(#944).
/// 카드 안에 남는 글자는 `오늘 섭취 칼로리`·`하루 평균 · 칼로리` 같은 **내용
/// 라벨**뿐이다 — 회원 앱이 쓰는 구조와 같다.
class ClientPeriodSection extends StatelessWidget {
  /// Creates the section.
  const ClientPeriodSection({
    super.key,
    required this.icon,
    required this.title,
    required this.period,
    required this.onChanged,
    required this.child,
  });

  /// 제목 앞 아이콘 — 식단·운동을 자리로 구분한다.
  final IconData icon;

  /// 섹션 제목 — `영양 요약` · `운동 현황`.
  final String title;

  final ClientPeriod period;
  final ValueChanged<ClientPeriod> onChanged;

  /// 기간에 따라 갈리는 본문.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          key: const ValueKey<String>('client-period-section-header'),
          // 남는 폭은 제목과 토글 **사이**로 간다. 제목을 `Expanded` 로 늘리면
          // 제목이 절반을 tight 로 가져가고, 그 절반을 다 쓰지 않은 토글의
          // 잔여분이 줄 끝에 빈 자리로 쌓여 토글이 가운데에 뜬다.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // 제목·토글 둘 다 접힌다. 좁은 열·큰 글자 배율에서 제목이 토글을
            // 밀어내 줄이 넘치면 안 된다.
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: OnCareSpacing.s8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 아이콘·간격·글자는 `AppSectionHeader` 와 같은 규격이다.
                    // 그 위젯은 제목을 `Expanded` 로 늘려 토글 자리를 밀어내므로
                    // 같은 값으로 이 자리에서 조립한다.
                    Icon(
                      icon,
                      size: OnCareSize.iconMedium,
                      color: tokens.brand.primary,
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AppSegmentedToggle<ClientPeriod>(
                  key: const ValueKey<String>('client-period-toggle'),
                  segments: clientPeriodSegments(l),
                  selected: period,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        child,
      ],
    );
  }
}

/// `오늘 / 이번 주 / 전체` 세그먼트 — 회원 앱 식단·운동 탭의 같은 토글과 문구도
/// 순서도 같다. (#914)
List<AppSegment<ClientPeriod>> clientPeriodSegments(AppLocalizations l) =>
    <AppSegment<ClientPeriod>>[
      for (final ClientPeriod period in ClientPeriod.values)
        AppSegment<ClientPeriod>(
          value: period,
          label: switch (period) {
            ClientPeriod.today => l.clientPeriodToday,
            ClientPeriod.week => l.clientPeriodWeek,
            ClientPeriod.month => l.clientPeriodMonth,
          },
        ),
    ];
