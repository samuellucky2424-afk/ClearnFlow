import 'domain.dart';

enum ReviewKind { temporary, oldDownload, installer, archive }

class ReviewFinding {
  const ReviewFinding(this.file, this.kind, this.reason);
  final StorageFile file;
  final ReviewKind kind;
  final String reason;
}

ReviewFinding? reviewFinding(StorageFile file, DateTime now) {
  final name = file.name.toLowerCase();
  final path = file.path.toLowerCase().replaceAll('\\', '/');
  final thumbnailImage = path.split('/').contains('.thumbnails') &&
      (file.mime.startsWith('image/') ||
       ['.jpg', '.jpeg', '.png', '.webp', '.heic'].any(name.endsWith));
  if (name.endsWith('.tmp') || name.endsWith('.temp') || thumbnailImage) {
    return ReviewFinding(file, ReviewKind.temporary,
      'Looks temporary. Open it and check before deleting.');
  }
  if (name.endsWith('.apk')) {
    return ReviewFinding(file, ReviewKind.installer,
      'APK installer. Review whether you still need this copy.');
  }
  if (['.zip', '.rar', '.7z', '.tar', '.gz'].any(name.endsWith)) {
    return ReviewFinding(file, ReviewKind.archive,
      'Archive. Check its contents or backup status before deleting.');
  }
  final old = file.modified > 0 &&
      DateTime.fromMillisecondsSinceEpoch(file.modified).isBefore(now.subtract(const Duration(days: 30)));
  if (file.download && old) {
    return ReviewFinding(file, ReviewKind.oldDownload,
      'Download older than 30 days. Review whether you still need it.');
  }
  return null;
}

List<ReviewFinding> reviewFindings(List<StorageFile> files, DateTime now) =>
    files.map((file) => reviewFinding(file, now)).whereType<ReviewFinding>().toList();
