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

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final DatabaseState databaseState = DatabaseState(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [databaseState];
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

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $DatabaseStateTableManager get databaseState =>
      $DatabaseStateTableManager(_db, _db.databaseState);
}
