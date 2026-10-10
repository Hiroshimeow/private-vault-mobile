package io.hiroshimeow.private_vault_pluginhost

import org.jf.dexlib2.DexFileFactory
import org.jf.dexlib2.Opcodes
import org.jf.dexlib2.iface.DexFile
import org.jf.dexlib2.iface.instruction.ReferenceInstruction
import org.jf.dexlib2.iface.reference.FieldReference
import org.jf.dexlib2.iface.reference.MethodReference
import org.jf.dexlib2.iface.reference.TypeReference
import org.jf.dexlib2.rewriter.DexRewriter
import org.jf.dexlib2.rewriter.Rewriter
import org.jf.dexlib2.rewriter.RewriterModule
import org.jf.dexlib2.rewriter.Rewriters
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

internal object GuestCompatibilityValidator {
    private const val ACTIVITY = "Landroid/app/Activity;"
    private const val APPLICATION = "Landroid/app/Application;"

    private val allowedActivityMethods = setOf(
        "<init>()V",
        "onCreate(Landroid/os/Bundle;)V",
        "setTitle(Ljava/lang/CharSequence;)V",
        "getApplication()Landroid/app/Application;",
        "getApplicationContext()Landroid/content/Context;",
        "getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;",
    )
    private val allowedApplicationMethods = setOf(
        "<init>()V",
        "onCreate()V",
        "getApplicationContext()Landroid/content/Context;",
        "getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;",
    )

    fun validate(dex: DexFile) {
        dex.classes.forEach { classDef ->
            classDef.methods.forEach { method ->
                method.implementation?.instructions?.forEach { instruction ->
                    val reference = (instruction as? ReferenceInstruction)?.reference ?: return@forEach
                    when (reference) {
                        is MethodReference -> validateMethod(reference)
                        is FieldReference -> validateField(reference)
                        is TypeReference -> validateResourceOwner(reference.type)
                    }
                }
            }
        }
    }

    internal fun validateMethod(reference: MethodReference) {
        validateResourceOwner(reference.definingClass)
        val signature = buildString {
            append(reference.name)
            append('(')
            reference.parameterTypes.forEach(::append)
            append(')')
            append(reference.returnType)
        }
        when (reference.definingClass) {
            ACTIVITY -> if (signature !in allowedActivityMethods) unsupported("Activity API $signature")
            APPLICATION -> if (signature !in allowedApplicationMethods) unsupported("Application API $signature")
        }
    }

    internal fun validateField(reference: FieldReference) {
        validateResourceOwner(reference.definingClass)
        when (reference.definingClass) {
            ACTIVITY -> unsupported("Activity field ${reference.name}:${reference.type}")
            APPLICATION -> unsupported("Application field ${reference.name}:${reference.type}")
        }
    }

    internal fun validateResourceOwner(type: String) {
        if (type.startsWith("Landroid/content/res/") ||
            type.matches(Regex("L[^;]+/R(?:\\$[^;]+)?;"))
        ) {
            unsupported("resource API/type $type")
        }
    }

    private fun unsupported(detail: String): Nothing =
        throw PluginTypedException(PluginResult.TRANSFORM_UNSUPPORTED, "unsupported guest shape: $detail")
}

class GuestTransformer {
    fun transform(sourceApks: List<File>, output: File) {
        val dexEntries = mutableListOf<Pair<File, String>>()
        sourceApks.forEach { apk ->
            ZipFile(apk).use { zip ->
                zip.entries().asSequence()
                    .filter { it.name.matches(Regex("classes(\\d*)\\.dex")) }
                    .forEach { dexEntries += apk to it.name }
            }
        }
        if (dexEntries.isEmpty()) throw PluginTypedException(PluginResult.TRANSFORM_UNSUPPORTED, "source has no dex")

        val tempDir = File(output.parentFile, "dex-work").apply { mkdirs() }
        try {
            ZipOutputStream(output.outputStream().buffered()).use { out ->
                dexEntries.forEachIndexed { index, (apk, entryName) ->
                    val raw = File(tempDir, "raw-$index.dex")
                    val rewritten = File(tempDir, "rewritten-$index.dex")
                    ZipFile(apk).use { zip ->
                        zip.getInputStream(zip.getEntry(entryName)).use { input -> raw.outputStream().use(input::copyTo) }
                    }
                    val dex = DexFileFactory.loadDexFile(raw, Opcodes.getDefault())
                    GuestCompatibilityValidator.validate(dex)
                    val module = object : RewriterModule() {
                        override fun getTypeRewriter(rewriters: Rewriters): Rewriter<String> = Rewriter { type ->
                            when (type) {
                                "Landroid/app/Activity;" -> "Lio/hiroshimeow/private_vault_pluginhost/PluginGuestActivity;"
                                "Landroid/app/Application;" -> "Lio/hiroshimeow/private_vault_pluginhost/PluginGuestApplication;"
                                else -> type
                            }
                        }
                    }
                    val result = DexRewriter(module).dexFileRewriter.rewrite(dex)
                    DexFileFactory.writeDexFile(rewritten.absolutePath, result)
                    out.putNextEntry(ZipEntry(if (index == 0) "classes.dex" else "classes${index + 1}.dex"))
                    rewritten.inputStream().use { it.copyTo(out) }
                    out.closeEntry()
                }
            }
        } finally {
            tempDir.deleteRecursively()
        }
    }
}
