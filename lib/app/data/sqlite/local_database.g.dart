// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class DatabaseState extends Table
    with TableInfo<DatabaseState, DatabaseStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DatabaseState(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (singleton = 1)',
  );
  static const VerificationMeta _datasetIdMeta = const VerificationMeta(
    'datasetId',
  );
  late final GeneratedColumn<String> datasetId = GeneratedColumn<String>(
    'dataset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(dataset_id) = 36 AND substr(dataset_id, 9, 1) = \'-\' AND substr(dataset_id, 14, 1) = \'-\' AND substr(dataset_id, 19, 1) = \'-\' AND substr(dataset_id, 24, 1) = \'-\' AND length("replace"(dataset_id, \'-\', \'\')) = 32 AND "replace"(dataset_id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(revision) = \'integer\' AND revision >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [singleton, datasetId, revision];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'database_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<DatabaseStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('dataset_id')) {
      context.handle(
        _datasetIdMeta,
        datasetId.isAcceptableOrUnknown(data['dataset_id']!, _datasetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  DatabaseStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DatabaseStateData(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      datasetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  DatabaseState createAlias(String alias) {
    return DatabaseState(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class DatabaseStateData extends DataClass
    implements Insertable<DatabaseStateData> {
  final int singleton;
  final String datasetId;
  final int revision;
  const DatabaseStateData({
    required this.singleton,
    required this.datasetId,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['dataset_id'] = Variable<String>(datasetId);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  DatabaseStateCompanion toCompanion(bool nullToAbsent) {
    return DatabaseStateCompanion(
      singleton: Value(singleton),
      datasetId: Value(datasetId),
      revision: Value(revision),
    );
  }

  factory DatabaseStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DatabaseStateData(
      singleton: serializer.fromJson<int>(json['singleton']),
      datasetId: serializer.fromJson<String>(json['dataset_id']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'dataset_id': serializer.toJson<String>(datasetId),
      'revision': serializer.toJson<int>(revision),
    };
  }

  DatabaseStateData copyWith({
    int? singleton,
    String? datasetId,
    int? revision,
  }) => DatabaseStateData(
    singleton: singleton ?? this.singleton,
    datasetId: datasetId ?? this.datasetId,
    revision: revision ?? this.revision,
  );
  DatabaseStateData copyWithCompanion(DatabaseStateCompanion data) {
    return DatabaseStateData(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      datasetId: data.datasetId.present ? data.datasetId.value : this.datasetId,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DatabaseStateData(')
          ..write('singleton: $singleton, ')
          ..write('datasetId: $datasetId, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singleton, datasetId, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DatabaseStateData &&
          other.singleton == this.singleton &&
          other.datasetId == this.datasetId &&
          other.revision == this.revision);
}

class DatabaseStateCompanion extends UpdateCompanion<DatabaseStateData> {
  final Value<int> singleton;
  final Value<String> datasetId;
  final Value<int> revision;
  const DatabaseStateCompanion({
    this.singleton = const Value.absent(),
    this.datasetId = const Value.absent(),
    this.revision = const Value.absent(),
  });
  DatabaseStateCompanion.insert({
    this.singleton = const Value.absent(),
    required String datasetId,
    required int revision,
  }) : datasetId = Value(datasetId),
       revision = Value(revision);
  static Insertable<DatabaseStateData> custom({
    Expression<int>? singleton,
    Expression<String>? datasetId,
    Expression<int>? revision,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (datasetId != null) 'dataset_id': datasetId,
      if (revision != null) 'revision': revision,
    });
  }

  DatabaseStateCompanion copyWith({
    Value<int>? singleton,
    Value<String>? datasetId,
    Value<int>? revision,
  }) {
    return DatabaseStateCompanion(
      singleton: singleton ?? this.singleton,
      datasetId: datasetId ?? this.datasetId,
      revision: revision ?? this.revision,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (datasetId.present) {
      map['dataset_id'] = Variable<String>(datasetId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DatabaseStateCompanion(')
          ..write('singleton: $singleton, ')
          ..write('datasetId: $datasetId, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }
}

class Categories extends Table with TableInfo<Categories, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Categories(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = \'-\' AND substr(id, 14, 1) = \'-\' AND substr(id, 19, 1) = \'-\' AND substr(id, 24, 1) = \'-\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'REFERENCES categories(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(name)) > 0)',
  );
  static const VerificationMeta _isIncomeMeta = const VerificationMeta(
    'isIncome',
  );
  late final GeneratedColumn<int> isIncome = GeneratedColumn<int>(
    'is_income',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (is_income IN (0, 1))',
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  late final GeneratedColumn<int> archived = GeneratedColumn<int>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (archived IN (0, 1))',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentId,
    name,
    isIncome,
    archived,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_income')) {
      context.handle(
        _isIncomeMeta,
        isIncome.isAcceptableOrUnknown(data['is_income']!, _isIncomeMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isIncome: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_income'],
      ),
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  Categories createAlias(String alias) {
    return Categories(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK((parent_id IS NULL AND is_income IS NOT NULL)OR(parent_id IS NOT NULL AND is_income IS NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String? parentId;
  final String name;
  final int? isIncome;
  final int archived;
  final String createdAt;
  final String updatedAt;
  const Category({
    required this.id,
    this.parentId,
    required this.name,
    this.isIncome,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || isIncome != null) {
      map['is_income'] = Variable<int>(isIncome);
    }
    map['archived'] = Variable<int>(archived);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      isIncome: isIncome == null && nullToAbsent
          ? const Value.absent()
          : Value(isIncome),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      parentId: serializer.fromJson<String?>(json['parent_id']),
      name: serializer.fromJson<String>(json['name']),
      isIncome: serializer.fromJson<int?>(json['is_income']),
      archived: serializer.fromJson<int>(json['archived']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      updatedAt: serializer.fromJson<String>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'parent_id': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'is_income': serializer.toJson<int?>(isIncome),
      'archived': serializer.toJson<int>(archived),
      'created_at': serializer.toJson<String>(createdAt),
      'updated_at': serializer.toJson<String>(updatedAt),
    };
  }

  Category copyWith({
    String? id,
    Value<String?> parentId = const Value.absent(),
    String? name,
    Value<int?> isIncome = const Value.absent(),
    int? archived,
    String? createdAt,
    String? updatedAt,
  }) => Category(
    id: id ?? this.id,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    isIncome: isIncome.present ? isIncome.value : this.isIncome,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      isIncome: data.isIncome.present ? data.isIncome.value : this.isIncome,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('isIncome: $isIncome, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, parentId, name, isIncome, archived, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.isIncome == this.isIncome &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<int?> isIncome;
  final Value<int> archived;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.isIncome = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
    required String name,
    this.isIncome = const Value.absent(),
    this.archived = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<int>? isIncome,
    Expression<int>? archived,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (isIncome != null) 'is_income': isIncome,
      if (archived != null) 'archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String?>? parentId,
    Value<String>? name,
    Value<int?>? isIncome,
    Value<int>? archived,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      isIncome: isIncome ?? this.isIncome,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isIncome.present) {
      map['is_income'] = Variable<int>(isIncome.value);
    }
    if (archived.present) {
      map['archived'] = Variable<int>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('isIncome: $isIncome, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final DatabaseState databaseState = DatabaseState(this);
  late final Categories categories = Categories(this);
  late final Index categoriesParent = Index(
    'categories_parent',
    'CREATE INDEX categories_parent ON categories (parent_id)',
  );
  late final Trigger categoriesInsert = Trigger(
    'CREATE TRIGGER categories_insert BEFORE INSERT ON categories BEGIN SELECT RAISE (ABORT, \'category_cycle\') WHERE NEW.parent_id = NEW.id OR EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT 1 FROM ancestors WHERE id = NEW.id);SELECT RAISE (ABORT, \'category_depth\') WHERE (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT count(*) FROM ancestors) + (WITH RECURSIVE descendants (id, depth) AS (SELECT NEW.id, 1 UNION ALL SELECT c.id, d.depth + 1 FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT max(depth) FROM descendants) > 3;END',
    'categories_insert',
  );
  late final Trigger categoriesUpdate = Trigger(
    'CREATE TRIGGER categories_update BEFORE UPDATE OF parent_id ON categories BEGIN SELECT RAISE (ABORT, \'category_cycle\') WHERE NEW.parent_id = NEW.id OR EXISTS (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT 1 FROM ancestors WHERE id = NEW.id);SELECT RAISE (ABORT, \'category_depth\') WHERE (WITH RECURSIVE ancestors (id, parent_id) AS (SELECT id, parent_id FROM categories WHERE id = NEW.parent_id UNION ALL SELECT c.id, c.parent_id FROM categories AS c JOIN ancestors AS a ON c.id = a.parent_id) SELECT count(*) FROM ancestors) + (WITH RECURSIVE descendants (id, depth) AS (SELECT NEW.id, 1 UNION ALL SELECT c.id, d.depth + 1 FROM categories AS c JOIN descendants AS d ON c.parent_id = d.id) SELECT max(depth) FROM descendants) > 3;END',
    'categories_update',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    databaseState,
    categories,
    categoriesParent,
    categoriesInsert,
    categoriesUpdate,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
  ]);
}

typedef $DatabaseStateCreateCompanionBuilder = DatabaseStateCompanion Function({
  Value<int> singleton,
  required String datasetId,
  required int revision,
});
typedef $DatabaseStateUpdateCompanionBuilder = DatabaseStateCompanion Function({
  Value<int> singleton,
  Value<String> datasetId,
  Value<int> revision,
});

class $DatabaseStateFilterComposer
    extends Composer<_$LocalDatabase, DatabaseState> {
  $DatabaseStateFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datasetId => $composableBuilder(
    column: $table.datasetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $DatabaseStateOrderingComposer
    extends Composer<_$LocalDatabase, DatabaseState> {
  $DatabaseStateOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datasetId => $composableBuilder(
    column: $table.datasetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $DatabaseStateAnnotationComposer
    extends Composer<_$LocalDatabase, DatabaseState> {
  $DatabaseStateAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton =>
      $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<String> get datasetId =>
      $composableBuilder(column: $table.datasetId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $DatabaseStateTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          DatabaseState,
          DatabaseStateData,
          $DatabaseStateFilterComposer,
          $DatabaseStateOrderingComposer,
          $DatabaseStateAnnotationComposer,
          $DatabaseStateCreateCompanionBuilder,
          $DatabaseStateUpdateCompanionBuilder,
          (
            DatabaseStateData,
            BaseReferences<_$LocalDatabase, DatabaseState, DatabaseStateData>,
          ),
          DatabaseStateData,
          PrefetchHooks Function()
        > {
  $DatabaseStateTableManager(_$LocalDatabase db, DatabaseState table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $DatabaseStateFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $DatabaseStateOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $DatabaseStateAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<String> datasetId = const Value.absent(),
                Value<int> revision = const Value.absent(),
              }) => DatabaseStateCompanion(
                singleton: singleton,
                datasetId: datasetId,
                revision: revision,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required String datasetId,
                required int revision,
              }) => DatabaseStateCompanion.insert(
                singleton: singleton,
                datasetId: datasetId,
                revision: revision,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<DatabaseState, DatabaseStateData>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    DatabaseState,
                    DatabaseStateData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $DatabaseStateProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      DatabaseState,
      DatabaseStateData,
      $DatabaseStateFilterComposer,
      $DatabaseStateOrderingComposer,
      $DatabaseStateAnnotationComposer,
      $DatabaseStateCreateCompanionBuilder,
      $DatabaseStateUpdateCompanionBuilder,
      (
        DatabaseStateData,
        BaseReferences<_$LocalDatabase, DatabaseState, DatabaseStateData>,
      ),
      DatabaseStateData,
      PrefetchHooks Function()
    >;
typedef $CategoriesCreateCompanionBuilder = CategoriesCompanion Function({
  required String id,
  Value<String?> parentId,
  required String name,
  Value<int?> isIncome,
  Value<int> archived,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $CategoriesUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<String?> parentId,
  Value<String> name,
  Value<int?> isIncome,
  Value<int> archived,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

final class $CategoriesReferences
    extends BaseReferences<_$LocalDatabase, Categories, Category> {
  $CategoriesReferences(super.$_db, super.$_table, super.$_typedResult);

  static Categories _parentIdTable(_$LocalDatabase db) =>
      db.categories.createAlias('categories__parent_id__categories__id');

  $CategoriesProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $CategoriesTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $CategoriesFilterComposer extends Composer<_$LocalDatabase, Categories> {
  $CategoriesFilterComposer({
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

  ColumnFilters<int> get isIncome => $composableBuilder(
    column: $table.isIncome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $CategoriesFilterComposer get parentId {
    final $CategoriesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CategoriesFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $CategoriesOrderingComposer
    extends Composer<_$LocalDatabase, Categories> {
  $CategoriesOrderingComposer({
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

  ColumnOrderings<int> get isIncome => $composableBuilder(
    column: $table.isIncome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $CategoriesOrderingComposer get parentId {
    final $CategoriesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CategoriesOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $CategoriesAnnotationComposer
    extends Composer<_$LocalDatabase, Categories> {
  $CategoriesAnnotationComposer({
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

  GeneratedColumn<int> get isIncome =>
      $composableBuilder(column: $table.isIncome, builder: (column) => column);

  GeneratedColumn<int> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $CategoriesAnnotationComposer get parentId {
    final $CategoriesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CategoriesAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $CategoriesTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          Categories,
          Category,
          $CategoriesFilterComposer,
          $CategoriesOrderingComposer,
          $CategoriesAnnotationComposer,
          $CategoriesCreateCompanionBuilder,
          $CategoriesUpdateCompanionBuilder,
          (Category, $CategoriesReferences),
          Category,
          PrefetchHooks Function({bool parentId})
        > {
  $CategoriesTableManager(_$LocalDatabase db, Categories table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $CategoriesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $CategoriesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $CategoriesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> isIncome = const Value.absent(),
                Value<int> archived = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                parentId: parentId,
                name: name,
                isIncome: isIncome,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> parentId = const Value.absent(),
                required String name,
                Value<int?> isIncome = const Value.absent(),
                Value<int> archived = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                parentId: parentId,
                name: name,
                isIncome: isIncome,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Categories, Category>(table),
                  $CategoriesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({parentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (parentId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.parentId,
                        referencedTable: $CategoriesReferences._parentIdTable(
                          db,
                        ),
                        referencedColumn: $CategoriesReferences
                            ._parentIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $CategoriesProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      Categories,
      Category,
      $CategoriesFilterComposer,
      $CategoriesOrderingComposer,
      $CategoriesAnnotationComposer,
      $CategoriesCreateCompanionBuilder,
      $CategoriesUpdateCompanionBuilder,
      (Category, $CategoriesReferences),
      Category,
      PrefetchHooks Function({bool parentId})
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $DatabaseStateTableManager get databaseState =>
      $DatabaseStateTableManager(_db, _db.databaseState);
  $CategoriesTableManager get categories =>
      $CategoriesTableManager(_db, _db.categories);
}
