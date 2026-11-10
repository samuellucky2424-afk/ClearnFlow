import 'package:flutter/material.dart';
import 'domain.dart';
import 'storage_service.dart';

void main() => runApp(const ClearnFlowApp());

const blue = Color(0xff0757f9);
const ink = Color(0xff071438);

class ClearnFlowApp extends StatelessWidget {
  const ClearnFlowApp({super.key, this.service});
  final StorageService? service;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ClearnFlow', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: blue, primary: blue),
      scaffoldBackgroundColor: const Color(0xfff7faff), appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff7faff), foregroundColor: ink),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      textTheme: const TextTheme(titleLarge: TextStyle(fontWeight: FontWeight.w800, color: ink), titleMedium: TextStyle(fontWeight: FontWeight.w700, color: ink))),
    home: Home(service: service ?? AndroidStorageService()),
  );
}

enum Area { duplicates, large, downloads, screenshots, all }

class Home extends StatefulWidget {
  const Home({super.key, required this.service});
  final StorageService service;
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  ScanReport report = const ScanReport();
  bool busy = false, welcome = true;
  int tab = 0;
  final selected = <String>{};
  DeleteReport? lastDelete;
  String? error;
  @override void initState() { super.initState(); _initialize(); }
  Future<void> _initialize() async {
    try { welcome = !(await widget.service.onboarded()); if (!welcome) { await _scan(); } else { setState(() {}); } }
    catch (e) { setState(() => error = '$e'); }
  }
  Future<void> _scan() async {
    setState(() { busy = true; error = null; selected.clear(); });
    try { final next = await widget.service.scan(); if (mounted) setState(() => report = next); }
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
      case Area.all: return files;
    }
  }
  String _title(Area area) => switch (area) {
    Area.duplicates => 'Duplicate files', Area.large => 'Large files', Area.downloads => 'Downloads',
    Area.screenshots => 'Screenshots', Area.all => 'All selected files'};
  IconData _icon(Area area) => switch (area) {
    Area.duplicates => Icons.file_copy_outlined, Area.large => Icons.folder_outlined,
    Area.downloads => Icons.download_outlined, Area.screenshots => Icons.screenshot_outlined,
    Area.all => Icons.folder_open_outlined};
  Future<void> _delete(List<StorageFile> visible) async {
    final items = visible.where((f) => selected.contains(f.uri)).toList();
    if (items.isEmpty) return;
    final bytes = items.fold<int>(0, (n, f) => n + f.bytes);
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Delete selected files?'),
      content: Text('Delete ${items.length} file(s), currently ${formatBytes(bytes)}? This cannot be undone. Open a file first if you are unsure.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      final result = await widget.service.delete(items.map((e) => e.uri).toList());
      lastDelete = result;
      await _scan();
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => _resultPage(result)));
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Widget _resultPage(DeleteReport result) => Scaffold(appBar: AppBar(title: const Text('Cleaning results')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.check_circle, color: Color(0xff00b985), size: 90), const SizedBox(height: 20),
      Center(child: Text('${result.count} files deleted', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))),
      Center(child: Text('${formatBytes(result.bytes)} removed', style: Theme.of(context).textTheme.titleLarge)),
      if (result.failures.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 24), child: Text('Could not delete:\n${result.failures.join('\n')}')),
      const Spacer(), FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ])));
  void _openArea(Area area) { selected.clear(); Navigator.push(context, MaterialPageRoute(builder: (_) => _areaPage(area))); }
  Widget _areaPage(Area area) {
    return StatefulBuilder(builder: (context, refresh) {
      final files = _files(area);
      final groups = duplicateGroups(report.files);
      final chosen = files.where((f) => selected.contains(f.uri)).toList();
      return Scaffold(appBar: AppBar(title: Text(_title(area)), actions: [IconButton(onPressed: busy ? null : () async { await _scan(); refresh(() {}); }, icon: const Icon(Icons.refresh))]),
        body: Column(children: [
          if (area == Area.duplicates) const Padding(padding: EdgeInsets.all(16), child: Text('Matching size and SHA-256 content. Review each copy before deleting.')),
          if (files.isEmpty) Expanded(child: Center(child: Text(report.files.isEmpty ? 'Choose a folder or files on Home to start.' : 'No files found in this category.')))
          else Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: files.length, itemBuilder: (c, i) {
            final f = files[i];
            final groupSize = groups['${f.bytes}:${f.digest}']?.length;
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: const Color(0xffe8f1ff), child: Icon(_icon(area), color: blue)),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${formatBytes(f.bytes)}  •  ${f.path}${groupSize == null ? '' : '  •  $groupSize identical'}', maxLines: 2),
              onTap: () async { try { await widget.service.preview(f.uri); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } },
              trailing: Checkbox(value: selected.contains(f.uri), onChanged: f.deletable ? (v) => refresh(() { if (v == true) { selected.add(f.uri); } else { selected.remove(f.uri); } }) : null),
            ));
          })),
          if (files.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: chosen.isEmpty || busy ? null : () async { await _delete(files); refresh(() {}); },
            icon: const Icon(Icons.delete_outline), label: Text('Delete ${chosen.length} selected (${formatBytes(chosen.fold(0, (n, f) => n + f.bytes))})')))),
        ]));
    });
  }
  @override Widget build(BuildContext context) {
    if (welcome) { return Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(28), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.cleaning_services_rounded, color: blue, size: 96),
        const SizedBox(height: 20), Text('ClearnFlow', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: blue, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16), const Text('Make room for what matters.', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12), const Text('Choose folders or individual files to review. ClearnFlow checks duplicates and large files, then asks before deletion. Your files stay on your device.', textAlign: TextAlign.center),
        const SizedBox(height: 32), FilledButton(onPressed: () async { await widget.service.finishOnboarding(); setState(() => welcome = false); await _scan(); }, child: const Text('Get started')),
      ])))); }
    return Scaffold(appBar: AppBar(title: const Text('ClearnFlow', style: TextStyle(color: blue, fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: () => setState(() => tab = 3), icon: const Icon(Icons.settings_outlined))]),
      body: busy && report.files.isEmpty ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Scanning selected files…')]))
        : switch (tab) { 0 => _dashboard(), 1 => _tools(), 2 => _history(), _ => _settings() },
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'), NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Tools'),
        NavigationDestination(icon: Icon(Icons.history), label: 'History'), NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings')],));
  }
  Widget _dashboard() {
    final used = report.total - report.available;
    final fraction = report.total > 0 ? used / report.total : 0.0;
    return RefreshIndicator(onRefresh: _scan, child: ListView(padding: const EdgeInsets.all(18), children: [
      Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
        SizedBox(width: 160, height: 160, child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(child: CircularProgressIndicator(value: fraction, strokeWidth: 13, backgroundColor: const Color(0xffdceaff), strokeCap: StrokeCap.round)),
          Column(mainAxisSize: MainAxisSize.min, children: [Text('${(fraction * 100).round()}%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)), const Text('Used')]),
        ])), const SizedBox(height: 16), Text('Internal storage', style: Theme.of(context).textTheme.titleMedium),
        Text('${formatBytes(used)} used  •  ${formatBytes(report.available)} free'),
      ]))),
      const SizedBox(height: 12), FilledButton.icon(onPressed: busy ? null : _scan, icon: const Icon(Icons.search), label: const Text('Scan selected locations')),
      const SizedBox(height: 12), Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Choose folder'))),
        const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.note_add_outlined), label: const Text('Choose files')))]),
      const SizedBox(height: 12), Text('Reviewed: ${report.files.length} files • ${formatBytes(report.reviewedBytes)}', textAlign: TextAlign.center),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      if (report.warnings.isNotEmpty) Text(report.warnings.join('\n'), style: const TextStyle(color: Colors.deepOrange)),
      const SizedBox(height: 20), Text('Review files', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
      _toolGrid(),
      const SizedBox(height: 16), const Text('The storage meter covers the device. File results cover only locations you chose. System caches and other apps’ private files are outside this scan.', textAlign: TextAlign.center),
    ]));
  }
  Widget _toolGrid() => GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.55, children: [
    for (final area in [Area.duplicates, Area.large, Area.downloads, Area.screenshots, Area.all]) Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => _openArea(area), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(_icon(area), color: blue), const Spacer(), Text(_title(area), style: const TextStyle(fontWeight: FontWeight.bold)), Text('${_files(area).length} files')])))),
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
