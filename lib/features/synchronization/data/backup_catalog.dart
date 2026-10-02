import 'backup_json.dart';
import '../domain/local_backup_creation.dart';

const validationFields = {
  'state',
  'checkedAtUtc',
  'policySchemaVersion',
  'issue',
};
const descriptorFields = {
  'kind',
  'formatVersion',
  'backupId',
  'datasetId',
  'applicationId',
  'schemaVersion',
  'revision',
  'createdAtUtc',
  'creationOrder',
  'origin',
  'restoreOperationId',
  'databaseFile',
  'sizeBytes',
  'databaseSha256',
  'initialValidation',
};
const intentFields = {
  'kind',
  'formatVersion',
  'backupId',
  'creationOrder',
  'origin',
  'restoreOperationId',
  'requestedAtUtc',
};

void checkBackupFormat(Map<String, dynamic> value, String kind) {
  if (value['kind'] != kind) invalidBackupMetadata();
  if (value['formatVersion'] is int && value['formatVersion'] > 1) {
    throw const LocalBackupFailure(LocalBackupFailureCode.incompatibleCatalog);
  }
  if (value['formatVersion'] is! int || value['formatVersion'] != 1) {
    invalidBackupMetadata();
  }
}

void checkBackupOrigin(Map<String, dynamic> value) {
  final operation = value['restoreOperationId'];
  if (!(value['origin'] == 'manual' && operation == null ||
      value['origin'] == 'preRestore' &&
          operation is String &&
          backupUuid.hasMatch(operation))) {
    invalidBackupMetadata();
  }
}

void checkBackupValidation(Object? value, {bool initial = false}) {
  final v = backupObject(value, validationFields);
  if (v['state'] == 'pending' && !initial) {
    if (v['checkedAtUtc'] != null ||
        v['policySchemaVersion'] != null ||
        v['issue'] != null) {
      invalidBackupMetadata();
    }
    return;
  }
  if (!{
        'valid',
        'invalid',
        'incompatible',
        'unavailable',
      }.contains(v['state']) ||
      initial && v['state'] != 'valid') {
    invalidBackupMetadata();
  }
  checkBackupUtc(v['checkedAtUtc']);
  if (v['policySchemaVersion'] is! int || v['policySchemaVersion'] < 1) {
    invalidBackupMetadata();
  }
  if (v['state'] == 'valid') {
    if (v['issue'] != null) invalidBackupMetadata();
  } else if (!{
    'incompleteFile',
    'sizeMismatch',
    'hashMismatch',
    'invalidMetadata',
    'foreignFormat',
    'futureFormat',
    'futureSchema',
    'unsupportedSchema',
    'schemaMismatch',
    'integrityFailure',
    'foreignKeyFailure',
    'financialRuleFailure',
    'missingFile',
    'storageFailure',
  }.contains(v['issue'])) {
    invalidBackupMetadata();
  }
}

void checkBackupDescriptor(Object? value) {
  final d = backupObject(value, descriptorFields);
  checkBackupFormat(d, 'autofinance.localBackup');
  if (d['backupId'] is! String ||
      !backupUuid.hasMatch(d['backupId']) ||
      d['datasetId'] is! String ||
      !datasetUuid.hasMatch(d['datasetId']) ||
      d['applicationId'] is! int ||
      d['applicationId'] != 1095126595 ||
      d['schemaVersion'] is! int ||
      d['schemaVersion'] < 1 ||
      d['databaseFile'] != 'autofinance.sqlite' ||
      d['databaseSha256'] is! String ||
      !backupHash.hasMatch(d['databaseSha256'])) {
    invalidBackupMetadata();
  }
  backupCounter(d['revision'], positive: false);
  backupCounter(d['creationOrder']);
  backupCounter(d['sizeBytes']);
  checkBackupUtc(d['createdAtUtc']);
  checkBackupOrigin(d);
  checkBackupValidation(d['initialValidation'], initial: true);
}

void checkBackupIntent(Map<String, dynamic> value, String id) {
  backupObject(value, intentFields);
  checkBackupFormat(value, 'autofinance.localBackupIntent');
  if (value['backupId'] != id || !backupUuid.hasMatch(id)) {
    invalidBackupMetadata();
  }
  backupCounter(value['creationOrder']);
  checkBackupOrigin(value);
  checkBackupUtc(value['requestedAtUtc']);
}

void checkBackupCatalog(Map<String, dynamic> value) {
  checkBackupFormat(value, 'autofinance.localBackupCatalog');
  backupObject(value, {
    'kind',
    'formatVersion',
    'generation',
    'writtenAtUtc',
    'nextCreationOrder',
    'localRestoreEpoch',
    'syncContrastRequired',
    'entries',
  });
  backupCounter(value['generation']);
  final next = backupCounter(value['nextCreationOrder']);
  checkBackupUtc(value['writtenAtUtc']);
  if (value['localRestoreEpoch'] is! String ||
      !backupUuid.hasMatch(value['localRestoreEpoch']) ||
      value['syncContrastRequired'] is! bool ||
      value['entries'] is! List) {
    invalidBackupMetadata();
  }
  final ids = <String>{};
  final orders = <int>{};
  for (final item in value['entries']) {
    final entry = backupObject(item, {
      'descriptor',
      'manifestPayloadSha256',
      'relativeDirectory',
      'availability',
      'validation',
    });
    checkBackupDescriptor(entry['descriptor']);
    final d = entry['descriptor'] as Map<String, dynamic>;
    final order = backupCounter(d['creationOrder']);
    if (!ids.add(d['backupId']) ||
        !orders.add(order) ||
        order >= next ||
        entry['relativeDirectory'] !=
            'local-backups/backups/${d['backupId']}' ||
        entry['manifestPayloadSha256'] != backupPayloadHash(d) ||
        !{
          'present',
          'missing',
          'incomplete',
          'quarantined',
          'deletionPending',
        }.contains(entry['availability'])) {
      invalidBackupMetadata();
    }
    checkBackupValidation(entry['validation']);
  }
}

void checkBackupDeletion(Map<String, dynamic> value, String id) {
  backupObject(value, {
    'kind',
    'formatVersion',
    'backupId',
    'creationOrder',
    'deletedAtUtc',
    'reason',
    'restoreOperationId',
  });
  checkBackupFormat(value, 'autofinance.localBackupDeletion');
  if (value['backupId'] != id || !backupUuid.hasMatch(id)) {
    invalidBackupMetadata();
  }
  backupCounter(value['creationOrder']);
  checkBackupUtc(value['deletedAtUtc']);
  if (!(value['reason'] == 'explicitUser' &&
          value['restoreOperationId'] == null ||
      value['reason'] == 'retention' &&
          value['restoreOperationId'] is String &&
          backupUuid.hasMatch(value['restoreOperationId']))) {
    invalidBackupMetadata();
  }
}
