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

class CloneTransferProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = APK_MIME_TYPE

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
        for (column in columns) {
            when (column) {
                OpenableColumns.DISPLAY_NAME -> row.add(file.name)
                OpenableColumns.SIZE -> row.add(file.length())
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Clone transfer is read-only")
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
        val name = uri.pathSegments.singleOrNull()
            ?: throw FileNotFoundException("Invalid clone transfer URI")
        val root = File(context.cacheDir, TRANSFER_DIR).canonicalFile
        val file = File(root, name).canonicalFile
        if (file.parentFile != root || !file.isFile) {
            throw FileNotFoundException("Clone transfer file not found")
        }
        return file
    }

    companion object {
        const val TRANSFER_DIR = "clone-transfer"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"

        fun uriFor(context: android.content.Context, file: File): Uri =
            Uri.Builder()
                .scheme("content")
                .authority("${context.packageName}.clone_transfer")
                .appendPath(file.name)
                .build()
    }
}
