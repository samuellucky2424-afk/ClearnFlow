# ClearnFlow

Flutter/Android storage review MVP. The repository and package name retain **ClearnFlow**; the display brand is **CleanFlow**, matching the supplied mockups.

## What works

- Usable internal shared-storage total and available space from Android `StatFs`, shown in decimal GB. The phone's advertised capacity can be larger because the system reserves part of the device.
- First-run access flow opens Android's all-files access settings. After the user enables it, the app scans accessible shared storage, including downloads and documents. A limited, user-selected file/folder mode remains available.
- Select folders or individual files with Android's Storage Access Framework. Access is saved where the document provider permits it; it can be revoked in Settings.
- Inventory of accessible files; large files (10 MB or more), downloads, screenshots, images, videos, audio, documents and other files.
- Storage dashboard shows real category byte totals and the last completed scan time.
- Duplicate candidates grouped by file size, sampled locally to narrow candidates, then compared with full SHA-256 hashes. A matching name or sample alone is not considered a duplicate.
- Duplicate groups show file sizes, locations, and on-demand thumbnails for images and videos. Audio album artwork and embedded APK icons appear when Android can read them. Files without artwork use a type-specific icon. Tapping a file opens it in a compatible app for review.
- No copy is selected by default. **Select duplicates** selects every deletable copy except the oldest-known one in each group; **Deselect all** clears the selection. Each group has its own select/clear actions. The oldest copy is a keep suggestion, not a proven original. The app prevents deleting every copy in any group.
- Review suggestions for accessible `.tmp`/`.temp` files, thumbnail images, APK installers, archives, and downloads older than 30 days. Thumbnail metadata files such as `.nomedia` are excluded. Suggestions do not prove a file is safe to remove.
- File preview, explicit selection, in-app confirmation, and deletion. The app checks size, modification time, and any scan-time hash again before deletion. Results count only confirmed deletions. Local history records confirmed deletions only.

The storage meter represents usable device storage. File counts and sizes represent **accessible shared storage** after all-files access is enabled, or only user-selected locations in limited mode. `Android/data`, `Android/obb`, other apps' private data and system caches are excluded. The app never claims to clear them. An Android settings switch controls all-files access; it cannot be silently granted by the app. Google Play requires a [Permissions Declaration Form and approval](https://support.google.com/googleplay/android-developer/answer/10467955) for `MANAGE_EXTERNAL_STORAGE` before publication. If that approval is denied, remove the permission and use limited mode.

## Build

Install a current stable Flutter SDK, Android SDK and JDK 17. Run `flutter pub get`, `flutter test`, `flutter analyze`, then `flutter build apk --debug` from this repository. For a Play release, replace the debug signing configuration, choose a permanent application ID, create a release keystore, and build an app bundle.

## Ads and billing

The Premium screen is informational. There is no AdMob SDK, ad unit, Billing SDK, product ID, purchase button or charge in this MVP. Before monetization, configure the production IDs, consent flow, purchase verification and restore behavior, then test with Google test ads and Play license testers. Keep core cleaning usable without purchase.

## Privacy and limits

No account, backend, analytics or network permission. Metadata and file content remain on-device; SHA-256 is computed locally. Selected URI grants and aggregate deletion history live in app preferences. Broad scans cap traversal at 50,000 files; selected-folder scans cap at 20,000 files and 32 levels and report a warning. Some providers do not support deletion or persistence. A real-device test across Android 10, 13 and 15 and multiple providers is needed before Play publication. Login is a future feature, not needed for on-device cleaning.
