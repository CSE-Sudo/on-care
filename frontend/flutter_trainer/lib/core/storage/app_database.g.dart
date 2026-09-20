// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppKeyValuesTable extends AppKeyValues
    with TableInfo<$AppKeyValuesTable, AppKeyValue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppKeyValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_key_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppKeyValue> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppKeyValue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppKeyValue(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppKeyValuesTable createAlias(String alias) {
    return $AppKeyValuesTable(attachedDatabase, alias);
  }
}

class AppKeyValue extends DataClass implements Insertable<AppKeyValue> {
  final String key;
  final String value;
  const AppKeyValue({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppKeyValuesCompanion toCompanion(bool nullToAbsent) {
    return AppKeyValuesCompanion(key: Value(key), value: Value(value));
  }

  factory AppKeyValue.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppKeyValue(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppKeyValue copyWith({String? key, String? value}) =>
      AppKeyValue(key: key ?? this.key, value: value ?? this.value);
  AppKeyValue copyWithCompanion(AppKeyValuesCompanion data) {
    return AppKeyValue(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppKeyValue(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppKeyValue &&
          other.key == this.key &&
          other.value == this.value);
}

class AppKeyValuesCompanion extends UpdateCompanion<AppKeyValue> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppKeyValuesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppKeyValuesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppKeyValue> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppKeyValuesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppKeyValuesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppKeyValuesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrainerClientsTable extends TrainerClients
    with TableInfo<$TrainerClientsTable, TrainerClientRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrainerClientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalMeta = const VerificationMeta('goal');
  @override
  late final GeneratedColumn<String> goal = GeneratedColumn<String>(
    'goal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastMessageMeta = const VerificationMeta(
    'lastMessage',
  );
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
    'last_message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastTimeMeta = const VerificationMeta(
    'lastTime',
  );
  @override
  late final GeneratedColumn<String> lastTime = GeneratedColumn<String>(
    'last_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _caloriesTodayMeta = const VerificationMeta(
    'caloriesToday',
  );
  @override
  late final GeneratedColumn<int> caloriesToday = GeneratedColumn<int>(
    'calories_today',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sodiumMgMeta = const VerificationMeta(
    'sodiumMg',
  );
  @override
  late final GeneratedColumn<int> sodiumMg = GeneratedColumn<int>(
    'sodium_mg',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sugarGMeta = const VerificationMeta('sugarG');
  @override
  late final GeneratedColumn<double> sugarG = GeneratedColumn<double>(
    'sugar_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbsGMeta = const VerificationMeta('carbsG');
  @override
  late final GeneratedColumn<double> carbsG = GeneratedColumn<double>(
    'carbs_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastRoutineMeta = const VerificationMeta(
    'lastRoutine',
  );
  @override
  late final GeneratedColumn<String> lastRoutine = GeneratedColumn<String>(
    'last_routine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekCompletionJsonMeta =
      const VerificationMeta('weekCompletionJson');
  @override
  late final GeneratedColumn<String> weekCompletionJson =
      GeneratedColumn<String>(
        'week_completion_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _sodiumWeekJsonMeta = const VerificationMeta(
    'sodiumWeekJson',
  );
  @override
  late final GeneratedColumn<String> sodiumWeekJson = GeneratedColumn<String>(
    'sodium_week_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _caloriesWeekJsonMeta = const VerificationMeta(
    'caloriesWeekJson',
  );
  @override
  late final GeneratedColumn<String> caloriesWeekJson = GeneratedColumn<String>(
    'calories_week_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _sugarWeekJsonMeta = const VerificationMeta(
    'sugarWeekJson',
  );
  @override
  late final GeneratedColumn<String> sugarWeekJson = GeneratedColumn<String>(
    'sugar_week_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ageMeta = const VerificationMeta('age');
  @override
  late final GeneratedColumn<int> age = GeneratedColumn<int>(
    'age',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatar,
    goal,
    lastMessage,
    lastTime,
    active,
    caloriesToday,
    sodiumMg,
    sugarG,
    carbsG,
    proteinG,
    fatG,
    lastRoutine,
    weekCompletionJson,
    sodiumWeekJson,
    caloriesWeekJson,
    sugarWeekJson,
    sortOrder,
    gender,
    age,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trainer_clients';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrainerClientRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    } else if (isInserting) {
      context.missing(_avatarMeta);
    }
    if (data.containsKey('goal')) {
      context.handle(
        _goalMeta,
        goal.isAcceptableOrUnknown(data['goal']!, _goalMeta),
      );
    } else if (isInserting) {
      context.missing(_goalMeta);
    }
    if (data.containsKey('last_message')) {
      context.handle(
        _lastMessageMeta,
        lastMessage.isAcceptableOrUnknown(
          data['last_message']!,
          _lastMessageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastMessageMeta);
    }
    if (data.containsKey('last_time')) {
      context.handle(
        _lastTimeMeta,
        lastTime.isAcceptableOrUnknown(data['last_time']!, _lastTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_lastTimeMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('calories_today')) {
      context.handle(
        _caloriesTodayMeta,
        caloriesToday.isAcceptableOrUnknown(
          data['calories_today']!,
          _caloriesTodayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_caloriesTodayMeta);
    }
    if (data.containsKey('sodium_mg')) {
      context.handle(
        _sodiumMgMeta,
        sodiumMg.isAcceptableOrUnknown(data['sodium_mg']!, _sodiumMgMeta),
      );
    } else if (isInserting) {
      context.missing(_sodiumMgMeta);
    }
    if (data.containsKey('sugar_g')) {
      context.handle(
        _sugarGMeta,
        sugarG.isAcceptableOrUnknown(data['sugar_g']!, _sugarGMeta),
      );
    } else if (isInserting) {
      context.missing(_sugarGMeta);
    }
    if (data.containsKey('carbs_g')) {
      context.handle(
        _carbsGMeta,
        carbsG.isAcceptableOrUnknown(data['carbs_g']!, _carbsGMeta),
      );
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    }
    if (data.containsKey('last_routine')) {
      context.handle(
        _lastRoutineMeta,
        lastRoutine.isAcceptableOrUnknown(
          data['last_routine']!,
          _lastRoutineMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastRoutineMeta);
    }
    if (data.containsKey('week_completion_json')) {
      context.handle(
        _weekCompletionJsonMeta,
        weekCompletionJson.isAcceptableOrUnknown(
          data['week_completion_json']!,
          _weekCompletionJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weekCompletionJsonMeta);
    }
    if (data.containsKey('sodium_week_json')) {
      context.handle(
        _sodiumWeekJsonMeta,
        sodiumWeekJson.isAcceptableOrUnknown(
          data['sodium_week_json']!,
          _sodiumWeekJsonMeta,
        ),
      );
    }
    if (data.containsKey('calories_week_json')) {
      context.handle(
        _caloriesWeekJsonMeta,
        caloriesWeekJson.isAcceptableOrUnknown(
          data['calories_week_json']!,
          _caloriesWeekJsonMeta,
        ),
      );
    }
    if (data.containsKey('sugar_week_json')) {
      context.handle(
        _sugarWeekJsonMeta,
        sugarWeekJson.isAcceptableOrUnknown(
          data['sugar_week_json']!,
          _sugarWeekJsonMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    }
    if (data.containsKey('age')) {
      context.handle(
        _ageMeta,
        age.isAcceptableOrUnknown(data['age']!, _ageMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrainerClientRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrainerClientRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      )!,
      goal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal'],
      )!,
      lastMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message'],
      )!,
      lastTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_time'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      caloriesToday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calories_today'],
      )!,
      sodiumMg: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sodium_mg'],
      )!,
      sugarG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sugar_g'],
      )!,
      carbsG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs_g'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      lastRoutine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_routine'],
      )!,
      weekCompletionJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_completion_json'],
      )!,
      sodiumWeekJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sodium_week_json'],
      )!,
      caloriesWeekJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}calories_week_json'],
      )!,
      sugarWeekJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sugar_week_json'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      ),
      age: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}age'],
      ),
    );
  }

  @override
  $TrainerClientsTable createAlias(String alias) {
    return $TrainerClientsTable(attachedDatabase, alias);
  }
}

class TrainerClientRow extends DataClass
    implements Insertable<TrainerClientRow> {
  final String id;
  final String name;
  final String avatar;
  final String goal;
  final String lastMessage;
  final String lastTime;
  final bool active;
  final int caloriesToday;
  final int sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;
  final String lastRoutine;
  final String weekCompletionJson;
  final String sodiumWeekJson;
  final String caloriesWeekJson;
  final String sugarWeekJson;
  final int sortOrder;

  /// 회원이 자기 프로필에 등록한 성별(`male`/`female`/`other`). 트레이너가
  /// 신규 등록 시 입력하는 값이 아니다 — 회원 ID로 연결할 때 회원의 실제
  /// 프로필에서 그대로 옮겨 온다. 비어 있으면 [TrainerClient.rosterGender] 가
  /// 예전 행을 위한 표시용 폴백을 쓴다(#960) — 새로 연결되는 회원은 이 값이
  /// 항상 채워지므로 폴백을 타지 않는다.
  final String? gender;

  /// 회원의 실제 나이 — 연결 시점에 회원 프로필의 생년월일로 계산해 저장한다.
  /// null 이면 [TrainerClient.rosterAge] 가 예전 행을 위한 표시용 폴백을
  /// 쓴다. 트레이너가 직접 입력하는 값이 아니다.
  final int? age;
  const TrainerClientRow({
    required this.id,
    required this.name,
    required this.avatar,
    required this.goal,
    required this.lastMessage,
    required this.lastTime,
    required this.active,
    required this.caloriesToday,
    required this.sodiumMg,
    required this.sugarG,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    required this.lastRoutine,
    required this.weekCompletionJson,
    required this.sodiumWeekJson,
    required this.caloriesWeekJson,
    required this.sugarWeekJson,
    required this.sortOrder,
    this.gender,
    this.age,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['avatar'] = Variable<String>(avatar);
    map['goal'] = Variable<String>(goal);
    map['last_message'] = Variable<String>(lastMessage);
    map['last_time'] = Variable<String>(lastTime);
    map['active'] = Variable<bool>(active);
    map['calories_today'] = Variable<int>(caloriesToday);
    map['sodium_mg'] = Variable<int>(sodiumMg);
    map['sugar_g'] = Variable<double>(sugarG);
    map['carbs_g'] = Variable<double>(carbsG);
    map['protein_g'] = Variable<double>(proteinG);
    map['fat_g'] = Variable<double>(fatG);
    map['last_routine'] = Variable<String>(lastRoutine);
    map['week_completion_json'] = Variable<String>(weekCompletionJson);
    map['sodium_week_json'] = Variable<String>(sodiumWeekJson);
    map['calories_week_json'] = Variable<String>(caloriesWeekJson);
    map['sugar_week_json'] = Variable<String>(sugarWeekJson);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || gender != null) {
      map['gender'] = Variable<String>(gender);
    }
    if (!nullToAbsent || age != null) {
      map['age'] = Variable<int>(age);
    }
    return map;
  }

  TrainerClientsCompanion toCompanion(bool nullToAbsent) {
    return TrainerClientsCompanion(
      id: Value(id),
      name: Value(name),
      avatar: Value(avatar),
      goal: Value(goal),
      lastMessage: Value(lastMessage),
      lastTime: Value(lastTime),
      active: Value(active),
      caloriesToday: Value(caloriesToday),
      sodiumMg: Value(sodiumMg),
      sugarG: Value(sugarG),
      carbsG: Value(carbsG),
      proteinG: Value(proteinG),
      fatG: Value(fatG),
      lastRoutine: Value(lastRoutine),
      weekCompletionJson: Value(weekCompletionJson),
      sodiumWeekJson: Value(sodiumWeekJson),
      caloriesWeekJson: Value(caloriesWeekJson),
      sugarWeekJson: Value(sugarWeekJson),
      sortOrder: Value(sortOrder),
      gender: gender == null && nullToAbsent
          ? const Value.absent()
          : Value(gender),
      age: age == null && nullToAbsent ? const Value.absent() : Value(age),
    );
  }

  factory TrainerClientRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrainerClientRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      avatar: serializer.fromJson<String>(json['avatar']),
      goal: serializer.fromJson<String>(json['goal']),
      lastMessage: serializer.fromJson<String>(json['lastMessage']),
      lastTime: serializer.fromJson<String>(json['lastTime']),
      active: serializer.fromJson<bool>(json['active']),
      caloriesToday: serializer.fromJson<int>(json['caloriesToday']),
      sodiumMg: serializer.fromJson<int>(json['sodiumMg']),
      sugarG: serializer.fromJson<double>(json['sugarG']),
      carbsG: serializer.fromJson<double>(json['carbsG']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      lastRoutine: serializer.fromJson<String>(json['lastRoutine']),
      weekCompletionJson: serializer.fromJson<String>(
        json['weekCompletionJson'],
      ),
      sodiumWeekJson: serializer.fromJson<String>(json['sodiumWeekJson']),
      caloriesWeekJson: serializer.fromJson<String>(json['caloriesWeekJson']),
      sugarWeekJson: serializer.fromJson<String>(json['sugarWeekJson']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      gender: serializer.fromJson<String?>(json['gender']),
      age: serializer.fromJson<int?>(json['age']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'avatar': serializer.toJson<String>(avatar),
      'goal': serializer.toJson<String>(goal),
      'lastMessage': serializer.toJson<String>(lastMessage),
      'lastTime': serializer.toJson<String>(lastTime),
      'active': serializer.toJson<bool>(active),
      'caloriesToday': serializer.toJson<int>(caloriesToday),
      'sodiumMg': serializer.toJson<int>(sodiumMg),
      'sugarG': serializer.toJson<double>(sugarG),
      'carbsG': serializer.toJson<double>(carbsG),
      'proteinG': serializer.toJson<double>(proteinG),
      'fatG': serializer.toJson<double>(fatG),
      'lastRoutine': serializer.toJson<String>(lastRoutine),
      'weekCompletionJson': serializer.toJson<String>(weekCompletionJson),
      'sodiumWeekJson': serializer.toJson<String>(sodiumWeekJson),
      'caloriesWeekJson': serializer.toJson<String>(caloriesWeekJson),
      'sugarWeekJson': serializer.toJson<String>(sugarWeekJson),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'gender': serializer.toJson<String?>(gender),
      'age': serializer.toJson<int?>(age),
    };
  }

  TrainerClientRow copyWith({
    String? id,
    String? name,
    String? avatar,
    String? goal,
    String? lastMessage,
    String? lastTime,
    bool? active,
    int? caloriesToday,
    int? sodiumMg,
    double? sugarG,
    double? carbsG,
    double? proteinG,
    double? fatG,
    String? lastRoutine,
    String? weekCompletionJson,
    String? sodiumWeekJson,
    String? caloriesWeekJson,
    String? sugarWeekJson,
    int? sortOrder,
    Value<String?> gender = const Value.absent(),
    Value<int?> age = const Value.absent(),
  }) => TrainerClientRow(
    id: id ?? this.id,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    goal: goal ?? this.goal,
    lastMessage: lastMessage ?? this.lastMessage,
    lastTime: lastTime ?? this.lastTime,
    active: active ?? this.active,
    caloriesToday: caloriesToday ?? this.caloriesToday,
    sodiumMg: sodiumMg ?? this.sodiumMg,
    sugarG: sugarG ?? this.sugarG,
    carbsG: carbsG ?? this.carbsG,
    proteinG: proteinG ?? this.proteinG,
    fatG: fatG ?? this.fatG,
    lastRoutine: lastRoutine ?? this.lastRoutine,
    weekCompletionJson: weekCompletionJson ?? this.weekCompletionJson,
    sodiumWeekJson: sodiumWeekJson ?? this.sodiumWeekJson,
    caloriesWeekJson: caloriesWeekJson ?? this.caloriesWeekJson,
    sugarWeekJson: sugarWeekJson ?? this.sugarWeekJson,
    sortOrder: sortOrder ?? this.sortOrder,
    gender: gender.present ? gender.value : this.gender,
    age: age.present ? age.value : this.age,
  );
  TrainerClientRow copyWithCompanion(TrainerClientsCompanion data) {
    return TrainerClientRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      goal: data.goal.present ? data.goal.value : this.goal,
      lastMessage: data.lastMessage.present
          ? data.lastMessage.value
          : this.lastMessage,
      lastTime: data.lastTime.present ? data.lastTime.value : this.lastTime,
      active: data.active.present ? data.active.value : this.active,
      caloriesToday: data.caloriesToday.present
          ? data.caloriesToday.value
          : this.caloriesToday,
      sodiumMg: data.sodiumMg.present ? data.sodiumMg.value : this.sodiumMg,
      sugarG: data.sugarG.present ? data.sugarG.value : this.sugarG,
      carbsG: data.carbsG.present ? data.carbsG.value : this.carbsG,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      lastRoutine: data.lastRoutine.present
          ? data.lastRoutine.value
          : this.lastRoutine,
      weekCompletionJson: data.weekCompletionJson.present
          ? data.weekCompletionJson.value
          : this.weekCompletionJson,
      sodiumWeekJson: data.sodiumWeekJson.present
          ? data.sodiumWeekJson.value
          : this.sodiumWeekJson,
      caloriesWeekJson: data.caloriesWeekJson.present
          ? data.caloriesWeekJson.value
          : this.caloriesWeekJson,
      sugarWeekJson: data.sugarWeekJson.present
          ? data.sugarWeekJson.value
          : this.sugarWeekJson,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      gender: data.gender.present ? data.gender.value : this.gender,
      age: data.age.present ? data.age.value : this.age,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrainerClientRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('goal: $goal, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastTime: $lastTime, ')
          ..write('active: $active, ')
          ..write('caloriesToday: $caloriesToday, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('sugarG: $sugarG, ')
          ..write('carbsG: $carbsG, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('lastRoutine: $lastRoutine, ')
          ..write('weekCompletionJson: $weekCompletionJson, ')
          ..write('sodiumWeekJson: $sodiumWeekJson, ')
          ..write('caloriesWeekJson: $caloriesWeekJson, ')
          ..write('sugarWeekJson: $sugarWeekJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('gender: $gender, ')
          ..write('age: $age')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    avatar,
    goal,
    lastMessage,
    lastTime,
    active,
    caloriesToday,
    sodiumMg,
    sugarG,
    carbsG,
    proteinG,
    fatG,
    lastRoutine,
    weekCompletionJson,
    sodiumWeekJson,
    caloriesWeekJson,
    sugarWeekJson,
    sortOrder,
    gender,
    age,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrainerClientRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatar == this.avatar &&
          other.goal == this.goal &&
          other.lastMessage == this.lastMessage &&
          other.lastTime == this.lastTime &&
          other.active == this.active &&
          other.caloriesToday == this.caloriesToday &&
          other.sodiumMg == this.sodiumMg &&
          other.sugarG == this.sugarG &&
          other.carbsG == this.carbsG &&
          other.proteinG == this.proteinG &&
          other.fatG == this.fatG &&
          other.lastRoutine == this.lastRoutine &&
          other.weekCompletionJson == this.weekCompletionJson &&
          other.sodiumWeekJson == this.sodiumWeekJson &&
          other.caloriesWeekJson == this.caloriesWeekJson &&
          other.sugarWeekJson == this.sugarWeekJson &&
          other.sortOrder == this.sortOrder &&
          other.gender == this.gender &&
          other.age == this.age);
}

class TrainerClientsCompanion extends UpdateCompanion<TrainerClientRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> avatar;
  final Value<String> goal;
  final Value<String> lastMessage;
  final Value<String> lastTime;
  final Value<bool> active;
  final Value<int> caloriesToday;
  final Value<int> sodiumMg;
  final Value<double> sugarG;
  final Value<double> carbsG;
  final Value<double> proteinG;
  final Value<double> fatG;
  final Value<String> lastRoutine;
  final Value<String> weekCompletionJson;
  final Value<String> sodiumWeekJson;
  final Value<String> caloriesWeekJson;
  final Value<String> sugarWeekJson;
  final Value<int> sortOrder;
  final Value<String?> gender;
  final Value<int?> age;
  final Value<int> rowid;
  const TrainerClientsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatar = const Value.absent(),
    this.goal = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastTime = const Value.absent(),
    this.active = const Value.absent(),
    this.caloriesToday = const Value.absent(),
    this.sodiumMg = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.carbsG = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.lastRoutine = const Value.absent(),
    this.weekCompletionJson = const Value.absent(),
    this.sodiumWeekJson = const Value.absent(),
    this.caloriesWeekJson = const Value.absent(),
    this.sugarWeekJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.gender = const Value.absent(),
    this.age = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrainerClientsCompanion.insert({
    required String id,
    required String name,
    required String avatar,
    required String goal,
    required String lastMessage,
    required String lastTime,
    this.active = const Value.absent(),
    required int caloriesToday,
    required int sodiumMg,
    required double sugarG,
    this.carbsG = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    required String lastRoutine,
    required String weekCompletionJson,
    this.sodiumWeekJson = const Value.absent(),
    this.caloriesWeekJson = const Value.absent(),
    this.sugarWeekJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.gender = const Value.absent(),
    this.age = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       avatar = Value(avatar),
       goal = Value(goal),
       lastMessage = Value(lastMessage),
       lastTime = Value(lastTime),
       caloriesToday = Value(caloriesToday),
       sodiumMg = Value(sodiumMg),
       sugarG = Value(sugarG),
       lastRoutine = Value(lastRoutine),
       weekCompletionJson = Value(weekCompletionJson);
  static Insertable<TrainerClientRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? avatar,
    Expression<String>? goal,
    Expression<String>? lastMessage,
    Expression<String>? lastTime,
    Expression<bool>? active,
    Expression<int>? caloriesToday,
    Expression<int>? sodiumMg,
    Expression<double>? sugarG,
    Expression<double>? carbsG,
    Expression<double>? proteinG,
    Expression<double>? fatG,
    Expression<String>? lastRoutine,
    Expression<String>? weekCompletionJson,
    Expression<String>? sodiumWeekJson,
    Expression<String>? caloriesWeekJson,
    Expression<String>? sugarWeekJson,
    Expression<int>? sortOrder,
    Expression<String>? gender,
    Expression<int>? age,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
      if (goal != null) 'goal': goal,
      if (lastMessage != null) 'last_message': lastMessage,
      if (lastTime != null) 'last_time': lastTime,
      if (active != null) 'active': active,
      if (caloriesToday != null) 'calories_today': caloriesToday,
      if (sodiumMg != null) 'sodium_mg': sodiumMg,
      if (sugarG != null) 'sugar_g': sugarG,
      if (carbsG != null) 'carbs_g': carbsG,
      if (proteinG != null) 'protein_g': proteinG,
      if (fatG != null) 'fat_g': fatG,
      if (lastRoutine != null) 'last_routine': lastRoutine,
      if (weekCompletionJson != null)
        'week_completion_json': weekCompletionJson,
      if (sodiumWeekJson != null) 'sodium_week_json': sodiumWeekJson,
      if (caloriesWeekJson != null) 'calories_week_json': caloriesWeekJson,
      if (sugarWeekJson != null) 'sugar_week_json': sugarWeekJson,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (gender != null) 'gender': gender,
      if (age != null) 'age': age,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrainerClientsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? avatar,
    Value<String>? goal,
    Value<String>? lastMessage,
    Value<String>? lastTime,
    Value<bool>? active,
    Value<int>? caloriesToday,
    Value<int>? sodiumMg,
    Value<double>? sugarG,
    Value<double>? carbsG,
    Value<double>? proteinG,
    Value<double>? fatG,
    Value<String>? lastRoutine,
    Value<String>? weekCompletionJson,
    Value<String>? sodiumWeekJson,
    Value<String>? caloriesWeekJson,
    Value<String>? sugarWeekJson,
    Value<int>? sortOrder,
    Value<String?>? gender,
    Value<int?>? age,
    Value<int>? rowid,
  }) {
    return TrainerClientsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      goal: goal ?? this.goal,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTime: lastTime ?? this.lastTime,
      active: active ?? this.active,
      caloriesToday: caloriesToday ?? this.caloriesToday,
      sodiumMg: sodiumMg ?? this.sodiumMg,
      sugarG: sugarG ?? this.sugarG,
      carbsG: carbsG ?? this.carbsG,
      proteinG: proteinG ?? this.proteinG,
      fatG: fatG ?? this.fatG,
      lastRoutine: lastRoutine ?? this.lastRoutine,
      weekCompletionJson: weekCompletionJson ?? this.weekCompletionJson,
      sodiumWeekJson: sodiumWeekJson ?? this.sodiumWeekJson,
      caloriesWeekJson: caloriesWeekJson ?? this.caloriesWeekJson,
      sugarWeekJson: sugarWeekJson ?? this.sugarWeekJson,
      sortOrder: sortOrder ?? this.sortOrder,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (goal.present) {
      map['goal'] = Variable<String>(goal.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (lastTime.present) {
      map['last_time'] = Variable<String>(lastTime.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (caloriesToday.present) {
      map['calories_today'] = Variable<int>(caloriesToday.value);
    }
    if (sodiumMg.present) {
      map['sodium_mg'] = Variable<int>(sodiumMg.value);
    }
    if (sugarG.present) {
      map['sugar_g'] = Variable<double>(sugarG.value);
    }
    if (carbsG.present) {
      map['carbs_g'] = Variable<double>(carbsG.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (lastRoutine.present) {
      map['last_routine'] = Variable<String>(lastRoutine.value);
    }
    if (weekCompletionJson.present) {
      map['week_completion_json'] = Variable<String>(weekCompletionJson.value);
    }
    if (sodiumWeekJson.present) {
      map['sodium_week_json'] = Variable<String>(sodiumWeekJson.value);
    }
    if (caloriesWeekJson.present) {
      map['calories_week_json'] = Variable<String>(caloriesWeekJson.value);
    }
    if (sugarWeekJson.present) {
      map['sugar_week_json'] = Variable<String>(sugarWeekJson.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (age.present) {
      map['age'] = Variable<int>(age.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrainerClientsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('goal: $goal, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastTime: $lastTime, ')
          ..write('active: $active, ')
          ..write('caloriesToday: $caloriesToday, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('sugarG: $sugarG, ')
          ..write('carbsG: $carbsG, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('lastRoutine: $lastRoutine, ')
          ..write('weekCompletionJson: $weekCompletionJson, ')
          ..write('sodiumWeekJson: $sodiumWeekJson, ')
          ..write('caloriesWeekJson: $caloriesWeekJson, ')
          ..write('sugarWeekJson: $sugarWeekJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('gender: $gender, ')
          ..write('age: $age, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientDietEntriesTable extends ClientDietEntries
    with TableInfo<$ClientDietEntriesTable, ClientDietEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientDietEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealMeta = const VerificationMeta('meal');
  @override
  late final GeneratedColumn<String> meal = GeneratedColumn<String>(
    'meal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemsMeta = const VerificationMeta('items');
  @override
  late final GeneratedColumn<String> items = GeneratedColumn<String>(
    'items',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _caloriesMeta = const VerificationMeta(
    'calories',
  );
  @override
  late final GeneratedColumn<int> calories = GeneratedColumn<int>(
    'calories',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sodiumMgMeta = const VerificationMeta(
    'sodiumMg',
  );
  @override
  late final GeneratedColumn<int> sodiumMg = GeneratedColumn<int>(
    'sodium_mg',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbsGMeta = const VerificationMeta('carbsG');
  @override
  late final GeneratedColumn<double> carbsG = GeneratedColumn<double>(
    'carbs_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sugarGMeta = const VerificationMeta('sugarG');
  @override
  late final GeneratedColumn<double> sugarG = GeneratedColumn<double>(
    'sugar_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _timeLabelMeta = const VerificationMeta(
    'timeLabel',
  );
  @override
  late final GeneratedColumn<String> timeLabel = GeneratedColumn<String>(
    'time_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _foodsJsonMeta = const VerificationMeta(
    'foodsJson',
  );
  @override
  late final GeneratedColumn<String> foodsJson = GeneratedColumn<String>(
    'foods_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _photoAssetMeta = const VerificationMeta(
    'photoAsset',
  );
  @override
  late final GeneratedColumn<String> photoAsset = GeneratedColumn<String>(
    'photo_asset',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    meal,
    items,
    calories,
    sodiumMg,
    carbsG,
    proteinG,
    fatG,
    sugarG,
    date,
    timeLabel,
    foodsJson,
    photoAsset,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_diet_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientDietEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('meal')) {
      context.handle(
        _mealMeta,
        meal.isAcceptableOrUnknown(data['meal']!, _mealMeta),
      );
    } else if (isInserting) {
      context.missing(_mealMeta);
    }
    if (data.containsKey('items')) {
      context.handle(
        _itemsMeta,
        items.isAcceptableOrUnknown(data['items']!, _itemsMeta),
      );
    } else if (isInserting) {
      context.missing(_itemsMeta);
    }
    if (data.containsKey('calories')) {
      context.handle(
        _caloriesMeta,
        calories.isAcceptableOrUnknown(data['calories']!, _caloriesMeta),
      );
    } else if (isInserting) {
      context.missing(_caloriesMeta);
    }
    if (data.containsKey('sodium_mg')) {
      context.handle(
        _sodiumMgMeta,
        sodiumMg.isAcceptableOrUnknown(data['sodium_mg']!, _sodiumMgMeta),
      );
    } else if (isInserting) {
      context.missing(_sodiumMgMeta);
    }
    if (data.containsKey('carbs_g')) {
      context.handle(
        _carbsGMeta,
        carbsG.isAcceptableOrUnknown(data['carbs_g']!, _carbsGMeta),
      );
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    }
    if (data.containsKey('sugar_g')) {
      context.handle(
        _sugarGMeta,
        sugarG.isAcceptableOrUnknown(data['sugar_g']!, _sugarGMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('time_label')) {
      context.handle(
        _timeLabelMeta,
        timeLabel.isAcceptableOrUnknown(data['time_label']!, _timeLabelMeta),
      );
    }
    if (data.containsKey('foods_json')) {
      context.handle(
        _foodsJsonMeta,
        foodsJson.isAcceptableOrUnknown(data['foods_json']!, _foodsJsonMeta),
      );
    }
    if (data.containsKey('photo_asset')) {
      context.handle(
        _photoAssetMeta,
        photoAsset.isAcceptableOrUnknown(data['photo_asset']!, _photoAssetMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClientDietEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientDietEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      meal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal'],
      )!,
      items: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}items'],
      )!,
      calories: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calories'],
      )!,
      sodiumMg: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sodium_mg'],
      )!,
      carbsG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs_g'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      sugarG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sugar_g'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      timeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_label'],
      )!,
      foodsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}foods_json'],
      )!,
      photoAsset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_asset'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $ClientDietEntriesTable createAlias(String alias) {
    return $ClientDietEntriesTable(attachedDatabase, alias);
  }
}

class ClientDietEntryRow extends DataClass
    implements Insertable<ClientDietEntryRow> {
  final String id;
  final String clientId;
  final String meal;
  final String items;
  final int calories;
  final int sodiumMg;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 그 끼니의 당류(g). 나트륨과 나란히 읽히는 값인데 여기만 빠져 있어,
  /// 트레이너는 끼니 카드에서 나트륨만 보고 당류는 하루 합계로만 볼 수
  /// 있었다(#1025).
  final double sugarG;

  /// 이 끼니를 먹은 날(`YYYY-MM-DD`).
  ///
  /// 예전에는 이 표가 **오늘 하루**만 담아 날짜가 필요 없었다. 기간 뷰에서
  /// 날짜를 눌러 그날 끼니를 펼치려면 어느 날 것인지 알아야 한다(#1025).
  /// 기본값이 빈 문자열이라 재시딩 전 행도 그대로 읽히고, 날짜로 거르는
  /// 조회에서는 걸리지 않는다.
  final String date;

  /// 끼니를 먹은 시각 문구(`08:30`). 회원 앱 끼니 카드가 끼니 배지 옆에 적는
  /// 값이라 트레이너 화면에도 같은 자리가 있어야 한다(#1166).
  final String timeLabel;

  /// 그 끼니의 **음식별** 영양(JSON 배열). 회원 앱은 음식 한 줄마다
  /// `이름 · kcal · 나트륨 · 당류` 를 적는데, 트레이너 화면은 이름을 쉼표로
  /// 이어 붙인 [items] 한 줄뿐이라 같은 끼니를 두 화면이 다른 수준으로
  /// 말했다(#1166). 비어 있으면 예전처럼 [items] 만 읽는다.
  final String foodsJson;

  /// 데모에서 이 끼니를 대신 보여 줄 번들 이미지 경로. 실 API 모드의 사진은
  /// 회원이 올린 것을 인증된 경로로 받아 오지만(#699), 데모에는 그 백엔드가
  /// 없어 사진이 한 장도 뜨지 않았다 — 사진 인식이 이 제품의 핵심인데
  /// 데모에서 확인할 수 없었다(#819).
  final String? photoAsset;
  final int sortOrder;
  const ClientDietEntryRow({
    required this.id,
    required this.clientId,
    required this.meal,
    required this.items,
    required this.calories,
    required this.sodiumMg,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    required this.sugarG,
    required this.date,
    required this.timeLabel,
    required this.foodsJson,
    this.photoAsset,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['meal'] = Variable<String>(meal);
    map['items'] = Variable<String>(items);
    map['calories'] = Variable<int>(calories);
    map['sodium_mg'] = Variable<int>(sodiumMg);
    map['carbs_g'] = Variable<double>(carbsG);
    map['protein_g'] = Variable<double>(proteinG);
    map['fat_g'] = Variable<double>(fatG);
    map['sugar_g'] = Variable<double>(sugarG);
    map['date'] = Variable<String>(date);
    map['time_label'] = Variable<String>(timeLabel);
    map['foods_json'] = Variable<String>(foodsJson);
    if (!nullToAbsent || photoAsset != null) {
      map['photo_asset'] = Variable<String>(photoAsset);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  ClientDietEntriesCompanion toCompanion(bool nullToAbsent) {
    return ClientDietEntriesCompanion(
      id: Value(id),
      clientId: Value(clientId),
      meal: Value(meal),
      items: Value(items),
      calories: Value(calories),
      sodiumMg: Value(sodiumMg),
      carbsG: Value(carbsG),
      proteinG: Value(proteinG),
      fatG: Value(fatG),
      sugarG: Value(sugarG),
      date: Value(date),
      timeLabel: Value(timeLabel),
      foodsJson: Value(foodsJson),
      photoAsset: photoAsset == null && nullToAbsent
          ? const Value.absent()
          : Value(photoAsset),
      sortOrder: Value(sortOrder),
    );
  }

  factory ClientDietEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientDietEntryRow(
      id: serializer.fromJson<String>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      meal: serializer.fromJson<String>(json['meal']),
      items: serializer.fromJson<String>(json['items']),
      calories: serializer.fromJson<int>(json['calories']),
      sodiumMg: serializer.fromJson<int>(json['sodiumMg']),
      carbsG: serializer.fromJson<double>(json['carbsG']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      sugarG: serializer.fromJson<double>(json['sugarG']),
      date: serializer.fromJson<String>(json['date']),
      timeLabel: serializer.fromJson<String>(json['timeLabel']),
      foodsJson: serializer.fromJson<String>(json['foodsJson']),
      photoAsset: serializer.fromJson<String?>(json['photoAsset']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientId': serializer.toJson<String>(clientId),
      'meal': serializer.toJson<String>(meal),
      'items': serializer.toJson<String>(items),
      'calories': serializer.toJson<int>(calories),
      'sodiumMg': serializer.toJson<int>(sodiumMg),
      'carbsG': serializer.toJson<double>(carbsG),
      'proteinG': serializer.toJson<double>(proteinG),
      'fatG': serializer.toJson<double>(fatG),
      'sugarG': serializer.toJson<double>(sugarG),
      'date': serializer.toJson<String>(date),
      'timeLabel': serializer.toJson<String>(timeLabel),
      'foodsJson': serializer.toJson<String>(foodsJson),
      'photoAsset': serializer.toJson<String?>(photoAsset),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  ClientDietEntryRow copyWith({
    String? id,
    String? clientId,
    String? meal,
    String? items,
    int? calories,
    int? sodiumMg,
    double? carbsG,
    double? proteinG,
    double? fatG,
    double? sugarG,
    String? date,
    String? timeLabel,
    String? foodsJson,
    Value<String?> photoAsset = const Value.absent(),
    int? sortOrder,
  }) => ClientDietEntryRow(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    meal: meal ?? this.meal,
    items: items ?? this.items,
    calories: calories ?? this.calories,
    sodiumMg: sodiumMg ?? this.sodiumMg,
    carbsG: carbsG ?? this.carbsG,
    proteinG: proteinG ?? this.proteinG,
    fatG: fatG ?? this.fatG,
    sugarG: sugarG ?? this.sugarG,
    date: date ?? this.date,
    timeLabel: timeLabel ?? this.timeLabel,
    foodsJson: foodsJson ?? this.foodsJson,
    photoAsset: photoAsset.present ? photoAsset.value : this.photoAsset,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  ClientDietEntryRow copyWithCompanion(ClientDietEntriesCompanion data) {
    return ClientDietEntryRow(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      meal: data.meal.present ? data.meal.value : this.meal,
      items: data.items.present ? data.items.value : this.items,
      calories: data.calories.present ? data.calories.value : this.calories,
      sodiumMg: data.sodiumMg.present ? data.sodiumMg.value : this.sodiumMg,
      carbsG: data.carbsG.present ? data.carbsG.value : this.carbsG,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      sugarG: data.sugarG.present ? data.sugarG.value : this.sugarG,
      date: data.date.present ? data.date.value : this.date,
      timeLabel: data.timeLabel.present ? data.timeLabel.value : this.timeLabel,
      foodsJson: data.foodsJson.present ? data.foodsJson.value : this.foodsJson,
      photoAsset: data.photoAsset.present
          ? data.photoAsset.value
          : this.photoAsset,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientDietEntryRow(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('meal: $meal, ')
          ..write('items: $items, ')
          ..write('calories: $calories, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('carbsG: $carbsG, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('sugarG: $sugarG, ')
          ..write('date: $date, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('foodsJson: $foodsJson, ')
          ..write('photoAsset: $photoAsset, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientId,
    meal,
    items,
    calories,
    sodiumMg,
    carbsG,
    proteinG,
    fatG,
    sugarG,
    date,
    timeLabel,
    foodsJson,
    photoAsset,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientDietEntryRow &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.meal == this.meal &&
          other.items == this.items &&
          other.calories == this.calories &&
          other.sodiumMg == this.sodiumMg &&
          other.carbsG == this.carbsG &&
          other.proteinG == this.proteinG &&
          other.fatG == this.fatG &&
          other.sugarG == this.sugarG &&
          other.date == this.date &&
          other.timeLabel == this.timeLabel &&
          other.foodsJson == this.foodsJson &&
          other.photoAsset == this.photoAsset &&
          other.sortOrder == this.sortOrder);
}

class ClientDietEntriesCompanion extends UpdateCompanion<ClientDietEntryRow> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<String> meal;
  final Value<String> items;
  final Value<int> calories;
  final Value<int> sodiumMg;
  final Value<double> carbsG;
  final Value<double> proteinG;
  final Value<double> fatG;
  final Value<double> sugarG;
  final Value<String> date;
  final Value<String> timeLabel;
  final Value<String> foodsJson;
  final Value<String?> photoAsset;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const ClientDietEntriesCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.meal = const Value.absent(),
    this.items = const Value.absent(),
    this.calories = const Value.absent(),
    this.sodiumMg = const Value.absent(),
    this.carbsG = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.date = const Value.absent(),
    this.timeLabel = const Value.absent(),
    this.foodsJson = const Value.absent(),
    this.photoAsset = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientDietEntriesCompanion.insert({
    required String id,
    required String clientId,
    required String meal,
    required String items,
    required int calories,
    required int sodiumMg,
    this.carbsG = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.date = const Value.absent(),
    this.timeLabel = const Value.absent(),
    this.foodsJson = const Value.absent(),
    this.photoAsset = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientId = Value(clientId),
       meal = Value(meal),
       items = Value(items),
       calories = Value(calories),
       sodiumMg = Value(sodiumMg);
  static Insertable<ClientDietEntryRow> custom({
    Expression<String>? id,
    Expression<String>? clientId,
    Expression<String>? meal,
    Expression<String>? items,
    Expression<int>? calories,
    Expression<int>? sodiumMg,
    Expression<double>? carbsG,
    Expression<double>? proteinG,
    Expression<double>? fatG,
    Expression<double>? sugarG,
    Expression<String>? date,
    Expression<String>? timeLabel,
    Expression<String>? foodsJson,
    Expression<String>? photoAsset,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (meal != null) 'meal': meal,
      if (items != null) 'items': items,
      if (calories != null) 'calories': calories,
      if (sodiumMg != null) 'sodium_mg': sodiumMg,
      if (carbsG != null) 'carbs_g': carbsG,
      if (proteinG != null) 'protein_g': proteinG,
      if (fatG != null) 'fat_g': fatG,
      if (sugarG != null) 'sugar_g': sugarG,
      if (date != null) 'date': date,
      if (timeLabel != null) 'time_label': timeLabel,
      if (foodsJson != null) 'foods_json': foodsJson,
      if (photoAsset != null) 'photo_asset': photoAsset,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientDietEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<String>? meal,
    Value<String>? items,
    Value<int>? calories,
    Value<int>? sodiumMg,
    Value<double>? carbsG,
    Value<double>? proteinG,
    Value<double>? fatG,
    Value<double>? sugarG,
    Value<String>? date,
    Value<String>? timeLabel,
    Value<String>? foodsJson,
    Value<String?>? photoAsset,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return ClientDietEntriesCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      meal: meal ?? this.meal,
      items: items ?? this.items,
      calories: calories ?? this.calories,
      sodiumMg: sodiumMg ?? this.sodiumMg,
      carbsG: carbsG ?? this.carbsG,
      proteinG: proteinG ?? this.proteinG,
      fatG: fatG ?? this.fatG,
      sugarG: sugarG ?? this.sugarG,
      date: date ?? this.date,
      timeLabel: timeLabel ?? this.timeLabel,
      foodsJson: foodsJson ?? this.foodsJson,
      photoAsset: photoAsset ?? this.photoAsset,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (meal.present) {
      map['meal'] = Variable<String>(meal.value);
    }
    if (items.present) {
      map['items'] = Variable<String>(items.value);
    }
    if (calories.present) {
      map['calories'] = Variable<int>(calories.value);
    }
    if (sodiumMg.present) {
      map['sodium_mg'] = Variable<int>(sodiumMg.value);
    }
    if (carbsG.present) {
      map['carbs_g'] = Variable<double>(carbsG.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (sugarG.present) {
      map['sugar_g'] = Variable<double>(sugarG.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (timeLabel.present) {
      map['time_label'] = Variable<String>(timeLabel.value);
    }
    if (foodsJson.present) {
      map['foods_json'] = Variable<String>(foodsJson.value);
    }
    if (photoAsset.present) {
      map['photo_asset'] = Variable<String>(photoAsset.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientDietEntriesCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('meal: $meal, ')
          ..write('items: $items, ')
          ..write('calories: $calories, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('carbsG: $carbsG, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('sugarG: $sugarG, ')
          ..write('date: $date, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('foodsJson: $foodsJson, ')
          ..write('photoAsset: $photoAsset, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientAiRoutinesTable extends ClientAiRoutines
    with TableInfo<$ClientAiRoutinesTable, ClientAiRoutineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientAiRoutinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minutesMeta = const VerificationMeta(
    'minutes',
  );
  @override
  late final GeneratedColumn<int> minutes = GeneratedColumn<int>(
    'minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    name,
    minutes,
    type,
    reason,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_ai_routines';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientAiRoutineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('minutes')) {
      context.handle(
        _minutesMeta,
        minutes.isAcceptableOrUnknown(data['minutes']!, _minutesMeta),
      );
    } else if (isInserting) {
      context.missing(_minutesMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClientAiRoutineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientAiRoutineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      minutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minutes'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $ClientAiRoutinesTable createAlias(String alias) {
    return $ClientAiRoutinesTable(attachedDatabase, alias);
  }
}

class ClientAiRoutineRow extends DataClass
    implements Insertable<ClientAiRoutineRow> {
  final String id;
  final String clientId;
  final String name;
  final int minutes;
  final String type;
  final String reason;
  final int sortOrder;
  const ClientAiRoutineRow({
    required this.id,
    required this.clientId,
    required this.name,
    required this.minutes,
    required this.type,
    required this.reason,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['name'] = Variable<String>(name);
    map['minutes'] = Variable<int>(minutes);
    map['type'] = Variable<String>(type);
    map['reason'] = Variable<String>(reason);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  ClientAiRoutinesCompanion toCompanion(bool nullToAbsent) {
    return ClientAiRoutinesCompanion(
      id: Value(id),
      clientId: Value(clientId),
      name: Value(name),
      minutes: Value(minutes),
      type: Value(type),
      reason: Value(reason),
      sortOrder: Value(sortOrder),
    );
  }

  factory ClientAiRoutineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientAiRoutineRow(
      id: serializer.fromJson<String>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      name: serializer.fromJson<String>(json['name']),
      minutes: serializer.fromJson<int>(json['minutes']),
      type: serializer.fromJson<String>(json['type']),
      reason: serializer.fromJson<String>(json['reason']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientId': serializer.toJson<String>(clientId),
      'name': serializer.toJson<String>(name),
      'minutes': serializer.toJson<int>(minutes),
      'type': serializer.toJson<String>(type),
      'reason': serializer.toJson<String>(reason),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  ClientAiRoutineRow copyWith({
    String? id,
    String? clientId,
    String? name,
    int? minutes,
    String? type,
    String? reason,
    int? sortOrder,
  }) => ClientAiRoutineRow(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    name: name ?? this.name,
    minutes: minutes ?? this.minutes,
    type: type ?? this.type,
    reason: reason ?? this.reason,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  ClientAiRoutineRow copyWithCompanion(ClientAiRoutinesCompanion data) {
    return ClientAiRoutineRow(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      name: data.name.present ? data.name.value : this.name,
      minutes: data.minutes.present ? data.minutes.value : this.minutes,
      type: data.type.present ? data.type.value : this.type,
      reason: data.reason.present ? data.reason.value : this.reason,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientAiRoutineRow(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('name: $name, ')
          ..write('minutes: $minutes, ')
          ..write('type: $type, ')
          ..write('reason: $reason, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, clientId, name, minutes, type, reason, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientAiRoutineRow &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.name == this.name &&
          other.minutes == this.minutes &&
          other.type == this.type &&
          other.reason == this.reason &&
          other.sortOrder == this.sortOrder);
}

class ClientAiRoutinesCompanion extends UpdateCompanion<ClientAiRoutineRow> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<String> name;
  final Value<int> minutes;
  final Value<String> type;
  final Value<String> reason;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const ClientAiRoutinesCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.name = const Value.absent(),
    this.minutes = const Value.absent(),
    this.type = const Value.absent(),
    this.reason = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientAiRoutinesCompanion.insert({
    required String id,
    required String clientId,
    required String name,
    required int minutes,
    required String type,
    required String reason,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientId = Value(clientId),
       name = Value(name),
       minutes = Value(minutes),
       type = Value(type),
       reason = Value(reason);
  static Insertable<ClientAiRoutineRow> custom({
    Expression<String>? id,
    Expression<String>? clientId,
    Expression<String>? name,
    Expression<int>? minutes,
    Expression<String>? type,
    Expression<String>? reason,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (name != null) 'name': name,
      if (minutes != null) 'minutes': minutes,
      if (type != null) 'type': type,
      if (reason != null) 'reason': reason,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientAiRoutinesCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<String>? name,
    Value<int>? minutes,
    Value<String>? type,
    Value<String>? reason,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return ClientAiRoutinesCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      minutes: minutes ?? this.minutes,
      type: type ?? this.type,
      reason: reason ?? this.reason,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (minutes.present) {
      map['minutes'] = Variable<int>(minutes.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientAiRoutinesCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('name: $name, ')
          ..write('minutes: $minutes, ')
          ..write('type: $type, ')
          ..write('reason: $reason, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientRoutineHistoryTable extends ClientRoutineHistory
    with TableInfo<$ClientRoutineHistoryTable, ClientRoutineHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientRoutineHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateLabelMeta = const VerificationMeta(
    'dateLabel',
  );
  @override
  late final GeneratedColumn<String> dateLabel = GeneratedColumn<String>(
    'date_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completionRateMeta = const VerificationMeta(
    'completionRate',
  );
  @override
  late final GeneratedColumn<int> completionRate = GeneratedColumn<int>(
    'completion_rate',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exercisesJsonMeta = const VerificationMeta(
    'exercisesJson',
  );
  @override
  late final GeneratedColumn<String> exercisesJson = GeneratedColumn<String>(
    'exercises_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientFeedbackMeta = const VerificationMeta(
    'clientFeedback',
  );
  @override
  late final GeneratedColumn<String> clientFeedback = GeneratedColumn<String>(
    'client_feedback',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _trainerNoteMeta = const VerificationMeta(
    'trainerNote',
  );
  @override
  late final GeneratedColumn<String> trainerNote = GeneratedColumn<String>(
    'trainer_note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    dateLabel,
    label,
    completionRate,
    exercisesJson,
    clientFeedback,
    trainerNote,
    sortOrder,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_routine_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientRoutineHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('date_label')) {
      context.handle(
        _dateLabelMeta,
        dateLabel.isAcceptableOrUnknown(data['date_label']!, _dateLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_dateLabelMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('completion_rate')) {
      context.handle(
        _completionRateMeta,
        completionRate.isAcceptableOrUnknown(
          data['completion_rate']!,
          _completionRateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completionRateMeta);
    }
    if (data.containsKey('exercises_json')) {
      context.handle(
        _exercisesJsonMeta,
        exercisesJson.isAcceptableOrUnknown(
          data['exercises_json']!,
          _exercisesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exercisesJsonMeta);
    }
    if (data.containsKey('client_feedback')) {
      context.handle(
        _clientFeedbackMeta,
        clientFeedback.isAcceptableOrUnknown(
          data['client_feedback']!,
          _clientFeedbackMeta,
        ),
      );
    }
    if (data.containsKey('trainer_note')) {
      context.handle(
        _trainerNoteMeta,
        trainerNote.isAcceptableOrUnknown(
          data['trainer_note']!,
          _trainerNoteMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClientRoutineHistoryRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientRoutineHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      dateLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date_label'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      completionRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completion_rate'],
      )!,
      exercisesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercises_json'],
      )!,
      clientFeedback: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_feedback'],
      )!,
      trainerNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trainer_note'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $ClientRoutineHistoryTable createAlias(String alias) {
    return $ClientRoutineHistoryTable(attachedDatabase, alias);
  }
}

class ClientRoutineHistoryRow extends DataClass
    implements Insertable<ClientRoutineHistoryRow> {
  final String id;
  final String clientId;
  final String dateLabel;
  final String label;
  final int completionRate;
  final String exercisesJson;
  final String clientFeedback;
  final String trainerNote;
  final int sortOrder;

  /// 실제로 운동을 마친 시각. `dateLabel` 은 화면에 그릴 문자열일 뿐이라
  /// 기간으로 거를 수 없다 — 실 API 가 주는 `completed_at` 과 같은 값을
  /// 데모도 들고 있어야 두 모드가 같은 목록을 보여 준다(#1114).
  final DateTime? completedAt;
  const ClientRoutineHistoryRow({
    required this.id,
    required this.clientId,
    required this.dateLabel,
    required this.label,
    required this.completionRate,
    required this.exercisesJson,
    required this.clientFeedback,
    required this.trainerNote,
    required this.sortOrder,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['date_label'] = Variable<String>(dateLabel);
    map['label'] = Variable<String>(label);
    map['completion_rate'] = Variable<int>(completionRate);
    map['exercises_json'] = Variable<String>(exercisesJson);
    map['client_feedback'] = Variable<String>(clientFeedback);
    map['trainer_note'] = Variable<String>(trainerNote);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  ClientRoutineHistoryCompanion toCompanion(bool nullToAbsent) {
    return ClientRoutineHistoryCompanion(
      id: Value(id),
      clientId: Value(clientId),
      dateLabel: Value(dateLabel),
      label: Value(label),
      completionRate: Value(completionRate),
      exercisesJson: Value(exercisesJson),
      clientFeedback: Value(clientFeedback),
      trainerNote: Value(trainerNote),
      sortOrder: Value(sortOrder),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory ClientRoutineHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientRoutineHistoryRow(
      id: serializer.fromJson<String>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      dateLabel: serializer.fromJson<String>(json['dateLabel']),
      label: serializer.fromJson<String>(json['label']),
      completionRate: serializer.fromJson<int>(json['completionRate']),
      exercisesJson: serializer.fromJson<String>(json['exercisesJson']),
      clientFeedback: serializer.fromJson<String>(json['clientFeedback']),
      trainerNote: serializer.fromJson<String>(json['trainerNote']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientId': serializer.toJson<String>(clientId),
      'dateLabel': serializer.toJson<String>(dateLabel),
      'label': serializer.toJson<String>(label),
      'completionRate': serializer.toJson<int>(completionRate),
      'exercisesJson': serializer.toJson<String>(exercisesJson),
      'clientFeedback': serializer.toJson<String>(clientFeedback),
      'trainerNote': serializer.toJson<String>(trainerNote),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  ClientRoutineHistoryRow copyWith({
    String? id,
    String? clientId,
    String? dateLabel,
    String? label,
    int? completionRate,
    String? exercisesJson,
    String? clientFeedback,
    String? trainerNote,
    int? sortOrder,
    Value<DateTime?> completedAt = const Value.absent(),
  }) => ClientRoutineHistoryRow(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    dateLabel: dateLabel ?? this.dateLabel,
    label: label ?? this.label,
    completionRate: completionRate ?? this.completionRate,
    exercisesJson: exercisesJson ?? this.exercisesJson,
    clientFeedback: clientFeedback ?? this.clientFeedback,
    trainerNote: trainerNote ?? this.trainerNote,
    sortOrder: sortOrder ?? this.sortOrder,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  ClientRoutineHistoryRow copyWithCompanion(
    ClientRoutineHistoryCompanion data,
  ) {
    return ClientRoutineHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      dateLabel: data.dateLabel.present ? data.dateLabel.value : this.dateLabel,
      label: data.label.present ? data.label.value : this.label,
      completionRate: data.completionRate.present
          ? data.completionRate.value
          : this.completionRate,
      exercisesJson: data.exercisesJson.present
          ? data.exercisesJson.value
          : this.exercisesJson,
      clientFeedback: data.clientFeedback.present
          ? data.clientFeedback.value
          : this.clientFeedback,
      trainerNote: data.trainerNote.present
          ? data.trainerNote.value
          : this.trainerNote,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientRoutineHistoryRow(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('dateLabel: $dateLabel, ')
          ..write('label: $label, ')
          ..write('completionRate: $completionRate, ')
          ..write('exercisesJson: $exercisesJson, ')
          ..write('clientFeedback: $clientFeedback, ')
          ..write('trainerNote: $trainerNote, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientId,
    dateLabel,
    label,
    completionRate,
    exercisesJson,
    clientFeedback,
    trainerNote,
    sortOrder,
    completedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientRoutineHistoryRow &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.dateLabel == this.dateLabel &&
          other.label == this.label &&
          other.completionRate == this.completionRate &&
          other.exercisesJson == this.exercisesJson &&
          other.clientFeedback == this.clientFeedback &&
          other.trainerNote == this.trainerNote &&
          other.sortOrder == this.sortOrder &&
          other.completedAt == this.completedAt);
}

class ClientRoutineHistoryCompanion
    extends UpdateCompanion<ClientRoutineHistoryRow> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<String> dateLabel;
  final Value<String> label;
  final Value<int> completionRate;
  final Value<String> exercisesJson;
  final Value<String> clientFeedback;
  final Value<String> trainerNote;
  final Value<int> sortOrder;
  final Value<DateTime?> completedAt;
  final Value<int> rowid;
  const ClientRoutineHistoryCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.dateLabel = const Value.absent(),
    this.label = const Value.absent(),
    this.completionRate = const Value.absent(),
    this.exercisesJson = const Value.absent(),
    this.clientFeedback = const Value.absent(),
    this.trainerNote = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientRoutineHistoryCompanion.insert({
    required String id,
    required String clientId,
    required String dateLabel,
    required String label,
    required int completionRate,
    required String exercisesJson,
    this.clientFeedback = const Value.absent(),
    this.trainerNote = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientId = Value(clientId),
       dateLabel = Value(dateLabel),
       label = Value(label),
       completionRate = Value(completionRate),
       exercisesJson = Value(exercisesJson);
  static Insertable<ClientRoutineHistoryRow> custom({
    Expression<String>? id,
    Expression<String>? clientId,
    Expression<String>? dateLabel,
    Expression<String>? label,
    Expression<int>? completionRate,
    Expression<String>? exercisesJson,
    Expression<String>? clientFeedback,
    Expression<String>? trainerNote,
    Expression<int>? sortOrder,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (dateLabel != null) 'date_label': dateLabel,
      if (label != null) 'label': label,
      if (completionRate != null) 'completion_rate': completionRate,
      if (exercisesJson != null) 'exercises_json': exercisesJson,
      if (clientFeedback != null) 'client_feedback': clientFeedback,
      if (trainerNote != null) 'trainer_note': trainerNote,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientRoutineHistoryCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<String>? dateLabel,
    Value<String>? label,
    Value<int>? completionRate,
    Value<String>? exercisesJson,
    Value<String>? clientFeedback,
    Value<String>? trainerNote,
    Value<int>? sortOrder,
    Value<DateTime?>? completedAt,
    Value<int>? rowid,
  }) {
    return ClientRoutineHistoryCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      dateLabel: dateLabel ?? this.dateLabel,
      label: label ?? this.label,
      completionRate: completionRate ?? this.completionRate,
      exercisesJson: exercisesJson ?? this.exercisesJson,
      clientFeedback: clientFeedback ?? this.clientFeedback,
      trainerNote: trainerNote ?? this.trainerNote,
      sortOrder: sortOrder ?? this.sortOrder,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (dateLabel.present) {
      map['date_label'] = Variable<String>(dateLabel.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (completionRate.present) {
      map['completion_rate'] = Variable<int>(completionRate.value);
    }
    if (exercisesJson.present) {
      map['exercises_json'] = Variable<String>(exercisesJson.value);
    }
    if (clientFeedback.present) {
      map['client_feedback'] = Variable<String>(clientFeedback.value);
    }
    if (trainerNote.present) {
      map['trainer_note'] = Variable<String>(trainerNote.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientRoutineHistoryCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('dateLabel: $dateLabel, ')
          ..write('label: $label, ')
          ..write('completionRate: $completionRate, ')
          ..write('exercisesJson: $exercisesJson, ')
          ..write('clientFeedback: $clientFeedback, ')
          ..write('trainerNote: $trainerNote, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientChatMessagesTable extends ClientChatMessages
    with TableInfo<$ClientChatMessagesTable, ClientChatMessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeLabelMeta = const VerificationMeta(
    'timeLabel',
  );
  @override
  late final GeneratedColumn<String> timeLabel = GeneratedColumn<String>(
    'time_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emoteIdMeta = const VerificationMeta(
    'emoteId',
  );
  @override
  late final GeneratedColumn<String> emoteId = GeneratedColumn<String>(
    'emote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    sender,
    body,
    timeLabel,
    createdAt,
    emoteId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientChatMessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(
        _senderMeta,
        sender.isAcceptableOrUnknown(data['sender']!, _senderMeta),
      );
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('time_label')) {
      context.handle(
        _timeLabelMeta,
        timeLabel.isAcceptableOrUnknown(data['time_label']!, _timeLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_timeLabelMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('emote_id')) {
      context.handle(
        _emoteIdMeta,
        emoteId.isAcceptableOrUnknown(data['emote_id']!, _emoteIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClientChatMessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientChatMessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      sender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      timeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_label'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      emoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emote_id'],
      ),
    );
  }

  @override
  $ClientChatMessagesTable createAlias(String alias) {
    return $ClientChatMessagesTable(attachedDatabase, alias);
  }
}

class ClientChatMessageRow extends DataClass
    implements Insertable<ClientChatMessageRow> {
  final String id;
  final String clientId;
  final String sender;
  final String body;
  final String timeLabel;
  final DateTime createdAt;

  /// 이 메시지가 이모티콘이면 그 id(`oni_owoon` …). (#2020)
  ///
  /// 본문(`body`)은 이모티콘을 그리지 못하는 자리(고객 목록의 마지막 메시지)가
  /// 읽는 글이라 함께 둔다.
  final String? emoteId;
  const ClientChatMessageRow({
    required this.id,
    required this.clientId,
    required this.sender,
    required this.body,
    required this.timeLabel,
    required this.createdAt,
    this.emoteId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['sender'] = Variable<String>(sender);
    map['body'] = Variable<String>(body);
    map['time_label'] = Variable<String>(timeLabel);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || emoteId != null) {
      map['emote_id'] = Variable<String>(emoteId);
    }
    return map;
  }

  ClientChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ClientChatMessagesCompanion(
      id: Value(id),
      clientId: Value(clientId),
      sender: Value(sender),
      body: Value(body),
      timeLabel: Value(timeLabel),
      createdAt: Value(createdAt),
      emoteId: emoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(emoteId),
    );
  }

  factory ClientChatMessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientChatMessageRow(
      id: serializer.fromJson<String>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      sender: serializer.fromJson<String>(json['sender']),
      body: serializer.fromJson<String>(json['body']),
      timeLabel: serializer.fromJson<String>(json['timeLabel']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      emoteId: serializer.fromJson<String?>(json['emoteId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientId': serializer.toJson<String>(clientId),
      'sender': serializer.toJson<String>(sender),
      'body': serializer.toJson<String>(body),
      'timeLabel': serializer.toJson<String>(timeLabel),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'emoteId': serializer.toJson<String?>(emoteId),
    };
  }

  ClientChatMessageRow copyWith({
    String? id,
    String? clientId,
    String? sender,
    String? body,
    String? timeLabel,
    DateTime? createdAt,
    Value<String?> emoteId = const Value.absent(),
  }) => ClientChatMessageRow(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    sender: sender ?? this.sender,
    body: body ?? this.body,
    timeLabel: timeLabel ?? this.timeLabel,
    createdAt: createdAt ?? this.createdAt,
    emoteId: emoteId.present ? emoteId.value : this.emoteId,
  );
  ClientChatMessageRow copyWithCompanion(ClientChatMessagesCompanion data) {
    return ClientChatMessageRow(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      sender: data.sender.present ? data.sender.value : this.sender,
      body: data.body.present ? data.body.value : this.body,
      timeLabel: data.timeLabel.present ? data.timeLabel.value : this.timeLabel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      emoteId: data.emoteId.present ? data.emoteId.value : this.emoteId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientChatMessageRow(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('sender: $sender, ')
          ..write('body: $body, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('createdAt: $createdAt, ')
          ..write('emoteId: $emoteId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, clientId, sender, body, timeLabel, createdAt, emoteId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientChatMessageRow &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.sender == this.sender &&
          other.body == this.body &&
          other.timeLabel == this.timeLabel &&
          other.createdAt == this.createdAt &&
          other.emoteId == this.emoteId);
}

class ClientChatMessagesCompanion
    extends UpdateCompanion<ClientChatMessageRow> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<String> sender;
  final Value<String> body;
  final Value<String> timeLabel;
  final Value<DateTime> createdAt;
  final Value<String?> emoteId;
  final Value<int> rowid;
  const ClientChatMessagesCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.sender = const Value.absent(),
    this.body = const Value.absent(),
    this.timeLabel = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.emoteId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientChatMessagesCompanion.insert({
    required String id,
    required String clientId,
    required String sender,
    required String body,
    required String timeLabel,
    required DateTime createdAt,
    this.emoteId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientId = Value(clientId),
       sender = Value(sender),
       body = Value(body),
       timeLabel = Value(timeLabel),
       createdAt = Value(createdAt);
  static Insertable<ClientChatMessageRow> custom({
    Expression<String>? id,
    Expression<String>? clientId,
    Expression<String>? sender,
    Expression<String>? body,
    Expression<String>? timeLabel,
    Expression<DateTime>? createdAt,
    Expression<String>? emoteId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (sender != null) 'sender': sender,
      if (body != null) 'body': body,
      if (timeLabel != null) 'time_label': timeLabel,
      if (createdAt != null) 'created_at': createdAt,
      if (emoteId != null) 'emote_id': emoteId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientChatMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<String>? sender,
    Value<String>? body,
    Value<String>? timeLabel,
    Value<DateTime>? createdAt,
    Value<String?>? emoteId,
    Value<int>? rowid,
  }) {
    return ClientChatMessagesCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      sender: sender ?? this.sender,
      body: body ?? this.body,
      timeLabel: timeLabel ?? this.timeLabel,
      createdAt: createdAt ?? this.createdAt,
      emoteId: emoteId ?? this.emoteId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (timeLabel.present) {
      map['time_label'] = Variable<String>(timeLabel.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (emoteId.present) {
      map['emote_id'] = Variable<String>(emoteId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('sender: $sender, ')
          ..write('body: $body, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('createdAt: $createdAt, ')
          ..write('emoteId: $emoteId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrainerScheduleEntriesTable extends TrainerScheduleEntries
    with TableInfo<$TrainerScheduleEntriesTable, TrainerScheduleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrainerScheduleEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<String> time = GeneratedColumn<String>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientNameMeta = const VerificationMeta(
    'clientName',
  );
  @override
  late final GeneratedColumn<String> clientName = GeneratedColumn<String>(
    'client_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _durationMinutesMeta = const VerificationMeta(
    'durationMinutes',
  );
  @override
  late final GeneratedColumn<int> durationMinutes = GeneratedColumn<int>(
    'duration_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cancelledAtMeta = const VerificationMeta(
    'cancelledAt',
  );
  @override
  late final GeneratedColumn<DateTime> cancelledAt = GeneratedColumn<DateTime>(
    'cancelled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cancellationSourceMeta =
      const VerificationMeta('cancellationSource');
  @override
  late final GeneratedColumn<String> cancellationSource =
      GeneratedColumn<String>(
        'cancellation_source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _cancellationReasonMeta =
      const VerificationMeta('cancellationReason');
  @override
  late final GeneratedColumn<String> cancellationReason =
      GeneratedColumn<String>(
        'cancellation_reason',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _noShowAtMeta = const VerificationMeta(
    'noShowAt',
  );
  @override
  late final GeneratedColumn<DateTime> noShowAt = GeneratedColumn<DateTime>(
    'no_show_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _programJsonMeta = const VerificationMeta(
    'programJson',
  );
  @override
  late final GeneratedColumn<String> programJson = GeneratedColumn<String>(
    'program_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _programSentMeta = const VerificationMeta(
    'programSent',
  );
  @override
  late final GeneratedColumn<bool> programSent = GeneratedColumn<bool>(
    'program_sent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("program_sent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    time,
    clientId,
    clientName,
    type,
    durationMinutes,
    status,
    cancelledAt,
    cancellationSource,
    cancellationReason,
    noShowAt,
    note,
    programJson,
    programSent,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trainer_schedule_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrainerScheduleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    }
    if (data.containsKey('client_name')) {
      context.handle(
        _clientNameMeta,
        clientName.isAcceptableOrUnknown(data['client_name']!, _clientNameMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('duration_minutes')) {
      context.handle(
        _durationMinutesMeta,
        durationMinutes.isAcceptableOrUnknown(
          data['duration_minutes']!,
          _durationMinutesMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('cancelled_at')) {
      context.handle(
        _cancelledAtMeta,
        cancelledAt.isAcceptableOrUnknown(
          data['cancelled_at']!,
          _cancelledAtMeta,
        ),
      );
    }
    if (data.containsKey('cancellation_source')) {
      context.handle(
        _cancellationSourceMeta,
        cancellationSource.isAcceptableOrUnknown(
          data['cancellation_source']!,
          _cancellationSourceMeta,
        ),
      );
    }
    if (data.containsKey('cancellation_reason')) {
      context.handle(
        _cancellationReasonMeta,
        cancellationReason.isAcceptableOrUnknown(
          data['cancellation_reason']!,
          _cancellationReasonMeta,
        ),
      );
    }
    if (data.containsKey('no_show_at')) {
      context.handle(
        _noShowAtMeta,
        noShowAt.isAcceptableOrUnknown(data['no_show_at']!, _noShowAtMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('program_json')) {
      context.handle(
        _programJsonMeta,
        programJson.isAcceptableOrUnknown(
          data['program_json']!,
          _programJsonMeta,
        ),
      );
    }
    if (data.containsKey('program_sent')) {
      context.handle(
        _programSentMeta,
        programSent.isAcceptableOrUnknown(
          data['program_sent']!,
          _programSentMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrainerScheduleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrainerScheduleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      ),
      clientName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      durationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_minutes'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      cancelledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cancelled_at'],
      ),
      cancellationSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cancellation_source'],
      )!,
      cancellationReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cancellation_reason'],
      )!,
      noShowAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}no_show_at'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      programJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}program_json'],
      )!,
      programSent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}program_sent'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $TrainerScheduleEntriesTable createAlias(String alias) {
    return $TrainerScheduleEntriesTable(attachedDatabase, alias);
  }
}

class TrainerScheduleRow extends DataClass
    implements Insertable<TrainerScheduleRow> {
  final String id;
  final String date;
  final String time;

  /// 예약된 고객의 id. 이름은 식별자가 아니다 — 고객 이름을 바꾸면 과거
  /// 세션이 통째로 끊기고, 조용히 "세션 0건" 리포트가 되어 그대로 회원에게
  /// 전송될 수 있었다(#386).
  ///
  /// nullable 인 이유: 상담 등 미등록 고객 슬롯과 공백 슬롯에는 붙일 id 가
  /// 없고, v3 이전에 저장된 기존 행도 값이 없다. 조회는 id 를 우선하고
  /// 없을 때만 이름으로 폴백한다.
  final String? clientId;
  final String clientName;
  final String type;
  final int durationMinutes;
  final String status;

  /// 취소·노쇼로 마무리된 세션의 기록(#871, #906). 삭제와 달리 **행을 남기는**
  /// 것이 이 상태의 목적이라, 언제·누가·왜가 함께 있어야 나중에 "그 시간에 무슨
  /// 일이 있었나" 를 읽을 수 있다. 예정·완료 행은 전부 비어 있다.
  final DateTime? cancelledAt;

  /// ''(해당 없음)|member|trainer|other. 트레이너 사정의 취소를 회원의
  /// 미이행으로 읽지 않으려면 주체가 남아야 한다.
  final String cancellationSource;

  /// 트레이너만 보는 짧은 사유. 회원 알림에는 싣지 않는다.
  final String cancellationReason;
  final DateTime? noShowAt;
  final String note;
  final String programJson;

  /// 완료한 세션의 프로그램을 회원에게 보냈는가. 데모에는 받을 회원 백엔드가
  /// 없어 전송은 이 표시로 끝나지만, 화면이 '전송됨' 을 사실대로 말하고 같은
  /// 세션을 두 번 보내지 않게 하려면 어딘가에 남아야 한다(#822).
  final bool programSent;
  final int sortOrder;
  const TrainerScheduleRow({
    required this.id,
    required this.date,
    required this.time,
    this.clientId,
    required this.clientName,
    required this.type,
    required this.durationMinutes,
    required this.status,
    this.cancelledAt,
    required this.cancellationSource,
    required this.cancellationReason,
    this.noShowAt,
    required this.note,
    required this.programJson,
    required this.programSent,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    map['time'] = Variable<String>(time);
    if (!nullToAbsent || clientId != null) {
      map['client_id'] = Variable<String>(clientId);
    }
    map['client_name'] = Variable<String>(clientName);
    map['type'] = Variable<String>(type);
    map['duration_minutes'] = Variable<int>(durationMinutes);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || cancelledAt != null) {
      map['cancelled_at'] = Variable<DateTime>(cancelledAt);
    }
    map['cancellation_source'] = Variable<String>(cancellationSource);
    map['cancellation_reason'] = Variable<String>(cancellationReason);
    if (!nullToAbsent || noShowAt != null) {
      map['no_show_at'] = Variable<DateTime>(noShowAt);
    }
    map['note'] = Variable<String>(note);
    map['program_json'] = Variable<String>(programJson);
    map['program_sent'] = Variable<bool>(programSent);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  TrainerScheduleEntriesCompanion toCompanion(bool nullToAbsent) {
    return TrainerScheduleEntriesCompanion(
      id: Value(id),
      date: Value(date),
      time: Value(time),
      clientId: clientId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientId),
      clientName: Value(clientName),
      type: Value(type),
      durationMinutes: Value(durationMinutes),
      status: Value(status),
      cancelledAt: cancelledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelledAt),
      cancellationSource: Value(cancellationSource),
      cancellationReason: Value(cancellationReason),
      noShowAt: noShowAt == null && nullToAbsent
          ? const Value.absent()
          : Value(noShowAt),
      note: Value(note),
      programJson: Value(programJson),
      programSent: Value(programSent),
      sortOrder: Value(sortOrder),
    );
  }

  factory TrainerScheduleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrainerScheduleRow(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      time: serializer.fromJson<String>(json['time']),
      clientId: serializer.fromJson<String?>(json['clientId']),
      clientName: serializer.fromJson<String>(json['clientName']),
      type: serializer.fromJson<String>(json['type']),
      durationMinutes: serializer.fromJson<int>(json['durationMinutes']),
      status: serializer.fromJson<String>(json['status']),
      cancelledAt: serializer.fromJson<DateTime?>(json['cancelledAt']),
      cancellationSource: serializer.fromJson<String>(
        json['cancellationSource'],
      ),
      cancellationReason: serializer.fromJson<String>(
        json['cancellationReason'],
      ),
      noShowAt: serializer.fromJson<DateTime?>(json['noShowAt']),
      note: serializer.fromJson<String>(json['note']),
      programJson: serializer.fromJson<String>(json['programJson']),
      programSent: serializer.fromJson<bool>(json['programSent']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'time': serializer.toJson<String>(time),
      'clientId': serializer.toJson<String?>(clientId),
      'clientName': serializer.toJson<String>(clientName),
      'type': serializer.toJson<String>(type),
      'durationMinutes': serializer.toJson<int>(durationMinutes),
      'status': serializer.toJson<String>(status),
      'cancelledAt': serializer.toJson<DateTime?>(cancelledAt),
      'cancellationSource': serializer.toJson<String>(cancellationSource),
      'cancellationReason': serializer.toJson<String>(cancellationReason),
      'noShowAt': serializer.toJson<DateTime?>(noShowAt),
      'note': serializer.toJson<String>(note),
      'programJson': serializer.toJson<String>(programJson),
      'programSent': serializer.toJson<bool>(programSent),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  TrainerScheduleRow copyWith({
    String? id,
    String? date,
    String? time,
    Value<String?> clientId = const Value.absent(),
    String? clientName,
    String? type,
    int? durationMinutes,
    String? status,
    Value<DateTime?> cancelledAt = const Value.absent(),
    String? cancellationSource,
    String? cancellationReason,
    Value<DateTime?> noShowAt = const Value.absent(),
    String? note,
    String? programJson,
    bool? programSent,
    int? sortOrder,
  }) => TrainerScheduleRow(
    id: id ?? this.id,
    date: date ?? this.date,
    time: time ?? this.time,
    clientId: clientId.present ? clientId.value : this.clientId,
    clientName: clientName ?? this.clientName,
    type: type ?? this.type,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    status: status ?? this.status,
    cancelledAt: cancelledAt.present ? cancelledAt.value : this.cancelledAt,
    cancellationSource: cancellationSource ?? this.cancellationSource,
    cancellationReason: cancellationReason ?? this.cancellationReason,
    noShowAt: noShowAt.present ? noShowAt.value : this.noShowAt,
    note: note ?? this.note,
    programJson: programJson ?? this.programJson,
    programSent: programSent ?? this.programSent,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  TrainerScheduleRow copyWithCompanion(TrainerScheduleEntriesCompanion data) {
    return TrainerScheduleRow(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      time: data.time.present ? data.time.value : this.time,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      clientName: data.clientName.present
          ? data.clientName.value
          : this.clientName,
      type: data.type.present ? data.type.value : this.type,
      durationMinutes: data.durationMinutes.present
          ? data.durationMinutes.value
          : this.durationMinutes,
      status: data.status.present ? data.status.value : this.status,
      cancelledAt: data.cancelledAt.present
          ? data.cancelledAt.value
          : this.cancelledAt,
      cancellationSource: data.cancellationSource.present
          ? data.cancellationSource.value
          : this.cancellationSource,
      cancellationReason: data.cancellationReason.present
          ? data.cancellationReason.value
          : this.cancellationReason,
      noShowAt: data.noShowAt.present ? data.noShowAt.value : this.noShowAt,
      note: data.note.present ? data.note.value : this.note,
      programJson: data.programJson.present
          ? data.programJson.value
          : this.programJson,
      programSent: data.programSent.present
          ? data.programSent.value
          : this.programSent,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrainerScheduleRow(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('time: $time, ')
          ..write('clientId: $clientId, ')
          ..write('clientName: $clientName, ')
          ..write('type: $type, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('status: $status, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('cancellationSource: $cancellationSource, ')
          ..write('cancellationReason: $cancellationReason, ')
          ..write('noShowAt: $noShowAt, ')
          ..write('note: $note, ')
          ..write('programJson: $programJson, ')
          ..write('programSent: $programSent, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    time,
    clientId,
    clientName,
    type,
    durationMinutes,
    status,
    cancelledAt,
    cancellationSource,
    cancellationReason,
    noShowAt,
    note,
    programJson,
    programSent,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrainerScheduleRow &&
          other.id == this.id &&
          other.date == this.date &&
          other.time == this.time &&
          other.clientId == this.clientId &&
          other.clientName == this.clientName &&
          other.type == this.type &&
          other.durationMinutes == this.durationMinutes &&
          other.status == this.status &&
          other.cancelledAt == this.cancelledAt &&
          other.cancellationSource == this.cancellationSource &&
          other.cancellationReason == this.cancellationReason &&
          other.noShowAt == this.noShowAt &&
          other.note == this.note &&
          other.programJson == this.programJson &&
          other.programSent == this.programSent &&
          other.sortOrder == this.sortOrder);
}

class TrainerScheduleEntriesCompanion
    extends UpdateCompanion<TrainerScheduleRow> {
  final Value<String> id;
  final Value<String> date;
  final Value<String> time;
  final Value<String?> clientId;
  final Value<String> clientName;
  final Value<String> type;
  final Value<int> durationMinutes;
  final Value<String> status;
  final Value<DateTime?> cancelledAt;
  final Value<String> cancellationSource;
  final Value<String> cancellationReason;
  final Value<DateTime?> noShowAt;
  final Value<String> note;
  final Value<String> programJson;
  final Value<bool> programSent;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const TrainerScheduleEntriesCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.time = const Value.absent(),
    this.clientId = const Value.absent(),
    this.clientName = const Value.absent(),
    this.type = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.status = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.cancellationSource = const Value.absent(),
    this.cancellationReason = const Value.absent(),
    this.noShowAt = const Value.absent(),
    this.note = const Value.absent(),
    this.programJson = const Value.absent(),
    this.programSent = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrainerScheduleEntriesCompanion.insert({
    required String id,
    required String date,
    required String time,
    this.clientId = const Value.absent(),
    this.clientName = const Value.absent(),
    this.type = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    required String status,
    this.cancelledAt = const Value.absent(),
    this.cancellationSource = const Value.absent(),
    this.cancellationReason = const Value.absent(),
    this.noShowAt = const Value.absent(),
    this.note = const Value.absent(),
    this.programJson = const Value.absent(),
    this.programSent = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date),
       time = Value(time),
       status = Value(status);
  static Insertable<TrainerScheduleRow> custom({
    Expression<String>? id,
    Expression<String>? date,
    Expression<String>? time,
    Expression<String>? clientId,
    Expression<String>? clientName,
    Expression<String>? type,
    Expression<int>? durationMinutes,
    Expression<String>? status,
    Expression<DateTime>? cancelledAt,
    Expression<String>? cancellationSource,
    Expression<String>? cancellationReason,
    Expression<DateTime>? noShowAt,
    Expression<String>? note,
    Expression<String>? programJson,
    Expression<bool>? programSent,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (time != null) 'time': time,
      if (clientId != null) 'client_id': clientId,
      if (clientName != null) 'client_name': clientName,
      if (type != null) 'type': type,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (status != null) 'status': status,
      if (cancelledAt != null) 'cancelled_at': cancelledAt,
      if (cancellationSource != null) 'cancellation_source': cancellationSource,
      if (cancellationReason != null) 'cancellation_reason': cancellationReason,
      if (noShowAt != null) 'no_show_at': noShowAt,
      if (note != null) 'note': note,
      if (programJson != null) 'program_json': programJson,
      if (programSent != null) 'program_sent': programSent,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrainerScheduleEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? date,
    Value<String>? time,
    Value<String?>? clientId,
    Value<String>? clientName,
    Value<String>? type,
    Value<int>? durationMinutes,
    Value<String>? status,
    Value<DateTime?>? cancelledAt,
    Value<String>? cancellationSource,
    Value<String>? cancellationReason,
    Value<DateTime?>? noShowAt,
    Value<String>? note,
    Value<String>? programJson,
    Value<bool>? programSent,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return TrainerScheduleEntriesCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      time: time ?? this.time,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      type: type ?? this.type,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      status: status ?? this.status,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationSource: cancellationSource ?? this.cancellationSource,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      noShowAt: noShowAt ?? this.noShowAt,
      note: note ?? this.note,
      programJson: programJson ?? this.programJson,
      programSent: programSent ?? this.programSent,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (time.present) {
      map['time'] = Variable<String>(time.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (clientName.present) {
      map['client_name'] = Variable<String>(clientName.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (durationMinutes.present) {
      map['duration_minutes'] = Variable<int>(durationMinutes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (cancelledAt.present) {
      map['cancelled_at'] = Variable<DateTime>(cancelledAt.value);
    }
    if (cancellationSource.present) {
      map['cancellation_source'] = Variable<String>(cancellationSource.value);
    }
    if (cancellationReason.present) {
      map['cancellation_reason'] = Variable<String>(cancellationReason.value);
    }
    if (noShowAt.present) {
      map['no_show_at'] = Variable<DateTime>(noShowAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (programJson.present) {
      map['program_json'] = Variable<String>(programJson.value);
    }
    if (programSent.present) {
      map['program_sent'] = Variable<bool>(programSent.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrainerScheduleEntriesCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('time: $time, ')
          ..write('clientId: $clientId, ')
          ..write('clientName: $clientName, ')
          ..write('type: $type, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('status: $status, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('cancellationSource: $cancellationSource, ')
          ..write('cancellationReason: $cancellationReason, ')
          ..write('noShowAt: $noShowAt, ')
          ..write('note: $note, ')
          ..write('programJson: $programJson, ')
          ..write('programSent: $programSent, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientDailyMetricsTable extends ClientDailyMetrics
    with TableInfo<$ClientDailyMetricsTable, ClientDailyMetricRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientDailyMetricsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completionMeta = const VerificationMeta(
    'completion',
  );
  @override
  late final GeneratedColumn<int> completion = GeneratedColumn<int>(
    'completion',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _caloriesMeta = const VerificationMeta(
    'calories',
  );
  @override
  late final GeneratedColumn<int> calories = GeneratedColumn<int>(
    'calories',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sodiumMgMeta = const VerificationMeta(
    'sodiumMg',
  );
  @override
  late final GeneratedColumn<int> sodiumMg = GeneratedColumn<int>(
    'sodium_mg',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sugarGMeta = const VerificationMeta('sugarG');
  @override
  late final GeneratedColumn<double> sugarG = GeneratedColumn<double>(
    'sugar_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _carbsGMeta = const VerificationMeta('carbsG');
  @override
  late final GeneratedColumn<double> carbsG = GeneratedColumn<double>(
    'carbs_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _exercisesJsonMeta = const VerificationMeta(
    'exercisesJson',
  );
  @override
  late final GeneratedColumn<String> exercisesJson = GeneratedColumn<String>(
    'exercises_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientId,
    date,
    completion,
    calories,
    sodiumMg,
    sugarG,
    carbsG,
    proteinG,
    fatG,
    exercisesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_daily_metrics';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientDailyMetricRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('completion')) {
      context.handle(
        _completionMeta,
        completion.isAcceptableOrUnknown(data['completion']!, _completionMeta),
      );
    }
    if (data.containsKey('calories')) {
      context.handle(
        _caloriesMeta,
        calories.isAcceptableOrUnknown(data['calories']!, _caloriesMeta),
      );
    }
    if (data.containsKey('sodium_mg')) {
      context.handle(
        _sodiumMgMeta,
        sodiumMg.isAcceptableOrUnknown(data['sodium_mg']!, _sodiumMgMeta),
      );
    }
    if (data.containsKey('sugar_g')) {
      context.handle(
        _sugarGMeta,
        sugarG.isAcceptableOrUnknown(data['sugar_g']!, _sugarGMeta),
      );
    }
    if (data.containsKey('carbs_g')) {
      context.handle(
        _carbsGMeta,
        carbsG.isAcceptableOrUnknown(data['carbs_g']!, _carbsGMeta),
      );
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    }
    if (data.containsKey('exercises_json')) {
      context.handle(
        _exercisesJsonMeta,
        exercisesJson.isAcceptableOrUnknown(
          data['exercises_json']!,
          _exercisesJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientId, date};
  @override
  ClientDailyMetricRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientDailyMetricRow(
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      completion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completion'],
      )!,
      calories: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calories'],
      )!,
      sodiumMg: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sodium_mg'],
      )!,
      sugarG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sugar_g'],
      )!,
      carbsG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs_g'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      exercisesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercises_json'],
      )!,
    );
  }

  @override
  $ClientDailyMetricsTable createAlias(String alias) {
    return $ClientDailyMetricsTable(attachedDatabase, alias);
  }
}

class ClientDailyMetricRow extends DataClass
    implements Insertable<ClientDailyMetricRow> {
  final String clientId;
  final String date;
  final int completion;
  final int calories;
  final int sodiumMg;
  final double sugarG;

  /// 그날의 탄·단·지(g). 트레이너 화면의 `이번 달` 칼로리 막대를 탄단지로 쌓는
  /// 재료다(#944). 실서버는 리포트 응답의 같은 이름 계열에서 온다.
  ///
  /// 당류와 같이 소수를 유지한다 — 반올림하면 회원 앱 식단 탭 수치와 어긋난다.
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 그날 배정된 운동 이름 JSON. 끝의 '✓'/'✗' 는 수행 여부를 나타내는 저장
  /// 규칙이며, 리포트의 요일별 상세가 이 값을 읽어 몇 개 중 몇 개인지 보여
  /// 준다 — 이행률만으로는 67% 의 분모를 알 수 없다(#754).
  final String exercisesJson;
  const ClientDailyMetricRow({
    required this.clientId,
    required this.date,
    required this.completion,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    required this.exercisesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['date'] = Variable<String>(date);
    map['completion'] = Variable<int>(completion);
    map['calories'] = Variable<int>(calories);
    map['sodium_mg'] = Variable<int>(sodiumMg);
    map['sugar_g'] = Variable<double>(sugarG);
    map['carbs_g'] = Variable<double>(carbsG);
    map['protein_g'] = Variable<double>(proteinG);
    map['fat_g'] = Variable<double>(fatG);
    map['exercises_json'] = Variable<String>(exercisesJson);
    return map;
  }

  ClientDailyMetricsCompanion toCompanion(bool nullToAbsent) {
    return ClientDailyMetricsCompanion(
      clientId: Value(clientId),
      date: Value(date),
      completion: Value(completion),
      calories: Value(calories),
      sodiumMg: Value(sodiumMg),
      sugarG: Value(sugarG),
      carbsG: Value(carbsG),
      proteinG: Value(proteinG),
      fatG: Value(fatG),
      exercisesJson: Value(exercisesJson),
    );
  }

  factory ClientDailyMetricRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientDailyMetricRow(
      clientId: serializer.fromJson<String>(json['clientId']),
      date: serializer.fromJson<String>(json['date']),
      completion: serializer.fromJson<int>(json['completion']),
      calories: serializer.fromJson<int>(json['calories']),
      sodiumMg: serializer.fromJson<int>(json['sodiumMg']),
      sugarG: serializer.fromJson<double>(json['sugarG']),
      carbsG: serializer.fromJson<double>(json['carbsG']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      exercisesJson: serializer.fromJson<String>(json['exercisesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'date': serializer.toJson<String>(date),
      'completion': serializer.toJson<int>(completion),
      'calories': serializer.toJson<int>(calories),
      'sodiumMg': serializer.toJson<int>(sodiumMg),
      'sugarG': serializer.toJson<double>(sugarG),
      'carbsG': serializer.toJson<double>(carbsG),
      'proteinG': serializer.toJson<double>(proteinG),
      'fatG': serializer.toJson<double>(fatG),
      'exercisesJson': serializer.toJson<String>(exercisesJson),
    };
  }

  ClientDailyMetricRow copyWith({
    String? clientId,
    String? date,
    int? completion,
    int? calories,
    int? sodiumMg,
    double? sugarG,
    double? carbsG,
    double? proteinG,
    double? fatG,
    String? exercisesJson,
  }) => ClientDailyMetricRow(
    clientId: clientId ?? this.clientId,
    date: date ?? this.date,
    completion: completion ?? this.completion,
    calories: calories ?? this.calories,
    sodiumMg: sodiumMg ?? this.sodiumMg,
    sugarG: sugarG ?? this.sugarG,
    carbsG: carbsG ?? this.carbsG,
    proteinG: proteinG ?? this.proteinG,
    fatG: fatG ?? this.fatG,
    exercisesJson: exercisesJson ?? this.exercisesJson,
  );
  ClientDailyMetricRow copyWithCompanion(ClientDailyMetricsCompanion data) {
    return ClientDailyMetricRow(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      date: data.date.present ? data.date.value : this.date,
      completion: data.completion.present
          ? data.completion.value
          : this.completion,
      calories: data.calories.present ? data.calories.value : this.calories,
      sodiumMg: data.sodiumMg.present ? data.sodiumMg.value : this.sodiumMg,
      sugarG: data.sugarG.present ? data.sugarG.value : this.sugarG,
      carbsG: data.carbsG.present ? data.carbsG.value : this.carbsG,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      exercisesJson: data.exercisesJson.present
          ? data.exercisesJson.value
          : this.exercisesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientDailyMetricRow(')
          ..write('clientId: $clientId, ')
          ..write('date: $date, ')
          ..write('completion: $completion, ')
          ..write('calories: $calories, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('sugarG: $sugarG, ')
          ..write('carbsG: $carbsG, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('exercisesJson: $exercisesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientId,
    date,
    completion,
    calories,
    sodiumMg,
    sugarG,
    carbsG,
    proteinG,
    fatG,
    exercisesJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientDailyMetricRow &&
          other.clientId == this.clientId &&
          other.date == this.date &&
          other.completion == this.completion &&
          other.calories == this.calories &&
          other.sodiumMg == this.sodiumMg &&
          other.sugarG == this.sugarG &&
          other.carbsG == this.carbsG &&
          other.proteinG == this.proteinG &&
          other.fatG == this.fatG &&
          other.exercisesJson == this.exercisesJson);
}

class ClientDailyMetricsCompanion
    extends UpdateCompanion<ClientDailyMetricRow> {
  final Value<String> clientId;
  final Value<String> date;
  final Value<int> completion;
  final Value<int> calories;
  final Value<int> sodiumMg;
  final Value<double> sugarG;
  final Value<double> carbsG;
  final Value<double> proteinG;
  final Value<double> fatG;
  final Value<String> exercisesJson;
  final Value<int> rowid;
  const ClientDailyMetricsCompanion({
    this.clientId = const Value.absent(),
    this.date = const Value.absent(),
    this.completion = const Value.absent(),
    this.calories = const Value.absent(),
    this.sodiumMg = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.carbsG = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.exercisesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientDailyMetricsCompanion.insert({
    required String clientId,
    required String date,
    this.completion = const Value.absent(),
    this.calories = const Value.absent(),
    this.sodiumMg = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.carbsG = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.exercisesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : clientId = Value(clientId),
       date = Value(date);
  static Insertable<ClientDailyMetricRow> custom({
    Expression<String>? clientId,
    Expression<String>? date,
    Expression<int>? completion,
    Expression<int>? calories,
    Expression<int>? sodiumMg,
    Expression<double>? sugarG,
    Expression<double>? carbsG,
    Expression<double>? proteinG,
    Expression<double>? fatG,
    Expression<String>? exercisesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (date != null) 'date': date,
      if (completion != null) 'completion': completion,
      if (calories != null) 'calories': calories,
      if (sodiumMg != null) 'sodium_mg': sodiumMg,
      if (sugarG != null) 'sugar_g': sugarG,
      if (carbsG != null) 'carbs_g': carbsG,
      if (proteinG != null) 'protein_g': proteinG,
      if (fatG != null) 'fat_g': fatG,
      if (exercisesJson != null) 'exercises_json': exercisesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientDailyMetricsCompanion copyWith({
    Value<String>? clientId,
    Value<String>? date,
    Value<int>? completion,
    Value<int>? calories,
    Value<int>? sodiumMg,
    Value<double>? sugarG,
    Value<double>? carbsG,
    Value<double>? proteinG,
    Value<double>? fatG,
    Value<String>? exercisesJson,
    Value<int>? rowid,
  }) {
    return ClientDailyMetricsCompanion(
      clientId: clientId ?? this.clientId,
      date: date ?? this.date,
      completion: completion ?? this.completion,
      calories: calories ?? this.calories,
      sodiumMg: sodiumMg ?? this.sodiumMg,
      sugarG: sugarG ?? this.sugarG,
      carbsG: carbsG ?? this.carbsG,
      proteinG: proteinG ?? this.proteinG,
      fatG: fatG ?? this.fatG,
      exercisesJson: exercisesJson ?? this.exercisesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (completion.present) {
      map['completion'] = Variable<int>(completion.value);
    }
    if (calories.present) {
      map['calories'] = Variable<int>(calories.value);
    }
    if (sodiumMg.present) {
      map['sodium_mg'] = Variable<int>(sodiumMg.value);
    }
    if (sugarG.present) {
      map['sugar_g'] = Variable<double>(sugarG.value);
    }
    if (carbsG.present) {
      map['carbs_g'] = Variable<double>(carbsG.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (exercisesJson.present) {
      map['exercises_json'] = Variable<String>(exercisesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientDailyMetricsCompanion(')
          ..write('clientId: $clientId, ')
          ..write('date: $date, ')
          ..write('completion: $completion, ')
          ..write('calories: $calories, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('sugarG: $sugarG, ')
          ..write('carbsG: $carbsG, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('exercisesJson: $exercisesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReportFeedbackDraftsTable extends ReportFeedbackDrafts
    with TableInfo<$ReportFeedbackDraftsTable, ReportFeedbackDraftRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReportFeedbackDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekStartMeta = const VerificationMeta(
    'weekStart',
  );
  @override
  late final GeneratedColumn<String> weekStart = GeneratedColumn<String>(
    'week_start',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [clientId, weekStart, body, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'report_feedback_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReportFeedbackDraftRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('week_start')) {
      context.handle(
        _weekStartMeta,
        weekStart.isAcceptableOrUnknown(data['week_start']!, _weekStartMeta),
      );
    } else if (isInserting) {
      context.missing(_weekStartMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientId, weekStart};
  @override
  ReportFeedbackDraftRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReportFeedbackDraftRow(
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      weekStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_start'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReportFeedbackDraftsTable createAlias(String alias) {
    return $ReportFeedbackDraftsTable(attachedDatabase, alias);
  }
}

class ReportFeedbackDraftRow extends DataClass
    implements Insertable<ReportFeedbackDraftRow> {
  final String clientId;
  final String weekStart;
  final String body;
  final DateTime updatedAt;
  const ReportFeedbackDraftRow({
    required this.clientId,
    required this.weekStart,
    required this.body,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['week_start'] = Variable<String>(weekStart);
    map['body'] = Variable<String>(body);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReportFeedbackDraftsCompanion toCompanion(bool nullToAbsent) {
    return ReportFeedbackDraftsCompanion(
      clientId: Value(clientId),
      weekStart: Value(weekStart),
      body: Value(body),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReportFeedbackDraftRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReportFeedbackDraftRow(
      clientId: serializer.fromJson<String>(json['clientId']),
      weekStart: serializer.fromJson<String>(json['weekStart']),
      body: serializer.fromJson<String>(json['body']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'weekStart': serializer.toJson<String>(weekStart),
      'body': serializer.toJson<String>(body),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReportFeedbackDraftRow copyWith({
    String? clientId,
    String? weekStart,
    String? body,
    DateTime? updatedAt,
  }) => ReportFeedbackDraftRow(
    clientId: clientId ?? this.clientId,
    weekStart: weekStart ?? this.weekStart,
    body: body ?? this.body,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReportFeedbackDraftRow copyWithCompanion(ReportFeedbackDraftsCompanion data) {
    return ReportFeedbackDraftRow(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      weekStart: data.weekStart.present ? data.weekStart.value : this.weekStart,
      body: data.body.present ? data.body.value : this.body,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReportFeedbackDraftRow(')
          ..write('clientId: $clientId, ')
          ..write('weekStart: $weekStart, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clientId, weekStart, body, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportFeedbackDraftRow &&
          other.clientId == this.clientId &&
          other.weekStart == this.weekStart &&
          other.body == this.body &&
          other.updatedAt == this.updatedAt);
}

class ReportFeedbackDraftsCompanion
    extends UpdateCompanion<ReportFeedbackDraftRow> {
  final Value<String> clientId;
  final Value<String> weekStart;
  final Value<String> body;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReportFeedbackDraftsCompanion({
    this.clientId = const Value.absent(),
    this.weekStart = const Value.absent(),
    this.body = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReportFeedbackDraftsCompanion.insert({
    required String clientId,
    required String weekStart,
    this.body = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : clientId = Value(clientId),
       weekStart = Value(weekStart),
       updatedAt = Value(updatedAt);
  static Insertable<ReportFeedbackDraftRow> custom({
    Expression<String>? clientId,
    Expression<String>? weekStart,
    Expression<String>? body,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (weekStart != null) 'week_start': weekStart,
      if (body != null) 'body': body,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReportFeedbackDraftsCompanion copyWith({
    Value<String>? clientId,
    Value<String>? weekStart,
    Value<String>? body,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReportFeedbackDraftsCompanion(
      clientId: clientId ?? this.clientId,
      weekStart: weekStart ?? this.weekStart,
      body: body ?? this.body,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (weekStart.present) {
      map['week_start'] = Variable<String>(weekStart.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReportFeedbackDraftsCompanion(')
          ..write('clientId: $clientId, ')
          ..write('weekStart: $weekStart, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppKeyValuesTable appKeyValues = $AppKeyValuesTable(this);
  late final $TrainerClientsTable trainerClients = $TrainerClientsTable(this);
  late final $ClientDietEntriesTable clientDietEntries =
      $ClientDietEntriesTable(this);
  late final $ClientAiRoutinesTable clientAiRoutines = $ClientAiRoutinesTable(
    this,
  );
  late final $ClientRoutineHistoryTable clientRoutineHistory =
      $ClientRoutineHistoryTable(this);
  late final $ClientChatMessagesTable clientChatMessages =
      $ClientChatMessagesTable(this);
  late final $TrainerScheduleEntriesTable trainerScheduleEntries =
      $TrainerScheduleEntriesTable(this);
  late final $ClientDailyMetricsTable clientDailyMetrics =
      $ClientDailyMetricsTable(this);
  late final $ReportFeedbackDraftsTable reportFeedbackDrafts =
      $ReportFeedbackDraftsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appKeyValues,
    trainerClients,
    clientDietEntries,
    clientAiRoutines,
    clientRoutineHistory,
    clientChatMessages,
    trainerScheduleEntries,
    clientDailyMetrics,
    reportFeedbackDrafts,
  ];
}

typedef $$AppKeyValuesTableCreateCompanionBuilder =
    AppKeyValuesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppKeyValuesTableUpdateCompanionBuilder =
    AppKeyValuesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppKeyValuesTableFilterComposer
    extends Composer<_$AppDatabase, $AppKeyValuesTable> {
  $$AppKeyValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppKeyValuesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppKeyValuesTable> {
  $$AppKeyValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppKeyValuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppKeyValuesTable> {
  $$AppKeyValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppKeyValuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppKeyValuesTable,
          AppKeyValue,
          $$AppKeyValuesTableFilterComposer,
          $$AppKeyValuesTableOrderingComposer,
          $$AppKeyValuesTableAnnotationComposer,
          $$AppKeyValuesTableCreateCompanionBuilder,
          $$AppKeyValuesTableUpdateCompanionBuilder,
          (
            AppKeyValue,
            BaseReferences<_$AppDatabase, $AppKeyValuesTable, AppKeyValue>,
          ),
          AppKeyValue,
          PrefetchHooks Function()
        > {
  $$AppKeyValuesTableTableManager(_$AppDatabase db, $AppKeyValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppKeyValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppKeyValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppKeyValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppKeyValuesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppKeyValuesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppKeyValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppKeyValuesTable,
      AppKeyValue,
      $$AppKeyValuesTableFilterComposer,
      $$AppKeyValuesTableOrderingComposer,
      $$AppKeyValuesTableAnnotationComposer,
      $$AppKeyValuesTableCreateCompanionBuilder,
      $$AppKeyValuesTableUpdateCompanionBuilder,
      (
        AppKeyValue,
        BaseReferences<_$AppDatabase, $AppKeyValuesTable, AppKeyValue>,
      ),
      AppKeyValue,
      PrefetchHooks Function()
    >;
typedef $$TrainerClientsTableCreateCompanionBuilder =
    TrainerClientsCompanion Function({
      required String id,
      required String name,
      required String avatar,
      required String goal,
      required String lastMessage,
      required String lastTime,
      Value<bool> active,
      required int caloriesToday,
      required int sodiumMg,
      required double sugarG,
      Value<double> carbsG,
      Value<double> proteinG,
      Value<double> fatG,
      required String lastRoutine,
      required String weekCompletionJson,
      Value<String> sodiumWeekJson,
      Value<String> caloriesWeekJson,
      Value<String> sugarWeekJson,
      Value<int> sortOrder,
      Value<String?> gender,
      Value<int?> age,
      Value<int> rowid,
    });
typedef $$TrainerClientsTableUpdateCompanionBuilder =
    TrainerClientsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> avatar,
      Value<String> goal,
      Value<String> lastMessage,
      Value<String> lastTime,
      Value<bool> active,
      Value<int> caloriesToday,
      Value<int> sodiumMg,
      Value<double> sugarG,
      Value<double> carbsG,
      Value<double> proteinG,
      Value<double> fatG,
      Value<String> lastRoutine,
      Value<String> weekCompletionJson,
      Value<String> sodiumWeekJson,
      Value<String> caloriesWeekJson,
      Value<String> sugarWeekJson,
      Value<int> sortOrder,
      Value<String?> gender,
      Value<int?> age,
      Value<int> rowid,
    });

class $$TrainerClientsTableFilterComposer
    extends Composer<_$AppDatabase, $TrainerClientsTable> {
  $$TrainerClientsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastTime => $composableBuilder(
    column: $table.lastTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get caloriesToday => $composableBuilder(
    column: $table.caloriesToday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRoutine => $composableBuilder(
    column: $table.lastRoutine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weekCompletionJson => $composableBuilder(
    column: $table.weekCompletionJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sodiumWeekJson => $composableBuilder(
    column: $table.sodiumWeekJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caloriesWeekJson => $composableBuilder(
    column: $table.caloriesWeekJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sugarWeekJson => $composableBuilder(
    column: $table.sugarWeekJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrainerClientsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrainerClientsTable> {
  $$TrainerClientsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastTime => $composableBuilder(
    column: $table.lastTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get caloriesToday => $composableBuilder(
    column: $table.caloriesToday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRoutine => $composableBuilder(
    column: $table.lastRoutine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekCompletionJson => $composableBuilder(
    column: $table.weekCompletionJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sodiumWeekJson => $composableBuilder(
    column: $table.sodiumWeekJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caloriesWeekJson => $composableBuilder(
    column: $table.caloriesWeekJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sugarWeekJson => $composableBuilder(
    column: $table.sugarWeekJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrainerClientsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrainerClientsTable> {
  $$TrainerClientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<String> get goal =>
      $composableBuilder(column: $table.goal, builder: (column) => column);

  GeneratedColumn<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastTime =>
      $composableBuilder(column: $table.lastTime, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get caloriesToday => $composableBuilder(
    column: $table.caloriesToday,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sodiumMg =>
      $composableBuilder(column: $table.sodiumMg, builder: (column) => column);

  GeneratedColumn<double> get sugarG =>
      $composableBuilder(column: $table.sugarG, builder: (column) => column);

  GeneratedColumn<double> get carbsG =>
      $composableBuilder(column: $table.carbsG, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<String> get lastRoutine => $composableBuilder(
    column: $table.lastRoutine,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weekCompletionJson => $composableBuilder(
    column: $table.weekCompletionJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sodiumWeekJson => $composableBuilder(
    column: $table.sodiumWeekJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get caloriesWeekJson => $composableBuilder(
    column: $table.caloriesWeekJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sugarWeekJson => $composableBuilder(
    column: $table.sugarWeekJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<int> get age =>
      $composableBuilder(column: $table.age, builder: (column) => column);
}

class $$TrainerClientsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrainerClientsTable,
          TrainerClientRow,
          $$TrainerClientsTableFilterComposer,
          $$TrainerClientsTableOrderingComposer,
          $$TrainerClientsTableAnnotationComposer,
          $$TrainerClientsTableCreateCompanionBuilder,
          $$TrainerClientsTableUpdateCompanionBuilder,
          (
            TrainerClientRow,
            BaseReferences<
              _$AppDatabase,
              $TrainerClientsTable,
              TrainerClientRow
            >,
          ),
          TrainerClientRow,
          PrefetchHooks Function()
        > {
  $$TrainerClientsTableTableManager(
    _$AppDatabase db,
    $TrainerClientsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrainerClientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrainerClientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrainerClientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<String> goal = const Value.absent(),
                Value<String> lastMessage = const Value.absent(),
                Value<String> lastTime = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> caloriesToday = const Value.absent(),
                Value<int> sodiumMg = const Value.absent(),
                Value<double> sugarG = const Value.absent(),
                Value<double> carbsG = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<String> lastRoutine = const Value.absent(),
                Value<String> weekCompletionJson = const Value.absent(),
                Value<String> sodiumWeekJson = const Value.absent(),
                Value<String> caloriesWeekJson = const Value.absent(),
                Value<String> sugarWeekJson = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> gender = const Value.absent(),
                Value<int?> age = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrainerClientsCompanion(
                id: id,
                name: name,
                avatar: avatar,
                goal: goal,
                lastMessage: lastMessage,
                lastTime: lastTime,
                active: active,
                caloriesToday: caloriesToday,
                sodiumMg: sodiumMg,
                sugarG: sugarG,
                carbsG: carbsG,
                proteinG: proteinG,
                fatG: fatG,
                lastRoutine: lastRoutine,
                weekCompletionJson: weekCompletionJson,
                sodiumWeekJson: sodiumWeekJson,
                caloriesWeekJson: caloriesWeekJson,
                sugarWeekJson: sugarWeekJson,
                sortOrder: sortOrder,
                gender: gender,
                age: age,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String avatar,
                required String goal,
                required String lastMessage,
                required String lastTime,
                Value<bool> active = const Value.absent(),
                required int caloriesToday,
                required int sodiumMg,
                required double sugarG,
                Value<double> carbsG = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                required String lastRoutine,
                required String weekCompletionJson,
                Value<String> sodiumWeekJson = const Value.absent(),
                Value<String> caloriesWeekJson = const Value.absent(),
                Value<String> sugarWeekJson = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> gender = const Value.absent(),
                Value<int?> age = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrainerClientsCompanion.insert(
                id: id,
                name: name,
                avatar: avatar,
                goal: goal,
                lastMessage: lastMessage,
                lastTime: lastTime,
                active: active,
                caloriesToday: caloriesToday,
                sodiumMg: sodiumMg,
                sugarG: sugarG,
                carbsG: carbsG,
                proteinG: proteinG,
                fatG: fatG,
                lastRoutine: lastRoutine,
                weekCompletionJson: weekCompletionJson,
                sodiumWeekJson: sodiumWeekJson,
                caloriesWeekJson: caloriesWeekJson,
                sugarWeekJson: sugarWeekJson,
                sortOrder: sortOrder,
                gender: gender,
                age: age,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrainerClientsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrainerClientsTable,
      TrainerClientRow,
      $$TrainerClientsTableFilterComposer,
      $$TrainerClientsTableOrderingComposer,
      $$TrainerClientsTableAnnotationComposer,
      $$TrainerClientsTableCreateCompanionBuilder,
      $$TrainerClientsTableUpdateCompanionBuilder,
      (
        TrainerClientRow,
        BaseReferences<_$AppDatabase, $TrainerClientsTable, TrainerClientRow>,
      ),
      TrainerClientRow,
      PrefetchHooks Function()
    >;
typedef $$ClientDietEntriesTableCreateCompanionBuilder =
    ClientDietEntriesCompanion Function({
      required String id,
      required String clientId,
      required String meal,
      required String items,
      required int calories,
      required int sodiumMg,
      Value<double> carbsG,
      Value<double> proteinG,
      Value<double> fatG,
      Value<double> sugarG,
      Value<String> date,
      Value<String> timeLabel,
      Value<String> foodsJson,
      Value<String?> photoAsset,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$ClientDietEntriesTableUpdateCompanionBuilder =
    ClientDietEntriesCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<String> meal,
      Value<String> items,
      Value<int> calories,
      Value<int> sodiumMg,
      Value<double> carbsG,
      Value<double> proteinG,
      Value<double> fatG,
      Value<double> sugarG,
      Value<String> date,
      Value<String> timeLabel,
      Value<String> foodsJson,
      Value<String?> photoAsset,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$ClientDietEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ClientDietEntriesTable> {
  $$ClientDietEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meal => $composableBuilder(
    column: $table.meal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get items => $composableBuilder(
    column: $table.items,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get foodsJson => $composableBuilder(
    column: $table.foodsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoAsset => $composableBuilder(
    column: $table.photoAsset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientDietEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientDietEntriesTable> {
  $$ClientDietEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meal => $composableBuilder(
    column: $table.meal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get items => $composableBuilder(
    column: $table.items,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foodsJson => $composableBuilder(
    column: $table.foodsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoAsset => $composableBuilder(
    column: $table.photoAsset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientDietEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientDietEntriesTable> {
  $$ClientDietEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get meal =>
      $composableBuilder(column: $table.meal, builder: (column) => column);

  GeneratedColumn<String> get items =>
      $composableBuilder(column: $table.items, builder: (column) => column);

  GeneratedColumn<int> get calories =>
      $composableBuilder(column: $table.calories, builder: (column) => column);

  GeneratedColumn<int> get sodiumMg =>
      $composableBuilder(column: $table.sodiumMg, builder: (column) => column);

  GeneratedColumn<double> get carbsG =>
      $composableBuilder(column: $table.carbsG, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<double> get sugarG =>
      $composableBuilder(column: $table.sugarG, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get timeLabel =>
      $composableBuilder(column: $table.timeLabel, builder: (column) => column);

  GeneratedColumn<String> get foodsJson =>
      $composableBuilder(column: $table.foodsJson, builder: (column) => column);

  GeneratedColumn<String> get photoAsset => $composableBuilder(
    column: $table.photoAsset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$ClientDietEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientDietEntriesTable,
          ClientDietEntryRow,
          $$ClientDietEntriesTableFilterComposer,
          $$ClientDietEntriesTableOrderingComposer,
          $$ClientDietEntriesTableAnnotationComposer,
          $$ClientDietEntriesTableCreateCompanionBuilder,
          $$ClientDietEntriesTableUpdateCompanionBuilder,
          (
            ClientDietEntryRow,
            BaseReferences<
              _$AppDatabase,
              $ClientDietEntriesTable,
              ClientDietEntryRow
            >,
          ),
          ClientDietEntryRow,
          PrefetchHooks Function()
        > {
  $$ClientDietEntriesTableTableManager(
    _$AppDatabase db,
    $ClientDietEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientDietEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientDietEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientDietEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> meal = const Value.absent(),
                Value<String> items = const Value.absent(),
                Value<int> calories = const Value.absent(),
                Value<int> sodiumMg = const Value.absent(),
                Value<double> carbsG = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<double> sugarG = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> timeLabel = const Value.absent(),
                Value<String> foodsJson = const Value.absent(),
                Value<String?> photoAsset = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientDietEntriesCompanion(
                id: id,
                clientId: clientId,
                meal: meal,
                items: items,
                calories: calories,
                sodiumMg: sodiumMg,
                carbsG: carbsG,
                proteinG: proteinG,
                fatG: fatG,
                sugarG: sugarG,
                date: date,
                timeLabel: timeLabel,
                foodsJson: foodsJson,
                photoAsset: photoAsset,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                required String meal,
                required String items,
                required int calories,
                required int sodiumMg,
                Value<double> carbsG = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<double> sugarG = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> timeLabel = const Value.absent(),
                Value<String> foodsJson = const Value.absent(),
                Value<String?> photoAsset = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientDietEntriesCompanion.insert(
                id: id,
                clientId: clientId,
                meal: meal,
                items: items,
                calories: calories,
                sodiumMg: sodiumMg,
                carbsG: carbsG,
                proteinG: proteinG,
                fatG: fatG,
                sugarG: sugarG,
                date: date,
                timeLabel: timeLabel,
                foodsJson: foodsJson,
                photoAsset: photoAsset,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientDietEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientDietEntriesTable,
      ClientDietEntryRow,
      $$ClientDietEntriesTableFilterComposer,
      $$ClientDietEntriesTableOrderingComposer,
      $$ClientDietEntriesTableAnnotationComposer,
      $$ClientDietEntriesTableCreateCompanionBuilder,
      $$ClientDietEntriesTableUpdateCompanionBuilder,
      (
        ClientDietEntryRow,
        BaseReferences<
          _$AppDatabase,
          $ClientDietEntriesTable,
          ClientDietEntryRow
        >,
      ),
      ClientDietEntryRow,
      PrefetchHooks Function()
    >;
typedef $$ClientAiRoutinesTableCreateCompanionBuilder =
    ClientAiRoutinesCompanion Function({
      required String id,
      required String clientId,
      required String name,
      required int minutes,
      required String type,
      required String reason,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$ClientAiRoutinesTableUpdateCompanionBuilder =
    ClientAiRoutinesCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<String> name,
      Value<int> minutes,
      Value<String> type,
      Value<String> reason,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$ClientAiRoutinesTableFilterComposer
    extends Composer<_$AppDatabase, $ClientAiRoutinesTable> {
  $$ClientAiRoutinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minutes => $composableBuilder(
    column: $table.minutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientAiRoutinesTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientAiRoutinesTable> {
  $$ClientAiRoutinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minutes => $composableBuilder(
    column: $table.minutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientAiRoutinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientAiRoutinesTable> {
  $$ClientAiRoutinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get minutes =>
      $composableBuilder(column: $table.minutes, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$ClientAiRoutinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientAiRoutinesTable,
          ClientAiRoutineRow,
          $$ClientAiRoutinesTableFilterComposer,
          $$ClientAiRoutinesTableOrderingComposer,
          $$ClientAiRoutinesTableAnnotationComposer,
          $$ClientAiRoutinesTableCreateCompanionBuilder,
          $$ClientAiRoutinesTableUpdateCompanionBuilder,
          (
            ClientAiRoutineRow,
            BaseReferences<
              _$AppDatabase,
              $ClientAiRoutinesTable,
              ClientAiRoutineRow
            >,
          ),
          ClientAiRoutineRow,
          PrefetchHooks Function()
        > {
  $$ClientAiRoutinesTableTableManager(
    _$AppDatabase db,
    $ClientAiRoutinesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientAiRoutinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientAiRoutinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientAiRoutinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> minutes = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientAiRoutinesCompanion(
                id: id,
                clientId: clientId,
                name: name,
                minutes: minutes,
                type: type,
                reason: reason,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                required String name,
                required int minutes,
                required String type,
                required String reason,
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientAiRoutinesCompanion.insert(
                id: id,
                clientId: clientId,
                name: name,
                minutes: minutes,
                type: type,
                reason: reason,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientAiRoutinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientAiRoutinesTable,
      ClientAiRoutineRow,
      $$ClientAiRoutinesTableFilterComposer,
      $$ClientAiRoutinesTableOrderingComposer,
      $$ClientAiRoutinesTableAnnotationComposer,
      $$ClientAiRoutinesTableCreateCompanionBuilder,
      $$ClientAiRoutinesTableUpdateCompanionBuilder,
      (
        ClientAiRoutineRow,
        BaseReferences<
          _$AppDatabase,
          $ClientAiRoutinesTable,
          ClientAiRoutineRow
        >,
      ),
      ClientAiRoutineRow,
      PrefetchHooks Function()
    >;
typedef $$ClientRoutineHistoryTableCreateCompanionBuilder =
    ClientRoutineHistoryCompanion Function({
      required String id,
      required String clientId,
      required String dateLabel,
      required String label,
      required int completionRate,
      required String exercisesJson,
      Value<String> clientFeedback,
      Value<String> trainerNote,
      Value<int> sortOrder,
      Value<DateTime?> completedAt,
      Value<int> rowid,
    });
typedef $$ClientRoutineHistoryTableUpdateCompanionBuilder =
    ClientRoutineHistoryCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<String> dateLabel,
      Value<String> label,
      Value<int> completionRate,
      Value<String> exercisesJson,
      Value<String> clientFeedback,
      Value<String> trainerNote,
      Value<int> sortOrder,
      Value<DateTime?> completedAt,
      Value<int> rowid,
    });

class $$ClientRoutineHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $ClientRoutineHistoryTable> {
  $$ClientRoutineHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dateLabel => $composableBuilder(
    column: $table.dateLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completionRate => $composableBuilder(
    column: $table.completionRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exercisesJson => $composableBuilder(
    column: $table.exercisesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientFeedback => $composableBuilder(
    column: $table.clientFeedback,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trainerNote => $composableBuilder(
    column: $table.trainerNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientRoutineHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientRoutineHistoryTable> {
  $$ClientRoutineHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dateLabel => $composableBuilder(
    column: $table.dateLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completionRate => $composableBuilder(
    column: $table.completionRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exercisesJson => $composableBuilder(
    column: $table.exercisesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientFeedback => $composableBuilder(
    column: $table.clientFeedback,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trainerNote => $composableBuilder(
    column: $table.trainerNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientRoutineHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientRoutineHistoryTable> {
  $$ClientRoutineHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get dateLabel =>
      $composableBuilder(column: $table.dateLabel, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get completionRate => $composableBuilder(
    column: $table.completionRate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exercisesJson => $composableBuilder(
    column: $table.exercisesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clientFeedback => $composableBuilder(
    column: $table.clientFeedback,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trainerNote => $composableBuilder(
    column: $table.trainerNote,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );
}

class $$ClientRoutineHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientRoutineHistoryTable,
          ClientRoutineHistoryRow,
          $$ClientRoutineHistoryTableFilterComposer,
          $$ClientRoutineHistoryTableOrderingComposer,
          $$ClientRoutineHistoryTableAnnotationComposer,
          $$ClientRoutineHistoryTableCreateCompanionBuilder,
          $$ClientRoutineHistoryTableUpdateCompanionBuilder,
          (
            ClientRoutineHistoryRow,
            BaseReferences<
              _$AppDatabase,
              $ClientRoutineHistoryTable,
              ClientRoutineHistoryRow
            >,
          ),
          ClientRoutineHistoryRow,
          PrefetchHooks Function()
        > {
  $$ClientRoutineHistoryTableTableManager(
    _$AppDatabase db,
    $ClientRoutineHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientRoutineHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientRoutineHistoryTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ClientRoutineHistoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> dateLabel = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> completionRate = const Value.absent(),
                Value<String> exercisesJson = const Value.absent(),
                Value<String> clientFeedback = const Value.absent(),
                Value<String> trainerNote = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientRoutineHistoryCompanion(
                id: id,
                clientId: clientId,
                dateLabel: dateLabel,
                label: label,
                completionRate: completionRate,
                exercisesJson: exercisesJson,
                clientFeedback: clientFeedback,
                trainerNote: trainerNote,
                sortOrder: sortOrder,
                completedAt: completedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                required String dateLabel,
                required String label,
                required int completionRate,
                required String exercisesJson,
                Value<String> clientFeedback = const Value.absent(),
                Value<String> trainerNote = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientRoutineHistoryCompanion.insert(
                id: id,
                clientId: clientId,
                dateLabel: dateLabel,
                label: label,
                completionRate: completionRate,
                exercisesJson: exercisesJson,
                clientFeedback: clientFeedback,
                trainerNote: trainerNote,
                sortOrder: sortOrder,
                completedAt: completedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientRoutineHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientRoutineHistoryTable,
      ClientRoutineHistoryRow,
      $$ClientRoutineHistoryTableFilterComposer,
      $$ClientRoutineHistoryTableOrderingComposer,
      $$ClientRoutineHistoryTableAnnotationComposer,
      $$ClientRoutineHistoryTableCreateCompanionBuilder,
      $$ClientRoutineHistoryTableUpdateCompanionBuilder,
      (
        ClientRoutineHistoryRow,
        BaseReferences<
          _$AppDatabase,
          $ClientRoutineHistoryTable,
          ClientRoutineHistoryRow
        >,
      ),
      ClientRoutineHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$ClientChatMessagesTableCreateCompanionBuilder =
    ClientChatMessagesCompanion Function({
      required String id,
      required String clientId,
      required String sender,
      required String body,
      required String timeLabel,
      required DateTime createdAt,
      Value<String?> emoteId,
      Value<int> rowid,
    });
typedef $$ClientChatMessagesTableUpdateCompanionBuilder =
    ClientChatMessagesCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<String> sender,
      Value<String> body,
      Value<String> timeLabel,
      Value<DateTime> createdAt,
      Value<String?> emoteId,
      Value<int> rowid,
    });

class $$ClientChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ClientChatMessagesTable> {
  $$ClientChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoteId => $composableBuilder(
    column: $table.emoteId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientChatMessagesTable> {
  $$ClientChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoteId => $composableBuilder(
    column: $table.emoteId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientChatMessagesTable> {
  $$ClientChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get timeLabel =>
      $composableBuilder(column: $table.timeLabel, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get emoteId =>
      $composableBuilder(column: $table.emoteId, builder: (column) => column);
}

class $$ClientChatMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientChatMessagesTable,
          ClientChatMessageRow,
          $$ClientChatMessagesTableFilterComposer,
          $$ClientChatMessagesTableOrderingComposer,
          $$ClientChatMessagesTableAnnotationComposer,
          $$ClientChatMessagesTableCreateCompanionBuilder,
          $$ClientChatMessagesTableUpdateCompanionBuilder,
          (
            ClientChatMessageRow,
            BaseReferences<
              _$AppDatabase,
              $ClientChatMessagesTable,
              ClientChatMessageRow
            >,
          ),
          ClientChatMessageRow,
          PrefetchHooks Function()
        > {
  $$ClientChatMessagesTableTableManager(
    _$AppDatabase db,
    $ClientChatMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientChatMessagesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> timeLabel = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> emoteId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientChatMessagesCompanion(
                id: id,
                clientId: clientId,
                sender: sender,
                body: body,
                timeLabel: timeLabel,
                createdAt: createdAt,
                emoteId: emoteId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                required String sender,
                required String body,
                required String timeLabel,
                required DateTime createdAt,
                Value<String?> emoteId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientChatMessagesCompanion.insert(
                id: id,
                clientId: clientId,
                sender: sender,
                body: body,
                timeLabel: timeLabel,
                createdAt: createdAt,
                emoteId: emoteId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientChatMessagesTable,
      ClientChatMessageRow,
      $$ClientChatMessagesTableFilterComposer,
      $$ClientChatMessagesTableOrderingComposer,
      $$ClientChatMessagesTableAnnotationComposer,
      $$ClientChatMessagesTableCreateCompanionBuilder,
      $$ClientChatMessagesTableUpdateCompanionBuilder,
      (
        ClientChatMessageRow,
        BaseReferences<
          _$AppDatabase,
          $ClientChatMessagesTable,
          ClientChatMessageRow
        >,
      ),
      ClientChatMessageRow,
      PrefetchHooks Function()
    >;
typedef $$TrainerScheduleEntriesTableCreateCompanionBuilder =
    TrainerScheduleEntriesCompanion Function({
      required String id,
      required String date,
      required String time,
      Value<String?> clientId,
      Value<String> clientName,
      Value<String> type,
      Value<int> durationMinutes,
      required String status,
      Value<DateTime?> cancelledAt,
      Value<String> cancellationSource,
      Value<String> cancellationReason,
      Value<DateTime?> noShowAt,
      Value<String> note,
      Value<String> programJson,
      Value<bool> programSent,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$TrainerScheduleEntriesTableUpdateCompanionBuilder =
    TrainerScheduleEntriesCompanion Function({
      Value<String> id,
      Value<String> date,
      Value<String> time,
      Value<String?> clientId,
      Value<String> clientName,
      Value<String> type,
      Value<int> durationMinutes,
      Value<String> status,
      Value<DateTime?> cancelledAt,
      Value<String> cancellationSource,
      Value<String> cancellationReason,
      Value<DateTime?> noShowAt,
      Value<String> note,
      Value<String> programJson,
      Value<bool> programSent,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$TrainerScheduleEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $TrainerScheduleEntriesTable> {
  $$TrainerScheduleEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientName => $composableBuilder(
    column: $table.clientName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cancelledAt => $composableBuilder(
    column: $table.cancelledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cancellationSource => $composableBuilder(
    column: $table.cancellationSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cancellationReason => $composableBuilder(
    column: $table.cancellationReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get noShowAt => $composableBuilder(
    column: $table.noShowAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get programJson => $composableBuilder(
    column: $table.programJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get programSent => $composableBuilder(
    column: $table.programSent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrainerScheduleEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $TrainerScheduleEntriesTable> {
  $$TrainerScheduleEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientName => $composableBuilder(
    column: $table.clientName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cancelledAt => $composableBuilder(
    column: $table.cancelledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cancellationSource => $composableBuilder(
    column: $table.cancellationSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cancellationReason => $composableBuilder(
    column: $table.cancellationReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get noShowAt => $composableBuilder(
    column: $table.noShowAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get programJson => $composableBuilder(
    column: $table.programJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get programSent => $composableBuilder(
    column: $table.programSent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrainerScheduleEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrainerScheduleEntriesTable> {
  $$TrainerScheduleEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get clientName => $composableBuilder(
    column: $table.clientName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get cancelledAt => $composableBuilder(
    column: $table.cancelledAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cancellationSource => $composableBuilder(
    column: $table.cancellationSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cancellationReason => $composableBuilder(
    column: $table.cancellationReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get noShowAt =>
      $composableBuilder(column: $table.noShowAt, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get programJson => $composableBuilder(
    column: $table.programJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get programSent => $composableBuilder(
    column: $table.programSent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$TrainerScheduleEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrainerScheduleEntriesTable,
          TrainerScheduleRow,
          $$TrainerScheduleEntriesTableFilterComposer,
          $$TrainerScheduleEntriesTableOrderingComposer,
          $$TrainerScheduleEntriesTableAnnotationComposer,
          $$TrainerScheduleEntriesTableCreateCompanionBuilder,
          $$TrainerScheduleEntriesTableUpdateCompanionBuilder,
          (
            TrainerScheduleRow,
            BaseReferences<
              _$AppDatabase,
              $TrainerScheduleEntriesTable,
              TrainerScheduleRow
            >,
          ),
          TrainerScheduleRow,
          PrefetchHooks Function()
        > {
  $$TrainerScheduleEntriesTableTableManager(
    _$AppDatabase db,
    $TrainerScheduleEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrainerScheduleEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$TrainerScheduleEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TrainerScheduleEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> time = const Value.absent(),
                Value<String?> clientId = const Value.absent(),
                Value<String> clientName = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> durationMinutes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> cancelledAt = const Value.absent(),
                Value<String> cancellationSource = const Value.absent(),
                Value<String> cancellationReason = const Value.absent(),
                Value<DateTime?> noShowAt = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String> programJson = const Value.absent(),
                Value<bool> programSent = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrainerScheduleEntriesCompanion(
                id: id,
                date: date,
                time: time,
                clientId: clientId,
                clientName: clientName,
                type: type,
                durationMinutes: durationMinutes,
                status: status,
                cancelledAt: cancelledAt,
                cancellationSource: cancellationSource,
                cancellationReason: cancellationReason,
                noShowAt: noShowAt,
                note: note,
                programJson: programJson,
                programSent: programSent,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String date,
                required String time,
                Value<String?> clientId = const Value.absent(),
                Value<String> clientName = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> durationMinutes = const Value.absent(),
                required String status,
                Value<DateTime?> cancelledAt = const Value.absent(),
                Value<String> cancellationSource = const Value.absent(),
                Value<String> cancellationReason = const Value.absent(),
                Value<DateTime?> noShowAt = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String> programJson = const Value.absent(),
                Value<bool> programSent = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrainerScheduleEntriesCompanion.insert(
                id: id,
                date: date,
                time: time,
                clientId: clientId,
                clientName: clientName,
                type: type,
                durationMinutes: durationMinutes,
                status: status,
                cancelledAt: cancelledAt,
                cancellationSource: cancellationSource,
                cancellationReason: cancellationReason,
                noShowAt: noShowAt,
                note: note,
                programJson: programJson,
                programSent: programSent,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrainerScheduleEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrainerScheduleEntriesTable,
      TrainerScheduleRow,
      $$TrainerScheduleEntriesTableFilterComposer,
      $$TrainerScheduleEntriesTableOrderingComposer,
      $$TrainerScheduleEntriesTableAnnotationComposer,
      $$TrainerScheduleEntriesTableCreateCompanionBuilder,
      $$TrainerScheduleEntriesTableUpdateCompanionBuilder,
      (
        TrainerScheduleRow,
        BaseReferences<
          _$AppDatabase,
          $TrainerScheduleEntriesTable,
          TrainerScheduleRow
        >,
      ),
      TrainerScheduleRow,
      PrefetchHooks Function()
    >;
typedef $$ClientDailyMetricsTableCreateCompanionBuilder =
    ClientDailyMetricsCompanion Function({
      required String clientId,
      required String date,
      Value<int> completion,
      Value<int> calories,
      Value<int> sodiumMg,
      Value<double> sugarG,
      Value<double> carbsG,
      Value<double> proteinG,
      Value<double> fatG,
      Value<String> exercisesJson,
      Value<int> rowid,
    });
typedef $$ClientDailyMetricsTableUpdateCompanionBuilder =
    ClientDailyMetricsCompanion Function({
      Value<String> clientId,
      Value<String> date,
      Value<int> completion,
      Value<int> calories,
      Value<int> sodiumMg,
      Value<double> sugarG,
      Value<double> carbsG,
      Value<double> proteinG,
      Value<double> fatG,
      Value<String> exercisesJson,
      Value<int> rowid,
    });

class $$ClientDailyMetricsTableFilterComposer
    extends Composer<_$AppDatabase, $ClientDailyMetricsTable> {
  $$ClientDailyMetricsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completion => $composableBuilder(
    column: $table.completion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exercisesJson => $composableBuilder(
    column: $table.exercisesJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientDailyMetricsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientDailyMetricsTable> {
  $$ClientDailyMetricsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completion => $composableBuilder(
    column: $table.completion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sodiumMg => $composableBuilder(
    column: $table.sodiumMg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exercisesJson => $composableBuilder(
    column: $table.exercisesJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientDailyMetricsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientDailyMetricsTable> {
  $$ClientDailyMetricsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get completion => $composableBuilder(
    column: $table.completion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get calories =>
      $composableBuilder(column: $table.calories, builder: (column) => column);

  GeneratedColumn<int> get sodiumMg =>
      $composableBuilder(column: $table.sodiumMg, builder: (column) => column);

  GeneratedColumn<double> get sugarG =>
      $composableBuilder(column: $table.sugarG, builder: (column) => column);

  GeneratedColumn<double> get carbsG =>
      $composableBuilder(column: $table.carbsG, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<String> get exercisesJson => $composableBuilder(
    column: $table.exercisesJson,
    builder: (column) => column,
  );
}

class $$ClientDailyMetricsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientDailyMetricsTable,
          ClientDailyMetricRow,
          $$ClientDailyMetricsTableFilterComposer,
          $$ClientDailyMetricsTableOrderingComposer,
          $$ClientDailyMetricsTableAnnotationComposer,
          $$ClientDailyMetricsTableCreateCompanionBuilder,
          $$ClientDailyMetricsTableUpdateCompanionBuilder,
          (
            ClientDailyMetricRow,
            BaseReferences<
              _$AppDatabase,
              $ClientDailyMetricsTable,
              ClientDailyMetricRow
            >,
          ),
          ClientDailyMetricRow,
          PrefetchHooks Function()
        > {
  $$ClientDailyMetricsTableTableManager(
    _$AppDatabase db,
    $ClientDailyMetricsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientDailyMetricsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientDailyMetricsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientDailyMetricsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> clientId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> completion = const Value.absent(),
                Value<int> calories = const Value.absent(),
                Value<int> sodiumMg = const Value.absent(),
                Value<double> sugarG = const Value.absent(),
                Value<double> carbsG = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<String> exercisesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientDailyMetricsCompanion(
                clientId: clientId,
                date: date,
                completion: completion,
                calories: calories,
                sodiumMg: sodiumMg,
                sugarG: sugarG,
                carbsG: carbsG,
                proteinG: proteinG,
                fatG: fatG,
                exercisesJson: exercisesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientId,
                required String date,
                Value<int> completion = const Value.absent(),
                Value<int> calories = const Value.absent(),
                Value<int> sodiumMg = const Value.absent(),
                Value<double> sugarG = const Value.absent(),
                Value<double> carbsG = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<String> exercisesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientDailyMetricsCompanion.insert(
                clientId: clientId,
                date: date,
                completion: completion,
                calories: calories,
                sodiumMg: sodiumMg,
                sugarG: sugarG,
                carbsG: carbsG,
                proteinG: proteinG,
                fatG: fatG,
                exercisesJson: exercisesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientDailyMetricsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientDailyMetricsTable,
      ClientDailyMetricRow,
      $$ClientDailyMetricsTableFilterComposer,
      $$ClientDailyMetricsTableOrderingComposer,
      $$ClientDailyMetricsTableAnnotationComposer,
      $$ClientDailyMetricsTableCreateCompanionBuilder,
      $$ClientDailyMetricsTableUpdateCompanionBuilder,
      (
        ClientDailyMetricRow,
        BaseReferences<
          _$AppDatabase,
          $ClientDailyMetricsTable,
          ClientDailyMetricRow
        >,
      ),
      ClientDailyMetricRow,
      PrefetchHooks Function()
    >;
typedef $$ReportFeedbackDraftsTableCreateCompanionBuilder =
    ReportFeedbackDraftsCompanion Function({
      required String clientId,
      required String weekStart,
      Value<String> body,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReportFeedbackDraftsTableUpdateCompanionBuilder =
    ReportFeedbackDraftsCompanion Function({
      Value<String> clientId,
      Value<String> weekStart,
      Value<String> body,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReportFeedbackDraftsTableFilterComposer
    extends Composer<_$AppDatabase, $ReportFeedbackDraftsTable> {
  $$ReportFeedbackDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weekStart => $composableBuilder(
    column: $table.weekStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReportFeedbackDraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReportFeedbackDraftsTable> {
  $$ReportFeedbackDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekStart => $composableBuilder(
    column: $table.weekStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReportFeedbackDraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReportFeedbackDraftsTable> {
  $$ReportFeedbackDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get weekStart =>
      $composableBuilder(column: $table.weekStart, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReportFeedbackDraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReportFeedbackDraftsTable,
          ReportFeedbackDraftRow,
          $$ReportFeedbackDraftsTableFilterComposer,
          $$ReportFeedbackDraftsTableOrderingComposer,
          $$ReportFeedbackDraftsTableAnnotationComposer,
          $$ReportFeedbackDraftsTableCreateCompanionBuilder,
          $$ReportFeedbackDraftsTableUpdateCompanionBuilder,
          (
            ReportFeedbackDraftRow,
            BaseReferences<
              _$AppDatabase,
              $ReportFeedbackDraftsTable,
              ReportFeedbackDraftRow
            >,
          ),
          ReportFeedbackDraftRow,
          PrefetchHooks Function()
        > {
  $$ReportFeedbackDraftsTableTableManager(
    _$AppDatabase db,
    $ReportFeedbackDraftsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReportFeedbackDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReportFeedbackDraftsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReportFeedbackDraftsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> clientId = const Value.absent(),
                Value<String> weekStart = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReportFeedbackDraftsCompanion(
                clientId: clientId,
                weekStart: weekStart,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientId,
                required String weekStart,
                Value<String> body = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReportFeedbackDraftsCompanion.insert(
                clientId: clientId,
                weekStart: weekStart,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReportFeedbackDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReportFeedbackDraftsTable,
      ReportFeedbackDraftRow,
      $$ReportFeedbackDraftsTableFilterComposer,
      $$ReportFeedbackDraftsTableOrderingComposer,
      $$ReportFeedbackDraftsTableAnnotationComposer,
      $$ReportFeedbackDraftsTableCreateCompanionBuilder,
      $$ReportFeedbackDraftsTableUpdateCompanionBuilder,
      (
        ReportFeedbackDraftRow,
        BaseReferences<
          _$AppDatabase,
          $ReportFeedbackDraftsTable,
          ReportFeedbackDraftRow
        >,
      ),
      ReportFeedbackDraftRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppKeyValuesTableTableManager get appKeyValues =>
      $$AppKeyValuesTableTableManager(_db, _db.appKeyValues);
  $$TrainerClientsTableTableManager get trainerClients =>
      $$TrainerClientsTableTableManager(_db, _db.trainerClients);
  $$ClientDietEntriesTableTableManager get clientDietEntries =>
      $$ClientDietEntriesTableTableManager(_db, _db.clientDietEntries);
  $$ClientAiRoutinesTableTableManager get clientAiRoutines =>
      $$ClientAiRoutinesTableTableManager(_db, _db.clientAiRoutines);
  $$ClientRoutineHistoryTableTableManager get clientRoutineHistory =>
      $$ClientRoutineHistoryTableTableManager(_db, _db.clientRoutineHistory);
  $$ClientChatMessagesTableTableManager get clientChatMessages =>
      $$ClientChatMessagesTableTableManager(_db, _db.clientChatMessages);
  $$TrainerScheduleEntriesTableTableManager get trainerScheduleEntries =>
      $$TrainerScheduleEntriesTableTableManager(
        _db,
        _db.trainerScheduleEntries,
      );
  $$ClientDailyMetricsTableTableManager get clientDailyMetrics =>
      $$ClientDailyMetricsTableTableManager(_db, _db.clientDailyMetrics);
  $$ReportFeedbackDraftsTableTableManager get reportFeedbackDrafts =>
      $$ReportFeedbackDraftsTableTableManager(_db, _db.reportFeedbackDrafts);
}
