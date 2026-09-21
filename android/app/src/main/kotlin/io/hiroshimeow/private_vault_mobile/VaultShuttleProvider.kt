package io.hiroshimeow.private_vault_mobile

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

class VaultShuttleProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String =
        uri.getQueryParameter(QUERY_MIME_TYPE)?.takeIf { it.isNotBlank() }
            ?: DEFAULT_MIME_TYPE

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = resolveFile(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns, 1)
        val row = cursor.newRow()
        val displayName =
            uri.getQueryParameter(QUERY_DISPLAY_NAME)
                ?.takeIf { it.isNotBlank() }
                ?.take(MAX_DISPLAY_NAME_LENGTH)
                ?: "vault-item"
        for (column in columns) {
            when (column) {
                OpenableColumns.DISPLAY_NAME -> row.add(displayName)
                OpenableColumns.SIZE -> row.add(file.length())
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Vault shuttle is read-only")
        return ParcelFileDescriptor.open(resolveFile(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private fun resolveFile(uri: Uri): File {
        val context = context ?: throw FileNotFoundException("Provider unavailable")
        val name =
            uri.pathSegments.singleOrNull()
                ?: throw FileNotFoundException("Invalid vault shuttle URI")
        val root = File(context.cacheDir, TRANSFER_DIR).canonicalFile
        val file = File(root, name).canonicalFile
        if (file.parentFile != root || !file.isFile) {
            throw FileNotFoundException("Vault shuttle file not found")
        }
        return file
    }

    companion object {
        const val TRANSFER_DIR = "vault-shuttle"
        private const val DEFAULT_MIME_TYPE = "application/octet-stream"
        private const val QUERY_MIME_TYPE = "mime"
        private const val QUERY_DISPLAY_NAME = "name"
        private const val MAX_DISPLAY_NAME_LENGTH = 96

        fun uriFor(
            context: android.content.Context,
            file: File,
            mimeType: String,
            displayName: String,
        ): Uri =
            Uri.Builder()
                .scheme("content")
                .authority("${context.packageName}.vault_shuttle")
                .appendPath(file.name)
                .appendQueryParameter(QUERY_MIME_TYPE, mimeType)
                .appendQueryParameter(QUERY_DISPLAY_NAME, displayName)
                .build()
    }
}
