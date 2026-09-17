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

class $DietEntriesTable extends DietEntries
    with TableInfo<$DietEntriesTable, DietEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DietEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _mealTypeMeta = const VerificationMeta(
    'mealType',
  );
  @override
  late final GeneratedColumn<String> mealType = GeneratedColumn<String>(
    'meal_type',
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
  static const VerificationMeta _foodsJsonMeta = const VerificationMeta(
    'foodsJson',
  );
  @override
  late final GeneratedColumn<String> foodsJson = GeneratedColumn<String>(
    'foods_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalCaloriesMeta = const VerificationMeta(
    'totalCalories',
  );
  @override
  late final GeneratedColumn<int> totalCalories = GeneratedColumn<int>(
    'total_calories',
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
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _aiCommentMeta = const VerificationMeta(
    'aiComment',
  );
  @override
  late final GeneratedColumn<String> aiComment = GeneratedColumn<String>(
    'ai_comment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _photoAssetMeta = const VerificationMeta(
    'photoAsset',
  );
  @override
  late final GeneratedColumn<String> photoAsset = GeneratedColumn<String>(
    'photo_asset',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _photoBytesMeta = const VerificationMeta(
    'photoBytes',
  );
  @override
  late final GeneratedColumn<Uint8List> photoBytes = GeneratedColumn<Uint8List>(
    'photo_bytes',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    mealType,
    timeLabel,
    foodsJson,
    totalCalories,
    sodiumMg,
    sugarG,
    aiComment,
    photoAsset,
    photoBytes,
    idempotencyKey,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diet_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DietEntryRow> instance, {
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
    if (data.containsKey('meal_type')) {
      context.handle(
        _mealTypeMeta,
        mealType.isAcceptableOrUnknown(data['meal_type']!, _mealTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mealTypeMeta);
    }
    if (data.containsKey('time_label')) {
      context.handle(
        _timeLabelMeta,
        timeLabel.isAcceptableOrUnknown(data['time_label']!, _timeLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_timeLabelMeta);
    }
    if (data.containsKey('foods_json')) {
      context.handle(
        _foodsJsonMeta,
        foodsJson.isAcceptableOrUnknown(data['foods_json']!, _foodsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_foodsJsonMeta);
    }
    if (data.containsKey('total_calories')) {
      context.handle(
        _totalCaloriesMeta,
        totalCalories.isAcceptableOrUnknown(
          data['total_calories']!,
          _totalCaloriesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalCaloriesMeta);
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
    if (data.containsKey('ai_comment')) {
      context.handle(
        _aiCommentMeta,
        aiComment.isAcceptableOrUnknown(data['ai_comment']!, _aiCommentMeta),
      );
    }
    if (data.containsKey('photo_asset')) {
      context.handle(
        _photoAssetMeta,
        photoAsset.isAcceptableOrUnknown(data['photo_asset']!, _photoAssetMeta),
      );
    }
    if (data.containsKey('photo_bytes')) {
      context.handle(
        _photoBytesMeta,
        photoBytes.isAcceptableOrUnknown(data['photo_bytes']!, _photoBytesMeta),
      );
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DietEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DietEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      mealType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_type'],
      )!,
      timeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_label'],
      )!,
      foodsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}foods_json'],
      )!,
      totalCalories: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_calories'],
      )!,
      sodiumMg: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sodium_mg'],
      )!,
      sugarG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sugar_g'],
      )!,
      aiComment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_comment'],
      )!,
      photoAsset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_asset'],
      )!,
      photoBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}photo_bytes'],
      ),
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DietEntriesTable createAlias(String alias) {
    return $DietEntriesTable(attachedDatabase, alias);
  }
}

class DietEntryRow extends DataClass implements Insertable<DietEntryRow> {
  final String id;
  final String date;
  final String mealType;
  final String timeLabel;
  final String foodsJson;
  final int totalCalories;
  final int sodiumMg;
  final double sugarG;
  final String aiComment;
  final String photoAsset;
  final Uint8List? photoBytes;
  final String? idempotencyKey;
  final DateTime createdAt;
  const DietEntryRow({
    required this.id,
    required this.date,
    required this.mealType,
    required this.timeLabel,
    required this.foodsJson,
    required this.totalCalories,
    required this.sodiumMg,
    required this.sugarG,
    required this.aiComment,
    required this.photoAsset,
    this.photoBytes,
    this.idempotencyKey,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    map['meal_type'] = Variable<String>(mealType);
    map['time_label'] = Variable<String>(timeLabel);
    map['foods_json'] = Variable<String>(foodsJson);
    map['total_calories'] = Variable<int>(totalCalories);
    map['sodium_mg'] = Variable<int>(sodiumMg);
    map['sugar_g'] = Variable<double>(sugarG);
    map['ai_comment'] = Variable<String>(aiComment);
    map['photo_asset'] = Variable<String>(photoAsset);
    if (!nullToAbsent || photoBytes != null) {
      map['photo_bytes'] = Variable<Uint8List>(photoBytes);
    }
    if (!nullToAbsent || idempotencyKey != null) {
      map['idempotency_key'] = Variable<String>(idempotencyKey);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DietEntriesCompanion toCompanion(bool nullToAbsent) {
    return DietEntriesCompanion(
      id: Value(id),
      date: Value(date),
      mealType: Value(mealType),
      timeLabel: Value(timeLabel),
      foodsJson: Value(foodsJson),
      totalCalories: Value(totalCalories),
      sodiumMg: Value(sodiumMg),
      sugarG: Value(sugarG),
      aiComment: Value(aiComment),
      photoAsset: Value(photoAsset),
      photoBytes: photoBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(photoBytes),
      idempotencyKey: idempotencyKey == null && nullToAbsent
          ? const Value.absent()
          : Value(idempotencyKey),
      createdAt: Value(createdAt),
    );
  }

  factory DietEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DietEntryRow(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      mealType: serializer.fromJson<String>(json['mealType']),
      timeLabel: serializer.fromJson<String>(json['timeLabel']),
      foodsJson: serializer.fromJson<String>(json['foodsJson']),
      totalCalories: serializer.fromJson<int>(json['totalCalories']),
      sodiumMg: serializer.fromJson<int>(json['sodiumMg']),
      sugarG: serializer.fromJson<double>(json['sugarG']),
      aiComment: serializer.fromJson<String>(json['aiComment']),
      photoAsset: serializer.fromJson<String>(json['photoAsset']),
      photoBytes: serializer.fromJson<Uint8List?>(json['photoBytes']),
      idempotencyKey: serializer.fromJson<String?>(json['idempotencyKey']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'mealType': serializer.toJson<String>(mealType),
      'timeLabel': serializer.toJson<String>(timeLabel),
      'foodsJson': serializer.toJson<String>(foodsJson),
      'totalCalories': serializer.toJson<int>(totalCalories),
      'sodiumMg': serializer.toJson<int>(sodiumMg),
      'sugarG': serializer.toJson<double>(sugarG),
      'aiComment': serializer.toJson<String>(aiComment),
      'photoAsset': serializer.toJson<String>(photoAsset),
      'photoBytes': serializer.toJson<Uint8List?>(photoBytes),
      'idempotencyKey': serializer.toJson<String?>(idempotencyKey),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DietEntryRow copyWith({
    String? id,
    String? date,
    String? mealType,
    String? timeLabel,
    String? foodsJson,
    int? totalCalories,
    int? sodiumMg,
    double? sugarG,
    String? aiComment,
    String? photoAsset,
    Value<Uint8List?> photoBytes = const Value.absent(),
    Value<String?> idempotencyKey = const Value.absent(),
    DateTime? createdAt,
  }) => DietEntryRow(
    id: id ?? this.id,
    date: date ?? this.date,
    mealType: mealType ?? this.mealType,
    timeLabel: timeLabel ?? this.timeLabel,
    foodsJson: foodsJson ?? this.foodsJson,
    totalCalories: totalCalories ?? this.totalCalories,
    sodiumMg: sodiumMg ?? this.sodiumMg,
    sugarG: sugarG ?? this.sugarG,
    aiComment: aiComment ?? this.aiComment,
    photoAsset: photoAsset ?? this.photoAsset,
    photoBytes: photoBytes.present ? photoBytes.value : this.photoBytes,
    idempotencyKey: idempotencyKey.present
        ? idempotencyKey.value
        : this.idempotencyKey,
    createdAt: createdAt ?? this.createdAt,
  );
  DietEntryRow copyWithCompanion(DietEntriesCompanion data) {
    return DietEntryRow(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      mealType: data.mealType.present ? data.mealType.value : this.mealType,
      timeLabel: data.timeLabel.present ? data.timeLabel.value : this.timeLabel,
      foodsJson: data.foodsJson.present ? data.foodsJson.value : this.foodsJson,
      totalCalories: data.totalCalories.present
          ? data.totalCalories.value
          : this.totalCalories,
      sodiumMg: data.sodiumMg.present ? data.sodiumMg.value : this.sodiumMg,
      sugarG: data.sugarG.present ? data.sugarG.value : this.sugarG,
      aiComment: data.aiComment.present ? data.aiComment.value : this.aiComment,
      photoAsset: data.photoAsset.present
          ? data.photoAsset.value
          : this.photoAsset,
      photoBytes: data.photoBytes.present
          ? data.photoBytes.value
          : this.photoBytes,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DietEntryRow(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('mealType: $mealType, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('foodsJson: $foodsJson, ')
          ..write('totalCalories: $totalCalories, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('sugarG: $sugarG, ')
          ..write('aiComment: $aiComment, ')
          ..write('photoAsset: $photoAsset, ')
          ..write('photoBytes: $photoBytes, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    mealType,
    timeLabel,
    foodsJson,
    totalCalories,
    sodiumMg,
    sugarG,
    aiComment,
    photoAsset,
    $driftBlobEquality.hash(photoBytes),
    idempotencyKey,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DietEntryRow &&
          other.id == this.id &&
          other.date == this.date &&
          other.mealType == this.mealType &&
          other.timeLabel == this.timeLabel &&
          other.foodsJson == this.foodsJson &&
          other.totalCalories == this.totalCalories &&
          other.sodiumMg == this.sodiumMg &&
          other.sugarG == this.sugarG &&
          other.aiComment == this.aiComment &&
          other.photoAsset == this.photoAsset &&
          $driftBlobEquality.equals(other.photoBytes, this.photoBytes) &&
          other.idempotencyKey == this.idempotencyKey &&
          other.createdAt == this.createdAt);
}

class DietEntriesCompanion extends UpdateCompanion<DietEntryRow> {
  final Value<String> id;
  final Value<String> date;
  final Value<String> mealType;
  final Value<String> timeLabel;
  final Value<String> foodsJson;
  final Value<int> totalCalories;
  final Value<int> sodiumMg;
  final Value<double> sugarG;
  final Value<String> aiComment;
  final Value<String> photoAsset;
  final Value<Uint8List?> photoBytes;
  final Value<String?> idempotencyKey;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DietEntriesCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.mealType = const Value.absent(),
    this.timeLabel = const Value.absent(),
    this.foodsJson = const Value.absent(),
    this.totalCalories = const Value.absent(),
    this.sodiumMg = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.aiComment = const Value.absent(),
    this.photoAsset = const Value.absent(),
    this.photoBytes = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DietEntriesCompanion.insert({
    required String id,
    required String date,
    required String mealType,
    required String timeLabel,
    required String foodsJson,
    required int totalCalories,
    this.sodiumMg = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.aiComment = const Value.absent(),
    this.photoAsset = const Value.absent(),
    this.photoBytes = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date),
       mealType = Value(mealType),
       timeLabel = Value(timeLabel),
       foodsJson = Value(foodsJson),
       totalCalories = Value(totalCalories);
  static Insertable<DietEntryRow> custom({
    Expression<String>? id,
    Expression<String>? date,
    Expression<String>? mealType,
    Expression<String>? timeLabel,
    Expression<String>? foodsJson,
    Expression<int>? totalCalories,
    Expression<int>? sodiumMg,
    Expression<double>? sugarG,
    Expression<String>? aiComment,
    Expression<String>? photoAsset,
    Expression<Uint8List>? photoBytes,
    Expression<String>? idempotencyKey,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (mealType != null) 'meal_type': mealType,
      if (timeLabel != null) 'time_label': timeLabel,
      if (foodsJson != null) 'foods_json': foodsJson,
      if (totalCalories != null) 'total_calories': totalCalories,
      if (sodiumMg != null) 'sodium_mg': sodiumMg,
      if (sugarG != null) 'sugar_g': sugarG,
      if (aiComment != null) 'ai_comment': aiComment,
      if (photoAsset != null) 'photo_asset': photoAsset,
      if (photoBytes != null) 'photo_bytes': photoBytes,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DietEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? date,
    Value<String>? mealType,
    Value<String>? timeLabel,
    Value<String>? foodsJson,
    Value<int>? totalCalories,
    Value<int>? sodiumMg,
    Value<double>? sugarG,
    Value<String>? aiComment,
    Value<String>? photoAsset,
    Value<Uint8List?>? photoBytes,
    Value<String?>? idempotencyKey,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return DietEntriesCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      mealType: mealType ?? this.mealType,
      timeLabel: timeLabel ?? this.timeLabel,
      foodsJson: foodsJson ?? this.foodsJson,
      totalCalories: totalCalories ?? this.totalCalories,
      sodiumMg: sodiumMg ?? this.sodiumMg,
      sugarG: sugarG ?? this.sugarG,
      aiComment: aiComment ?? this.aiComment,
      photoAsset: photoAsset ?? this.photoAsset,
      photoBytes: photoBytes ?? this.photoBytes,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdAt: createdAt ?? this.createdAt,
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
    if (mealType.present) {
      map['meal_type'] = Variable<String>(mealType.value);
    }
    if (timeLabel.present) {
      map['time_label'] = Variable<String>(timeLabel.value);
    }
    if (foodsJson.present) {
      map['foods_json'] = Variable<String>(foodsJson.value);
    }
    if (totalCalories.present) {
      map['total_calories'] = Variable<int>(totalCalories.value);
    }
    if (sodiumMg.present) {
      map['sodium_mg'] = Variable<int>(sodiumMg.value);
    }
    if (sugarG.present) {
      map['sugar_g'] = Variable<double>(sugarG.value);
    }
    if (aiComment.present) {
      map['ai_comment'] = Variable<String>(aiComment.value);
    }
    if (photoAsset.present) {
      map['photo_asset'] = Variable<String>(photoAsset.value);
    }
    if (photoBytes.present) {
      map['photo_bytes'] = Variable<Uint8List>(photoBytes.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DietEntriesCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('mealType: $mealType, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('foodsJson: $foodsJson, ')
          ..write('totalCalories: $totalCalories, ')
          ..write('sodiumMg: $sodiumMg, ')
          ..write('sugarG: $sugarG, ')
          ..write('aiComment: $aiComment, ')
          ..write('photoAsset: $photoAsset, ')
          ..write('photoBytes: $photoBytes, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExerciseSessionsTable extends ExerciseSessions
    with TableInfo<$ExerciseSessionsTable, ExerciseSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExerciseSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _dayLabelMeta = const VerificationMeta(
    'dayLabel',
  );
  @override
  late final GeneratedColumn<String> dayLabel = GeneratedColumn<String>(
    'day_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  static const VerificationMeta _setsMeta = const VerificationMeta('sets');
  @override
  late final GeneratedColumn<int> sets = GeneratedColumn<int>(
    'sets',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repsMeta = const VerificationMeta('reps');
  @override
  late final GeneratedColumn<int> reps = GeneratedColumn<int>(
    'reps',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
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
  static const VerificationMeta _intensityMeta = const VerificationMeta(
    'intensity',
  );
  @override
  late final GeneratedColumn<String> intensity = GeneratedColumn<String>(
    'intensity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('moderate'),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    weekStart,
    dayLabel,
    type,
    name,
    minutes,
    sets,
    reps,
    weight,
    calories,
    intensity,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exercise_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExerciseSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('week_start')) {
      context.handle(
        _weekStartMeta,
        weekStart.isAcceptableOrUnknown(data['week_start']!, _weekStartMeta),
      );
    } else if (isInserting) {
      context.missing(_weekStartMeta);
    }
    if (data.containsKey('day_label')) {
      context.handle(
        _dayLabelMeta,
        dayLabel.isAcceptableOrUnknown(data['day_label']!, _dayLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_dayLabelMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('minutes')) {
      context.handle(
        _minutesMeta,
        minutes.isAcceptableOrUnknown(data['minutes']!, _minutesMeta),
      );
    } else if (isInserting) {
      context.missing(_minutesMeta);
    }
    if (data.containsKey('sets')) {
      context.handle(
        _setsMeta,
        sets.isAcceptableOrUnknown(data['sets']!, _setsMeta),
      );
    }
    if (data.containsKey('reps')) {
      context.handle(
        _repsMeta,
        reps.isAcceptableOrUnknown(data['reps']!, _repsMeta),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('calories')) {
      context.handle(
        _caloriesMeta,
        calories.isAcceptableOrUnknown(data['calories']!, _caloriesMeta),
      );
    } else if (isInserting) {
      context.missing(_caloriesMeta);
    }
    if (data.containsKey('intensity')) {
      context.handle(
        _intensityMeta,
        intensity.isAcceptableOrUnknown(data['intensity']!, _intensityMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExerciseSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExerciseSessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      weekStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_start'],
      )!,
      dayLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_label'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      minutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minutes'],
      )!,
      sets: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sets'],
      ),
      reps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reps'],
      ),
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      ),
      calories: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calories'],
      )!,
      intensity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intensity'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ExerciseSessionsTable createAlias(String alias) {
    return $ExerciseSessionsTable(attachedDatabase, alias);
  }
}

class ExerciseSessionRow extends DataClass
    implements Insertable<ExerciseSessionRow> {
  final String id;
  final String weekStart;
  final String dayLabel;
  final String type;

  /// 회원이 적은 운동 이름. 유형은 집계 축이라 넷뿐이라, 무슨 운동을 했는지는
  /// 이 칸에만 남는다. 이 컬럼이 생기기 전 기록은 빈 문자열이다. (#1276)
  final String name;
  final int minutes;

  /// 근력 기록의 세트 수. 근력이 아니거나 세트를 모르는 기록은 null 이고,
  /// 그때는 분에서 환산해 읽는다. (#1262)
  final int? sets;

  /// 근력 기록의 한 세트당 횟수. 세트·중량과 한 벌이라 근력에만 있다. (#1310)
  final int? reps;

  /// 근력 기록의 중량(kg). 세트와 짝이라 근력에만 있다. (#1276)
  final double? weight;
  final int calories;
  final String intensity;
  final DateTime createdAt;
  const ExerciseSessionRow({
    required this.id,
    required this.weekStart,
    required this.dayLabel,
    required this.type,
    required this.name,
    required this.minutes,
    this.sets,
    this.reps,
    this.weight,
    required this.calories,
    required this.intensity,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['week_start'] = Variable<String>(weekStart);
    map['day_label'] = Variable<String>(dayLabel);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    map['minutes'] = Variable<int>(minutes);
    if (!nullToAbsent || sets != null) {
      map['sets'] = Variable<int>(sets);
    }
    if (!nullToAbsent || reps != null) {
      map['reps'] = Variable<int>(reps);
    }
    if (!nullToAbsent || weight != null) {
      map['weight'] = Variable<double>(weight);
    }
    map['calories'] = Variable<int>(calories);
    map['intensity'] = Variable<String>(intensity);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ExerciseSessionsCompanion toCompanion(bool nullToAbsent) {
    return ExerciseSessionsCompanion(
      id: Value(id),
      weekStart: Value(weekStart),
      dayLabel: Value(dayLabel),
      type: Value(type),
      name: Value(name),
      minutes: Value(minutes),
      sets: sets == null && nullToAbsent ? const Value.absent() : Value(sets),
      reps: reps == null && nullToAbsent ? const Value.absent() : Value(reps),
      weight: weight == null && nullToAbsent
          ? const Value.absent()
          : Value(weight),
      calories: Value(calories),
      intensity: Value(intensity),
      createdAt: Value(createdAt),
    );
  }

  factory ExerciseSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExerciseSessionRow(
      id: serializer.fromJson<String>(json['id']),
      weekStart: serializer.fromJson<String>(json['weekStart']),
      dayLabel: serializer.fromJson<String>(json['dayLabel']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      minutes: serializer.fromJson<int>(json['minutes']),
      sets: serializer.fromJson<int?>(json['sets']),
      reps: serializer.fromJson<int?>(json['reps']),
      weight: serializer.fromJson<double?>(json['weight']),
      calories: serializer.fromJson<int>(json['calories']),
      intensity: serializer.fromJson<String>(json['intensity']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'weekStart': serializer.toJson<String>(weekStart),
      'dayLabel': serializer.toJson<String>(dayLabel),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'minutes': serializer.toJson<int>(minutes),
      'sets': serializer.toJson<int?>(sets),
      'reps': serializer.toJson<int?>(reps),
      'weight': serializer.toJson<double?>(weight),
      'calories': serializer.toJson<int>(calories),
      'intensity': serializer.toJson<String>(intensity),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ExerciseSessionRow copyWith({
    String? id,
    String? weekStart,
    String? dayLabel,
    String? type,
    String? name,
    int? minutes,
    Value<int?> sets = const Value.absent(),
    Value<int?> reps = const Value.absent(),
    Value<double?> weight = const Value.absent(),
    int? calories,
    String? intensity,
    DateTime? createdAt,
  }) => ExerciseSessionRow(
    id: id ?? this.id,
    weekStart: weekStart ?? this.weekStart,
    dayLabel: dayLabel ?? this.dayLabel,
    type: type ?? this.type,
    name: name ?? this.name,
    minutes: minutes ?? this.minutes,
    sets: sets.present ? sets.value : this.sets,
    reps: reps.present ? reps.value : this.reps,
    weight: weight.present ? weight.value : this.weight,
    calories: calories ?? this.calories,
    intensity: intensity ?? this.intensity,
    createdAt: createdAt ?? this.createdAt,
  );
  ExerciseSessionRow copyWithCompanion(ExerciseSessionsCompanion data) {
    return ExerciseSessionRow(
      id: data.id.present ? data.id.value : this.id,
      weekStart: data.weekStart.present ? data.weekStart.value : this.weekStart,
      dayLabel: data.dayLabel.present ? data.dayLabel.value : this.dayLabel,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      minutes: data.minutes.present ? data.minutes.value : this.minutes,
      sets: data.sets.present ? data.sets.value : this.sets,
      reps: data.reps.present ? data.reps.value : this.reps,
      weight: data.weight.present ? data.weight.value : this.weight,
      calories: data.calories.present ? data.calories.value : this.calories,
      intensity: data.intensity.present ? data.intensity.value : this.intensity,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExerciseSessionRow(')
          ..write('id: $id, ')
          ..write('weekStart: $weekStart, ')
          ..write('dayLabel: $dayLabel, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('minutes: $minutes, ')
          ..write('sets: $sets, ')
          ..write('reps: $reps, ')
          ..write('weight: $weight, ')
          ..write('calories: $calories, ')
          ..write('intensity: $intensity, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    weekStart,
    dayLabel,
    type,
    name,
    minutes,
    sets,
    reps,
    weight,
    calories,
    intensity,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExerciseSessionRow &&
          other.id == this.id &&
          other.weekStart == this.weekStart &&
          other.dayLabel == this.dayLabel &&
          other.type == this.type &&
          other.name == this.name &&
          other.minutes == this.minutes &&
          other.sets == this.sets &&
          other.reps == this.reps &&
          other.weight == this.weight &&
          other.calories == this.calories &&
          other.intensity == this.intensity &&
          other.createdAt == this.createdAt);
}

class ExerciseSessionsCompanion extends UpdateCompanion<ExerciseSessionRow> {
  final Value<String> id;
  final Value<String> weekStart;
  final Value<String> dayLabel;
  final Value<String> type;
  final Value<String> name;
  final Value<int> minutes;
  final Value<int?> sets;
  final Value<int?> reps;
  final Value<double?> weight;
  final Value<int> calories;
  final Value<String> intensity;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ExerciseSessionsCompanion({
    this.id = const Value.absent(),
    this.weekStart = const Value.absent(),
    this.dayLabel = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.minutes = const Value.absent(),
    this.sets = const Value.absent(),
    this.reps = const Value.absent(),
    this.weight = const Value.absent(),
    this.calories = const Value.absent(),
    this.intensity = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExerciseSessionsCompanion.insert({
    required String id,
    required String weekStart,
    required String dayLabel,
    required String type,
    this.name = const Value.absent(),
    required int minutes,
    this.sets = const Value.absent(),
    this.reps = const Value.absent(),
    this.weight = const Value.absent(),
    required int calories,
    this.intensity = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       weekStart = Value(weekStart),
       dayLabel = Value(dayLabel),
       type = Value(type),
       minutes = Value(minutes),
       calories = Value(calories);
  static Insertable<ExerciseSessionRow> custom({
    Expression<String>? id,
    Expression<String>? weekStart,
    Expression<String>? dayLabel,
    Expression<String>? type,
    Expression<String>? name,
    Expression<int>? minutes,
    Expression<int>? sets,
    Expression<int>? reps,
    Expression<double>? weight,
    Expression<int>? calories,
    Expression<String>? intensity,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (weekStart != null) 'week_start': weekStart,
      if (dayLabel != null) 'day_label': dayLabel,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (minutes != null) 'minutes': minutes,
      if (sets != null) 'sets': sets,
      if (reps != null) 'reps': reps,
      if (weight != null) 'weight': weight,
      if (calories != null) 'calories': calories,
      if (intensity != null) 'intensity': intensity,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExerciseSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? weekStart,
    Value<String>? dayLabel,
    Value<String>? type,
    Value<String>? name,
    Value<int>? minutes,
    Value<int?>? sets,
    Value<int?>? reps,
    Value<double?>? weight,
    Value<int>? calories,
    Value<String>? intensity,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ExerciseSessionsCompanion(
      id: id ?? this.id,
      weekStart: weekStart ?? this.weekStart,
      dayLabel: dayLabel ?? this.dayLabel,
      type: type ?? this.type,
      name: name ?? this.name,
      minutes: minutes ?? this.minutes,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
      calories: calories ?? this.calories,
      intensity: intensity ?? this.intensity,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (weekStart.present) {
      map['week_start'] = Variable<String>(weekStart.value);
    }
    if (dayLabel.present) {
      map['day_label'] = Variable<String>(dayLabel.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (minutes.present) {
      map['minutes'] = Variable<int>(minutes.value);
    }
    if (sets.present) {
      map['sets'] = Variable<int>(sets.value);
    }
    if (reps.present) {
      map['reps'] = Variable<int>(reps.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (calories.present) {
      map['calories'] = Variable<int>(calories.value);
    }
    if (intensity.present) {
      map['intensity'] = Variable<String>(intensity.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExerciseSessionsCompanion(')
          ..write('id: $id, ')
          ..write('weekStart: $weekStart, ')
          ..write('dayLabel: $dayLabel, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('minutes: $minutes, ')
          ..write('sets: $sets, ')
          ..write('reps: $reps, ')
          ..write('weight: $weight, ')
          ..write('calories: $calories, ')
          ..write('intensity: $intensity, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotificationItemsTable extends NotificationItems
    with TableInfo<$NotificationItemsTable, NotificationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
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
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  @override
  late final GeneratedColumn<bool> read = GeneratedColumn<bool>(
    'read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    title,
    body,
    category,
    read,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('read')) {
      context.handle(
        _readMeta,
        read.isAcceptableOrUnknown(data['read']!, _readMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      read: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read'],
      )!,
    );
  }

  @override
  $NotificationItemsTable createAlias(String alias) {
    return $NotificationItemsTable(attachedDatabase, alias);
  }
}

class NotificationRow extends DataClass implements Insertable<NotificationRow> {
  final String id;
  final DateTime createdAt;
  final String title;
  final String body;
  final String category;
  final bool read;
  const NotificationRow({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.body,
    required this.category,
    required this.read,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['category'] = Variable<String>(category);
    map['read'] = Variable<bool>(read);
    return map;
  }

  NotificationItemsCompanion toCompanion(bool nullToAbsent) {
    return NotificationItemsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      title: Value(title),
      body: Value(body),
      category: Value(category),
      read: Value(read),
    );
  }

  factory NotificationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      category: serializer.fromJson<String>(json['category']),
      read: serializer.fromJson<bool>(json['read']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'category': serializer.toJson<String>(category),
      'read': serializer.toJson<bool>(read),
    };
  }

  NotificationRow copyWith({
    String? id,
    DateTime? createdAt,
    String? title,
    String? body,
    String? category,
    bool? read,
  }) => NotificationRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    title: title ?? this.title,
    body: body ?? this.body,
    category: category ?? this.category,
    read: read ?? this.read,
  );
  NotificationRow copyWithCompanion(NotificationItemsCompanion data) {
    return NotificationRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      category: data.category.present ? data.category.value : this.category,
      read: data.read.present ? data.read.value : this.read,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('category: $category, ')
          ..write('read: $read')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, createdAt, title, body, category, read);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.title == this.title &&
          other.body == this.body &&
          other.category == this.category &&
          other.read == this.read);
}

class NotificationItemsCompanion extends UpdateCompanion<NotificationRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<String> title;
  final Value<String> body;
  final Value<String> category;
  final Value<bool> read;
  final Value<int> rowid;
  const NotificationItemsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.category = const Value.absent(),
    this.read = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotificationItemsCompanion.insert({
    required String id,
    required DateTime createdAt,
    required String title,
    required String body,
    required String category,
    this.read = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       title = Value(title),
       body = Value(body),
       category = Value(category);
  static Insertable<NotificationRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? category,
    Expression<bool>? read,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (category != null) 'category': category,
      if (read != null) 'read': read,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationItemsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<String>? title,
    Value<String>? body,
    Value<String>? category,
    Value<bool>? read,
    Value<int>? rowid,
  }) {
    return NotificationItemsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      body: body ?? this.body,
      category: category ?? this.category,
      read: read ?? this.read,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (read.present) {
      map['read'] = Variable<bool>(read.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationItemsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('category: $category, ')
          ..write('read: $read, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppKeyValuesTable appKeyValues = $AppKeyValuesTable(this);
  late final $DietEntriesTable dietEntries = $DietEntriesTable(this);
  late final $ExerciseSessionsTable exerciseSessions = $ExerciseSessionsTable(
    this,
  );
  late final $NotificationItemsTable notificationItems =
      $NotificationItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appKeyValues,
    dietEntries,
    exerciseSessions,
    notificationItems,
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
typedef $$DietEntriesTableCreateCompanionBuilder =
    DietEntriesCompanion Function({
      required String id,
      required String date,
      required String mealType,
      required String timeLabel,
      required String foodsJson,
      required int totalCalories,
      Value<int> sodiumMg,
      Value<double> sugarG,
      Value<String> aiComment,
      Value<String> photoAsset,
      Value<Uint8List?> photoBytes,
      Value<String?> idempotencyKey,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$DietEntriesTableUpdateCompanionBuilder =
    DietEntriesCompanion Function({
      Value<String> id,
      Value<String> date,
      Value<String> mealType,
      Value<String> timeLabel,
      Value<String> foodsJson,
      Value<int> totalCalories,
      Value<int> sodiumMg,
      Value<double> sugarG,
      Value<String> aiComment,
      Value<String> photoAsset,
      Value<Uint8List?> photoBytes,
      Value<String?> idempotencyKey,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$DietEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $DietEntriesTable> {
  $$DietEntriesTableFilterComposer({
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

  ColumnFilters<String> get mealType => $composableBuilder(
    column: $table.mealType,
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

  ColumnFilters<int> get totalCalories => $composableBuilder(
    column: $table.totalCalories,
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

  ColumnFilters<String> get aiComment => $composableBuilder(
    column: $table.aiComment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoAsset => $composableBuilder(
    column: $table.photoAsset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get photoBytes => $composableBuilder(
    column: $table.photoBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DietEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $DietEntriesTable> {
  $$DietEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get mealType => $composableBuilder(
    column: $table.mealType,
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

  ColumnOrderings<int> get totalCalories => $composableBuilder(
    column: $table.totalCalories,
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

  ColumnOrderings<String> get aiComment => $composableBuilder(
    column: $table.aiComment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoAsset => $composableBuilder(
    column: $table.photoAsset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get photoBytes => $composableBuilder(
    column: $table.photoBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DietEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DietEntriesTable> {
  $$DietEntriesTableAnnotationComposer({
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

  GeneratedColumn<String> get mealType =>
      $composableBuilder(column: $table.mealType, builder: (column) => column);

  GeneratedColumn<String> get timeLabel =>
      $composableBuilder(column: $table.timeLabel, builder: (column) => column);

  GeneratedColumn<String> get foodsJson =>
      $composableBuilder(column: $table.foodsJson, builder: (column) => column);

  GeneratedColumn<int> get totalCalories => $composableBuilder(
    column: $table.totalCalories,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sodiumMg =>
      $composableBuilder(column: $table.sodiumMg, builder: (column) => column);

  GeneratedColumn<double> get sugarG =>
      $composableBuilder(column: $table.sugarG, builder: (column) => column);

  GeneratedColumn<String> get aiComment =>
      $composableBuilder(column: $table.aiComment, builder: (column) => column);

  GeneratedColumn<String> get photoAsset => $composableBuilder(
    column: $table.photoAsset,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get photoBytes => $composableBuilder(
    column: $table.photoBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DietEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DietEntriesTable,
          DietEntryRow,
          $$DietEntriesTableFilterComposer,
          $$DietEntriesTableOrderingComposer,
          $$DietEntriesTableAnnotationComposer,
          $$DietEntriesTableCreateCompanionBuilder,
          $$DietEntriesTableUpdateCompanionBuilder,
          (
            DietEntryRow,
            BaseReferences<_$AppDatabase, $DietEntriesTable, DietEntryRow>,
          ),
          DietEntryRow,
          PrefetchHooks Function()
        > {
  $$DietEntriesTableTableManager(_$AppDatabase db, $DietEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DietEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DietEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DietEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> mealType = const Value.absent(),
                Value<String> timeLabel = const Value.absent(),
                Value<String> foodsJson = const Value.absent(),
                Value<int> totalCalories = const Value.absent(),
                Value<int> sodiumMg = const Value.absent(),
                Value<double> sugarG = const Value.absent(),
                Value<String> aiComment = const Value.absent(),
                Value<String> photoAsset = const Value.absent(),
                Value<Uint8List?> photoBytes = const Value.absent(),
                Value<String?> idempotencyKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DietEntriesCompanion(
                id: id,
                date: date,
                mealType: mealType,
                timeLabel: timeLabel,
                foodsJson: foodsJson,
                totalCalories: totalCalories,
                sodiumMg: sodiumMg,
                sugarG: sugarG,
                aiComment: aiComment,
                photoAsset: photoAsset,
                photoBytes: photoBytes,
                idempotencyKey: idempotencyKey,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String date,
                required String mealType,
                required String timeLabel,
                required String foodsJson,
                required int totalCalories,
                Value<int> sodiumMg = const Value.absent(),
                Value<double> sugarG = const Value.absent(),
                Value<String> aiComment = const Value.absent(),
                Value<String> photoAsset = const Value.absent(),
                Value<Uint8List?> photoBytes = const Value.absent(),
                Value<String?> idempotencyKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DietEntriesCompanion.insert(
                id: id,
                date: date,
                mealType: mealType,
                timeLabel: timeLabel,
                foodsJson: foodsJson,
                totalCalories: totalCalories,
                sodiumMg: sodiumMg,
                sugarG: sugarG,
                aiComment: aiComment,
                photoAsset: photoAsset,
                photoBytes: photoBytes,
                idempotencyKey: idempotencyKey,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DietEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DietEntriesTable,
      DietEntryRow,
      $$DietEntriesTableFilterComposer,
      $$DietEntriesTableOrderingComposer,
      $$DietEntriesTableAnnotationComposer,
      $$DietEntriesTableCreateCompanionBuilder,
      $$DietEntriesTableUpdateCompanionBuilder,
      (
        DietEntryRow,
        BaseReferences<_$AppDatabase, $DietEntriesTable, DietEntryRow>,
      ),
      DietEntryRow,
      PrefetchHooks Function()
    >;
typedef $$ExerciseSessionsTableCreateCompanionBuilder =
    ExerciseSessionsCompanion Function({
      required String id,
      required String weekStart,
      required String dayLabel,
      required String type,
      Value<String> name,
      required int minutes,
      Value<int?> sets,
      Value<int?> reps,
      Value<double?> weight,
      required int calories,
      Value<String> intensity,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ExerciseSessionsTableUpdateCompanionBuilder =
    ExerciseSessionsCompanion Function({
      Value<String> id,
      Value<String> weekStart,
      Value<String> dayLabel,
      Value<String> type,
      Value<String> name,
      Value<int> minutes,
      Value<int?> sets,
      Value<int?> reps,
      Value<double?> weight,
      Value<int> calories,
      Value<String> intensity,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ExerciseSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ExerciseSessionsTable> {
  $$ExerciseSessionsTableFilterComposer({
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

  ColumnFilters<String> get weekStart => $composableBuilder(
    column: $table.weekStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayLabel => $composableBuilder(
    column: $table.dayLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
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

  ColumnFilters<int> get sets => $composableBuilder(
    column: $table.sets,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intensity => $composableBuilder(
    column: $table.intensity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExerciseSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExerciseSessionsTable> {
  $$ExerciseSessionsTableOrderingComposer({
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

  ColumnOrderings<String> get weekStart => $composableBuilder(
    column: $table.weekStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayLabel => $composableBuilder(
    column: $table.dayLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
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

  ColumnOrderings<int> get sets => $composableBuilder(
    column: $table.sets,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intensity => $composableBuilder(
    column: $table.intensity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExerciseSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExerciseSessionsTable> {
  $$ExerciseSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get weekStart =>
      $composableBuilder(column: $table.weekStart, builder: (column) => column);

  GeneratedColumn<String> get dayLabel =>
      $composableBuilder(column: $table.dayLabel, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get minutes =>
      $composableBuilder(column: $table.minutes, builder: (column) => column);

  GeneratedColumn<int> get sets =>
      $composableBuilder(column: $table.sets, builder: (column) => column);

  GeneratedColumn<int> get reps =>
      $composableBuilder(column: $table.reps, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<int> get calories =>
      $composableBuilder(column: $table.calories, builder: (column) => column);

  GeneratedColumn<String> get intensity =>
      $composableBuilder(column: $table.intensity, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ExerciseSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExerciseSessionsTable,
          ExerciseSessionRow,
          $$ExerciseSessionsTableFilterComposer,
          $$ExerciseSessionsTableOrderingComposer,
          $$ExerciseSessionsTableAnnotationComposer,
          $$ExerciseSessionsTableCreateCompanionBuilder,
          $$ExerciseSessionsTableUpdateCompanionBuilder,
          (
            ExerciseSessionRow,
            BaseReferences<
              _$AppDatabase,
              $ExerciseSessionsTable,
              ExerciseSessionRow
            >,
          ),
          ExerciseSessionRow,
          PrefetchHooks Function()
        > {
  $$ExerciseSessionsTableTableManager(
    _$AppDatabase db,
    $ExerciseSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExerciseSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExerciseSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExerciseSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> weekStart = const Value.absent(),
                Value<String> dayLabel = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> minutes = const Value.absent(),
                Value<int?> sets = const Value.absent(),
                Value<int?> reps = const Value.absent(),
                Value<double?> weight = const Value.absent(),
                Value<int> calories = const Value.absent(),
                Value<String> intensity = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExerciseSessionsCompanion(
                id: id,
                weekStart: weekStart,
                dayLabel: dayLabel,
                type: type,
                name: name,
                minutes: minutes,
                sets: sets,
                reps: reps,
                weight: weight,
                calories: calories,
                intensity: intensity,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String weekStart,
                required String dayLabel,
                required String type,
                Value<String> name = const Value.absent(),
                required int minutes,
                Value<int?> sets = const Value.absent(),
                Value<int?> reps = const Value.absent(),
                Value<double?> weight = const Value.absent(),
                required int calories,
                Value<String> intensity = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExerciseSessionsCompanion.insert(
                id: id,
                weekStart: weekStart,
                dayLabel: dayLabel,
                type: type,
                name: name,
                minutes: minutes,
                sets: sets,
                reps: reps,
                weight: weight,
                calories: calories,
                intensity: intensity,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExerciseSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExerciseSessionsTable,
      ExerciseSessionRow,
      $$ExerciseSessionsTableFilterComposer,
      $$ExerciseSessionsTableOrderingComposer,
      $$ExerciseSessionsTableAnnotationComposer,
      $$ExerciseSessionsTableCreateCompanionBuilder,
      $$ExerciseSessionsTableUpdateCompanionBuilder,
      (
        ExerciseSessionRow,
        BaseReferences<
          _$AppDatabase,
          $ExerciseSessionsTable,
          ExerciseSessionRow
        >,
      ),
      ExerciseSessionRow,
      PrefetchHooks Function()
    >;
typedef $$NotificationItemsTableCreateCompanionBuilder =
    NotificationItemsCompanion Function({
      required String id,
      required DateTime createdAt,
      required String title,
      required String body,
      required String category,
      Value<bool> read,
      Value<int> rowid,
    });
typedef $$NotificationItemsTableUpdateCompanionBuilder =
    NotificationItemsCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<String> title,
      Value<String> body,
      Value<String> category,
      Value<bool> read,
      Value<int> rowid,
    });

class $$NotificationItemsTableFilterComposer
    extends Composer<_$AppDatabase, $NotificationItemsTable> {
  $$NotificationItemsTableFilterComposer({
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

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotificationItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $NotificationItemsTable> {
  $$NotificationItemsTableOrderingComposer({
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

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotificationItemsTable> {
  $$NotificationItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<bool> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);
}

class $$NotificationItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotificationItemsTable,
          NotificationRow,
          $$NotificationItemsTableFilterComposer,
          $$NotificationItemsTableOrderingComposer,
          $$NotificationItemsTableAnnotationComposer,
          $$NotificationItemsTableCreateCompanionBuilder,
          $$NotificationItemsTableUpdateCompanionBuilder,
          (
            NotificationRow,
            BaseReferences<
              _$AppDatabase,
              $NotificationItemsTable,
              NotificationRow
            >,
          ),
          NotificationRow,
          PrefetchHooks Function()
        > {
  $$NotificationItemsTableTableManager(
    _$AppDatabase db,
    $NotificationItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotificationItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotificationItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationItemsCompanion(
                id: id,
                createdAt: createdAt,
                title: title,
                body: body,
                category: category,
                read: read,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required String title,
                required String body,
                required String category,
                Value<bool> read = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationItemsCompanion.insert(
                id: id,
                createdAt: createdAt,
                title: title,
                body: body,
                category: category,
                read: read,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotificationItemsTable,
      NotificationRow,
      $$NotificationItemsTableFilterComposer,
      $$NotificationItemsTableOrderingComposer,
      $$NotificationItemsTableAnnotationComposer,
      $$NotificationItemsTableCreateCompanionBuilder,
      $$NotificationItemsTableUpdateCompanionBuilder,
      (
        NotificationRow,
        BaseReferences<_$AppDatabase, $NotificationItemsTable, NotificationRow>,
      ),
      NotificationRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppKeyValuesTableTableManager get appKeyValues =>
      $$AppKeyValuesTableTableManager(_db, _db.appKeyValues);
  $$DietEntriesTableTableManager get dietEntries =>
      $$DietEntriesTableTableManager(_db, _db.dietEntries);
  $$ExerciseSessionsTableTableManager get exerciseSessions =>
      $$ExerciseSessionsTableTableManager(_db, _db.exerciseSessions);
  $$NotificationItemsTableTableManager get notificationItems =>
      $$NotificationItemsTableTableManager(_db, _db.notificationItems);
}
