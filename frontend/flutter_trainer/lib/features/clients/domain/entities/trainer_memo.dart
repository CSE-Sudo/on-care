/// Where a memo came from.
///
/// All kinds live in one list on the client detail screen — the trainer
/// cares about "what did I record about this member", not about which screen
/// created the row.
enum TrainerMemoSource {
  /// Written by the trainer on the client detail screen.
  trainer,

  /// Saved from a signal detected in the member's chat messages.
  chatInsight,

  /// Left from a record card on the client detail workout tab (#2332).
  exerciseMemo;

  /// The backend wire value (`source` on `/trainer/clients/{id}/memos`).
  String get wire => switch (this) {
    TrainerMemoSource.trainer => 'trainer',
    TrainerMemoSource.chatInsight => 'chat_insight',
    TrainerMemoSource.exerciseMemo => 'exercise_memo',
  };

  static TrainerMemoSource fromWire(String? value) => switch (value) {
    'chat_insight' => TrainerMemoSource.chatInsight,
    'exercise_memo' => TrainerMemoSource.exerciseMemo,
    _ => TrainerMemoSource.trainer,
  };
}

/// Which kind of workout record an exercise memo points at. (#2332)
enum TrainerMemoRefKind {
  /// A PT session the trainer ran.
  ptSession,

  /// A personal workout — an assigned routine or an AI personal routine.
  personal,

  /// The member's own logs for one day (one card per day, no id).
  memberLog;

  String get wire => switch (this) {
    TrainerMemoRefKind.ptSession => 'pt_session',
    TrainerMemoRefKind.personal => 'personal',
    TrainerMemoRefKind.memberLog => 'member_log',
  };

  static TrainerMemoRefKind? fromWire(String? value) => switch (value) {
    'pt_session' => TrainerMemoRefKind.ptSession,
    'personal' => TrainerMemoRefKind.personal,
    'member_log' => TrainerMemoRefKind.memberLog,
    _ => null,
  };
}

/// The workout record an exercise memo was left from. (#2332)
///
/// The server fills these from the record itself; the app only says which
/// card was tapped ([id] for a history card, [day] for a member-log card).
/// Kept on the memo so its source tag survives the record being removed.
class TrainerMemoRef {
  const TrainerMemoRef({required this.kind, this.id, this.day, this.name = ''});

  final TrainerMemoRefKind kind;

  /// The history row id. Null for a member-log card.
  final String? id;

  /// The day the record belongs to (`YYYY-MM-DD`, KST).
  final String? day;

  /// A routine name the trainer gave. Empty for fixed names — the app
  /// translates those itself.
  final String name;
}

/// A memo a trainer keeps about one member. Never shown to the member.
class TrainerMemo {
  const TrainerMemo({
    required this.id,
    required this.body,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.insightId,
    this.insightKind = '',
    this.ref,
  });

  final String id;
  final String body;
  final TrainerMemoSource source;

  /// Identifier of the chat insight this memo was saved from. Memos written
  /// by hand have none — saving the same insight twice must not add a second
  /// memo, and this is the key that enforces it (server-side and locally).
  final String? insightId;

  /// `discomfort` / `negativeFeedback` for chat-insight memos, empty
  /// otherwise. Kept so the demo's local memos keep their label.
  final String insightKind;

  /// The workout record an exercise memo was left from; null otherwise.
  final TrainerMemoRef? ref;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 본문을 고친 적이 있는가. 작성과 거의 같은 순간의 저장(서버가 두 시각을
  /// 따로 찍는 몇 ms 차이)은 고친 것으로 치지 않는다.
  bool get isEdited => updatedAt.difference(createdAt).inSeconds >= 1;

  factory TrainerMemo.fromJson(Map<String, Object?> json) {
    final TrainerMemoRefKind? refKind = TrainerMemoRefKind.fromWire(
      json['ref_kind'] as String?,
    );
    return TrainerMemo(
      id: json['id']! as String,
      body: json['body'] as String? ?? '',
      source: TrainerMemoSource.fromWire(json['source'] as String?),
      insightId: json['insight_id'] as String?,
      insightKind: json['insight_kind'] as String? ?? '',
      ref: refKind == null
          ? null
          : TrainerMemoRef(
              kind: refKind,
              id: json['ref_id'] as String?,
              day: json['ref_date'] as String?,
              name: json['ref_name'] as String? ?? '',
            ),
      createdAt: DateTime.parse(json['created_at']! as String),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? json['created_at']! as String,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'body': body,
    'source': source.wire,
    'insight_id': insightId,
    'insight_kind': insightKind,
    'ref_kind': ref?.kind.wire,
    'ref_id': ref?.id,
    'ref_date': ref?.day,
    'ref_name': ref?.name ?? '',
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  TrainerMemo copyWith({String? body, DateTime? updatedAt}) => TrainerMemo(
    id: id,
    body: body ?? this.body,
    source: source,
    insightId: insightId,
    insightKind: insightKind,
    ref: ref,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
