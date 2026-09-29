package io.hiroshimeow.private_vault_mobile

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream

internal const val MAX_APP_ICON_BYTES = 64 * 1024
internal const val APP_ICON_EDGE_PX = 96

internal fun boundedAppIconPng(
    packageManager: PackageManager,
    app: ApplicationInfo,
): ByteArray? = runCatching {
    val drawable = app.loadIcon(packageManager)
    val bitmap = Bitmap.createBitmap(
        APP_ICON_EDGE_PX,
        APP_ICON_EDGE_PX,
        Bitmap.Config.ARGB_8888,
    )
    try {
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, APP_ICON_EDGE_PX, APP_ICON_EDGE_PX)
        drawable.draw(canvas)
        ByteArrayOutputStream().use { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                return@runCatching null
            }
            output.toByteArray().takeIf { it.size <= MAX_APP_ICON_BYTES }
        }
    } finally {
        bitmap.recycle()
    }
}.getOrNull()
