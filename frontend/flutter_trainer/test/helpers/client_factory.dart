import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// Builds a [TrainerClient] with sane defaults so a test only states the
/// fields it actually cares about.
///
/// Defaults describe a client with nothing wrong: under the sodium
/// target, a fully recorded week at 80% completion, active.
TrainerClient makeClient({
  String id = 'c1',
  String name = '테스트회원',
  String goal = '체중 감량',
  bool active = true,
  int calories = 1800,
  int sodiumMg = 1500,
  double sugarG = 30,
  double carbsG = 0,
  double proteinG = 0,
  double fatG = 0,
  String lastMessage = '안녕하세요',
  String lastTime = '방금',
  String lastRoutine = '오늘',
  List<int>? weekCompletion,
  List<int>? sodiumWeek,
}) {
  return TrainerClient(
    id: id,
    name: name,
    avatar: name.isEmpty ? '?' : String.fromCharCode(name.runes.first),
    goal: goal,
    lastMessage: lastMessage,
    lastTime: lastTime,
    active: active,
    calories: calories,
    sodiumMg: sodiumMg,
    sugarG: sugarG,
    carbsG: carbsG,
    proteinG: proteinG,
    fatG: fatG,
    lastRoutine: lastRoutine,
    weekCompletion: weekCompletion ?? const <int>[80, 80, 80, 80, 80, 80, 80],
    sodiumWeek:
        sodiumWeek ?? const <int>[1500, 1500, 1500, 1500, 1500, 1500, 1500],
  );
}
