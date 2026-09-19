import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/streak_shield_repository.dart';

/// 위젯 테스트용 보호권 저장소 — 넣어 준 상태를 돌려주고 사용한 날을 기록한다.
class FakeStreakShieldRepository implements StreakShieldRepository {
  FakeStreakShieldRepository({StreakShields? shields, this.onUse})
    : shields = shields ?? const StreakShields(held: 0, maxHeld: 2, cost: 300);

  StreakShields shields;

  /// 사용이 끝난 뒤 부른다 — 운동 주간 대역을 보호한 상태로 바꾸는 데 쓴다.
  final void Function(DateTime date)? onUse;

  final List<DateTime> used = <DateTime>[];
  int fetchCalls = 0;

  @override
  Future<StreakShields> fetch() async {
    fetchCalls++;
    return shields;
  }

  @override
  Future<StreakShields> use(DateTime date) async {
    used.add(date);
    shields = StreakShields(
      held: shields.held > 0 ? shields.held - 1 : 0,
      maxHeld: shields.maxHeld,
      cost: shields.cost,
      used: <StreakShieldUse>[StreakShieldUse(date: date), ...shields.used],
    );
    onUse?.call(date);
    return shields;
  }
}
