package io.hiroshimeow.private_vault_mobile

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.FileNotFoundException

class StandaloneCloneArtifactProvider : ContentProvider() {
    override fun onCreate(): Boolean = context != null

    override fun getType(uri: Uri): String = APK_MIME

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = resolveOwnedArtifact(uri)
            ?: throw FileNotFoundException("Unknown clone artifact")
        val requested = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val columns = requested.filter { it == OpenableColumns.DISPLAY_NAME || it == OpenableColumns.SIZE }
        return MatrixCursor(columns.toTypedArray(), 1).apply {
            addRow(
                columns.map<String, Any?> { column ->
                    when (column) {
                        OpenableColumns.DISPLAY_NAME -> file.name
                        OpenableColumns.SIZE -> file.length()
                        else -> null
                    }
                }.toTypedArray(),
            )
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Clone artifacts are read-only")
        val file = resolveOwnedArtifact(uri)
            ?: throw FileNotFoundException("Unknown clone artifact")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("Clone artifacts are read-only")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException("Clone artifacts are read-only")

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException("Clone artifacts are read-only")

    private fun resolveOwnedArtifact(uri: Uri): java.io.File? {
        val localContext = context ?: return null
        if (uri.authority != "${localContext.packageName}.clone_artifacts") return null
        val segments = uri.pathSegments
        if (segments.size != 2) return null
        val cloneId = segments[0]
        val fileName = segments[1]
        if (!cloneId.matches(Regex("[0-9a-f]{24}"))) return null
        return StandaloneCloneStore(localContext).artifactFromProviderPath(cloneId, fileName)
    }

    companion object {
        const val APK_MIME = "application/vnd.android.package-archive"
    }
}
