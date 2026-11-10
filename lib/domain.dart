class StorageFile {
  const StorageFile({required this.uri, required this.name, required this.bytes,
    required this.path, required this.mime, this.digest, required this.deletable, this.modified = 0});
  factory StorageFile.fromMap(Map<Object?, Object?> m) => StorageFile(
    uri: m['uri']! as String, name: m['name']! as String,
    bytes: (m['bytes']! as num).toInt(), path: m['path']! as String,
    mime: m['mime']! as String, digest: m['digest'] as String?,
    deletable: m['deletable'] == true, modified: (m['modified'] as num?)?.toInt() ?? 0);
  final String uri, name, path, mime;
  final int bytes;
  final int modified;
  final String? digest;
  final bool deletable;
  bool get screenshot => '$path/$name'.toLowerCase().contains('screenshot');
  bool get download => path.toLowerCase().split('/').any((p) => p == 'download' || p == 'downloads');
}

Map<String, List<StorageFile>> duplicateGroups(List<StorageFile> files) {
  final groups = <String, List<StorageFile>>{};
  for (final f in files) {
    // Hidden media-index files are not personal copies to offer in bulk review.
    if (f.name.startsWith('.') || f.path.replaceAll('\\', '/').split('/')
        .any((part) => part == '.thumbnails')) {
      continue;
    }
    if (f.digest != null && f.bytes > 0) {
      (groups['${f.bytes}:${f.digest}'] ??= []).add(f);
    }
  }
  groups.removeWhere((_, group) => group.length < 2);
  return groups;
}

StorageFile suggestedKeep(List<StorageFile> group) {
  assert(group.isNotEmpty);
  final ranked = group.toList()..sort((a, b) {
    final am = a.modified == 0 ? 0x7fffffffffffffff : a.modified;
    final bm = b.modified == 0 ? 0x7fffffffffffffff : b.modified;
    final byDate = am.compareTo(bm);
    return byDate != 0 ? byDate : a.uri.compareTo(b.uri);
  });
  return ranked.first;
}

bool maySelectDuplicate(StorageFile candidate, List<StorageFile> group, Set<String> selected) =>
    !selected.contains(candidate.uri) &&
    group.where((file) => selected.contains(file.uri)).length < group.length - 1;

Set<String> selectAllDuplicateCopies(Iterable<List<StorageFile>> groups) {
  final chosen = <String>{};
  for (final group in groups) {
    if (group.length < 2) continue;
    final keep = suggestedKeep(group).uri;
    chosen.addAll(group.where((file) => file.deletable && file.uri != keep)
        .map((file) => file.uri));
  }
  return chosen;
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var unit = 0;
  while (n >= 1000 && unit < units.length - 1) { n /= 1000; unit++; }
  return '${n.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

class ScanReport {
  const ScanReport({this.files = const [], this.total = 0, this.available = 0, this.warnings = const [], this.fullAccess = false, this.scannedAt = 0});
  final List<StorageFile> files;
  final int total, available;
  final List<String> warnings;
  final bool fullAccess;
  final int scannedAt;
  int get reviewedBytes => files.fold(0, (sum, f) => sum + f.bytes);
}

class DeleteReport {
  const DeleteReport(this.count, this.bytes, this.failures);
  final int count, bytes;
  final List<String> failures;
}

class DeleteProgress {
  const DeleteProgress({required this.total, this.processed = 0, this.deleted = 0,
    this.bytes = 0, this.stage = 'starting', this.name = ''});
  factory DeleteProgress.fromMap(Map<Object?, Object?> value) => DeleteProgress(
    total: (value['total'] as num).toInt(),
    processed: (value['processed'] as num).toInt(),
    deleted: (value['deleted'] as num).toInt(),
    bytes: (value['bytes'] as num).toInt(),
    stage: value['stage'] as String,
    name: value['name'] as String? ?? '',
  );
  final int total, processed, deleted, bytes;
  final String stage, name;
}
