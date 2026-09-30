/// 트레이너 대화를 쪽 단위로 받고 합치는 규칙. (#2640)
///
/// 서버는 대화를 한 번에 최신 [chatPageSize] 건만 주고, 그 앞은 가장 오래된
/// 메시지를 커서로 넘겨 받는다. 쪽을 여럿 받으면 그 사이가 겹치거나 비지 않게
/// 합쳐야 하는데, 이 일을 화면·provider 마다 따로 하면 규칙이 갈라진다. 그래서
/// 여기 순수 함수로 모은다.
library;

import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';

/// 대화 순서 — 시각이 먼저, 같은 시각이면 id. (#2127)
///
/// 서버 커서(`before`, `before_id`)도 같은 짝으로 가른다.
int compareCoachMessages(CoachMessage first, CoachMessage second) {
  final int byTime = first.createdAt.compareTo(second.createdAt);
  return byTime != 0 ? byTime : first.id.compareTo(second.id);
}

/// [older] 와 [newer] 를 id 로 합쳐 오래된→최신으로 돌려준다.
///
/// 같은 id 가 양쪽에 있으면 [newer] 쪽을 쓴다 — 나중에 받은 것이 서버의
/// 지금 모습이다(첨부가 채워졌거나 글이 바뀐 경우). 순서는 받은 차례가 아니라
/// [compareCoachMessages] 로 정한다.
List<CoachMessage> mergeCoachThread(
  Iterable<CoachMessage> older,
  Iterable<CoachMessage> newer,
) {
  final Map<String, CoachMessage> byId = <String, CoachMessage>{
    for (final CoachMessage m in older) m.id: m,
  };
  for (final CoachMessage m in newer) {
    byId[m.id] = m;
  }
  return byId.values.toList()..sort(compareCoachMessages);
}

/// [all] 에서 서버가 줄 한 쪽을 잘라 준다 — [before] 보다 앞선 것 중 최신
/// [size] 건(오래된→최신).
///
/// 데모 저장소와 테스트 대역이 서버와 **같은 쪽**을 주게 하려고 둔다. 데모가
/// 언제나 전부를 주면 쪽 사이의 경계가 데모에서만 없어 보인다.
List<CoachMessage> pageCoachChat(
  Iterable<CoachMessage> all, {
  CoachMessage? before,
  int size = chatPageSize,
}) {
  final List<CoachMessage> sorted = all.toList()..sort(compareCoachMessages);
  final List<CoachMessage> earlier = before == null
      ? sorted
      : <CoachMessage>[
          for (final CoachMessage m in sorted)
            if (compareCoachMessages(m, before) < 0) m,
        ];
  final int start = earlier.length > size ? earlier.length - size : 0;
  return earlier.sublist(start);
}
