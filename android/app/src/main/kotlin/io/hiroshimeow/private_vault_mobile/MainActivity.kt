package io.hiroshimeow.private_vault_mobile

import android.content.ComponentName
import android.content.ContentResolver
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "private_vault/platform"
    private var workProfileApiAdapter: WorkProfileHostApiAdapter? = null
    private var portableVaultTreeBridge: PortableVaultTreeBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val adapter = WorkProfileHostApiAdapter(this)
        workProfileApiAdapter = adapter
        WorkProfileHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            adapter,
        )
        portableVaultTreeBridge = PortableVaultTreeBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDisguiseCapabilities" -> result.success(
                        mapOf(
                            "androidLauncherAliases" to true,
                            "iosAlternateIcons" to false,
                        ),
                    )
                    "setDisguise" -> {
                        val choice = call.arguments as? String
                        if (choice == "calculator" || choice == "notes") {
                            setLauncherAlias(choice)
                            result.success(true)
                        } else {
                            result.error("invalid_choice", "Unknown disguise choice", null)
                        }
                    }
                    "deleteDocumentUri" -> {
                        val rawUri = call.argument<String>("uri")
                        if (rawUri == null) {
                            result.error("invalid_uri", "Missing source URI", null)
                        } else {
                            try {
                                result.success(deleteDocumentUri(rawUri))
                            } catch (error: SecurityException) {
                                result.error("permission_denied", error.message, null)
                            } catch (error: Exception) {
                                result.error("delete_failed", error.message, null)
                            }
                        }
                    }
                    "videoThumbnail" -> {
                        val rawUri = call.argument<String>("uri")
                        if (rawUri == null) {
                            result.error("invalid_uri", "Missing video URI", null)
                        } else {
                            try {
                                result.success(videoThumbnail(rawUri))
                            } catch (error: SecurityException) {
                                result.error("permission_denied", error.message, null)
                            } catch (error: Exception) {
                                result.error("thumbnail_failed", error.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (portableVaultTreeBridge?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        if (workProfileApiAdapter?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        portableVaultTreeBridge?.dispose()
        portableVaultTreeBridge = null
        WorkProfileHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        workProfileApiAdapter = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun deleteDocumentUri(rawUri: String): Boolean {
        val uri = Uri.parse(rawUri)
        require(uri.scheme == ContentResolver.SCHEME_CONTENT) {
            "Only content URIs can be deleted through Android SAF"
        }
        return DocumentsContract.deleteDocument(contentResolver, uri)
    }

    private fun videoThumbnail(rawUri: String): ByteArray? {
        val uri = Uri.parse(rawUri)
        val retriever = MediaMetadataRetriever()
        try {
            when (uri.scheme) {
                ContentResolver.SCHEME_CONTENT -> retriever.setDataSource(this, uri)
                ContentResolver.SCHEME_FILE -> {
                    val path = uri.path ?: return null
                    retriever.setDataSource(path)
                }
                else -> return null
            }
            val frame = retriever.getFrameAtTime(
                1_000_000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: retriever.getFrameAtTime(
                -1L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: return null
            val scaled = if (frame.width > 384) {
                val targetHeight = (frame.height * (384.0 / frame.width))
                    .toInt()
                    .coerceAtLeast(1)
                Bitmap.createScaledBitmap(frame, 384, targetHeight, true)
            } else {
                frame
            }
            return ByteArrayOutputStream().use { output ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 78, output)
                output.toByteArray()
            }.also {
                if (scaled !== frame) scaled.recycle()
                frame.recycle()
            }
        } finally {
            retriever.release()
        }
    }

    private fun setLauncherAlias(choice: String) {
        val calculator = ComponentName(packageName, "$packageName.CalculatorAlias")
        val notes = ComponentName(packageName, "$packageName.NotesAlias")
        val enabled = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val disabled = PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        val flags = PackageManager.DONT_KILL_APP

        packageManager.setComponentEnabledSetting(
            calculator,
            if (choice == "calculator") enabled else disabled,
            flags,
        )
        packageManager.setComponentEnabledSetting(
            notes,
            if (choice == "notes") enabled else disabled,
            flags,
        )
    }
}
