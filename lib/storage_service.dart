import 'package:flutter/services.dart';
import 'domain.dart';

abstract class StorageService {
  Future<bool> accessStatus();
  Future<bool> requestAccess();
  Future<ScanReport> scan();
  Future<bool> chooseFolder();
  Future<bool> chooseFiles();
  Future<void> preview(String uri);
  Future<DeleteReport> delete(List<String> uris);
  Future<bool> onboarded();
  Future<void> finishOnboarding();
  Future<void> forgetAccess();
  Future<List<Map<Object?, Object?>>> history();
}

class AndroidStorageService implements StorageService {
  static const channel = MethodChannel('clearnflow/storage');
  @override
  Future<bool> accessStatus() async => await channel.invokeMethod<bool>('accessStatus') ?? false;
  @override
  Future<bool> requestAccess() async => await channel.invokeMethod<bool>('requestAccess') ?? false;
  @override
  Future<ScanReport> scan() async {
    final m = (await channel.invokeMapMethod<Object?, Object?>('scan'))!;
    return ScanReport(files: (m['files']! as List).map((e) => StorageFile.fromMap(e as Map<Object?, Object?>)).toList(),
      total: (m['total']! as num).toInt(), available: (m['available']! as num).toInt(),
      warnings: (m['warnings']! as List).cast<String>(), fullAccess: m['access'] == true,
      scannedAt: (m['scannedAt'] as num?)?.toInt() ?? 0);
  }
  @override
  Future<bool> chooseFolder() async => await channel.invokeMethod<bool>('chooseFolder') ?? false;
  @override
  Future<bool> chooseFiles() async => await channel.invokeMethod<bool>('chooseFiles') ?? false;
  @override
  Future<void> preview(String uri) => channel.invokeMethod('preview', uri);
  @override
  Future<DeleteReport> delete(List<String> uris) async {
    final m = (await channel.invokeMapMethod<Object?, Object?>('delete', uris))!;
    return DeleteReport((m['count']! as num).toInt(), (m['bytes']! as num).toInt(), (m['failures']! as List).cast<String>());
  }
  @override
  Future<bool> onboarded() async => await channel.invokeMethod<bool>('onboarded') ?? false;
  @override
  Future<void> finishOnboarding() => channel.invokeMethod('finishOnboarding');
  @override
  Future<void> forgetAccess() => channel.invokeMethod('forgetAccess');
  @override
  Future<List<Map<Object?, Object?>>> history() async => (await channel.invokeListMethod<Object?>('history') ?? []).cast<Map<Object?, Object?>>();
}
