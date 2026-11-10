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
  test('duplicate review always retains one copy', () {
    final a = file('a', 'same', 100);
    final b = file('b', 'same', 100);
    final group = [a, b];
    expect(maySelectDuplicate(a, group, {}), isTrue);
    expect(maySelectDuplicate(b, group, {a.uri}), isFalse);
    expect(suggestedKeep(group).uri, 'a');
  });
  test('select all duplicates keeps one per group and can be cleared', () {
    final a = file('a', 'first', 100);
    final b = file('b', 'first', 100);
    final c = file('c', 'first', 100);
    final d = file('d', 'second', 50);
    final e = file('e', 'second', 50);
    final selected = selectAllDuplicateCopies([[a, b, c], [d, e]]);
    expect(selected, {'b', 'c', 'e'});
    expect(selected.length, 3);
    selected.clear();
    expect(selected, isEmpty);
  });
}
