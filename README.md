# ClearnFlow

Flutter/Android storage review MVP. Product name follows the existing repository spelling. The UI takes its blue and white direction from the supplied mockups.

## What works

- Device total and available storage from Android `StatFs`.
- Select folders or individual files with Android's Storage Access Framework. Access is saved where the document provider permits it; it can be revoked in Settings.
- Inventory of selected files; large files (10 MB or more), downloads and screenshots within selected locations.
- Duplicate candidates grouped by file size, then compared with full SHA-256 hashes. A matching name alone is not considered a duplicate.
- File preview, explicit selection, in-app confirmation, and document-provider deletion. The app checks size and any scan-time hash again before deletion. Results count only files the provider confirms deleted. Local history records confirmed deletions only.

The storage meter represents device storage. File counts and sizes represent **only selected locations**, not the whole phone. Selecting the `Download` root is restricted on recent Android versions; select files within it using **Choose files**, or another permitted folder. Other apps' caches and private data are inaccessible. The app never claims to clear them.

## Build

Install a current stable Flutter SDK, Android SDK and JDK 17. Run `flutter pub get`, `flutter test`, `flutter analyze`, then `flutter build apk --debug` from this repository. For a Play release, replace the debug signing configuration, choose a permanent application ID, create a release keystore, and build an app bundle.

## Ads and billing

The Premium screen is informational. There is no AdMob SDK, ad unit, Billing SDK, product ID, purchase button or charge in this MVP. Before monetization, configure the production IDs, consent flow, purchase verification and restore behavior, then test with Google test ads and Play license testers. Keep core cleaning usable without purchase.

## Privacy and limits

No account, backend, analytics or network permission. Metadata and file content remain on-device; SHA-256 is computed locally. Selected URI grants and aggregate deletion history live in app preferences. Selecting a huge folder may take time; scans cap traversal at 20,000 files and 32 levels and report a warning. Some providers do not support deletion or persistence. A real-device test across Android 10, 13 and 15 and multiple providers is needed before Play publication.
