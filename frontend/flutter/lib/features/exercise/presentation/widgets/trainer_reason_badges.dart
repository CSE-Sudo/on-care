import 'package:flutter/material.dart';

import 'package:oncare_ui/oncare_ui.dart';

/// 추천 이유를 알약으로 늘어놓는 줄 (#1445 · #1847 · #1881).
///
/// 같은 근거를 헬스장 찾기 트레이너 줄·트레이너 목록 카드·트레이너 상세가 함께
/// 쓴다. 세 곳이 제각기 그리면 같은 값이 화면마다 다른 모양으로 읽혀, 목록에서
/// 본 것을 상세에서 다시 찾아야 한다.
///
/// 근거가 없을 때 무엇을 적을지는 화면마다 다르다(찾기 줄은 아무것도 적지 않고,
/// 상세는 기본 문구로 박스를 채운다). 그래서 빈 목록 처리는 여기서 하지 않고
/// 부르는 쪽에 맡긴다 — 이 위젯은 "있는 만큼 알약으로 세운다"만 한다.
class TrainerReasonBadges extends StatelessWidget {
  const TrainerReasonBadges({
    required this.reasons,
    required this.keyPrefix,
    super.key,
  });

  final List<String> reasons;

  /// 화면마다 제 키를 갖는다 — 묶음은 `<접두어>-reasons`, 낱개는
  /// `<접두어>-reason-<순번>`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    key: ValueKey<String>('$keyPrefix-reasons'),
    spacing: OnCareSpacing.s4,
    runSpacing: OnCareSpacing.s4,
    children: <Widget>[
      for (final (int i, String reason) in reasons.indexed)
        _ReasonBadge(
          // 형제끼리 같은 키를 쓸 수 없어 순번을 붙인다. 사유 문구를 키로 쓰면
          // 같은 키워드를 두 번 단 순간 같은 키가 된다.
          key: ValueKey<String>('$keyPrefix-reason-$i'),
          reason: reason,
        ),
    ],
  );
}

/// 추천 이유 하나를 담는 알약.
///
/// 추천 이유는 고를 근거다 — 흰 배경에 회색 글씨면 옆의 일반 설명과 위계가
/// 같아진다. 트레이너 목록·상세가 이미 쓰는 브랜드 파랑으로 윤곽선과 글자를
/// 맞춘다(#1445). 배경은 흰색 그대로다 — 헬스장 찾기 줄 자체가 옅은 파랑이라
/// 배지까지 파래지면 배지가 사라진다. 상세의 자격증 태그(`AppTag`)가 옅은
/// 파랑으로 채운 알약이라, 윤곽선 알약은 그 옆에서도 근거임이 구분된다.
class _ReasonBadge extends StatelessWidget {
  const _ReasonBadge({required this.reason, super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s8,
        vertical: OnCareSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: Border.all(color: tokens.brand.border),
        borderRadius: OnCareRadius.pillAll,
      ),
      child: Text(
        // 사유만 적는다 — 앞에 `추천 이유:` 를 붙이면 읽는 사람은 매번 라벨을
        // 먼저 지나치고 나서야 정작 볼 것을 만나고, 길어진 글자가 알약을 줄
        // 끝까지 늘려 배지가 아니라 한 문장처럼 읽힌다 (#1847). 무엇을 적은
        // 자리인지는 알약 모양이 이미 말하고 있다.
        reason,
        maxLines: 2,
        // 두 줄을 넘기면 줄여 적는다 — 큰 배율에서 배지가 카드 밖으로 밀려
        // 나가지 않게.
        overflow: TextOverflow.ellipsis,
        style: tokens
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(color: tokens.brand.primary),
      ),
    );
  }
}
