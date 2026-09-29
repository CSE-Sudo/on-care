/// 고객이 그날 한 운동 **한 종목**. (#1902)
///
/// 예전에는 이름 문자열 하나였고, 세트·횟수·중량은 그 이름 안에 적혀 있었다
/// (`레그프레스 70kg · 4세트`). 서버는 같은 값을 `sets`·`reps`·`weight` 칸으로
/// 내려보내는데 앱이 이름만 읽어서, 이름을 쓰는 화면과 필드를 읽는 화면이 같은
/// 기록을 다르게 말했다.
///
/// 한 줄로 읽히는 표기는 화면이 만든다 — `세트`·`회`·`kg` 은 로케일을 타는
/// 문구라, 여기서 이어 붙이면 영어 화면에 한글이 새어 나온다(#1933).
class ClientExerciseItem {
  const ClientExerciseItem({
    required this.name,
    this.type = '',
    this.minutes = 0,
    this.sets,
    this.reps,
    this.holdSeconds,
    this.durationSeconds,
    this.weight,
    this.intensity,
    this.done = true,
    this.source = '',
    this.assignedRoutineId,
  });

  /// 이름만 아는 옛 기록. 값이 이름 문자열에 섞여 있던 시절의 자료와, 이름만
  /// 싣던 응답이 여기로 떨어진다 — 그때는 적힌 그대로 보여 준다.
  /// `벤치프레스 ✓` 처럼 수행 표시가 붙어 있던 줄도 받는다.
  factory ClientExerciseItem.nameOnly(String raw) => ClientExerciseItem(
    name: raw.replaceAll(RegExp(r'\s*[✓✗]\s*'), ' ').trim(),
    done: !raw.contains('✗'),
  );

  /// 한국어 문장으로 저장된 옛 기록 한 줄을 값으로 되돌린다. (#2300)
  ///
  /// 완료한 PT 세션과 시드는 `스쿼트 3세트 12회 40kg`·`스쿼트 3세트 · 12회 ·
  /// 40kg ✓` 처럼 단위가 한국어로 박힌 문장을 저장한다. 그대로 그리면 영어
  /// 화면에도 `세트`·`회` 가 나오므로, 단위가 이름 **끝에** 이어 붙은 모양만
  /// 값으로 읽는다. 그 밖의 줄은 [ClientExerciseItem.nameOnly] 와 같다. 서버
  /// `parse_history_exercise` 와 같은 규칙이다.
  factory ClientExerciseItem.fromLegacyLine(String raw) {
    final bool done = !raw.contains('✗');
    final String body = raw
        .replaceAll(RegExp(r'\s*[✓✗]\s*'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .join(' ');
    final RegExpMatch? tail = _legacyAmountTail.firstMatch(body);
    final String name = tail == null
        ? body
        : body
              .substring(0, tail.start)
              .trim()
              .replaceAll(RegExp(r'·$'), '')
              .trim();
    if (tail == null || name.isEmpty) {
      return ClientExerciseItem(name: body, done: done);
    }
    final Map<String, String> amounts = <String, String>{};
    for (final RegExpMatch m in _legacyAmount.allMatches(tail.group(0)!)) {
      // 같은 단위가 두 번 적힌 줄은 없다 — 있으면 처음 것을 믿는다.
      amounts.putIfAbsent(m.group(2)!, () => m.group(1)!);
    }
    int? asInt(String unit) {
      final String? value = amounts[unit];
      return value == null ? null : double.parse(value).toInt();
    }

    final String? weight = amounts['kg'];
    final bool strength = <String>[
      '세트',
      '회',
      '초',
      'kg',
    ].any(amounts.containsKey);
    return ClientExerciseItem(
      name: name,
      type: strength ? 'strength' : '',
      minutes: asInt('분') ?? 0,
      sets: asInt('세트'),
      reps: asInt('회'),
      holdSeconds: asInt('초'),
      weight: weight == null ? null : double.parse(weight),
      done: done,
    );
  }

  factory ClientExerciseItem.fromJson(Map<String, Object?> json) =>
      ClientExerciseItem(
        name: (json['name'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
        sets: (json['sets'] as num?)?.toInt(),
        reps: (json['reps'] as num?)?.toInt(),
        holdSeconds: (json['hold_seconds'] as num?)?.toInt(),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        weight: (json['weight'] as num?)?.toDouble(),
        intensity: switch (json['intensity']) {
          final String value when value.isNotEmpty => value,
          _ => null,
        },
        done: json['done'] as bool? ?? true,
        source: (json['source'] as String?) ?? '',
        assignedRoutineId: switch (json['assigned_routine_id']) {
          final String value when value.isNotEmpty => value,
          _ => null,
        },
      );

  final String name;

  /// `cardio` | `strength` | `stretching` | `other`. 비어 있으면 모른다.
  final String type;

  final int minutes;

  /// 근력의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 null 이다.
  final int? sets;
  final int? reps;

  /// 버티는 운동이면 한 세트를 버틴 시간(초). [reps] 와 한 자리를 나눠 쓴다 —
  /// 플랭크를 `3회` 로 적으면 45초를 "3회" 라고 말하게 된다(#1969).
  final int? holdSeconds;

  /// 유산소·스트레칭·기타에 쓴 시간(초). 회원 앱이 시·분·초로 적는다(#2071) —
  /// [minutes] 는 여기서 반올림한 값이라 `45초` 가 `1분` 으로 보였다. 초를
  /// 싣지 않는 옛 기록·응답은 비어 있다 — [seconds] 로 읽는다.
  final int? durationSeconds;

  /// 이 운동에 쓴 시간(초). 초가 없으면 분 × 60 이다.
  int get seconds => durationSeconds ?? minutes * 60;

  final double? weight;

  /// `light` | `moderate` | `high`. 강도를 적은 기록(배정 수행)만 있다(#2300).
  final String? intensity;

  /// 실제로 했는가. 운동 기록 탭이 ✓/✗ 로 그린다 — 배정만 되고 하지 않은 항목도
  /// 이력에는 남는다.
  final bool done;

  /// 기록 출처 — `member` | `trainer_pt` | `assigned_routine`. 운동 행 응답만
  /// 싣는다. 비어 있으면 모른다(이력 줄·데모·옛 응답).
  final String source;

  /// 배정 운동을 완료해 생긴 행이면 그 배정 id. 서버 옛 시드는 출처를
  /// `member` 로 둔 채 이 값만 채운다.
  final String? assignedRoutineId;

  /// 회원이 앱에서 **직접 적은** 기록인가. (#2534)
  ///
  /// PT 완료·배정 운동 완료로 생긴 행은 이력 카드가 이미 말한다 — 그 행까지
  /// 직접 기록으로 붙이면 같은 운동이 두 번 나온다. 출처를 모르는 행도 여기
  /// 들지 않는다: 직접 적었다고 확인되지 않은 것을 그렇게 부르지 않는다.
  bool get isMemberLog => source == 'member' && assignedRoutineId == null;

  /// 이름 말고 적힌 값이 하나라도 있는가.
  bool get hasAmount =>
      sets != null || reps != null || holdSeconds != null || seconds > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (type.isNotEmpty) 'type': type,
    if (minutes > 0) 'minutes': minutes,
    if (sets != null) 'sets': sets,
    if (reps != null) 'reps': reps,
    if (holdSeconds != null) 'hold_seconds': holdSeconds,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
    if (weight != null) 'weight': weight,
    if (intensity != null) 'intensity': intensity,
    if (!done) 'done': done,
    if (source.isNotEmpty) 'source': source,
    if (assignedRoutineId != null) 'assigned_routine_id': assignedRoutineId,
  };
}

/// 옛 기록 문장 끝에 붙는 양 — `3세트`·`12회`·`60초`·`40kg`·`25분` 이 공백이나
/// `·` 로 이어진다.
final RegExp _legacyAmountTail = RegExp(
  r'(?:(?:\s*·\s*|\s+)\d+(?:\.\d+)?(?:세트|회|초|kg|분))+\s*$',
);
final RegExp _legacyAmount = RegExp(r'(\d+(?:\.\d+)?)(세트|회|초|kg|분)');
