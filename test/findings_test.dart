import 'package:flutter_test/flutter_test.dart';
import 'package:clearnflow/domain.dart';
import 'package:clearnflow/findings.dart';

void main() {
  final now = DateTime(2026, 11, 10);
  StorageFile file(String name, String path, DateTime modified) => StorageFile(
    uri: name, name: name, bytes: 100, path: path, mime: 'application/octet-stream',
    deletable: true, modified: modified.millisecondsSinceEpoch);

  test('only evidence-backed patterns become review candidates', () {
    expect(reviewFinding(file('notes.txt', 'Documents', now), now), isNull);
    expect(reviewFinding(file('old.txt', 'Download', DateTime(2026, 9, 1)), now)?.kind,
      ReviewKind.oldDownload);
    expect(reviewFinding(file('setup.apk', 'Download', now), now)?.kind,
      ReviewKind.installer);
    expect(reviewFinding(file('backup.zip', 'Documents', now), now)?.kind,
      ReviewKind.archive);
    expect(reviewFinding(file('cache.tmp', 'Documents', now), now)?.kind,
      ReviewKind.temporary);
  });
  test('recent downloads are not marked old', () {
    expect(reviewFinding(file('new.txt', 'Download', now), now), isNull);
  });
}
