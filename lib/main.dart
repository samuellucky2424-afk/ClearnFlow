import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'findings.dart';
import 'storage_service.dart';

void main() => runApp(const ClearnFlowApp());

const blue = Color(0xff0757f9);
const ink = Color(0xff071438);

class ClearnFlowApp extends StatelessWidget {
  const ClearnFlowApp({super.key, this.service});
  final StorageService? service;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CleanFlow', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: blue, primary: blue),
      scaffoldBackgroundColor: const Color(0xfff7faff), appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff7faff), foregroundColor: ink),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      textTheme: const TextTheme(titleLarge: TextStyle(fontWeight: FontWeight.w800, color: ink), titleMedium: TextStyle(fontWeight: FontWeight.w700, color: ink))),
    home: Home(service: service ?? AndroidStorageService()),
  );
}

enum Area { duplicates, large, downloads, screenshots, review, images, videos, audio, documents, other, all }

class Home extends StatefulWidget {
  const Home({super.key, required this.service});
  final StorageService service;
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  ScanReport report = const ScanReport();
  bool busy = false, splash = true, welcome = false, needsAccess = false;
  int tab = 0;
  final selected = <String>{};
  final thumbnails = <String, Future<Uint8List?>>{};
  DeleteReport? lastDelete;
  String? error;
  @override void initState() { super.initState(); _initialize(); }
  Future<void> _initialize() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final firstRun = !(await widget.service.onboarded());
      final hasAccess = await widget.service.accessStatus();
      if (!mounted) return;
      setState(() { splash = false; welcome = firstRun; needsAccess = !hasAccess && !firstRun; });
      if (hasAccess) await _scan();
    }
    catch (e) { setState(() => error = '$e'); }
  }
  Future<void> _grantAccess() async {
    try {
      final granted = await widget.service.requestAccess();
      if (!mounted) return;
      setState(() => needsAccess = !granted);
      if (granted) await _scan();
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  Future<void> _scan() async {
    setState(() { busy = true; error = null; selected.clear(); });
    try { final next = await widget.service.scan(); if (mounted) setState(() { report = next; thumbnails.clear(); }); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> _pick(bool folder) async {
    try { if (await (folder ? widget.service.chooseFolder() : widget.service.chooseFiles())) await _scan(); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  List<StorageFile> _files(Area area) {
    final files = report.files;
    switch (area) {
      case Area.duplicates:
        final ids = duplicateGroups(files).values.expand((e) => e).map((e) => e.uri).toSet();
        return files.where((e) => ids.contains(e.uri)).toList();
      case Area.large: return files.where((e) => e.bytes >= 10 * 1024 * 1024).toList()..sort((a, b) => b.bytes.compareTo(a.bytes));
      case Area.downloads: return files.where((e) => e.download).toList();
      case Area.screenshots: return files.where((e) => e.screenshot).toList();
      case Area.review: return reviewFindings(files, DateTime.now()).map((e) => e.file).toList();
      case Area.images: return files.where((e) => e.mime.startsWith('image/')).toList();
      case Area.videos: return files.where((e) => e.mime.startsWith('video/')).toList();
      case Area.audio: return files.where((e) => e.mime.startsWith('audio/')).toList();
      case Area.documents: return files.where((e) => _isDocument(e)).toList();
      case Area.other: return files.where((e) => !e.mime.startsWith('image/') && !e.mime.startsWith('video/') && !e.mime.startsWith('audio/') && !_isDocument(e)).toList();
      case Area.all: return files;
    }
  }
  bool _isDocument(StorageFile file) => file.mime.startsWith('text/') ||
    ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].any((ext) => file.name.toLowerCase().endsWith('.$ext'));
  String _title(Area area) => switch (area) {
    Area.duplicates => 'Duplicate files', Area.large => 'Large files', Area.downloads => 'Downloads',
    Area.screenshots => 'Screenshots', Area.review => 'Review suggested files', Area.images => 'Images', Area.videos => 'Videos',
    Area.audio => 'Audio', Area.documents => 'Documents', Area.other => 'Other files', Area.all => 'All files'};
  IconData _icon(Area area) => switch (area) {
    Area.duplicates => Icons.file_copy_outlined, Area.large => Icons.folder_outlined,
    Area.downloads => Icons.download_outlined, Area.screenshots => Icons.screenshot_outlined,
    Area.review => Icons.cleaning_services_outlined,
    Area.images => Icons.image_outlined, Area.videos => Icons.movie_outlined,
    Area.audio => Icons.music_note_outlined, Area.documents => Icons.description_outlined,
    Area.other => Icons.insert_drive_file_outlined, Area.all => Icons.folder_open_outlined};
  Future<void> _delete(List<StorageFile> visible) async {
    if (busy) return;
    final items = visible.where((f) => selected.contains(f.uri)).toList();
    if (items.isEmpty) return;
    final deleting = items.map((f) => f.uri).toSet();
    if (duplicateGroups(report.files).values.any((group) =>
        group.every((file) => deleting.contains(file.uri)))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Keep at least one copy in each duplicate group.')));
      return;
    }
    final bytes = items.fold<int>(0, (n, f) => n + f.bytes);
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Delete selected files?'),
      content: Text('Delete ${items.length} file(s), currently ${formatBytes(bytes)}? This cannot be undone. Open a file first if you are unsure.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    final progress = ValueNotifier(DeleteProgress(total: items.length));
    final dialog = showDialog<void>(context: context, barrierDismissible: false,
      builder: (_) => _deleteProgressDialog(progress));
    DeleteReport? result;
    Object? failure;
    try {
      result = await widget.service.delete(items.map((e) => e.uri).toList(),
        onProgress: (next) { if (mounted) progress.value = next; });
      lastDelete = result;
      progress.value = DeleteProgress(total: items.length, processed: items.length,
        deleted: result.count, bytes: result.bytes, stage: 'refreshing');
      await _scan();
    } catch (e) { failure = e; }
    finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await dialog;
        setState(() => busy = false);
      }
      progress.dispose();
    }
    if (!mounted) return;
    if (result != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => _resultPage(result!)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not finish deletion: $failure')));
    }
  }
  Widget _deleteProgressDialog(ValueNotifier<DeleteProgress> progress) => PopScope(
    canPop: false, child: AlertDialog(
      title: const Text('Checking and deleting files'),
      content: ValueListenableBuilder<DeleteProgress>(valueListenable: progress,
        builder: (context, value, _) => Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 12),
            Expanded(child: Text(value.stage == 'refreshing' ? 'Refreshing file list…' :
              value.stage == 'checking' ? 'Checking ${value.processed + 1} of ${value.total}…' :
              'Processing ${value.processed} of ${value.total}…'))]),
          const SizedBox(height: 18),
          LinearProgressIndicator(value: value.stage == 'starting' || value.stage == 'refreshing'
            ? null : value.processed / value.total),
          const SizedBox(height: 12),
          Text('${value.processed} of ${value.total} files checked'),
          Text('${value.deleted} deleted • ${formatBytes(value.bytes)} removed'),
          if (value.name.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(value.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ])),
    ));
  Widget _resultPage(DeleteReport result) => Scaffold(appBar: AppBar(title: const Text('Cleaning results')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.check_circle, color: Color(0xff00b985), size: 90), const SizedBox(height: 20),
      Center(child: Text('${result.count} files deleted', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))),
      Center(child: Text('${formatBytes(result.bytes)} removed', style: Theme.of(context).textTheme.titleLarge)),
      if (result.failures.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 24), child: Text('Could not delete:\n${result.failures.join('\n')}')),
      const Spacer(), FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ])));
  void _openArea(Area area) { selected.clear(); Navigator.push(context, MaterialPageRoute(builder: (_) => area == Area.duplicates ? _duplicatesPage() : _areaPage(area))); }
  Future<Uint8List?> _loadThumbnail(String uri) async {
    try { return await widget.service.thumbnail(uri, 256); }
    catch (_) { return null; }
  }
  Future<Uint8List?> _thumbnail(StorageFile file) {
    final key = '${file.uri}:${file.modified}';
    if (!thumbnails.containsKey(key) && thumbnails.length >= 160) {
      thumbnails.remove(thumbnails.keys.first);
    }
    return thumbnails.putIfAbsent(key, () => _loadThumbnail(file.uri));
  }
  Widget _fileIcon(StorageFile file, double size) {
    final name = file.name.toLowerCase();
    final icon = file.mime.startsWith('image/') ? Icons.image_outlined :
      file.mime.startsWith('video/') ? Icons.movie_outlined :
      file.mime.startsWith('audio/') ? Icons.music_note_outlined :
      name.endsWith('.apk') ? Icons.android :
      name.endsWith('.pdf') ? Icons.picture_as_pdf_outlined :
      ['.zip', '.rar', '.7z'].any(name.endsWith) ? Icons.folder_zip_outlined :
      Icons.description_outlined;
    final color = name.endsWith('.pdf') ? const Color(0xffd84343) :
      file.mime.startsWith('audio/') ? const Color(0xff8552df) : blue;
    return SizedBox(width: size, height: size, child: ColoredBox(
      color: const Color(0xffe8f1ff), child: Icon(icon, color: color, size: size * .52)));
  }
  Widget _artwork(StorageFile file, {double size = 52}) {
    final visual = file.mime.startsWith('image/') || file.mime.startsWith('video/') ||
        file.mime.startsWith('audio/') || file.name.toLowerCase().endsWith('.apk');
    if (!visual) return _fileIcon(file, size);
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: FutureBuilder<Uint8List?>(
      future: _thumbnail(file), builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return _fileIcon(file, size);
        return Stack(alignment: Alignment.center, children: [
          Image.memory(bytes, width: size, height: size, fit: BoxFit.cover,
            gaplessPlayback: true, errorBuilder: (_, _, _) => _fileIcon(file, size)),
          if (file.mime.startsWith('video/')) Container(
            decoration: const BoxDecoration(color: Color(0x99071438), shape: BoxShape.circle),
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size * .34)),
        ]);
      }));
  }
  Widget _duplicatesPage() => StatefulBuilder(builder: (context, refresh) {
    final groups = duplicateGroups(report.files).values.toList()
      ..sort((a, b) => b.first.bytes.compareTo(a.first.bytes));
    final visible = groups.expand((group) => group).toList();
    final chosen = visible.where((file) => selected.contains(file.uri)).toList();
    final avoidableBytes = groups.fold<int>(0, (sum, group) => sum + (group.length - 1) * group.first.bytes);
    return Scaffold(appBar: AppBar(title: const Text('Duplicate files')),
      body: Column(children: [
        Container(width: double.infinity, margin: const EdgeInsets.all(14), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xffe3ecff), borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${groups.length} ${groups.length == 1 ? 'group' : 'groups'} • ${visible.length} identical files', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Up to ${formatBytes(avoidableBytes)} if one copy from each group is kept.'),
            const Text('No files are selected at first. Tap a preview to open it.'),
            const Text('The oldest known copy is suggested to keep; its age does not prove it is the original.'),
          ])),
        if (groups.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => refresh(() {
            selected..clear()..addAll(selectAllDuplicateCopies(groups));
          }), icon: const Icon(Icons.select_all), label: const Text('Select all duplicates'))),
          const SizedBox(width: 8),
          TextButton(onPressed: selected.isEmpty ? null : () => refresh(selected.clear),
            child: const Text('Deselect all')),
        ])),
        if (groups.isEmpty) const Expanded(child: Center(child: Text('No exact duplicates found in accessible files.')))
        else Expanded(child: ListView.builder(itemCount: groups.length, itemBuilder: (context, index) {
          final group = groups[index].toList()..sort((a, b) => a.modified.compareTo(b.modified));
          final recommended = suggestedKeep(group);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(18, 14, 12, 8), child: Row(children: [
              Expanded(child: Text('${group.length} identical • ${formatBytes(group.first.bytes)} each',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              TextButton(onPressed: () => refresh(() {
                for (final file in group) { selected.remove(file.uri); }
                selected.addAll(selectAllDuplicateCopies([group]));
              }), child: const Text('Select others')),
              TextButton(onPressed: group.any((file) => selected.contains(file.uri))
                ? () => refresh(() { for (final file in group) { selected.remove(file.uri); } })
                : null, child: const Text('Clear')),
            ])),
            SizedBox(height: 224, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal, itemCount: group.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8), itemBuilder: (context, i) {
                final file = group[i];
                return SizedBox(width: 152, child: Card(clipBehavior: Clip.antiAlias, child: InkWell(
                  onTap: () async { try { await widget.service.preview(file.uri); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Stack(children: [
                      SizedBox(width: 152, height: 112, child: _artwork(file, size: 152)),
                      Positioned(right: 2, top: 2, child: Checkbox(value: selected.contains(file.uri),
                        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? blue : Colors.white),
                        onChanged: (value) {
                          if (value == true && !maySelectDuplicate(file, group, selected)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keep at least one copy in each group.')));
                            return;
                          }
                          refresh(() { if (value == true) { selected.add(file.uri); } else { selected.remove(file.uri); } });
                        })),
                    ]),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: Text('${formatBytes(file.bytes)} • ${file.path}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (file.uri == recommended.uri) const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: Text('Keep suggested', style: TextStyle(color: Color(0xff008c72), fontWeight: FontWeight.bold, fontSize: 12))),
                  ]))));
              })),
          ]);
        })),
        Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: chosen.isEmpty ? null : () async { await _delete(visible); refresh(() {}); },
          icon: const Icon(Icons.delete_outline),
          label: Text('Delete ${chosen.length} selected • ${formatBytes(chosen.fold<int>(0, (sum, f) => sum + f.bytes))}'),
        ))),
      ]));
  });
  Widget _areaPage(Area area) {
    return StatefulBuilder(builder: (context, refresh) {
      final files = _files(area);
      final groups = duplicateGroups(report.files);
      final chosen = files.where((f) => selected.contains(f.uri)).toList();
      return Scaffold(appBar: AppBar(title: Text(_title(area)), actions: [IconButton(onPressed: busy ? null : () async { await _scan(); refresh(() {}); }, icon: const Icon(Icons.refresh))]),
        body: Column(children: [
          if (area == Area.review) Padding(padding: const EdgeInsets.all(16), child: Text(
            '${files.length} items • ${formatBytes(files.fold<int>(0, (sum, file) => sum + file.bytes))}. These are suggestions, not files proven safe to delete. Preview each one first.')),
          if (files.isEmpty) Expanded(child: Center(child: Text(report.files.isEmpty ? 'Choose a folder or files on Home to start.' : 'No files found in this category.')))
          else Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: files.length, itemBuilder: (c, i) {
            final f = files[i];
            final groupSize = groups['${f.bytes}:${f.digest}']?.length;
            return Card(child: ListTile(
              leading: _artwork(f),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${formatBytes(f.bytes)}  •  ${f.path}${f.modified == 0 ? '' : '\nModified ${DateTime.fromMillisecondsSinceEpoch(f.modified).toLocal().toString().split(' ').first}'}${groupSize == null ? '' : '  •  $groupSize identical'}${area == Area.review ? '\n${reviewFinding(f, DateTime.now())?.reason ?? ''}' : ''}', maxLines: 4),
              onTap: () async { try { await widget.service.preview(f.uri); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } },
              trailing: Checkbox(value: selected.contains(f.uri), onChanged: f.deletable ? (v) {
                final group = groups['${f.bytes}:${f.digest}'];
                if (v == true && group != null && !maySelectDuplicate(f, group, selected)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Keep at least one copy in each duplicate group.')));
                  return;
                }
                refresh(() { if (v == true) { selected.add(f.uri); } else { selected.remove(f.uri); } });
              } : null),
            ));
          })),
          if (files.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: chosen.isEmpty || busy ? null : () async { await _delete(files); refresh(() {}); },
            icon: const Icon(Icons.delete_outline), label: Text('Delete ${chosen.length} selected (${formatBytes(chosen.fold(0, (n, f) => n + f.bytes))})')))),
        ]));
    });
  }
  @override Widget build(BuildContext context) {
    if (splash) return _splashPage();
    if (welcome) return _welcomePage();
    if (needsAccess) return _accessPage();
    return Scaffold(appBar: AppBar(title: const Row(children: [Icon(Icons.cleaning_services_rounded, color: blue), SizedBox(width: 8), Text('CleanFlow', style: TextStyle(color: blue, fontWeight: FontWeight.w800))]), actions: [IconButton(onPressed: () => setState(() => tab = 3), icon: const Icon(Icons.settings_outlined))]),
      body: busy ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Scanning shared storage…')]))
        : switch (tab) { 0 => _dashboard(), 1 => _tools(), 2 => _history(), _ => _settings() },
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'), NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Tools'),
        NavigationDestination(icon: Icon(Icons.history), label: 'History'), NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings')],));
  }
  Widget _splashPage() => Scaffold(body: Container(
    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xff0879ff), Color(0xff0754ee), Color(0xff0038c9)])),
    child: SafeArea(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
      const Spacer(flex: 3),
      Stack(alignment: Alignment.center, children: [
        Container(width: 142, height: 142, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(36))),
        Transform.rotate(angle: .35, child: const Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 110)),
        const Positioned(top: 4, right: 8, child: Icon(Icons.auto_awesome, color: Color(0xff56e5ff), size: 30)),
      ]),
      const SizedBox(height: 24), const Text('CleanFlow', style: TextStyle(color: Colors.white, fontSize: 43, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6), const Text('More Space. Better Performance.', style: TextStyle(color: Colors.white, fontSize: 16)),
      const Spacer(flex: 3),
      LinearProgressIndicator(minHeight: 4, borderRadius: BorderRadius.circular(8), color: Colors.white, backgroundColor: Colors.white30),
      const SizedBox(height: 12), const Text('Preparing your cleaner…', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 42),
    ]))),
  ));
  Widget _welcomePage() => Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
    const Spacer(),
    Stack(alignment: Alignment.center, children: [
      Container(width: 260, height: 260, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xffe8f3ff))),
      Container(width: 145, height: 225, decoration: BoxDecoration(color: const Color(0xff072e8c), borderRadius: BorderRadius.circular(25), border: Border.all(color: ink, width: 4)),
        child: Column(children: [const SizedBox(height: 12), Expanded(child: Container(margin: const EdgeInsets.all(7), decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(15)), child: const Center(child: Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 68)))), const SizedBox(height: 8)])),
      const Positioned(left: 5, top: 45, child: Icon(Icons.image, color: Color(0xff3ca9f4), size: 37)),
      const Positioned(right: 5, top: 75, child: Icon(Icons.folder, color: Color(0xff16c4a2), size: 40)),
      const Positioned(left: 20, bottom: 42, child: Icon(Icons.file_copy, color: Color(0xff7d67f7), size: 31)),
    ]),
    const SizedBox(height: 30), const Text('Keep Your Phone\nClean & Fast', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 16), const Text('Find duplicate files, large files, downloads and screenshots. Review every file before removing it.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Color(0xff425477))),
    const Spacer(),
    const Text('●  ○  ○', style: TextStyle(color: blue, fontSize: 18)),
    const SizedBox(height: 24), SizedBox(width: double.infinity, child: FilledButton(onPressed: () async {
      await widget.service.finishOnboarding(); if (!mounted) return;
      setState(() => welcome = false); await _grantAccess();
    }, child: const Text('Get Started'))),
    const SizedBox(height: 14), TextButton(onPressed: () async {
      await widget.service.finishOnboarding(); if (!mounted) return;
      setState(() { welcome = false; needsAccess = false; }); await _scan();
    }, child: const Text('Use limited access')),
    const SizedBox(height: 20),
  ]))));
  Widget _accessPage() => Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(26), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.folder_open_rounded, size: 100, color: blue), const SizedBox(height: 26),
    const Text('Find files across your phone', textAlign: TextAlign.center, style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 16),
    const Text('Allow all-files access to scan shared storage for duplicates, large files, downloads and screenshots. Android opens a settings screen where you choose whether to allow it. Private app data stays outside this scan.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
    const SizedBox(height: 25), SizedBox(width: double.infinity, child: FilledButton(onPressed: _grantAccess, child: const Text('Continue to access settings'))),
    TextButton(onPressed: () async { setState(() => needsAccess = false); await _scan(); }, child: const Text('Use limited access instead')),
    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
  ]))));
  Widget _dashboard() {
    final used = report.total - report.available;
    final fraction = report.total > 0 ? used / report.total : 0.0;
    return RefreshIndicator(onRefresh: _scan, child: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
        SizedBox(width: 148, height: 148, child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(child: CircularProgressIndicator(value: fraction, strokeWidth: 11, backgroundColor: const Color(0xffdff0ff), color: const Color(0xff00b9d7), strokeCap: StrokeCap.round)),
          Column(mainAxisSize: MainAxisSize.min, children: [Text('${(fraction * 100).round()}%', style: const TextStyle(fontSize: 35, fontWeight: FontWeight.w900)), const Text('Used'), Text('${formatBytes(used)} / ${formatBytes(report.total)}', style: const TextStyle(fontSize: 11, color: Color(0xff596a83)))]),
        ])), const SizedBox(height: 14),
        const Text('Usable internal storage', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10), LinearProgressIndicator(value: fraction, minHeight: 8, borderRadius: BorderRadius.circular(10)),
        const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Used: ${formatBytes(used)}'), Text('Free: ${formatBytes(report.available)}')]),
      ]))),
      const SizedBox(height: 8),
      Card(child: ListTile(leading: const Icon(Icons.pie_chart_outline, color: blue), title: const Text('Storage Analyzer'),
        subtitle: Text('${report.files.length} files indexed\nLast completed scan: ${report.scannedAt == 0 ? 'Never' : DateTime.fromMillisecondsSinceEpoch(report.scannedAt).toLocal().toString().split('.').first}'),
        isThreeLine: true, trailing: const Icon(Icons.chevron_right), onTap: _storageDetails)),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Accessible file categories', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (final area in [Area.images, Area.videos, Area.audio, Area.documents, Area.other])
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
            Icon(_icon(area), color: blue, size: 18), const SizedBox(width: 8), Expanded(child: Text(_title(area))),
            Text(formatBytes(_files(area).fold<int>(0, (sum, f) => sum + f.bytes))),
          ])),
      ]))),
      const SizedBox(height: 8),
      if (!report.fullAccess) Card(child: ListTile(leading: const Icon(Icons.lock_open, color: blue), title: const Text('Allow a full scan'), subtitle: const Text('Currently showing only files you selected'), trailing: const Icon(Icons.chevron_right), onTap: _grantAccess)),
      FilledButton.icon(onPressed: busy ? null : _scan, icon: const Icon(Icons.search), label: const Text('Scan Again')),
      if (!report.fullAccess) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Choose folder'))),
        const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.note_add_outlined), label: const Text('Choose files')))])),
      const SizedBox(height: 12), Text('Reviewed: ${report.files.length} files • ${formatBytes(report.reviewedBytes)}', textAlign: TextAlign.center),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      if (report.warnings.isNotEmpty) Text(report.warnings.join('\n'), style: const TextStyle(color: Colors.deepOrange)),
      const SizedBox(height: 20), Text('Clean & review', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
      _toolGrid(),
      const SizedBox(height: 16), Text(report.fullAccess
        ? 'The meter shows usable device storage. File results cover accessible shared storage. Private app data and system caches are excluded.'
        : 'The meter shows usable device storage. File results cover only locations you chose.', textAlign: TextAlign.center),
    ]));
  }
  void _storageDetails() => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
    appBar: AppBar(title: const Text('Storage Analyzer')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
        Text('${formatBytes(report.total - report.available)} used', style: Theme.of(context).textTheme.titleLarge),
        Text('${formatBytes(report.available)} free of ${formatBytes(report.total)} usable'),
      ]))),
      const SizedBox(height: 12), const Text('Accessible files by category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      for (final area in [Area.images, Area.videos, Area.audio, Area.documents, Area.other]) Card(child: ListTile(
        leading: Icon(_icon(area), color: blue), title: Text(_title(area)),
        subtitle: Text('${_files(area).length} files'), trailing: Text(formatBytes(_files(area).fold<int>(0, (sum, file) => sum + file.bytes))),
        onTap: () => _openArea(area),
      )),
      const SizedBox(height: 12), Text(report.fullAccess ? 'Categories cover accessible shared storage, not apps or system files.' : 'Categories cover only locations you selected.'),
    ]),
  )));
  Widget _toolGrid() => GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.45, children: [
    for (final area in [Area.duplicates, Area.large, Area.downloads, Area.screenshots, Area.review, Area.all]) Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => _openArea(area), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(_icon(area), color: blue), const Spacer(), Text(_title(area), style: const TextStyle(fontWeight: FontWeight.bold)), Text('${_files(area).length} files')])))),
  ]);
  Widget _tools() => ListView(padding: const EdgeInsets.all(18), children: [Text('Your tools', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12), _toolGrid(),
    const SizedBox(height: 16), const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Junk files: Android does not allow this app to clear other apps’ caches. You can review your own selected folders and files instead.')))]);
  Widget _history() => FutureBuilder<List<Map<Object?, Object?>>>(future: widget.service.history(), builder: (context, snap) => ListView(padding: const EdgeInsets.all(18), children: [
    Text('Cleaning history', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
    if (snap.data?.isEmpty ?? true) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No completed deletions yet.'))),
    for (final row in snap.data ?? []) Card(child: ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text('${row['count']} files deleted'),
      subtitle: Text(DateTime.fromMillisecondsSinceEpoch(row['time'] as int).toLocal().toString().split('.').first), trailing: Text(formatBytes(row['bytes'] as int)))),
  ]));
  Widget _settings() => ListView(padding: const EdgeInsets.all(18), children: [
    Text('Settings', style: Theme.of(context).textTheme.titleLarge),
    const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('ClearnFlow MVP'), subtitle: Text('Private, on-device storage review'))),
    Card(child: ListTile(leading: const Icon(Icons.folder_off_outlined), title: const Text('Forget selected locations'), subtitle: const Text('Remove folder and file access granted to this app'), onTap: () async { await widget.service.forgetAccess(); await _scan(); })),
    Card(child: ListTile(
      leading: const Icon(Icons.workspace_premium_outlined),
      title: const Text('Premium'),
      subtitle: const Text('Purchases are not available yet'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Premium')),
        body: const Center(child: Padding(padding: EdgeInsets.all(28), child: Text(
          'Premium is coming later. No payment is charged in this version.',
          textAlign: TextAlign.center,
        ))),
      ))),
    )),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Ads and purchases are disabled until configured, tested, and reviewed.'))),
  ]);
}
