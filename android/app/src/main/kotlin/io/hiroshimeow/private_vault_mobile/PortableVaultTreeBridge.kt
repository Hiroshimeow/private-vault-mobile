package io.hiroshimeow.private_vault_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PortableVaultTreeBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var pendingPickResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickRoot" -> pickRoot(result)
                "hasRoot" -> respond(result) { hasRootAccess() }
                "list" -> respond(result) { list(call.argument<String>("path") ?: "") }
                "read" -> respond(result) { read(call.argument<String>("path") ?: "") }
                "write" -> {
                    val path = call.argument<String>("path") ?: ""
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("invalid_bytes", "Missing bytes", null)
                    } else {
                        respond(result) { write(path, bytes) }
                    }
                }
                "delete" -> respond(result) { delete(call.argument<String>("path") ?: "") }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_ROOT) return false
        val pending = pendingPickResult ?: return true
        pendingPickResult = null
        if (resultCode != Activity.RESULT_OK) {
            pending.success(false)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            pending.success(false)
            return true
        }
        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            activity.contentResolver.takePersistableUriPermission(uri, flags)
            activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
                .edit()
                .putString(KEY_ROOT_URI, uri.toString())
                .apply()
            pending.success(true)
        } catch (error: SecurityException) {
            pending.error("persist_failed", error.message, null)
        }
        return true
    }

    private fun pickRoot(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("pick_in_progress", "A root picker is already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_PICK_ROOT)
    }

    private fun loadRootUri(): Uri? = activity
        .getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
        .getString(KEY_ROOT_URI, null)
        ?.let(Uri::parse)

    private fun root(): DocumentFile? = loadRootUri()?.let { uri ->
        DocumentFile.fromTreeUri(activity, uri)
    }

    private fun hasRootAccess(): Boolean {
        val root = root() ?: return false
        return root.exists() && root.isDirectory && root.canRead() && root.canWrite()
    }

    private fun pathSegments(path: String): List<String> {
        val segments = path.split('/').filter { it.isNotBlank() }
        require(segments.none { it == "." || it == ".." || it.contains('\\') }) {
            "Invalid portable vault path"
        }
        return segments
    }

    private fun resolve(path: String): DocumentFile? {
        var current = root() ?: return null
        for (segment in pathSegments(path)) {
            current = current.findFile(segment) ?: return null
        }
        return current
    }

    private fun parentAndName(path: String): Pair<DocumentFile, String>? {
        val segments = pathSegments(path)
        if (segments.isEmpty()) return null
        var current = root() ?: return null
        for (segment in segments.dropLast(1)) {
            current = current.findFile(segment)
                ?: current.createDirectory(segment)
                ?: return null
            if (!current.isDirectory) return null
        }
        return current to segments.last()
    }

    private fun list(path: String): List<String> {
        val dir = if (path.isBlank()) root() else resolve(path)
            ?: throw IllegalStateException("Portable Vault root unavailable")
        if (!dir.isDirectory) throw IllegalStateException("Portable Vault path is not a directory")
        return dir.listFiles().mapNotNull { it.name }
    }

    private fun read(path: String): ByteArray? {
        val file = resolve(path) ?: return null
        if (!file.isFile) return null
        return activity.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Portable Vault object could not be opened")
    }

    private fun write(path: String, bytes: ByteArray): Boolean {
        val (parent, name) = parentAndName(path)
            ?: throw IllegalStateException("Portable Vault root unavailable")
        val existing = parent.findFile(name)
        if (existing != null && !existing.isFile) {
            throw IllegalStateException("Portable Vault object path is not a file")
        }
        val file = existing
            ?: parent.createFile("application/octet-stream", name)
            ?: throw IllegalStateException("Portable Vault object could not be created")
        activity.contentResolver.openOutputStream(file.uri, "wt")?.use { stream ->
            stream.write(bytes)
            stream.flush()
        } ?: throw IllegalStateException("Portable Vault object could not be opened for write")
        return true
    }

    private fun delete(path: String): Boolean {
        val file = resolve(path) ?: return true
        return file.delete()
    }

    private fun <T> respond(result: MethodChannel.Result, block: () -> T) {
        try {
            result.success(block())
        } catch (error: SecurityException) {
            result.error("permission_denied", error.message, null)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_path", error.message, null)
        } catch (error: Exception) {
            result.error("storage_error", error.message, null)
        }
    }

    companion object {
        const val CHANNEL_NAME = "private_vault/portable_tree"
        private const val REQUEST_PICK_ROOT = 0x5056
        private const val PREFS = "portable_vault_tree"
        private const val KEY_ROOT_URI = "root_uri"
    }
}
