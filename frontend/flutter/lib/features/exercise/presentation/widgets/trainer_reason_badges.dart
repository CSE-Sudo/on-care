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
        AppTag(
          // 형제끼리 같은 키를 쓸 수 없어 순번을 붙인다. 사유 문구를 키로 쓰면
          // 같은 키워드를 두 번 단 순간 같은 키가 된다.
          key: ValueKey<String>('$keyPrefix-reason-$i'),
          label: reason,
          tone: AppTagTone.brand,
        ),
    ],
  );
}
