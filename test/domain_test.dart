import 'package:flutter_test/flutter_test.dart';
import 'package:clearnflow/domain.dart';

void main() {
  StorageFile file(String name, String? hash, int bytes) => StorageFile(uri: name, name: name,
    bytes: bytes, path: '', mime: 'image/jpeg', digest: hash, deletable: true);
  test('duplicates require same size and content hash', () {
    final groups = duplicateGroups([file('a', 'same', 100), file('b', 'same', 100),
      file('c', 'same', 101), file('d', null, 100)]);
    expect(groups.length, 1);
    expect(groups.values.single.map((f) => f.name), ['a', 'b']);
  });
  test('no false duplicates for unreadable or empty files', () {
    expect(duplicateGroups([file('a', null, 10), file('b', null, 10), file('c', 'hash', 0), file('d', 'hash', 0)]), isEmpty);
  });
}
