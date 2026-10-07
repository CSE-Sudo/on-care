import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';

/// 끝난 PT 에 남아 있는 개인운동 — 보낼 수 있는데 아직 안 보낸 것. (#2225)
///
/// 위젯이 아니라 provider 가 들고 있다. 보낸 뒤 이 자리를 다시 읽어야 하는데,
/// 위젯이 제 상태에 들고 있으면 그 사이 다시 그려져 상태가 버려질 때 읽기가
/// 조용히 사라진다 — 보냈는데 알림이 그대로 남는다.
///
/// 코칭 탭 밖에 두는 까닭: 탭은 `StatefulShellRoute.indexedStack` 이라 스케줄로
/// 건너가도 코칭 탭이 살아 있어 이 값을 계속 쥐고 있다. 스케줄 탭에서 보내거나
/// 보내지 않기로 정리한 뒤 스케줄 쪽이 직접 무효화해야 돌아왔을 때 맞는다.
final unsentRoutinesProvider = FutureProvider.autoDispose
    .family<List<UnsentRoutine>, String>(
      (ref, clientId) => ref
          .watch(scheduleRepositoryProvider)
          .fetchUnsentRoutinesFor(clientId),
    );

/// 가장 최근에 보낸 것 한 묶음. (#2225) — 무효화 규칙은
/// [unsentRoutinesProvider] 와 같다.
final latestDeliveryProvider = FutureProvider.autoDispose
    .family<SentDelivery?, String>(
      (ref, clientId) => ref
          .watch(trainerRoutineRepositoryProvider)
          .fetchLatestDelivery(clientId),
    );

/// 회원에게 무엇이 나갔는지가 바뀐 뒤 코칭 탭의 두 읽기를 버린다.
///
/// 어느 회원인지 모를 수 있는 자리(스케줄)에서도 부르도록 family 전체를
/// 버린다 — 살아 있는 것은 지금 열린 회원 하나뿐이라 비용이 없다.
void invalidateDeliveryStatus(WidgetRef ref) {
  ref
    ..invalidate(unsentRoutinesProvider)
    ..invalidate(latestDeliveryProvider);
}
