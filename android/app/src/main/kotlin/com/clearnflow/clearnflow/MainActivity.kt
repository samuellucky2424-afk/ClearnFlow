package com.clearnflow.clearnflow

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.io.File
import java.io.InputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "clearnflow/storage"
    private val prefs by lazy { getSharedPreferences("clearnflow", MODE_PRIVATE) }
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var latest = emptyMap<String, Entry>()
    private data class Entry(val uri: Uri, val name: String, val path: String,
                             val size: Long, val mime: String, val digest: String?,
                             val file: File? = null, val modified: Long = 0)
    private fun broadAccess() = Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "onboarded" -> result.success(prefs.getBoolean("onboarded", false))
                "finishOnboarding" -> { prefs.edit().putBoolean("onboarded", true).apply(); result.success(null) }
                "accessStatus" -> result.success(broadAccess())
                "requestAccess" -> {
                    if (broadAccess()) { result.success(true); return@setMethodCallHandler }
                    if (Build.VERSION.SDK_INT < 30) { result.success(false); return@setMethodCallHandler }
                    if (pending != null) { result.error("BUSY", "Picker already open", null); return@setMethodCallHandler }
                    pending = result
                    try {
                        startActivityForResult(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:$packageName")), 102)
                    } catch (e: Exception) {
                        try { startActivityForResult(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION), 102) }
                        catch (fallback: Exception) { pending = null; result.error("ACCESS", fallback.message, null) }
                    }
                }
                "chooseFolder", "chooseFiles" -> {
                    if (pending != null) { result.error("BUSY", "Picker already open", null); return@setMethodCallHandler }
                    pending = result
                    val folder = call.method == "chooseFolder"
                    val intent = Intent(if (folder) Intent.ACTION_OPEN_DOCUMENT_TREE else Intent.ACTION_OPEN_DOCUMENT).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        if (!folder) { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"; putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true) }
                    }
                    startActivityForResult(intent, if (folder) 100 else 101)
                }
                "scan" -> worker.execute {
                    try { val report = scan(); runOnUiThread { result.success(report) } }
                    catch (e: Exception) { runOnUiThread { result.error("SCAN", e.message, null) } }
                }
                "delete" -> worker.execute {
                    try {
                        val uris = call.arguments as? List<*> ?: emptyList<Any>()
                        val deleted = mutableListOf<String>()
                        val failures = mutableListOf<String>()
                        var bytes = 0L
                        for (candidate in uris) {
                            val id = candidate as? String ?: continue
                            val entry = latest[id] ?: continue
                            try {
                                // A file changed since scanning must be reviewed again.
                                val currentSize = if (entry.file != null) entry.file.length() else
                                    contentResolver.query(entry.uri, arrayOf(DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else -1L } ?: -1L
                                val changed = currentSize != entry.size ||
                                    (entry.file != null && entry.file.lastModified() != entry.modified) ||
                                    (entry.digest != null && hash(entry) != entry.digest)
                                if (changed) {
                                    failures.add("${entry.name}: changed since scan"); continue
                                }
                                val removed = if (entry.file != null) {
                                    if (!broadAccess()) false else entry.file.delete()
                                } else DocumentsContract.deleteDocument(contentResolver, entry.uri)
                                if (removed) {
                                    deleted.add(id); bytes += entry.size
                                } else failures.add("${entry.name}: provider refused deletion")
                            } catch (e: Exception) { failures.add("${entry.name}: ${e.message ?: "deletion failed"}") }
                        }
                        latest = latest.filterKeys { it !in deleted }
                        if (deleted.isNotEmpty()) {
                            val old = prefs.getString("history", "") ?: ""
                            prefs.edit().putString("history", "${System.currentTimeMillis()},${deleted.size},$bytes\n$old").apply()
                        }
                        runOnUiThread { result.success(mapOf("count" to deleted.size, "bytes" to bytes, "failures" to failures)) }
                    } catch (e: Exception) { runOnUiThread { result.error("DELETE", e.message, null) } }
                }
                "preview" -> {
                    try {
                        val entry = latest[call.arguments as String] ?: throw IllegalArgumentException("Scan again to open this file")
                        val uri = if (entry.file == null) entry.uri else FileProvider.getUriForFile(this, "$packageName.files", entry.file)
                        startActivity(Intent(Intent.ACTION_VIEW).apply { setDataAndType(uri, entry.mime); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) })
                        result.success(null)
                    } catch (e: Exception) { result.error("PREVIEW", e.message, null) }
                }
                "history" -> result.success((prefs.getString("history", "") ?: "").lines().filter { it.isNotBlank() }.take(30).mapNotNull {
                    val parts = it.split(','); if (parts.size != 3) null else mapOf("time" to parts[0].toLongOrNull(), "count" to parts[1].toIntOrNull(), "bytes" to parts[2].toLongOrNull())
                })
                "forgetAccess" -> {
                    contentResolver.persistedUriPermissions.forEach {
                        val flags = (if (it.isReadPermission) Intent.FLAG_GRANT_READ_URI_PERMISSION else 0) or
                            (if (it.isWritePermission) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
                        contentResolver.releasePersistableUriPermission(it.uri, flags)
                    }
                    prefs.edit().remove("uris").apply(); latest = emptyMap(); result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 102) { pending?.success(broadAccess()); pending = null; return }
        if (requestCode != 100 && requestCode != 101) return
        val result = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) { result.success(false); return }
        val uris = mutableListOf<Uri>()
        data.data?.let { uris.add(it) }
        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        val saved = (prefs.getString("uris", "") ?: "").lines().filter { it.isNotBlank() }.toMutableSet()
        for (uri in uris.distinct()) {
            try {
                val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(uri, flags)
                saved.add(uri.toString())
            } catch (_: Exception) { /* A transient grant can still be used this session. */ saved.add(uri.toString()) }
        }
        prefs.edit().putString("uris", saved.joinToString("\n")).apply()
        result.success(uris.isNotEmpty())
    }

    private fun scan(): Map<String, Any> {
        val warnings = mutableListOf<String>()
        val entries = linkedMapOf<String, Entry>()
        if (broadAccess()) {
            val root = Environment.getExternalStorageDirectory()
            walkFiles(root, root, entries, warnings, 0)
        }
        val roots = if (broadAccess()) emptyList() else (prefs.getString("uris", "") ?: "").lines().filter { it.isNotBlank() }
        for (root in roots) {
            try {
                val uri = Uri.parse(root)
                if (DocumentsContract.isTreeUri(uri)) {
                    val treeId = DocumentsContract.getTreeDocumentId(uri)
                    walk(DocumentsContract.buildDocumentUriUsingTree(uri, treeId), treeId.substringAfter(':').substringAfterLast('/'), entries, warnings, 0)
                } else addFile(uri, "Selected files", entries, warnings)
            } catch (e: Exception) { warnings.add("A selected location is unavailable: ${e.message}") }
        }
        val sizeBuckets = entries.values.groupBy { it.size }.filterKeys { it > 0 }.filterValues { it.size > 1 }
        val digests = mutableMapOf<String, String?>()
        for (sameSize in sizeBuckets.values) {
            val quickGroups = mutableMapOf<String, MutableList<Entry>>()
            for (item in sameSize) {
                try { quickGroups.getOrPut(quickHash(item)) { mutableListOf() }.add(item) }
                catch (e: Exception) { warnings.add("Could not read ${item.name}") }
            }
            for (candidates in quickGroups.values.filter { it.size > 1 }) for (item in candidates) {
                try { digests[item.uri.toString()] = hash(item) }
                catch (e: Exception) { warnings.add("Could not read ${item.name}") }
            }
        }
        latest = entries.mapValues { (_, e) -> e.copy(digest = digests[e.uri.toString()]) }
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return mapOf("total" to stat.totalBytes, "available" to stat.availableBytes,
            "warnings" to warnings.take(25), "access" to broadAccess(), "files" to latest.values.map {
                mapOf("uri" to it.uri.toString(), "name" to it.name, "path" to it.path,
                    "bytes" to it.size, "mime" to it.mime, "digest" to it.digest, "deletable" to true)
            })
    }

    private fun walkFiles(root: File, dir: File, out: MutableMap<String, Entry>, warnings: MutableList<String>, depth: Int) {
        if (depth > 32 || out.size >= 50000) { warnings.add("Scan limit reached; some files are not shown."); return }
        val children = dir.listFiles() ?: run { warnings.add("Could not read ${dir.name}"); return }
        for (child in children) {
            if (child.isDirectory) {
                if (dir.name.equals("Android", true) &&
                    (child.name.equals("data", true) || child.name.equals("obb", true))) continue
                walkFiles(root, child, out, warnings, depth + 1)
            } else if (child.isFile && child.canRead()) {
                val uri = Uri.fromFile(child)
                val extension = child.extension.lowercase()
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
                out[uri.toString()] = Entry(uri, child.name, child.parentFile?.relativeTo(root)?.path ?: "",
                    child.length(), mime, null, child, child.lastModified())
            }
            if (out.size >= 50000) { warnings.add("Scan limit reached; some files are not shown."); return }
        }
    }

    private fun walk(dir: Uri, path: String, out: MutableMap<String, Entry>, warnings: MutableList<String>, depth: Int) {
        if (depth > 32 || out.size > 20000) { warnings.add("Scan limit reached; select a smaller folder."); return }
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(dir, DocumentsContract.getDocumentId(dir))
        contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                val child = DocumentsContract.buildDocumentUriUsingTree(dir, cursor.getString(idCol))
                val name = cursor.getString(nameCol) ?: "Untitled"
                if (cursor.getString(mimeCol) == DocumentsContract.Document.MIME_TYPE_DIR) walk(child, "$path/$name", out, warnings, depth + 1)
                else addFile(child, path, out, warnings)
            }
        } ?: warnings.add("Could not open $path")
    }

    private fun addFile(uri: Uri, path: String, out: MutableMap<String, Entry>, warnings: MutableList<String>) {
        try {
            contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val name = c.getString(0) ?: "Untitled"
                    val bytes = if (c.isNull(1)) 0L else c.getLong(1)
                    out[uri.toString()] = Entry(uri, name, path, bytes, c.getString(2) ?: "application/octet-stream", null)
                }
            }
        } catch (e: Exception) { warnings.add("Could not inspect a file in $path") }
    }

    private fun hash(entry: Entry): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val stream: InputStream = entry.file?.inputStream() ?: contentResolver.openInputStream(entry.uri)!!
        stream.use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun quickHash(entry: Entry): String {
        val file = entry.file ?: return hash(entry)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val start = ByteArray(64 * 1024)
            val read = input.read(start)
            if (read > 0) digest.update(start, 0, read)
        }
        if (entry.size > 64 * 1024) file.inputStream().use { input ->
            input.skip(entry.size - 64 * 1024)
            val end = ByteArray(64 * 1024)
            val read = input.read(end)
            if (read > 0) digest.update(end, 0, read)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
