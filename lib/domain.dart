class StorageFile {
  const StorageFile({required this.uri, required this.name, required this.bytes,
    required this.path, required this.mime, this.digest, required this.deletable});
  factory StorageFile.fromMap(Map<Object?, Object?> m) => StorageFile(
    uri: m['uri']! as String, name: m['name']! as String,
    bytes: (m['bytes']! as num).toInt(), path: m['path']! as String,
    mime: m['mime']! as String, digest: m['digest'] as String?,
    deletable: m['deletable'] == true);
  final String uri, name, path, mime;
  final int bytes;
  final String? digest;
  final bool deletable;
  bool get screenshot => '$path/$name'.toLowerCase().contains('screenshot');
  bool get download => path.toLowerCase().split('/').any((p) => p == 'download' || p == 'downloads');
}

Map<String, List<StorageFile>> duplicateGroups(List<StorageFile> files) {
  final groups = <String, List<StorageFile>>{};
  for (final f in files) {
    if (f.digest != null && f.bytes > 0) {
      (groups['${f.bytes}:${f.digest}'] ??= []).add(f);
    }
  }
  groups.removeWhere((_, group) => group.length < 2);
  return groups;
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var unit = 0;
  while (n >= 1024 && unit < units.length - 1) { n /= 1024; unit++; }
  return '${n.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

class ScanReport {
  const ScanReport({this.files = const [], this.total = 0, this.available = 0, this.warnings = const []});
  final List<StorageFile> files;
  final int total, available;
  final List<String> warnings;
  int get reviewedBytes => files.fold(0, (sum, f) => sum + f.bytes);
}

class DeleteReport {
  const DeleteReport(this.count, this.bytes, this.failures);
  final int count, bytes;
  final List<String> failures;
}
