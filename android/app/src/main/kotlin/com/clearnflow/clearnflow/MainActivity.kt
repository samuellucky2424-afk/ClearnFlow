package com.clearnflow.clearnflow

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.provider.DocumentsContract
import android.database.Cursor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "clearnflow/storage"
    private val prefs by lazy { getSharedPreferences("clearnflow", MODE_PRIVATE) }
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var latest = emptyMap<String, Entry>()
    private data class Entry(val uri: Uri, val name: String, val path: String,
                             val size: Long, val mime: String, val digest: String?)

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "onboarded" -> result.success(prefs.getBoolean("onboarded", false))
                "finishOnboarding" -> { prefs.edit().putBoolean("onboarded", true).apply(); result.success(null) }
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
                                val currentSize = contentResolver.query(entry.uri, arrayOf(DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else -1L } ?: -1L
                                if (currentSize != entry.size || (entry.digest != null && hash(entry.uri) != entry.digest)) {
                                    failures.add("${entry.name}: changed since scan"); continue
                                }
                                if (DocumentsContract.deleteDocument(contentResolver, entry.uri)) {
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
                        val uri = Uri.parse(call.arguments as String)
                        startActivity(Intent(Intent.ACTION_VIEW).apply { setDataAndType(uri, contentResolver.getType(uri) ?: "*/*"); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) })
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
        val roots = (prefs.getString("uris", "") ?: "").lines().filter { it.isNotBlank() }
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
        for (group in sizeBuckets.values) for (item in group) {
            try { digests[item.uri.toString()] = hash(item.uri) }
            catch (e: Exception) { warnings.add("Could not read ${item.name}") }
        }
        latest = entries.mapValues { (_, e) -> e.copy(digest = digests[e.uri.toString()]) }
        val stat = StatFs(Environment.getDataDirectory().path)
        return mapOf("total" to stat.totalBytes, "available" to stat.availableBytes,
            "warnings" to warnings.take(25), "files" to latest.values.map {
                mapOf("uri" to it.uri.toString(), "name" to it.name, "path" to it.path,
                    "bytes" to it.size, "mime" to it.mime, "digest" to it.digest, "deletable" to true)
            })
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

    private fun hash(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        contentResolver.openInputStream(uri)!!.use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
