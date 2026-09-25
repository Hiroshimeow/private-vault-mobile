package io.hiroshimeow.private_vault_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

class PortableVaultTreeBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var pendingPickResult: MethodChannel.Result? = null
    @Volatile private var disposed = false
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val nextWriteHandle = AtomicLong(1)
    private val pendingWrites = mutableMapOf<Long, PendingWrite>()

    private data class PendingWrite(
        val temporaryUri: Uri,
        val targetName: String,
        val stream: FileOutputStream,
    )

    private data class DocumentEntry(
        val uri: Uri,
        val name: String,
        val mimeType: String,
    )

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickRoot" -> pickRoot(result)
                "hasRoot" -> respond(result) { hasRootAccess() }
                "list" -> respond(result) { list(call.argument<String>("path") ?: "") }
                "listMetadata" -> respond(result) { listMetadata(call.argument<String>("path") ?: "") }
                "metadata" -> respond(result) { metadata(call.argument<String>("path") ?: "") }
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
                "beginWrite" -> {
                    val path = call.argument<String>("path") ?: ""
                    respond(result) { beginWrite(path) }
                }
                "appendWrite" -> {
                    val handle = call.argument<Number>("handle")?.toLong()
                    val bytes = call.argument<ByteArray>("bytes")
                    if (handle == null || bytes == null) {
                        result.error("invalid_write", "Missing write handle or bytes", null)
                    } else {
                        respond(result) { appendWrite(handle, bytes) }
                    }
                }
                "patchWrite" -> {
                    val handle = call.argument<Number>("handle")?.toLong()
                    val offset = call.argument<Number>("offset")?.toLong()
                    val bytes = call.argument<ByteArray>("bytes")
                    if (handle == null || offset == null || bytes == null) {
                        result.error("invalid_write", "Missing patch arguments", null)
                    } else {
                        respond(result) { patchWrite(handle, offset, bytes) }
                    }
                }
                "commitWrite" -> {
                    val handle = call.argument<Number>("handle")?.toLong()
                    if (handle == null) {
                        result.error("invalid_write", "Missing write handle", null)
                    } else {
                        respond(result) { commitWrite(handle) }
                    }
                }
                "abortWrite" -> {
                    val handle = call.argument<Number>("handle")?.toLong()
                    if (handle == null) {
                        result.error("invalid_write", "Missing write handle", null)
                    } else {
                        respond(result) { abortWrite(handle) }
                    }
                }
                "delete" -> respond(result) { delete(call.argument<String>("path") ?: "") }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_ROOT) return false
        val pending = pendingPickResult
        pendingPickResult = null
        if (resultCode != Activity.RESULT_OK) {
            pending?.success(false)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            pending?.success(false)
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
            pending?.success(true)
        } catch (error: SecurityException) {
            pending?.error("persist_failed", error.message, null)
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
        try {
            activity.startActivityForResult(intent, REQUEST_PICK_ROOT)
        } catch (error: Exception) {
            pendingPickResult = null
            result.error("pick_failed", error.message, null)
        }
    }

    private fun loadRootUri(): Uri? = activity
        .getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
        .getString(KEY_ROOT_URI, null)
        ?.let(Uri::parse)

    private fun rootUri(): Uri? {
        val treeUri = loadRootUri() ?: return null
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
    }

    private fun hasRootAccess(): Boolean {
        val root = rootUri() ?: return false
        val entry = queryDocument(root) ?: return false
        if (entry.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) return false
        val permission = activity.contentResolver.persistedUriPermissions
            .firstOrNull { it.uri == loadRootUri() }
            ?: return false
        return permission.isReadPermission && permission.isWritePermission
    }

    private fun pathSegments(path: String): List<String> {
        val segments = path.split('/').filter { it.isNotBlank() }
        require(segments.none { it == "." || it == ".." || it.contains('\\') }) {
            "Invalid portable vault path"
        }
        return segments
    }

    private fun queryDocument(uri: Uri): DocumentEntry? {
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        activity.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val nameIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val name = cursor.getString(nameIndex) ?: return null
            val mimeType = cursor.getString(mimeIndex) ?: return null
            return DocumentEntry(uri = uri, name = name, mimeType = mimeType)
        }
        return null
    }

    private fun findChild(parentUri: Uri, displayName: String): DocumentEntry? {
        val parentId = DocumentsContract.getDocumentId(parentUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            parentUri,
            parentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameIndex) ?: continue
                if (name != displayName) continue
                val documentId = cursor.getString(idIndex) ?: continue
                val mimeType = cursor.getString(mimeIndex) ?: continue
                return DocumentEntry(
                    uri = DocumentsContract.buildDocumentUriUsingTree(
                        parentUri,
                        documentId,
                    ),
                    name = name,
                    mimeType = mimeType,
                )
            }
        } ?: throw IllegalStateException("Portable Vault directory could not be queried")
        return null
    }

    private fun resolve(path: String): DocumentEntry? {
        val root = rootUri() ?: return null
        var current = DocumentEntry(
            uri = root,
            name = "",
            mimeType = DocumentsContract.Document.MIME_TYPE_DIR,
        )
        for (segment in pathSegments(path)) {
            if (current.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) return null
            current = findChild(current.uri, segment) ?: return null
        }
        return current
    }

    private fun createDirectory(parentUri: Uri, name: String): DocumentEntry? {
        val created = DocumentsContract.createDocument(
            activity.contentResolver,
            parentUri,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        ) ?: return null
        val exact = ensureExactDisplayName(created, name)
        return DocumentEntry(
            uri = exact,
            name = name,
            mimeType = DocumentsContract.Document.MIME_TYPE_DIR,
        )
    }

    private fun parentAndName(path: String): Pair<Uri, String>? {
        val segments = pathSegments(path)
        if (segments.isEmpty()) return null
        var current = rootUri() ?: return null
        for (segment in segments.dropLast(1)) {
            val existing = findChild(current, segment)
            val next = existing ?: createDirectory(current, segment) ?: return null
            if (next.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) return null
            current = next.uri
        }
        return current to segments.last()
    }

    private fun list(path: String): List<String> =
        queryChildren(path, includeMetadata = false)
            .map { it["name"] as String }

    private fun listMetadata(path: String): List<Map<String, Any>> =
        queryChildren(path, includeMetadata = true)

    private fun queryChildren(
        path: String,
        includeMetadata: Boolean,
    ): List<Map<String, Any>> {
        val dir = if (path.isBlank()) {
            val root = rootUri()
                ?: throw IllegalStateException("Portable Vault root unavailable")
            DocumentEntry(
                uri = root,
                name = "",
                mimeType = DocumentsContract.Document.MIME_TYPE_DIR,
            )
        } else {
            resolve(path)
                ?: throw IllegalStateException("Portable Vault root unavailable")
        }
        if (dir.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) {
            throw IllegalStateException("Portable Vault path is not a directory")
        }
        val documentId = DocumentsContract.getDocumentId(dir.uri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            dir.uri,
            documentId,
        )
        val projection = if (includeMetadata) {
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
        } else {
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
        }
        val entries = mutableListOf<Map<String, Any>>()
        activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val sizeIndex = if (includeMetadata) {
                cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            } else {
                -1
            }
            val modifiedIndex = if (includeMetadata) {
                cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            } else {
                -1
            }
            while (cursor.moveToNext()) {
                if (cursor.getString(mimeIndex) == DocumentsContract.Document.MIME_TYPE_DIR) {
                    continue
                }
                val name = cursor.getString(nameIndex) ?: continue
                if (includeMetadata) {
                    entries += mapOf(
                        "name" to name,
                        "sizeBytes" to if (sizeIndex < 0 || cursor.isNull(sizeIndex)) {
                            -1L
                        } else {
                            cursor.getLong(sizeIndex)
                        },
                        "modifiedAtMillis" to if (
                            modifiedIndex < 0 || cursor.isNull(modifiedIndex)
                        ) {
                            0L
                        } else {
                            cursor.getLong(modifiedIndex)
                        },
                    )
                } else {
                    entries += mapOf("name" to name)
                }
            }
        } ?: throw IllegalStateException("Portable Vault directory could not be queried")
        return entries
    }

    private fun metadata(path: String): Map<String, Any>? {
        val file = resolve(path) ?: return null
        if (file.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) return null
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        activity.contentResolver.query(file.uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val mimeIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            if (cursor.getString(mimeIndex) == DocumentsContract.Document.MIME_TYPE_DIR) {
                return null
            }
            val nameIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val sizeIndex = cursor.getColumnIndex(
                DocumentsContract.Document.COLUMN_SIZE,
            )
            val modifiedIndex = cursor.getColumnIndex(
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            val name = cursor.getString(nameIndex) ?: return null
            return mapOf(
                "name" to name,
                "sizeBytes" to if (sizeIndex < 0 || cursor.isNull(sizeIndex)) {
                    -1L
                } else {
                    cursor.getLong(sizeIndex)
                },
                "modifiedAtMillis" to if (
                    modifiedIndex < 0 || cursor.isNull(modifiedIndex)
                ) {
                    0L
                } else {
                    cursor.getLong(modifiedIndex)
                },
            )
        }
        return null
    }

    private fun read(path: String): ByteArray? {
        val file = resolve(path) ?: return null
        if (file.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) return null
        return activity.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Portable Vault object could not be opened")
    }

    private fun write(path: String, bytes: ByteArray): Boolean {
        val (parent, name) = parentAndName(path)
            ?: throw IllegalStateException("Portable Vault root unavailable")
        val existing = findChild(parent, name)
        if (existing != null &&
            existing.mimeType == DocumentsContract.Document.MIME_TYPE_DIR
        ) {
            throw IllegalStateException("Portable Vault object path is not a file")
        }
        val fileUri = existing?.uri ?: ensureExactDisplayName(
            DocumentsContract.createDocument(
                activity.contentResolver,
                parent,
                "application/octet-stream",
                name,
            ) ?: throw IllegalStateException("Portable Vault object could not be created"),
            name,
        )
        activity.contentResolver.openOutputStream(fileUri, "wt")?.use { stream ->
            stream.write(bytes)
            stream.flush()
        } ?: throw IllegalStateException("Portable Vault object could not be opened for write")
        return true
    }

    private fun beginWrite(path: String): Long {
        val (parent, targetName) = parentAndName(path)
            ?: throw IllegalStateException("Portable Vault root unavailable")
        if (findChild(parent, targetName) != null) {
            throw IllegalStateException("Portable Vault object already exists")
        }

        val temporaryName =
            ".${targetName}.partial-${System.currentTimeMillis()}-${System.nanoTime()}"
        val temporaryUri = ensureExactDisplayName(
            DocumentsContract.createDocument(
                activity.contentResolver,
                parent,
                "application/octet-stream",
                temporaryName,
            ) ?: throw IllegalStateException("Portable Vault temporary object could not be created"),
            temporaryName,
        )
        val descriptor = activity.contentResolver.openFileDescriptor(temporaryUri, "rw")
        if (descriptor == null) {
            DocumentsContract.deleteDocument(activity.contentResolver, temporaryUri)
            throw IllegalStateException("Portable Vault temporary object could not be opened")
        }

        val stream = ParcelFileDescriptor.AutoCloseOutputStream(descriptor)
        val handle = nextWriteHandle.getAndIncrement()
        pendingWrites[handle] = PendingWrite(
            temporaryUri = temporaryUri,
            targetName = targetName,
            stream = stream,
        )
        return handle
    }

    private fun appendWrite(handle: Long, bytes: ByteArray): Boolean {
        val pending = pendingWrites[handle]
            ?: throw IllegalStateException("Portable Vault write session is not active")
        val channel = pending.stream.channel
        channel.position(channel.size())
        pending.stream.write(bytes)
        return true
    }

    private fun patchWrite(handle: Long, offset: Long, bytes: ByteArray): Boolean {
        require(offset >= 0) { "Patch offset must be non-negative" }
        val pending = pendingWrites[handle]
            ?: throw IllegalStateException("Portable Vault write session is not active")
        val channel = pending.stream.channel
        val end = channel.size()
        if (offset + bytes.size > end) {
            throw IllegalArgumentException("Patch exceeds written object length")
        }
        channel.position(offset)
        pending.stream.write(bytes)
        channel.position(end)
        return true
    }

    private fun commitWrite(handle: Long): Boolean {
        val pending = pendingWrites.remove(handle)
            ?: throw IllegalStateException("Portable Vault write session is not active")
        try {
            pending.stream.flush()
            pending.stream.fd.sync()
            pending.stream.close()
            val renamed = DocumentsContract.renameDocument(
                activity.contentResolver,
                pending.temporaryUri,
                pending.targetName,
            ) ?: throw IllegalStateException("Portable Vault object commit failed")
            ensureExactDisplayName(renamed, pending.targetName)
            return true
        } catch (error: Exception) {
            closeQuietly(pending.stream)
            try {
                DocumentsContract.deleteDocument(
                    activity.contentResolver,
                    pending.temporaryUri,
                )
            } catch (_: Exception) {
                // Preserve the original commit failure.
            }
            throw error
        }
    }

    private fun abortWrite(handle: Long): Boolean {
        val pending = pendingWrites.remove(handle) ?: return true
        closeQuietly(pending.stream)
        DocumentsContract.deleteDocument(activity.contentResolver, pending.temporaryUri)
        return true
    }

    private fun ensureExactDisplayName(
        uri: Uri,
        expectedName: String,
    ): Uri {
        val current = queryDocument(uri)
        if (current?.name == expectedName) return uri
        val renamed = DocumentsContract.renameDocument(
            activity.contentResolver,
            uri,
            expectedName,
        )
        if (renamed != null && queryDocument(renamed)?.name == expectedName) {
            return renamed
        }
        val unsafe = renamed ?: uri
        try {
            DocumentsContract.deleteDocument(activity.contentResolver, unsafe)
        } catch (_: Exception) {
            // Preserve the original unsafe-name failure.
        }
        throw IllegalStateException(
            "Portable Vault provider changed object name; refusing unsafe commit",
        )
    }

    private fun closeQuietly(stream: FileOutputStream) {
        try {
            stream.close()
        } catch (_: Exception) {
            // Best effort cleanup.
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)

        ioExecutor.execute {
            val writes = pendingWrites.values.toList()
            pendingWrites.clear()
            for (pending in writes) {
                closeQuietly(pending.stream)
                try {
                    DocumentsContract.deleteDocument(
                        activity.contentResolver,
                        pending.temporaryUri,
                    )
                } catch (_: Exception) {
                    // Best effort teardown cleanup.
                }
            }
            ioExecutor.shutdown()
        }

        val pickResult = pendingPickResult
        pendingPickResult = null
        if (pickResult != null) {
            try {
                pickResult.error(
                    "bridge_disposed",
                    "Portable Vault picker was interrupted by activity teardown",
                    null,
                )
            } catch (_: Exception) {
                // Flutter engine may already be detached.
            }
        }
    }

    private fun delete(path: String): Boolean {
        val file = resolve(path) ?: return true
        return DocumentsContract.deleteDocument(activity.contentResolver, file.uri)
    }

    private fun <T> respond(result: MethodChannel.Result, block: () -> T) {
        ioExecutor.execute {
            try {
                val value = block()
                activity.runOnUiThread { if (!disposed) result.success(value) }
            } catch (error: SecurityException) {
                activity.runOnUiThread { if (!disposed) result.error("permission_denied", error.message, null) }
            } catch (error: IllegalArgumentException) {
                activity.runOnUiThread { if (!disposed) result.error("invalid_path", error.message, null) }
            } catch (error: Exception) {
                activity.runOnUiThread { if (!disposed) result.error("storage_error", error.message, null) }
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "private_vault/portable_tree"
        private const val REQUEST_PICK_ROOT = 0x5056
        private const val PREFS = "portable_vault_tree"
        private const val KEY_ROOT_URI = "root_uri"
    }
}
