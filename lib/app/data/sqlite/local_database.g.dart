// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class ImportBatches extends Table with TableInfo<ImportBatches, ImportBatche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ImportBatches(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = \'-\' AND substr(id, 14, 1) = \'-\' AND substr(id, 19, 1) = \'-\' AND substr(id, 24, 1) = \'-\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _contentSha256Meta = const VerificationMeta(
    'contentSha256',
  );
  late final GeneratedColumn<String> contentSha256 = GeneratedColumn<String>(
    'content_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE CHECK (length(content_sha256) = 64 AND content_sha256 NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (source_kind IN (\'historical_csv\', \'bank_xls\'))',
  );
  static const VerificationMeta _originalNameMeta = const VerificationMeta(
    'originalName',
  );
  late final GeneratedColumn<String> originalName = GeneratedColumn<String>(
    'original_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(original_name)) > 0)',
  );
  static const VerificationMeta _contractVersionMeta = const VerificationMeta(
    'contractVersion',
  );
  late final GeneratedColumn<String> contractVersion = GeneratedColumn<String>(
    'contract_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(contract_version)) > 0)',
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  late final GeneratedColumn<String> importedAt = GeneratedColumn<String>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
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
    contentSha256,
    sourceKind,
    originalName,
    contractVersion,
    importedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportBatche> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content_sha256')) {
      context.handle(
        _contentSha256Meta,
        contentSha256.isAcceptableOrUnknown(
          data['content_sha256']!,
          _contentSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentSha256Meta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('original_name')) {
      context.handle(
        _originalNameMeta,
        originalName.isAcceptableOrUnknown(
          data['original_name']!,
          _originalNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalNameMeta);
    }
    if (data.containsKey('contract_version')) {
      context.handle(
        _contractVersionMeta,
        contractVersion.isAcceptableOrUnknown(
          data['contract_version']!,
          _contractVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contractVersionMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
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
  ImportBatche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportBatche(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      contentSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_sha256'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      originalName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_name'],
      )!,
      contractVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contract_version'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}imported_at'],
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
  ImportBatches createAlias(String alias) {
    return ImportBatches(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class ImportBatche extends DataClass implements Insertable<ImportBatche> {
  final String id;
  final String contentSha256;
  final String sourceKind;
  final String originalName;
  final String contractVersion;
  final String importedAt;
  final String createdAt;
  final String updatedAt;
  const ImportBatche({
    required this.id,
    required this.contentSha256,
    required this.sourceKind,
    required this.originalName,
    required this.contractVersion,
    required this.importedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content_sha256'] = Variable<String>(contentSha256);
    map['source_kind'] = Variable<String>(sourceKind);
    map['original_name'] = Variable<String>(originalName);
    map['contract_version'] = Variable<String>(contractVersion);
    map['imported_at'] = Variable<String>(importedAt);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ImportBatchesCompanion toCompanion(bool nullToAbsent) {
    return ImportBatchesCompanion(
      id: Value(id),
      contentSha256: Value(contentSha256),
      sourceKind: Value(sourceKind),
      originalName: Value(originalName),
      contractVersion: Value(contractVersion),
      importedAt: Value(importedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ImportBatche.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportBatche(
      id: serializer.fromJson<String>(json['id']),
      contentSha256: serializer.fromJson<String>(json['content_sha256']),
      sourceKind: serializer.fromJson<String>(json['source_kind']),
      originalName: serializer.fromJson<String>(json['original_name']),
      contractVersion: serializer.fromJson<String>(json['contract_version']),
      importedAt: serializer.fromJson<String>(json['imported_at']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      updatedAt: serializer.fromJson<String>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content_sha256': serializer.toJson<String>(contentSha256),
      'source_kind': serializer.toJson<String>(sourceKind),
      'original_name': serializer.toJson<String>(originalName),
      'contract_version': serializer.toJson<String>(contractVersion),
      'imported_at': serializer.toJson<String>(importedAt),
      'created_at': serializer.toJson<String>(createdAt),
      'updated_at': serializer.toJson<String>(updatedAt),
    };
  }

  ImportBatche copyWith({
    String? id,
    String? contentSha256,
    String? sourceKind,
    String? originalName,
    String? contractVersion,
    String? importedAt,
    String? createdAt,
    String? updatedAt,
  }) => ImportBatche(
    id: id ?? this.id,
    contentSha256: contentSha256 ?? this.contentSha256,
    sourceKind: sourceKind ?? this.sourceKind,
    originalName: originalName ?? this.originalName,
    contractVersion: contractVersion ?? this.contractVersion,
    importedAt: importedAt ?? this.importedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ImportBatche copyWithCompanion(ImportBatchesCompanion data) {
    return ImportBatche(
      id: data.id.present ? data.id.value : this.id,
      contentSha256: data.contentSha256.present
          ? data.contentSha256.value
          : this.contentSha256,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      originalName: data.originalName.present
          ? data.originalName.value
          : this.originalName,
      contractVersion: data.contractVersion.present
          ? data.contractVersion.value
          : this.contractVersion,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportBatche(')
          ..write('id: $id, ')
          ..write('contentSha256: $contentSha256, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('originalName: $originalName, ')
          ..write('contractVersion: $contractVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    contentSha256,
    sourceKind,
    originalName,
    contractVersion,
    importedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportBatche &&
          other.id == this.id &&
          other.contentSha256 == this.contentSha256 &&
          other.sourceKind == this.sourceKind &&
          other.originalName == this.originalName &&
          other.contractVersion == this.contractVersion &&
          other.importedAt == this.importedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ImportBatchesCompanion extends UpdateCompanion<ImportBatche> {
  final Value<String> id;
  final Value<String> contentSha256;
  final Value<String> sourceKind;
  final Value<String> originalName;
  final Value<String> contractVersion;
  final Value<String> importedAt;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ImportBatchesCompanion({
    this.id = const Value.absent(),
    this.contentSha256 = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.originalName = const Value.absent(),
    this.contractVersion = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportBatchesCompanion.insert({
    required String id,
    required String contentSha256,
    required String sourceKind,
    required String originalName,
    required String contractVersion,
    required String importedAt,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       contentSha256 = Value(contentSha256),
       sourceKind = Value(sourceKind),
       originalName = Value(originalName),
       contractVersion = Value(contractVersion),
       importedAt = Value(importedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ImportBatche> custom({
    Expression<String>? id,
    Expression<String>? contentSha256,
    Expression<String>? sourceKind,
    Expression<String>? originalName,
    Expression<String>? contractVersion,
    Expression<String>? importedAt,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (contentSha256 != null) 'content_sha256': contentSha256,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (originalName != null) 'original_name': originalName,
      if (contractVersion != null) 'contract_version': contractVersion,
      if (importedAt != null) 'imported_at': importedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportBatchesCompanion copyWith({
    Value<String>? id,
    Value<String>? contentSha256,
    Value<String>? sourceKind,
    Value<String>? originalName,
    Value<String>? contractVersion,
    Value<String>? importedAt,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ImportBatchesCompanion(
      id: id ?? this.id,
      contentSha256: contentSha256 ?? this.contentSha256,
      sourceKind: sourceKind ?? this.sourceKind,
      originalName: originalName ?? this.originalName,
      contractVersion: contractVersion ?? this.contractVersion,
      importedAt: importedAt ?? this.importedAt,
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
    if (contentSha256.present) {
      map['content_sha256'] = Variable<String>(contentSha256.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (originalName.present) {
      map['original_name'] = Variable<String>(originalName.value);
    }
    if (contractVersion.present) {
      map['contract_version'] = Variable<String>(contractVersion.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<String>(importedAt.value);
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
    return (StringBuffer('ImportBatchesCompanion(')
          ..write('id: $id, ')
          ..write('contentSha256: $contentSha256, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('originalName: $originalName, ')
          ..write('contractVersion: $contractVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ImportRows extends Table with TableInfo<ImportRows, ImportRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ImportRows(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = \'-\' AND substr(id, 14, 1) = \'-\' AND substr(id, 19, 1) = \'-\' AND substr(id, 24, 1) = \'-\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES import_batches(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
  );
  static const VerificationMeta _sourceOrdinalMeta = const VerificationMeta(
    'sourceOrdinal',
  );
  late final GeneratedColumn<int> sourceOrdinal = GeneratedColumn<int>(
    'source_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(source_ordinal) = \'integer\' AND source_ordinal >= 2)',
  );
  static const VerificationMeta _recordKindMeta = const VerificationMeta(
    'recordKind',
  );
  late final GeneratedColumn<String> recordKind = GeneratedColumn<String>(
    'record_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (record_kind IN (\'movement\', \'budget\'))',
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
    batchId,
    sourceOrdinal,
    recordKind,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('source_ordinal')) {
      context.handle(
        _sourceOrdinalMeta,
        sourceOrdinal.isAcceptableOrUnknown(
          data['source_ordinal']!,
          _sourceOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceOrdinalMeta);
    }
    if (data.containsKey('record_kind')) {
      context.handle(
        _recordKindMeta,
        recordKind.isAcceptableOrUnknown(data['record_kind']!, _recordKindMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKindMeta);
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {batchId, sourceOrdinal},
  ];
  @override
  ImportRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      sourceOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_ordinal'],
      )!,
      recordKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_kind'],
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
  ImportRows createAlias(String alias) {
    return ImportRows(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE(batch_id, source_ordinal)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ImportRow extends DataClass implements Insertable<ImportRow> {
  final String id;
  final String batchId;
  final int sourceOrdinal;
  final String recordKind;
  final String createdAt;
  final String updatedAt;
  const ImportRow({
    required this.id,
    required this.batchId,
    required this.sourceOrdinal,
    required this.recordKind,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['batch_id'] = Variable<String>(batchId);
    map['source_ordinal'] = Variable<int>(sourceOrdinal);
    map['record_kind'] = Variable<String>(recordKind);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ImportRowsCompanion toCompanion(bool nullToAbsent) {
    return ImportRowsCompanion(
      id: Value(id),
      batchId: Value(batchId),
      sourceOrdinal: Value(sourceOrdinal),
      recordKind: Value(recordKind),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ImportRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportRow(
      id: serializer.fromJson<String>(json['id']),
      batchId: serializer.fromJson<String>(json['batch_id']),
      sourceOrdinal: serializer.fromJson<int>(json['source_ordinal']),
      recordKind: serializer.fromJson<String>(json['record_kind']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      updatedAt: serializer.fromJson<String>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'batch_id': serializer.toJson<String>(batchId),
      'source_ordinal': serializer.toJson<int>(sourceOrdinal),
      'record_kind': serializer.toJson<String>(recordKind),
      'created_at': serializer.toJson<String>(createdAt),
      'updated_at': serializer.toJson<String>(updatedAt),
    };
  }

  ImportRow copyWith({
    String? id,
    String? batchId,
    int? sourceOrdinal,
    String? recordKind,
    String? createdAt,
    String? updatedAt,
  }) => ImportRow(
    id: id ?? this.id,
    batchId: batchId ?? this.batchId,
    sourceOrdinal: sourceOrdinal ?? this.sourceOrdinal,
    recordKind: recordKind ?? this.recordKind,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ImportRow copyWithCompanion(ImportRowsCompanion data) {
    return ImportRow(
      id: data.id.present ? data.id.value : this.id,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      sourceOrdinal: data.sourceOrdinal.present
          ? data.sourceOrdinal.value
          : this.sourceOrdinal,
      recordKind: data.recordKind.present
          ? data.recordKind.value
          : this.recordKind,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportRow(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('sourceOrdinal: $sourceOrdinal, ')
          ..write('recordKind: $recordKind, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, batchId, sourceOrdinal, recordKind, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportRow &&
          other.id == this.id &&
          other.batchId == this.batchId &&
          other.sourceOrdinal == this.sourceOrdinal &&
          other.recordKind == this.recordKind &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ImportRowsCompanion extends UpdateCompanion<ImportRow> {
  final Value<String> id;
  final Value<String> batchId;
  final Value<int> sourceOrdinal;
  final Value<String> recordKind;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ImportRowsCompanion({
    this.id = const Value.absent(),
    this.batchId = const Value.absent(),
    this.sourceOrdinal = const Value.absent(),
    this.recordKind = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportRowsCompanion.insert({
    required String id,
    required String batchId,
    required int sourceOrdinal,
    required String recordKind,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       batchId = Value(batchId),
       sourceOrdinal = Value(sourceOrdinal),
       recordKind = Value(recordKind),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ImportRow> custom({
    Expression<String>? id,
    Expression<String>? batchId,
    Expression<int>? sourceOrdinal,
    Expression<String>? recordKind,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (batchId != null) 'batch_id': batchId,
      if (sourceOrdinal != null) 'source_ordinal': sourceOrdinal,
      if (recordKind != null) 'record_kind': recordKind,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? batchId,
    Value<int>? sourceOrdinal,
    Value<String>? recordKind,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ImportRowsCompanion(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      sourceOrdinal: sourceOrdinal ?? this.sourceOrdinal,
      recordKind: recordKind ?? this.recordKind,
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
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (sourceOrdinal.present) {
      map['source_ordinal'] = Variable<int>(sourceOrdinal.value);
    }
    if (recordKind.present) {
      map['record_kind'] = Variable<String>(recordKind.value);
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
    return (StringBuffer('ImportRowsCompanion(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('sourceOrdinal: $sourceOrdinal, ')
          ..write('recordKind: $recordKind, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Accounts extends Table with TableInfo<Accounts, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Accounts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = \'-\' AND substr(id, 14, 1) = \'-\' AND substr(id, 19, 1) = \'-\' AND substr(id, 24, 1) = \'-\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (kind IN (\'account\', \'portfolio\', \'debt\'))',
  );
  static const VerificationMeta _activeFromMeta = const VerificationMeta(
    'activeFrom',
  );
  late final GeneratedColumn<String> activeFrom = GeneratedColumn<String>(
    'active_from',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (active_from GLOB \'[0-9][0-9][0-9][0-9]-[0-9][0-9]-01\' AND substr(active_from, 1, 4) BETWEEN \'0001\' AND \'9999\' AND substr(active_from, 6, 2) BETWEEN \'01\' AND \'12\')',
  );
  static const VerificationMeta _activeThroughMeta = const VerificationMeta(
    'activeThrough',
  );
  late final GeneratedColumn<String> activeThrough = GeneratedColumn<String>(
    'active_through',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (active_through IS NULL OR(active_through GLOB \'[0-9][0-9][0-9][0-9]-[0-9][0-9]-01\' AND substr(active_through, 1, 4) BETWEEN \'0001\' AND \'9999\' AND substr(active_through, 6, 2) BETWEEN \'01\' AND \'12\'))',
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
    name,
    kind,
    activeFrom,
    activeThrough,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
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
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('active_from')) {
      context.handle(
        _activeFromMeta,
        activeFrom.isAcceptableOrUnknown(data['active_from']!, _activeFromMeta),
      );
    } else if (isInserting) {
      context.missing(_activeFromMeta);
    }
    if (data.containsKey('active_through')) {
      context.handle(
        _activeThroughMeta,
        activeThrough.isAcceptableOrUnknown(
          data['active_through']!,
          _activeThroughMeta,
        ),
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
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      activeFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_from'],
      )!,
      activeThrough: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_through'],
      ),
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
  Accounts createAlias(String alias) {
    return Accounts(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(active_through IS NULL OR active_through >= active_from)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Account extends DataClass implements Insertable<Account> {
  final String id;
  final String name;
  final String kind;
  final String activeFrom;
  final String? activeThrough;
  final String createdAt;
  final String updatedAt;
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.activeFrom,
    this.activeThrough,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['active_from'] = Variable<String>(activeFrom);
    if (!nullToAbsent || activeThrough != null) {
      map['active_through'] = Variable<String>(activeThrough);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      activeFrom: Value(activeFrom),
      activeThrough: activeThrough == null && nullToAbsent
          ? const Value.absent()
          : Value(activeThrough),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      activeFrom: serializer.fromJson<String>(json['active_from']),
      activeThrough: serializer.fromJson<String?>(json['active_through']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      updatedAt: serializer.fromJson<String>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'active_from': serializer.toJson<String>(activeFrom),
      'active_through': serializer.toJson<String?>(activeThrough),
      'created_at': serializer.toJson<String>(createdAt),
      'updated_at': serializer.toJson<String>(updatedAt),
    };
  }

  Account copyWith({
    String? id,
    String? name,
    String? kind,
    String? activeFrom,
    Value<String?> activeThrough = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    activeFrom: activeFrom ?? this.activeFrom,
    activeThrough: activeThrough.present
        ? activeThrough.value
        : this.activeThrough,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      activeFrom: data.activeFrom.present
          ? data.activeFrom.value
          : this.activeFrom,
      activeThrough: data.activeThrough.present
          ? data.activeThrough.value
          : this.activeThrough,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('activeFrom: $activeFrom, ')
          ..write('activeThrough: $activeThrough, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    activeFrom,
    activeThrough,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.activeFrom == this.activeFrom &&
          other.activeThrough == this.activeThrough &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<String> activeFrom;
  final Value<String?> activeThrough;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.activeFrom = const Value.absent(),
    this.activeThrough = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required String name,
    required String kind,
    required String activeFrom,
    this.activeThrough = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       kind = Value(kind),
       activeFrom = Value(activeFrom),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Account> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? activeFrom,
    Expression<String>? activeThrough,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (activeFrom != null) 'active_from': activeFrom,
      if (activeThrough != null) 'active_through': activeThrough,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? kind,
    Value<String>? activeFrom,
    Value<String?>? activeThrough,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      activeFrom: activeFrom ?? this.activeFrom,
      activeThrough: activeThrough ?? this.activeThrough,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (activeFrom.present) {
      map['active_from'] = Variable<String>(activeFrom.value);
    }
    if (activeThrough.present) {
      map['active_through'] = Variable<String>(activeThrough.value);
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
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('activeFrom: $activeFrom, ')
          ..write('activeThrough: $activeThrough, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
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

class Movements extends Table with TableInfo<Movements, Movement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Movements(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = \'-\' AND substr(id, 14, 1) = \'-\' AND substr(id, 19, 1) = \'-\' AND substr(id, 24, 1) = \'-\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES accounts(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
  );
  static const VerificationMeta _valueDateMeta = const VerificationMeta(
    'valueDate',
  );
  late final GeneratedColumn<String> valueDate = GeneratedColumn<String>(
    'value_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (value_date GLOB \'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\' AND substr(value_date, 1, 4) BETWEEN \'0001\' AND \'9999\' AND date(value_date, \'+0 days\') IS NOT NULL AND date(value_date, \'+0 days\') = value_date)',
  );
  static const VerificationMeta _conceptMeta = const VerificationMeta(
    'concept',
  );
  late final GeneratedColumn<String> concept = GeneratedColumn<String>(
    'concept',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(concept)) > 0)',
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(amount_cents) = \'integer\' AND amount_cents <> 0)',
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'REFERENCES categories(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
  );
  static const VerificationMeta _discretionMeta = const VerificationMeta(
    'discretion',
  );
  late final GeneratedColumn<String> discretion = GeneratedColumn<String>(
    'discretion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _importRowIdMeta = const VerificationMeta(
    'importRowId',
  );
  late final GeneratedColumn<String> importRowId = GeneratedColumn<String>(
    'import_row_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'UNIQUE REFERENCES import_rows(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
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
    accountId,
    valueDate,
    concept,
    amountCents,
    categoryId,
    discretion,
    importRowId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'movements';
  @override
  VerificationContext validateIntegrity(
    Insertable<Movement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('value_date')) {
      context.handle(
        _valueDateMeta,
        valueDate.isAcceptableOrUnknown(data['value_date']!, _valueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_valueDateMeta);
    }
    if (data.containsKey('concept')) {
      context.handle(
        _conceptMeta,
        concept.isAcceptableOrUnknown(data['concept']!, _conceptMeta),
      );
    } else if (isInserting) {
      context.missing(_conceptMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('discretion')) {
      context.handle(
        _discretionMeta,
        discretion.isAcceptableOrUnknown(data['discretion']!, _discretionMeta),
      );
    }
    if (data.containsKey('import_row_id')) {
      context.handle(
        _importRowIdMeta,
        importRowId.isAcceptableOrUnknown(
          data['import_row_id']!,
          _importRowIdMeta,
        ),
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
  Movement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Movement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      valueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_date'],
      )!,
      concept: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concept'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      discretion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discretion'],
      ),
      importRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_row_id'],
      ),
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
  Movements createAlias(String alias) {
    return Movements(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Movement extends DataClass implements Insertable<Movement> {
  final String id;
  final String accountId;
  final String valueDate;
  final String concept;
  final int amountCents;
  final String? categoryId;
  final String? discretion;
  final String? importRowId;
  final String createdAt;
  final String updatedAt;
  const Movement({
    required this.id,
    required this.accountId,
    required this.valueDate,
    required this.concept,
    required this.amountCents,
    this.categoryId,
    this.discretion,
    this.importRowId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    map['value_date'] = Variable<String>(valueDate);
    map['concept'] = Variable<String>(concept);
    map['amount_cents'] = Variable<int>(amountCents);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || discretion != null) {
      map['discretion'] = Variable<String>(discretion);
    }
    if (!nullToAbsent || importRowId != null) {
      map['import_row_id'] = Variable<String>(importRowId);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  MovementsCompanion toCompanion(bool nullToAbsent) {
    return MovementsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      valueDate: Value(valueDate),
      concept: Value(concept),
      amountCents: Value(amountCents),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      discretion: discretion == null && nullToAbsent
          ? const Value.absent()
          : Value(discretion),
      importRowId: importRowId == null && nullToAbsent
          ? const Value.absent()
          : Value(importRowId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Movement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Movement(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['account_id']),
      valueDate: serializer.fromJson<String>(json['value_date']),
      concept: serializer.fromJson<String>(json['concept']),
      amountCents: serializer.fromJson<int>(json['amount_cents']),
      categoryId: serializer.fromJson<String?>(json['category_id']),
      discretion: serializer.fromJson<String?>(json['discretion']),
      importRowId: serializer.fromJson<String?>(json['import_row_id']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      updatedAt: serializer.fromJson<String>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'account_id': serializer.toJson<String>(accountId),
      'value_date': serializer.toJson<String>(valueDate),
      'concept': serializer.toJson<String>(concept),
      'amount_cents': serializer.toJson<int>(amountCents),
      'category_id': serializer.toJson<String?>(categoryId),
      'discretion': serializer.toJson<String?>(discretion),
      'import_row_id': serializer.toJson<String?>(importRowId),
      'created_at': serializer.toJson<String>(createdAt),
      'updated_at': serializer.toJson<String>(updatedAt),
    };
  }

  Movement copyWith({
    String? id,
    String? accountId,
    String? valueDate,
    String? concept,
    int? amountCents,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> discretion = const Value.absent(),
    Value<String?> importRowId = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => Movement(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    valueDate: valueDate ?? this.valueDate,
    concept: concept ?? this.concept,
    amountCents: amountCents ?? this.amountCents,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    discretion: discretion.present ? discretion.value : this.discretion,
    importRowId: importRowId.present ? importRowId.value : this.importRowId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Movement copyWithCompanion(MovementsCompanion data) {
    return Movement(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      valueDate: data.valueDate.present ? data.valueDate.value : this.valueDate,
      concept: data.concept.present ? data.concept.value : this.concept,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      discretion: data.discretion.present
          ? data.discretion.value
          : this.discretion,
      importRowId: data.importRowId.present
          ? data.importRowId.value
          : this.importRowId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Movement(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('valueDate: $valueDate, ')
          ..write('concept: $concept, ')
          ..write('amountCents: $amountCents, ')
          ..write('categoryId: $categoryId, ')
          ..write('discretion: $discretion, ')
          ..write('importRowId: $importRowId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    valueDate,
    concept,
    amountCents,
    categoryId,
    discretion,
    importRowId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Movement &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.valueDate == this.valueDate &&
          other.concept == this.concept &&
          other.amountCents == this.amountCents &&
          other.categoryId == this.categoryId &&
          other.discretion == this.discretion &&
          other.importRowId == this.importRowId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MovementsCompanion extends UpdateCompanion<Movement> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String> valueDate;
  final Value<String> concept;
  final Value<int> amountCents;
  final Value<String?> categoryId;
  final Value<String?> discretion;
  final Value<String?> importRowId;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const MovementsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.valueDate = const Value.absent(),
    this.concept = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.discretion = const Value.absent(),
    this.importRowId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MovementsCompanion.insert({
    required String id,
    required String accountId,
    required String valueDate,
    required String concept,
    required int amountCents,
    this.categoryId = const Value.absent(),
    this.discretion = const Value.absent(),
    this.importRowId = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       valueDate = Value(valueDate),
       concept = Value(concept),
       amountCents = Value(amountCents),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Movement> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? valueDate,
    Expression<String>? concept,
    Expression<int>? amountCents,
    Expression<String>? categoryId,
    Expression<String>? discretion,
    Expression<String>? importRowId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (valueDate != null) 'value_date': valueDate,
      if (concept != null) 'concept': concept,
      if (amountCents != null) 'amount_cents': amountCents,
      if (categoryId != null) 'category_id': categoryId,
      if (discretion != null) 'discretion': discretion,
      if (importRowId != null) 'import_row_id': importRowId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MovementsCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String>? valueDate,
    Value<String>? concept,
    Value<int>? amountCents,
    Value<String?>? categoryId,
    Value<String?>? discretion,
    Value<String?>? importRowId,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return MovementsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      valueDate: valueDate ?? this.valueDate,
      concept: concept ?? this.concept,
      amountCents: amountCents ?? this.amountCents,
      categoryId: categoryId ?? this.categoryId,
      discretion: discretion ?? this.discretion,
      importRowId: importRowId ?? this.importRowId,
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
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (valueDate.present) {
      map['value_date'] = Variable<String>(valueDate.value);
    }
    if (concept.present) {
      map['concept'] = Variable<String>(concept.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (discretion.present) {
      map['discretion'] = Variable<String>(discretion.value);
    }
    if (importRowId.present) {
      map['import_row_id'] = Variable<String>(importRowId.value);
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
    return (StringBuffer('MovementsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('valueDate: $valueDate, ')
          ..write('concept: $concept, ')
          ..write('amountCents: $amountCents, ')
          ..write('categoryId: $categoryId, ')
          ..write('discretion: $discretion, ')
          ..write('importRowId: $importRowId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

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

class AccountLiquidityPeriods extends Table
    with TableInfo<AccountLiquidityPeriods, AccountLiquidityPeriod> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AccountLiquidityPeriods(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND substr(id, 9, 1) = \'-\' AND substr(id, 14, 1) = \'-\' AND substr(id, 19, 1) = \'-\' AND substr(id, 24, 1) = \'-\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES accounts(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
  );
  static const VerificationMeta _fromMonthMeta = const VerificationMeta(
    'fromMonth',
  );
  late final GeneratedColumn<String> fromMonth = GeneratedColumn<String>(
    'from_month',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (from_month GLOB \'[0-9][0-9][0-9][0-9]-[0-9][0-9]-01\' AND substr(from_month, 1, 4) BETWEEN \'0001\' AND \'9999\' AND substr(from_month, 6, 2) BETWEEN \'01\' AND \'12\')',
  );
  static const VerificationMeta _untilMonthMeta = const VerificationMeta(
    'untilMonth',
  );
  late final GeneratedColumn<String> untilMonth = GeneratedColumn<String>(
    'until_month',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (until_month IS NULL OR(until_month GLOB \'[0-9][0-9][0-9][0-9]-[0-9][0-9]-01\' AND substr(until_month, 1, 4) BETWEEN \'0001\' AND \'9999\' AND substr(until_month, 6, 2) BETWEEN \'01\' AND \'12\'))',
  );
  static const VerificationMeta _liquidityMeta = const VerificationMeta(
    'liquidity',
  );
  late final GeneratedColumn<String> liquidity = GeneratedColumn<String>(
    'liquidity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (liquidity IN (\'liquid\', \'medium\', \'illiquid\'))',
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
    accountId,
    fromMonth,
    untilMonth,
    liquidity,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'account_liquidity_periods';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountLiquidityPeriod> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('from_month')) {
      context.handle(
        _fromMonthMeta,
        fromMonth.isAcceptableOrUnknown(data['from_month']!, _fromMonthMeta),
      );
    } else if (isInserting) {
      context.missing(_fromMonthMeta);
    }
    if (data.containsKey('until_month')) {
      context.handle(
        _untilMonthMeta,
        untilMonth.isAcceptableOrUnknown(data['until_month']!, _untilMonthMeta),
      );
    }
    if (data.containsKey('liquidity')) {
      context.handle(
        _liquidityMeta,
        liquidity.isAcceptableOrUnknown(data['liquidity']!, _liquidityMeta),
      );
    } else if (isInserting) {
      context.missing(_liquidityMeta);
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {accountId, fromMonth},
  ];
  @override
  AccountLiquidityPeriod map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountLiquidityPeriod(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      fromMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_month'],
      )!,
      untilMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}until_month'],
      ),
      liquidity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}liquidity'],
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
  AccountLiquidityPeriods createAlias(String alias) {
    return AccountLiquidityPeriods(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(until_month IS NULL OR until_month > from_month)',
    'UNIQUE(account_id, from_month)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class AccountLiquidityPeriod extends DataClass
    implements Insertable<AccountLiquidityPeriod> {
  final String id;
  final String accountId;
  final String fromMonth;
  final String? untilMonth;
  final String liquidity;
  final String createdAt;
  final String updatedAt;
  const AccountLiquidityPeriod({
    required this.id,
    required this.accountId,
    required this.fromMonth,
    this.untilMonth,
    required this.liquidity,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_id'] = Variable<String>(accountId);
    map['from_month'] = Variable<String>(fromMonth);
    if (!nullToAbsent || untilMonth != null) {
      map['until_month'] = Variable<String>(untilMonth);
    }
    map['liquidity'] = Variable<String>(liquidity);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AccountLiquidityPeriodsCompanion toCompanion(bool nullToAbsent) {
    return AccountLiquidityPeriodsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      fromMonth: Value(fromMonth),
      untilMonth: untilMonth == null && nullToAbsent
          ? const Value.absent()
          : Value(untilMonth),
      liquidity: Value(liquidity),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AccountLiquidityPeriod.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountLiquidityPeriod(
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String>(json['account_id']),
      fromMonth: serializer.fromJson<String>(json['from_month']),
      untilMonth: serializer.fromJson<String?>(json['until_month']),
      liquidity: serializer.fromJson<String>(json['liquidity']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      updatedAt: serializer.fromJson<String>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'account_id': serializer.toJson<String>(accountId),
      'from_month': serializer.toJson<String>(fromMonth),
      'until_month': serializer.toJson<String?>(untilMonth),
      'liquidity': serializer.toJson<String>(liquidity),
      'created_at': serializer.toJson<String>(createdAt),
      'updated_at': serializer.toJson<String>(updatedAt),
    };
  }

  AccountLiquidityPeriod copyWith({
    String? id,
    String? accountId,
    String? fromMonth,
    Value<String?> untilMonth = const Value.absent(),
    String? liquidity,
    String? createdAt,
    String? updatedAt,
  }) => AccountLiquidityPeriod(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    fromMonth: fromMonth ?? this.fromMonth,
    untilMonth: untilMonth.present ? untilMonth.value : this.untilMonth,
    liquidity: liquidity ?? this.liquidity,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AccountLiquidityPeriod copyWithCompanion(
    AccountLiquidityPeriodsCompanion data,
  ) {
    return AccountLiquidityPeriod(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      fromMonth: data.fromMonth.present ? data.fromMonth.value : this.fromMonth,
      untilMonth: data.untilMonth.present
          ? data.untilMonth.value
          : this.untilMonth,
      liquidity: data.liquidity.present ? data.liquidity.value : this.liquidity,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountLiquidityPeriod(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('fromMonth: $fromMonth, ')
          ..write('untilMonth: $untilMonth, ')
          ..write('liquidity: $liquidity, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    fromMonth,
    untilMonth,
    liquidity,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountLiquidityPeriod &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.fromMonth == this.fromMonth &&
          other.untilMonth == this.untilMonth &&
          other.liquidity == this.liquidity &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AccountLiquidityPeriodsCompanion
    extends UpdateCompanion<AccountLiquidityPeriod> {
  final Value<String> id;
  final Value<String> accountId;
  final Value<String> fromMonth;
  final Value<String?> untilMonth;
  final Value<String> liquidity;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AccountLiquidityPeriodsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.fromMonth = const Value.absent(),
    this.untilMonth = const Value.absent(),
    this.liquidity = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountLiquidityPeriodsCompanion.insert({
    required String id,
    required String accountId,
    required String fromMonth,
    this.untilMonth = const Value.absent(),
    required String liquidity,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       accountId = Value(accountId),
       fromMonth = Value(fromMonth),
       liquidity = Value(liquidity),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AccountLiquidityPeriod> custom({
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? fromMonth,
    Expression<String>? untilMonth,
    Expression<String>? liquidity,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (fromMonth != null) 'from_month': fromMonth,
      if (untilMonth != null) 'until_month': untilMonth,
      if (liquidity != null) 'liquidity': liquidity,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountLiquidityPeriodsCompanion copyWith({
    Value<String>? id,
    Value<String>? accountId,
    Value<String>? fromMonth,
    Value<String?>? untilMonth,
    Value<String>? liquidity,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AccountLiquidityPeriodsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      fromMonth: fromMonth ?? this.fromMonth,
      untilMonth: untilMonth ?? this.untilMonth,
      liquidity: liquidity ?? this.liquidity,
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
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (fromMonth.present) {
      map['from_month'] = Variable<String>(fromMonth.value);
    }
    if (untilMonth.present) {
      map['until_month'] = Variable<String>(untilMonth.value);
    }
    if (liquidity.present) {
      map['liquidity'] = Variable<String>(liquidity.value);
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
    return (StringBuffer('AccountLiquidityPeriodsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('fromMonth: $fromMonth, ')
          ..write('untilMonth: $untilMonth, ')
          ..write('liquidity: $liquidity, ')
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
  late final ImportBatches importBatches = ImportBatches(this);
  late final ImportRows importRows = ImportRows(this);
  late final Accounts accounts = Accounts(this);
  late final Categories categories = Categories(this);
  late final Movements movements = Movements(this);
  late final Index movementsDate = Index(
    'movements_date',
    'CREATE INDEX movements_date ON movements (value_date, id)',
  );
  late final Index movementsAccountDate = Index(
    'movements_account_date',
    'CREATE INDEX movements_account_date ON movements (account_id, value_date, id)',
  );
  late final Index movementsCategoryDate = Index(
    'movements_category_date',
    'CREATE INDEX movements_category_date ON movements (category_id, value_date, id)',
  );
  late final Trigger movementsInsert = Trigger(
    'CREATE TRIGGER movements_insert BEFORE INSERT ON movements BEGIN SELECT RAISE (ABORT, \'movement_account\') WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE id = NEW.account_id AND kind = \'account\' AND substr(NEW.value_date, 1, 7) || \'-01\' >= active_from AND(active_through IS NULL OR substr(NEW.value_date, 1, 7) || \'-01\' <= active_through));SELECT RAISE (ABORT, \'movement_origin\') WHERE NEW.import_row_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM import_rows WHERE id = NEW.import_row_id AND record_kind = \'movement\');END',
    'movements_insert',
  );
  late final Trigger movementsUpdate = Trigger(
    'CREATE TRIGGER movements_update BEFORE UPDATE ON movements BEGIN SELECT RAISE (ABORT, \'movement_account\') WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE id = NEW.account_id AND kind = \'account\' AND substr(NEW.value_date, 1, 7) || \'-01\' >= active_from AND(active_through IS NULL OR substr(NEW.value_date, 1, 7) || \'-01\' <= active_through));SELECT RAISE (ABORT, \'movement_origin_immutable\') WHERE NEW.import_row_id IS NOT OLD.import_row_id;END',
    'movements_update',
  );
  late final Trigger importRowsImmutable = Trigger(
    'CREATE TRIGGER import_rows_immutable BEFORE UPDATE ON import_rows BEGIN SELECT RAISE (ABORT, \'import_origin_immutable\');END',
    'import_rows_immutable',
  );
  late final Trigger importRowsKeep = Trigger(
    'CREATE TRIGGER import_rows_keep BEFORE DELETE ON import_rows BEGIN SELECT RAISE (ABORT, \'import_origin_keep\');END',
    'import_rows_keep',
  );
  late final Trigger importBatchesImmutable = Trigger(
    'CREATE TRIGGER import_batches_immutable BEFORE UPDATE ON import_batches BEGIN SELECT RAISE (ABORT, \'import_origin_immutable\');END',
    'import_batches_immutable',
  );
  late final Trigger importBatchesKeep = Trigger(
    'CREATE TRIGGER import_batches_keep BEFORE DELETE ON import_batches BEGIN SELECT RAISE (ABORT, \'import_origin_keep\');END',
    'import_batches_keep',
  );
  late final Trigger accountsMovementBounds = Trigger(
    'CREATE TRIGGER accounts_movement_bounds BEFORE UPDATE OF active_from, active_through ON accounts BEGIN SELECT RAISE (ABORT, \'movement_bounds\') WHERE EXISTS (SELECT 1 FROM movements WHERE account_id = NEW.id AND(substr(value_date, 1, 7) || \'-01\' < NEW.active_from OR(NEW.active_through IS NOT NULL AND substr(value_date, 1, 7) || \'-01\' > NEW.active_through)));END',
    'accounts_movement_bounds',
  );
  late final DatabaseState databaseState = DatabaseState(this);
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
  late final AccountLiquidityPeriods accountLiquidityPeriods =
      AccountLiquidityPeriods(this);
  late final Trigger liquidityInsert = Trigger(
    'CREATE TRIGGER liquidity_insert BEFORE INSERT ON account_liquidity_periods BEGIN SELECT RAISE (ABORT, \'liquidity_bounds\') WHERE NOT EXISTS (SELECT 1 FROM accounts AS a WHERE a.id = NEW.account_id AND a.kind <> \'debt\' AND NEW.from_month >= a.active_from AND(a.active_through IS NULL OR(NEW.from_month <= a.active_through AND(a.active_through = \'9999-12-01\' OR(NEW.until_month IS NOT NULL AND NEW.until_month <= date(a.active_through, \'+1 month\'))))));SELECT RAISE (ABORT, \'liquidity_overlap\') WHERE EXISTS (SELECT 1 FROM account_liquidity_periods AS p WHERE p.account_id = NEW.account_id AND(NEW.until_month IS NULL OR p.from_month < NEW.until_month)AND(p.until_month IS NULL OR NEW.from_month < p.until_month));END',
    'liquidity_insert',
  );
  late final Trigger liquidityUpdate = Trigger(
    'CREATE TRIGGER liquidity_update BEFORE UPDATE ON account_liquidity_periods BEGIN SELECT RAISE (ABORT, \'liquidity_bounds\') WHERE NOT EXISTS (SELECT 1 FROM accounts AS a WHERE a.id = NEW.account_id AND a.kind <> \'debt\' AND NEW.from_month >= a.active_from AND(a.active_through IS NULL OR(NEW.from_month <= a.active_through AND(a.active_through = \'9999-12-01\' OR(NEW.until_month IS NOT NULL AND NEW.until_month <= date(a.active_through, \'+1 month\'))))));SELECT RAISE (ABORT, \'liquidity_overlap\') WHERE EXISTS (SELECT 1 FROM account_liquidity_periods AS p WHERE p.account_id = NEW.account_id AND p.id <> OLD.id AND(NEW.until_month IS NULL OR p.from_month < NEW.until_month)AND(p.until_month IS NULL OR NEW.from_month < p.until_month));END',
    'liquidity_update',
  );
  late final Trigger accountKindImmutable = Trigger(
    'CREATE TRIGGER account_kind_immutable BEFORE UPDATE OF kind ON accounts WHEN NEW.kind <> OLD.kind BEGIN SELECT RAISE (ABORT, \'account_kind_immutable\');END',
    'account_kind_immutable',
  );
  late final Trigger accountPeriodBounds = Trigger(
    'CREATE TRIGGER account_period_bounds BEFORE UPDATE OF active_from, active_through ON accounts BEGIN SELECT RAISE (ABORT, \'liquidity_bounds\') WHERE EXISTS (SELECT 1 FROM account_liquidity_periods AS p WHERE p.account_id = NEW.id AND(p.from_month < NEW.active_from OR(NEW.active_through IS NOT NULL AND(p.from_month > NEW.active_through OR(NEW.active_through <> \'9999-12-01\' AND(p.until_month IS NULL OR p.until_month > date(NEW.active_through, \'+1 month\')))))));END',
    'account_period_bounds',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    importBatches,
    importRows,
    accounts,
    categories,
    movements,
    movementsDate,
    movementsAccountDate,
    movementsCategoryDate,
    movementsInsert,
    movementsUpdate,
    importRowsImmutable,
    importRowsKeep,
    importBatchesImmutable,
    importBatchesKeep,
    accountsMovementBounds,
    databaseState,
    categoriesParent,
    categoriesInsert,
    categoriesUpdate,
    accountLiquidityPeriods,
    liquidityInsert,
    liquidityUpdate,
    accountKindImmutable,
    accountPeriodBounds,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'movements',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'movements',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'import_rows',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'import_rows',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'import_batches',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'import_batches',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
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
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'account_liquidity_periods',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'account_liquidity_periods',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
  ]);
}

typedef $ImportBatchesCreateCompanionBuilder = ImportBatchesCompanion Function({
  required String id,
  required String contentSha256,
  required String sourceKind,
  required String originalName,
  required String contractVersion,
  required String importedAt,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $ImportBatchesUpdateCompanionBuilder = ImportBatchesCompanion Function({
  Value<String> id,
  Value<String> contentSha256,
  Value<String> sourceKind,
  Value<String> originalName,
  Value<String> contractVersion,
  Value<String> importedAt,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

final class $ImportBatchesReferences
    extends BaseReferences<_$LocalDatabase, ImportBatches, ImportBatche> {
  $ImportBatchesReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<ImportRows, List<ImportRow>> _importRowsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.importRows,
    aliasName: 'import_batches__id__import_rows__batch_id',
  );

  $ImportRowsProcessedTableManager get importRowsRefs {
    final manager = $ImportRowsTableManager(
      $_db,
      $_db.importRows,
    ).filter((f) => f.batchId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_importRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $ImportBatchesFilterComposer
    extends Composer<_$LocalDatabase, ImportBatches> {
  $ImportBatchesFilterComposer({
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

  ColumnFilters<String> get contentSha256 => $composableBuilder(
    column: $table.contentSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contractVersion => $composableBuilder(
    column: $table.contractVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importedAt => $composableBuilder(
    column: $table.importedAt,
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

  Expression<bool> importRowsRefs(
    Expression<bool> Function($ImportRowsFilterComposer f) f,
  ) {
    final $ImportRowsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.batchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportRowsFilterComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ImportBatchesOrderingComposer
    extends Composer<_$LocalDatabase, ImportBatches> {
  $ImportBatchesOrderingComposer({
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

  ColumnOrderings<String> get contentSha256 => $composableBuilder(
    column: $table.contentSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contractVersion => $composableBuilder(
    column: $table.contractVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importedAt => $composableBuilder(
    column: $table.importedAt,
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
}

class $ImportBatchesAnnotationComposer
    extends Composer<_$LocalDatabase, ImportBatches> {
  $ImportBatchesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get contentSha256 => $composableBuilder(
    column: $table.contentSha256,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalName => $composableBuilder(
    column: $table.originalName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contractVersion => $composableBuilder(
    column: $table.contractVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> importRowsRefs<T extends Object>(
    Expression<T> Function($ImportRowsAnnotationComposer a) f,
  ) {
    final $ImportRowsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.batchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportRowsAnnotationComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ImportBatchesTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          ImportBatches,
          ImportBatche,
          $ImportBatchesFilterComposer,
          $ImportBatchesOrderingComposer,
          $ImportBatchesAnnotationComposer,
          $ImportBatchesCreateCompanionBuilder,
          $ImportBatchesUpdateCompanionBuilder,
          (ImportBatche, $ImportBatchesReferences),
          ImportBatche,
          PrefetchHooks Function({bool importRowsRefs})
        > {
  $ImportBatchesTableManager(_$LocalDatabase db, ImportBatches table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ImportBatchesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ImportBatchesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ImportBatchesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> contentSha256 = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String> originalName = const Value.absent(),
                Value<String> contractVersion = const Value.absent(),
                Value<String> importedAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportBatchesCompanion(
                id: id,
                contentSha256: contentSha256,
                sourceKind: sourceKind,
                originalName: originalName,
                contractVersion: contractVersion,
                importedAt: importedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String contentSha256,
                required String sourceKind,
                required String originalName,
                required String contractVersion,
                required String importedAt,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ImportBatchesCompanion.insert(
                id: id,
                contentSha256: contentSha256,
                sourceKind: sourceKind,
                originalName: originalName,
                contractVersion: contractVersion,
                importedAt: importedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<ImportBatches, ImportBatche>(table),
                  $ImportBatchesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({importRowsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (importRowsRefs) db.importRows],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (importRowsRefs)
                    await $_getPrefetchedData<
                      ImportBatche,
                      ImportBatches,
                      ImportRow
                    >(
                      currentTable: table,
                      referencedTable: $ImportBatchesReferences
                          ._importRowsRefsTable(db),
                      managerFromTypedResult: (p0) => $ImportBatchesReferences(
                        db,
                        table,
                        p0,
                      ).importRowsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.batchId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $ImportBatchesProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      ImportBatches,
      ImportBatche,
      $ImportBatchesFilterComposer,
      $ImportBatchesOrderingComposer,
      $ImportBatchesAnnotationComposer,
      $ImportBatchesCreateCompanionBuilder,
      $ImportBatchesUpdateCompanionBuilder,
      (ImportBatche, $ImportBatchesReferences),
      ImportBatche,
      PrefetchHooks Function({bool importRowsRefs})
    >;
typedef $ImportRowsCreateCompanionBuilder = ImportRowsCompanion Function({
  required String id,
  required String batchId,
  required int sourceOrdinal,
  required String recordKind,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $ImportRowsUpdateCompanionBuilder = ImportRowsCompanion Function({
  Value<String> id,
  Value<String> batchId,
  Value<int> sourceOrdinal,
  Value<String> recordKind,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

final class $ImportRowsReferences
    extends BaseReferences<_$LocalDatabase, ImportRows, ImportRow> {
  $ImportRowsReferences(super.$_db, super.$_table, super.$_typedResult);

  static ImportBatches _batchIdTable(_$LocalDatabase db) =>
      db.importBatches.createAlias('import_rows__batch_id__import_batches__id');

  $ImportBatchesProcessedTableManager get batchId {
    final $_column = $_itemColumn<String>('batch_id')!;

    final manager = $ImportBatchesTableManager(
      $_db,
      $_db.importBatches,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_batchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<Movements, List<Movement>> _movementsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.movements,
    aliasName: 'import_rows__id__movements__import_row_id',
  );

  $MovementsProcessedTableManager get movementsRefs {
    final manager = $MovementsTableManager(
      $_db,
      $_db.movements,
    ).filter((f) => f.importRowId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_movementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $ImportRowsFilterComposer extends Composer<_$LocalDatabase, ImportRows> {
  $ImportRowsFilterComposer({
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

  ColumnFilters<int> get sourceOrdinal => $composableBuilder(
    column: $table.sourceOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordKind => $composableBuilder(
    column: $table.recordKind,
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

  $ImportBatchesFilterComposer get batchId {
    final $ImportBatchesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.importBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportBatchesFilterComposer(
            $db: $db,
            $table: $db.importBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> movementsRefs(
    Expression<bool> Function($MovementsFilterComposer f) f,
  ) {
    final $MovementsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.movements,
      getReferencedColumn: (t) => t.importRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MovementsFilterComposer(
            $db: $db,
            $table: $db.movements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ImportRowsOrderingComposer
    extends Composer<_$LocalDatabase, ImportRows> {
  $ImportRowsOrderingComposer({
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

  ColumnOrderings<int> get sourceOrdinal => $composableBuilder(
    column: $table.sourceOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordKind => $composableBuilder(
    column: $table.recordKind,
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

  $ImportBatchesOrderingComposer get batchId {
    final $ImportBatchesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.importBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportBatchesOrderingComposer(
            $db: $db,
            $table: $db.importBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ImportRowsAnnotationComposer
    extends Composer<_$LocalDatabase, ImportRows> {
  $ImportRowsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sourceOrdinal => $composableBuilder(
    column: $table.sourceOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordKind => $composableBuilder(
    column: $table.recordKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $ImportBatchesAnnotationComposer get batchId {
    final $ImportBatchesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.importBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportBatchesAnnotationComposer(
            $db: $db,
            $table: $db.importBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> movementsRefs<T extends Object>(
    Expression<T> Function($MovementsAnnotationComposer a) f,
  ) {
    final $MovementsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.movements,
      getReferencedColumn: (t) => t.importRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MovementsAnnotationComposer(
            $db: $db,
            $table: $db.movements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ImportRowsTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          ImportRows,
          ImportRow,
          $ImportRowsFilterComposer,
          $ImportRowsOrderingComposer,
          $ImportRowsAnnotationComposer,
          $ImportRowsCreateCompanionBuilder,
          $ImportRowsUpdateCompanionBuilder,
          (ImportRow, $ImportRowsReferences),
          ImportRow,
          PrefetchHooks Function({bool batchId, bool movementsRefs})
        > {
  $ImportRowsTableManager(_$LocalDatabase db, ImportRows table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ImportRowsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ImportRowsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ImportRowsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<int> sourceOrdinal = const Value.absent(),
                Value<String> recordKind = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportRowsCompanion(
                id: id,
                batchId: batchId,
                sourceOrdinal: sourceOrdinal,
                recordKind: recordKind,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String batchId,
                required int sourceOrdinal,
                required String recordKind,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ImportRowsCompanion.insert(
                id: id,
                batchId: batchId,
                sourceOrdinal: sourceOrdinal,
                recordKind: recordKind,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<ImportRows, ImportRow>(table),
                  $ImportRowsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({batchId = false, movementsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (movementsRefs) db.movements],
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
                    if (batchId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.batchId,
                        referencedTable: $ImportRowsReferences._batchIdTable(
                          db,
                        ),
                        referencedColumn: $ImportRowsReferences
                            ._batchIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (movementsRefs)
                    await $_getPrefetchedData<ImportRow, ImportRows, Movement>(
                      currentTable: table,
                      referencedTable: $ImportRowsReferences
                          ._movementsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $ImportRowsReferences(db, table, p0).movementsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.importRowId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $ImportRowsProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      ImportRows,
      ImportRow,
      $ImportRowsFilterComposer,
      $ImportRowsOrderingComposer,
      $ImportRowsAnnotationComposer,
      $ImportRowsCreateCompanionBuilder,
      $ImportRowsUpdateCompanionBuilder,
      (ImportRow, $ImportRowsReferences),
      ImportRow,
      PrefetchHooks Function({bool batchId, bool movementsRefs})
    >;
typedef $AccountsCreateCompanionBuilder = AccountsCompanion Function({
  required String id,
  required String name,
  required String kind,
  required String activeFrom,
  Value<String?> activeThrough,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $AccountsUpdateCompanionBuilder = AccountsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> kind,
  Value<String> activeFrom,
  Value<String?> activeThrough,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

final class $AccountsReferences
    extends BaseReferences<_$LocalDatabase, Accounts, Account> {
  $AccountsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<Movements, List<Movement>> _movementsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.movements,
    aliasName: 'accounts__id__movements__account_id',
  );

  $MovementsProcessedTableManager get movementsRefs {
    final manager = $MovementsTableManager(
      $_db,
      $_db.movements,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_movementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    AccountLiquidityPeriods,
    List<AccountLiquidityPeriod>
  >
  _accountLiquidityPeriodsRefsTable(_$LocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.accountLiquidityPeriods,
        aliasName: 'accounts__id__account_liquidity_periods__account_id',
      );

  $AccountLiquidityPeriodsProcessedTableManager
  get accountLiquidityPeriodsRefs {
    final manager = $AccountLiquidityPeriodsTableManager(
      $_db,
      $_db.accountLiquidityPeriods,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _accountLiquidityPeriodsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $AccountsFilterComposer extends Composer<_$LocalDatabase, Accounts> {
  $AccountsFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeFrom => $composableBuilder(
    column: $table.activeFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeThrough => $composableBuilder(
    column: $table.activeThrough,
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

  Expression<bool> movementsRefs(
    Expression<bool> Function($MovementsFilterComposer f) f,
  ) {
    final $MovementsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.movements,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MovementsFilterComposer(
            $db: $db,
            $table: $db.movements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> accountLiquidityPeriodsRefs(
    Expression<bool> Function($AccountLiquidityPeriodsFilterComposer f) f,
  ) {
    final $AccountLiquidityPeriodsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.accountLiquidityPeriods,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountLiquidityPeriodsFilterComposer(
            $db: $db,
            $table: $db.accountLiquidityPeriods,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $AccountsOrderingComposer extends Composer<_$LocalDatabase, Accounts> {
  $AccountsOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeFrom => $composableBuilder(
    column: $table.activeFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeThrough => $composableBuilder(
    column: $table.activeThrough,
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
}

class $AccountsAnnotationComposer extends Composer<_$LocalDatabase, Accounts> {
  $AccountsAnnotationComposer({
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

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get activeFrom => $composableBuilder(
    column: $table.activeFrom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activeThrough => $composableBuilder(
    column: $table.activeThrough,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> movementsRefs<T extends Object>(
    Expression<T> Function($MovementsAnnotationComposer a) f,
  ) {
    final $MovementsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.movements,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MovementsAnnotationComposer(
            $db: $db,
            $table: $db.movements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> accountLiquidityPeriodsRefs<T extends Object>(
    Expression<T> Function($AccountLiquidityPeriodsAnnotationComposer a) f,
  ) {
    final $AccountLiquidityPeriodsAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.accountLiquidityPeriods,
          getReferencedColumn: (t) => t.accountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $AccountLiquidityPeriodsAnnotationComposer(
                $db: $db,
                $table: $db.accountLiquidityPeriods,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $AccountsTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          Accounts,
          Account,
          $AccountsFilterComposer,
          $AccountsOrderingComposer,
          $AccountsAnnotationComposer,
          $AccountsCreateCompanionBuilder,
          $AccountsUpdateCompanionBuilder,
          (Account, $AccountsReferences),
          Account,
          PrefetchHooks Function({
            bool movementsRefs,
            bool accountLiquidityPeriodsRefs,
          })
        > {
  $AccountsTableManager(_$LocalDatabase db, Accounts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $AccountsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $AccountsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $AccountsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> activeFrom = const Value.absent(),
                Value<String?> activeThrough = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                name: name,
                kind: kind,
                activeFrom: activeFrom,
                activeThrough: activeThrough,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String kind,
                required String activeFrom,
                Value<String?> activeThrough = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                activeFrom: activeFrom,
                activeThrough: activeThrough,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Accounts, Account>(table),
                  $AccountsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({movementsRefs = false, accountLiquidityPeriodsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (movementsRefs) db.movements,
                    if (accountLiquidityPeriodsRefs) db.accountLiquidityPeriods,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (movementsRefs)
                        await $_getPrefetchedData<Account, Accounts, Movement>(
                          currentTable: table,
                          referencedTable: $AccountsReferences
                              ._movementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $AccountsReferences(db, table, p0).movementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (accountLiquidityPeriodsRefs)
                        await $_getPrefetchedData<
                          Account,
                          Accounts,
                          AccountLiquidityPeriod
                        >(
                          currentTable: table,
                          referencedTable: $AccountsReferences
                              ._accountLiquidityPeriodsRefsTable(db),
                          managerFromTypedResult: (p0) => $AccountsReferences(
                            db,
                            table,
                            p0,
                          ).accountLiquidityPeriodsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $AccountsProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      Accounts,
      Account,
      $AccountsFilterComposer,
      $AccountsOrderingComposer,
      $AccountsAnnotationComposer,
      $AccountsCreateCompanionBuilder,
      $AccountsUpdateCompanionBuilder,
      (Account, $AccountsReferences),
      Account,
      PrefetchHooks Function({
        bool movementsRefs,
        bool accountLiquidityPeriodsRefs,
      })
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

  static MultiTypedResultKey<Movements, List<Movement>> _movementsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.movements,
    aliasName: 'categories__id__movements__category_id',
  );

  $MovementsProcessedTableManager get movementsRefs {
    final manager = $MovementsTableManager(
      $_db,
      $_db.movements,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_movementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
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

  Expression<bool> movementsRefs(
    Expression<bool> Function($MovementsFilterComposer f) f,
  ) {
    final $MovementsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.movements,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MovementsFilterComposer(
            $db: $db,
            $table: $db.movements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
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

  Expression<T> movementsRefs<T extends Object>(
    Expression<T> Function($MovementsAnnotationComposer a) f,
  ) {
    final $MovementsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.movements,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MovementsAnnotationComposer(
            $db: $db,
            $table: $db.movements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
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
          PrefetchHooks Function({bool parentId, bool movementsRefs})
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
          prefetchHooksCallback: ({parentId = false, movementsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (movementsRefs) db.movements],
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
                return [
                  if (movementsRefs)
                    await $_getPrefetchedData<Category, Categories, Movement>(
                      currentTable: table,
                      referencedTable: $CategoriesReferences
                          ._movementsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $CategoriesReferences(db, table, p0).movementsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
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
      PrefetchHooks Function({bool parentId, bool movementsRefs})
    >;
typedef $MovementsCreateCompanionBuilder = MovementsCompanion Function({
  required String id,
  required String accountId,
  required String valueDate,
  required String concept,
  required int amountCents,
  Value<String?> categoryId,
  Value<String?> discretion,
  Value<String?> importRowId,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $MovementsUpdateCompanionBuilder = MovementsCompanion Function({
  Value<String> id,
  Value<String> accountId,
  Value<String> valueDate,
  Value<String> concept,
  Value<int> amountCents,
  Value<String?> categoryId,
  Value<String?> discretion,
  Value<String?> importRowId,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

final class $MovementsReferences
    extends BaseReferences<_$LocalDatabase, Movements, Movement> {
  $MovementsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Accounts _accountIdTable(_$LocalDatabase db) =>
      db.accounts.createAlias('movements__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static Categories _categoryIdTable(_$LocalDatabase db) =>
      db.categories.createAlias('movements__category_id__categories__id');

  $CategoriesProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $CategoriesTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static ImportRows _importRowIdTable(_$LocalDatabase db) =>
      db.importRows.createAlias('movements__import_row_id__import_rows__id');

  $ImportRowsProcessedTableManager? get importRowId {
    final $_column = $_itemColumn<String>('import_row_id');
    if ($_column == null) return null;
    final manager = $ImportRowsTableManager(
      $_db,
      $_db.importRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importRowIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MovementsFilterComposer extends Composer<_$LocalDatabase, Movements> {
  $MovementsFilterComposer({
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

  ColumnFilters<String> get valueDate => $composableBuilder(
    column: $table.valueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get concept => $composableBuilder(
    column: $table.concept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get discretion => $composableBuilder(
    column: $table.discretion,
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

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $CategoriesFilterComposer get categoryId {
    final $CategoriesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
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

  $ImportRowsFilterComposer get importRowId {
    final $ImportRowsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importRowId,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportRowsFilterComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MovementsOrderingComposer extends Composer<_$LocalDatabase, Movements> {
  $MovementsOrderingComposer({
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

  ColumnOrderings<String> get valueDate => $composableBuilder(
    column: $table.valueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get concept => $composableBuilder(
    column: $table.concept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get discretion => $composableBuilder(
    column: $table.discretion,
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

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $CategoriesOrderingComposer get categoryId {
    final $CategoriesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
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

  $ImportRowsOrderingComposer get importRowId {
    final $ImportRowsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importRowId,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportRowsOrderingComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MovementsAnnotationComposer
    extends Composer<_$LocalDatabase, Movements> {
  $MovementsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get valueDate =>
      $composableBuilder(column: $table.valueDate, builder: (column) => column);

  GeneratedColumn<String> get concept =>
      $composableBuilder(column: $table.concept, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get discretion => $composableBuilder(
    column: $table.discretion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $CategoriesAnnotationComposer get categoryId {
    final $CategoriesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
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

  $ImportRowsAnnotationComposer get importRowId {
    final $ImportRowsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importRowId,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ImportRowsAnnotationComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MovementsTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          Movements,
          Movement,
          $MovementsFilterComposer,
          $MovementsOrderingComposer,
          $MovementsAnnotationComposer,
          $MovementsCreateCompanionBuilder,
          $MovementsUpdateCompanionBuilder,
          (Movement, $MovementsReferences),
          Movement,
          PrefetchHooks Function({
            bool accountId,
            bool categoryId,
            bool importRowId,
          })
        > {
  $MovementsTableManager(_$LocalDatabase db, Movements table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MovementsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MovementsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MovementsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> valueDate = const Value.absent(),
                Value<String> concept = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> discretion = const Value.absent(),
                Value<String?> importRowId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MovementsCompanion(
                id: id,
                accountId: accountId,
                valueDate: valueDate,
                concept: concept,
                amountCents: amountCents,
                categoryId: categoryId,
                discretion: discretion,
                importRowId: importRowId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                required String valueDate,
                required String concept,
                required int amountCents,
                Value<String?> categoryId = const Value.absent(),
                Value<String?> discretion = const Value.absent(),
                Value<String?> importRowId = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MovementsCompanion.insert(
                id: id,
                accountId: accountId,
                valueDate: valueDate,
                concept: concept,
                amountCents: amountCents,
                categoryId: categoryId,
                discretion: discretion,
                importRowId: importRowId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Movements, Movement>(table),
                  $MovementsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({accountId = false, categoryId = false, importRowId = false}) {
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
                        if (accountId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.accountId,
                            referencedTable: $MovementsReferences
                                ._accountIdTable(db),
                            referencedColumn: $MovementsReferences
                                ._accountIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (categoryId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.categoryId,
                            referencedTable: $MovementsReferences
                                ._categoryIdTable(db),
                            referencedColumn: $MovementsReferences
                                ._categoryIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (importRowId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.importRowId,
                            referencedTable: $MovementsReferences
                                ._importRowIdTable(db),
                            referencedColumn: $MovementsReferences
                                ._importRowIdTable(db)
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

typedef $MovementsProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      Movements,
      Movement,
      $MovementsFilterComposer,
      $MovementsOrderingComposer,
      $MovementsAnnotationComposer,
      $MovementsCreateCompanionBuilder,
      $MovementsUpdateCompanionBuilder,
      (Movement, $MovementsReferences),
      Movement,
      PrefetchHooks Function({
        bool accountId,
        bool categoryId,
        bool importRowId,
      })
    >;
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
typedef $AccountLiquidityPeriodsCreateCompanionBuilder =
    AccountLiquidityPeriodsCompanion Function({
      required String id,
      required String accountId,
      required String fromMonth,
      Value<String?> untilMonth,
      required String liquidity,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $AccountLiquidityPeriodsUpdateCompanionBuilder =
    AccountLiquidityPeriodsCompanion Function({
      Value<String> id,
      Value<String> accountId,
      Value<String> fromMonth,
      Value<String?> untilMonth,
      Value<String> liquidity,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $AccountLiquidityPeriodsReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          AccountLiquidityPeriods,
          AccountLiquidityPeriod
        > {
  $AccountLiquidityPeriodsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static Accounts _accountIdTable(_$LocalDatabase db) => db.accounts
      .createAlias('account_liquidity_periods__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $AccountLiquidityPeriodsFilterComposer
    extends Composer<_$LocalDatabase, AccountLiquidityPeriods> {
  $AccountLiquidityPeriodsFilterComposer({
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

  ColumnFilters<String> get fromMonth => $composableBuilder(
    column: $table.fromMonth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get untilMonth => $composableBuilder(
    column: $table.untilMonth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get liquidity => $composableBuilder(
    column: $table.liquidity,
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

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $AccountLiquidityPeriodsOrderingComposer
    extends Composer<_$LocalDatabase, AccountLiquidityPeriods> {
  $AccountLiquidityPeriodsOrderingComposer({
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

  ColumnOrderings<String> get fromMonth => $composableBuilder(
    column: $table.fromMonth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get untilMonth => $composableBuilder(
    column: $table.untilMonth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get liquidity => $composableBuilder(
    column: $table.liquidity,
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

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $AccountLiquidityPeriodsAnnotationComposer
    extends Composer<_$LocalDatabase, AccountLiquidityPeriods> {
  $AccountLiquidityPeriodsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromMonth =>
      $composableBuilder(column: $table.fromMonth, builder: (column) => column);

  GeneratedColumn<String> get untilMonth => $composableBuilder(
    column: $table.untilMonth,
    builder: (column) => column,
  );

  GeneratedColumn<String> get liquidity =>
      $composableBuilder(column: $table.liquidity, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $AccountLiquidityPeriodsTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          AccountLiquidityPeriods,
          AccountLiquidityPeriod,
          $AccountLiquidityPeriodsFilterComposer,
          $AccountLiquidityPeriodsOrderingComposer,
          $AccountLiquidityPeriodsAnnotationComposer,
          $AccountLiquidityPeriodsCreateCompanionBuilder,
          $AccountLiquidityPeriodsUpdateCompanionBuilder,
          (AccountLiquidityPeriod, $AccountLiquidityPeriodsReferences),
          AccountLiquidityPeriod,
          PrefetchHooks Function({bool accountId})
        > {
  $AccountLiquidityPeriodsTableManager(
    _$LocalDatabase db,
    AccountLiquidityPeriods table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $AccountLiquidityPeriodsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $AccountLiquidityPeriodsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $AccountLiquidityPeriodsAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> fromMonth = const Value.absent(),
                Value<String?> untilMonth = const Value.absent(),
                Value<String> liquidity = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountLiquidityPeriodsCompanion(
                id: id,
                accountId: accountId,
                fromMonth: fromMonth,
                untilMonth: untilMonth,
                liquidity: liquidity,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String accountId,
                required String fromMonth,
                Value<String?> untilMonth = const Value.absent(),
                required String liquidity,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AccountLiquidityPeriodsCompanion.insert(
                id: id,
                accountId: accountId,
                fromMonth: fromMonth,
                untilMonth: untilMonth,
                liquidity: liquidity,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<AccountLiquidityPeriods, AccountLiquidityPeriod>(
                    table,
                  ),
                  $AccountLiquidityPeriodsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
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
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $AccountLiquidityPeriodsReferences
                            ._accountIdTable(db),
                        referencedColumn: $AccountLiquidityPeriodsReferences
                            ._accountIdTable(db)
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

typedef $AccountLiquidityPeriodsProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      AccountLiquidityPeriods,
      AccountLiquidityPeriod,
      $AccountLiquidityPeriodsFilterComposer,
      $AccountLiquidityPeriodsOrderingComposer,
      $AccountLiquidityPeriodsAnnotationComposer,
      $AccountLiquidityPeriodsCreateCompanionBuilder,
      $AccountLiquidityPeriodsUpdateCompanionBuilder,
      (AccountLiquidityPeriod, $AccountLiquidityPeriodsReferences),
      AccountLiquidityPeriod,
      PrefetchHooks Function({bool accountId})
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $ImportBatchesTableManager get importBatches =>
      $ImportBatchesTableManager(_db, _db.importBatches);
  $ImportRowsTableManager get importRows =>
      $ImportRowsTableManager(_db, _db.importRows);
  $AccountsTableManager get accounts =>
      $AccountsTableManager(_db, _db.accounts);
  $CategoriesTableManager get categories =>
      $CategoriesTableManager(_db, _db.categories);
  $MovementsTableManager get movements =>
      $MovementsTableManager(_db, _db.movements);
  $DatabaseStateTableManager get databaseState =>
      $DatabaseStateTableManager(_db, _db.databaseState);
  $AccountLiquidityPeriodsTableManager get accountLiquidityPeriods =>
      $AccountLiquidityPeriodsTableManager(_db, _db.accountLiquidityPeriods);
}
