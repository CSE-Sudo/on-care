import 'dart:async';

import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';

/// 데모에서 트레이너가 코드를 입력하기까지 걸리는 시간. 회원이 코드를 불러 주고
/// 트레이너가 받아 적는 사이만큼 둔다.
const Duration demoPairingEntryDelay = Duration(seconds: 6);

/// 데모의 동기화 코드 저장소 — 발급·취소는 실서비스와 같은 경로를 타고, **코드를
/// 입력해 줄 트레이너**만 대신한다. (#3342)
///
/// 실서버에서는 트레이너가 웹에 코드를 넣는 순간 담당 연결이 생기고, 회원의
/// 시트가 그것을 확인해 `연결됐어요` 로 바뀐다. 데모에는 그 트레이너가 없어
/// 코드를 띄워도 시트가 끝까지 코드만 보여 줬다. 코드를 발급하고 [entryDelay] 가
/// 지나면 [onCodeEntered] 를 불러 데모의 연결 상태를 잇는다 — 연결 상태는 헬스장
/// 저장소가 들고 있어 이 저장소는 누구와 잇는지 모른다.
///
/// 시트를 닫으면(= [revoke]) 입력도 없던 일이 된다. 실서버에서도 버린 코드는
/// 쓸 수 없다.
class DemoTrainerSyncRepository extends TrainerSyncRepository {
  DemoTrainerSyncRepository(
    super.dio, {
    required void Function() onCodeEntered,
    Duration entryDelay = demoPairingEntryDelay,
  }) : _onCodeEntered = onCodeEntered,
       _entryDelay = entryDelay;

  final void Function() _onCodeEntered;
  final Duration _entryDelay;
  Timer? _entry;

  @override
  Future<PairingCode> issue() async {
    final PairingCode issued = await super.issue();
    // 다시 받으면(만료 뒤 `새 코드 받기`) 입력도 그때부터 다시 센다.
    _entry?.cancel();
    _entry = Timer(_entryDelay, _onCodeEntered);
    return issued;
  }

  @override
  Future<void> revoke() async {
    _cancelEntry();
    await super.revoke();
  }

  /// provider 가 사라질 때 부른다 — 남은 타이머가 사라진 저장소를 건드리지 않게.
  void dispose() => _cancelEntry();

  void _cancelEntry() {
    _entry?.cancel();
    _entry = null;
  }
}
