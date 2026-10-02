import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/local_backup_creation.dart';

/// Namespace durable: MoveFileExW WRITE_THROUGH en Windows; fsync de ambos
/// directorios en Android/Linux. No depende de canales Flutter ni de Drive.
class NativeBackupPersistence {
  final _native = _BackupNative();

  Future<void> flushFile(String path) async {
    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.flush();
    } finally {
      await file.close();
    }
  }

  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    if (!replace &&
        await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const LocalBackupFailure(LocalBackupFailureCode.storageFailure);
    }
    if (Platform.isWindows) {
      _native.moveWindows(source, target, replace);
    } else {
      final type = await FileSystemEntity.type(source, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(source).rename(target);
      } else {
        await File(source).rename(target);
      }
      _native.syncDirectory(p.dirname(source));
      if (p.dirname(source) != p.dirname(target)) {
        _native.syncDirectory(p.dirname(target));
      }
    }
  }

  Future<void> createDirectory(String path) async {
    if (await Directory(path).exists()) return;
    final temporary = '$path.${const Uuid().v4()}.next';
    await Directory(temporary).create();
    await move(temporary, path);
  }

  Future<T> exclusively<T>(String lockPath, Future<T> Function() action) async {
    if (!Platform.isWindows) {
      final fd = _native.acquire(lockPath);
      try {
        return await action();
      } finally {
        _native.release(fd);
      }
    }
    final handle = await File(lockPath).open(mode: FileMode.append);
    var locked = false;
    try {
      try {
        await handle.lock(FileLock.exclusive, 0, 1);
        locked = true;
      } on FileSystemException {
        throw const LocalBackupFailure(
          LocalBackupFailureCode.operationInProgress,
        );
      }
      return await action();
    } finally {
      if (locked) await handle.unlock(0, 1);
      await handle.close();
    }
  }
}

final class _BackupNative {
  _BackupNative() {
    if (!Platform.isWindows && !Platform.isAndroid && !Platform.isLinux) {
      throw const LocalBackupFailure(LocalBackupFailureCode.storageFailure);
    }
  }
  late final DynamicLibrary _lib = Platform.isWindows
      ? DynamicLibrary.open('msvcrt.dll')
      : DynamicLibrary.process();
  late final _malloc = _lib
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  late final _free = _lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  late final _kernel = DynamicLibrary.open('kernel32.dll');
  late final _move = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
        int Function(Pointer<Uint16>, Pointer<Uint16>, int)
      >('MoveFileExW');
  late final _open = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Int32, Uint32),
        int Function(Pointer<Uint8>, int, int)
      >('open');
  late final _fsync = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  late final _close = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final _flock = _lib
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );

  Pointer<Uint16> _wide(String value) {
    final ptr = _malloc((value.length + 1) * 2).cast<Uint16>();
    if (ptr == nullptr) _fail();
    ptr.asTypedList(value.length + 1).setAll(0, [...value.codeUnits, 0]);
    return ptr;
  }

  int _openPath(String path, int flags, int mode) {
    final bytes = [...utf8.encode(path), 0];
    final ptr = _malloc(bytes.length).cast<Uint8>();
    if (ptr == nullptr) _fail();
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return _open(ptr, flags, mode);
    } finally {
      _free(ptr.cast());
    }
  }

  void moveWindows(String source, String target, bool replace) {
    final from = _wide(source);
    Pointer<Uint16>? to;
    try {
      to = _wide(target);
      if (_move(from, to, 8 | (replace ? 1 : 0)) == 0) _fail();
    } finally {
      _free(from.cast());
      if (to != null) _free(to.cast());
    }
  }

  void syncDirectory(String path) {
    // O_DIRECTORY differs between Android ARM and x86. Check the directory
    // explicitly and use the portable O_RDONLY instead of an ABI-specific flag.
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      _fail();
    }
    final fd = _openPath(path, 0, 0); // O_RDONLY
    if (fd < 0) _fail();
    try {
      if (_fsync(fd) != 0) _fail();
    } finally {
      if (_close(fd) != 0) _fail();
    }
  }

  int acquire(String path) {
    final fd = _openPath(path, 2 | 64, 384); // O_RDWR | O_CREAT, 0600
    if (fd < 0) _fail();
    if (_flock(fd, 2 | 4) != 0) {
      _close(fd);
      throw const LocalBackupFailure(
        LocalBackupFailureCode.operationInProgress,
      );
    }
    return fd;
  }

  void release(int fd) {
    if (_close(fd) != 0) _fail();
  }

  Never _fail() =>
      throw const LocalBackupFailure(LocalBackupFailureCode.storageFailure);
}
