package io.hiroshimeow.private_vault_mobile

import android.content.Context
import android.system.ErrnoException
import android.system.Os
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

internal data class StandaloneCloneRecord(
    val cloneId: String,
    val sourcePackage: String,
    val sourceSignerSha256: String,
    val clonePackage: String,
    val signingAlias: String,
    val cloneSignerSha256: String,
    val artifactRelativePath: String,
    val versionCode: Int?,
    val versionName: String?,
    val compatibilityWarnings: List<String>,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val installStatus: String,
) {
    fun matchesOwnershipIdentity(other: StandaloneCloneRecord): Boolean =
        cloneId == other.cloneId &&
            sourcePackage == other.sourcePackage &&
            sourceSignerSha256.equals(other.sourceSignerSha256, ignoreCase = true) &&
            clonePackage == other.clonePackage &&
            signingAlias == other.signingAlias &&
            cloneSignerSha256.equals(other.cloneSignerSha256, ignoreCase = true) &&
            artifactRelativePath == other.artifactRelativePath

    fun toMap(): Map<String, Any?> = mapOf(
        "cloneId" to cloneId,
        "sourcePackage" to sourcePackage,
        "sourceSignerSha256" to sourceSignerSha256,
        "clonePackage" to clonePackage,
        "signingAlias" to signingAlias,
        "cloneSignerSha256" to cloneSignerSha256,
        "artifactRelativePath" to artifactRelativePath,
        "versionCode" to versionCode,
        "versionName" to versionName,
        "compatibilityWarnings" to compatibilityWarnings,
        "createdAtMs" to createdAtMs,
        "updatedAtMs" to updatedAtMs,
        "installStatus" to installStatus,
    )
}

internal fun commitConfirmedUninstallCleanup(
    persistRegistryRemoval: () -> Unit,
    deleteArtifact: () -> Boolean,
): Boolean {
    persistRegistryRemoval()
    return deleteArtifact()
}

internal fun finalizeCloneRegistryFile(
    temp: File,
    registryFile: File,
    rename: (File, File) -> Unit = { source, target ->
        try {
            Os.rename(source.absolutePath, target.absolutePath)
        } catch (error: ErrnoException) {
            throw IOException("Unable to finalize clone registry", error)
        }
    },
) {
    rename(temp, registryFile)
}

internal class StandaloneCloneStore(private val context: Context) {
    private val workRoot = File(context.cacheDir, "clone-lab/work")
    private val artifactRoot = File(context.filesDir, "clone-lab/artifacts")
    private val registryFile = File(context.filesDir, "clone-lab/registry.json")
    private val lock = Any()

    init {
        requireInside(context.cacheDir, workRoot)
        requireInside(context.filesDir, artifactRoot)
        requireInside(context.filesDir, registryFile)
        workRoot.mkdirs()
        artifactRoot.mkdirs()
        registryFile.parentFile?.mkdirs()
        workRoot.listFiles()?.forEach { stale ->
            runCatching {
                requireInside(workRoot, stale)
                stale.deleteRecursively()
            }
        }
    }

    fun newWorkDir(): File {
        val dir = File(workRoot, UUID.randomUUID().toString())
        requireInside(workRoot, dir)
        check(dir.mkdirs()) { "Unable to create clone-lab work directory" }
        return dir
    }

    fun cleanWorkDir(dir: File) {
        requireInside(workRoot, dir)
        if (dir.exists()) dir.deleteRecursively()
    }

    fun retainSignedArtifact(
        inspection: StandaloneCloneInspection,
        signing: StandaloneCloneSigningResult,
        signedApk: File,
    ): StandaloneCloneRecord = synchronized(lock) {
        check(inspection.supported) { "Unsupported clone cannot be retained" }
        require(signedApk.isFile) { "Signed clone APK is unavailable" }
        val cloneId = requireNotNull(inspection.cloneId)
        val sourcePackage = requireNotNull(inspection.sourcePackage)
        val sourceSigner = requireNotNull(inspection.sourceSignerSha256)
        val clonePackage = requireNotNull(inspection.clonePackage)
        val signingAlias = requireNotNull(inspection.signingAlias)
        check(
            clonePackage == StandaloneClonePolicy.deriveClonePackage(sourcePackage, sourceSigner),
        ) { "Clone package is not deterministic for source identity" }
        check(
            signingAlias == StandaloneClonePolicy.deriveSigningAlias(sourcePackage, sourceSigner),
        ) { "Signing alias is not deterministic for source identity" }
        check(cloneId == StandaloneClonePolicy.deriveCloneId(sourcePackage, sourceSigner)) {
            "Clone ID is not deterministic for source identity"
        }

        val destinationDir = File(artifactRoot, cloneId)
        val destination = File(destinationDir, ARTIFACT_FILE_NAME)
        requireInside(artifactRoot, destination)
        destinationDir.mkdirs()
        val temp = File(destinationDir, "$ARTIFACT_FILE_NAME.tmp")
        signedApk.copyTo(temp, overwrite = true)
        if (destination.exists() && !destination.delete()) {
            temp.delete()
            error("Unable to replace retained clone artifact")
        }
        check(temp.renameTo(destination)) { "Unable to finalize retained clone artifact" }

        val records = readRecordsLocked().associateBy { it.cloneId }.toMutableMap()
        val now = System.currentTimeMillis()
        val previous = records[cloneId]
        val record = StandaloneCloneRecord(
            cloneId = cloneId,
            sourcePackage = sourcePackage,
            sourceSignerSha256 = sourceSigner,
            clonePackage = clonePackage,
            signingAlias = signingAlias,
            cloneSignerSha256 = signing.signerSha256,
            artifactRelativePath = "$cloneId/$ARTIFACT_FILE_NAME",
            versionCode = inspection.versionCode,
            versionName = inspection.versionName,
            compatibilityWarnings = inspection.compatibility.warnings,
            createdAtMs = previous?.createdAtMs ?: now,
            updatedAtMs = now,
            installStatus = "artifact_ready",
        )
        records[cloneId] = record
        writeRecordsLocked(records.values.sortedBy { it.createdAtMs })
        record
    }

    fun listRecords(): List<StandaloneCloneRecord> = synchronized(lock) {
        readRecordsLocked()
    }

    fun getOwnedRecord(cloneId: String): StandaloneCloneRecord? = synchronized(lock) {
        val record = readRecordsLocked().firstOrNull { it.cloneId == cloneId } ?: return@synchronized null
        validateOwnedRecord(record)
        record
    }

    fun updateInstallStatus(cloneId: String, status: String): StandaloneCloneRecord? = synchronized(lock) {
        val records = readRecordsLocked().associateBy { it.cloneId }.toMutableMap()
        val current = records[cloneId] ?: return@synchronized null
        validateOwnedRecord(current)
        val updated = current.copy(
            installStatus = status,
            updatedAtMs = System.currentTimeMillis(),
        )
        records[cloneId] = updated
        writeRecordsLocked(records.values.sortedBy { it.createdAtMs })
        updated
    }

    fun removeRecordAndArtifact(cloneId: String): Boolean = synchronized(lock) {
        val records = readRecordsLocked().associateBy { it.cloneId }.toMutableMap()
        val record = records[cloneId] ?: return@synchronized false
        validateOwnedRecord(record)
        val artifactDir = File(artifactRoot, record.cloneId)
        requireInside(artifactRoot, artifactDir)
        records.remove(cloneId)

        commitConfirmedUninstallCleanup(
            persistRegistryRemoval = {
                writeRecordsLocked(records.values.sortedBy { it.createdAtMs })
            },
            deleteArtifact = {
                !artifactDir.exists() || artifactDir.deleteRecursively()
            },
        )
        true
    }

    fun artifactFor(record: StandaloneCloneRecord): File {
        validateOwnedRecord(record)
        val artifact = File(artifactRoot, record.artifactRelativePath)
        requireInside(artifactRoot, artifact)
        check(artifact.isFile) { "Retained clone artifact is missing" }
        return artifact
    }

    fun artifactFromProviderPath(cloneId: String, fileName: String): File? {
        if (fileName != ARTIFACT_FILE_NAME) return null
        val record = getOwnedRecord(cloneId) ?: return null
        val artifact = artifactFor(record)
        return artifact.takeIf { it.name == fileName }
    }

    private fun validateOwnedRecord(record: StandaloneCloneRecord) {
        check(
            record.clonePackage == StandaloneClonePolicy.deriveClonePackage(
                record.sourcePackage,
                record.sourceSignerSha256,
            ),
        ) { "Registry clone package failed ownership validation" }
        check(
            record.signingAlias == StandaloneClonePolicy.deriveSigningAlias(
                record.sourcePackage,
                record.sourceSignerSha256,
            ),
        ) { "Registry signing alias failed ownership validation" }
        check(
            record.cloneId == StandaloneClonePolicy.deriveCloneId(
                record.sourcePackage,
                record.sourceSignerSha256,
            ),
        ) { "Registry clone ID failed ownership validation" }
        val artifact = File(artifactRoot, record.artifactRelativePath)
        requireInside(artifactRoot, artifact)
    }

    private fun readRecordsLocked(): List<StandaloneCloneRecord> {
        if (!registryFile.isFile) return emptyList()
        val raw = registryFile.readText(Charsets.UTF_8)
        if (raw.isBlank()) return emptyList()
        val root = JSONObject(raw)
        check(root.optInt("schemaVersion", -1) == REGISTRY_SCHEMA) {
            "Unsupported clone registry schema"
        }
        val array = root.optJSONArray("clones") ?: JSONArray()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val record = StandaloneCloneRecord(
                    cloneId = item.getString("cloneId"),
                    sourcePackage = item.getString("sourcePackage"),
                    sourceSignerSha256 = item.getString("sourceSignerSha256"),
                    clonePackage = item.getString("clonePackage"),
                    signingAlias = item.getString("signingAlias"),
                    cloneSignerSha256 = item.getString("cloneSignerSha256"),
                    artifactRelativePath = item.getString("artifactRelativePath"),
                    versionCode = item.optInt("versionCode").takeIf { item.has("versionCode") && !item.isNull("versionCode") },
                    versionName = item.optString("versionName", null),
                    compatibilityWarnings = item.optJSONArray("compatibilityWarnings")?.let { warnings ->
                        buildList {
                            for (warningIndex in 0 until warnings.length()) {
                                add(warnings.getString(warningIndex))
                            }
                        }
                    } ?: emptyList(),
                    createdAtMs = item.getLong("createdAtMs"),
                    updatedAtMs = item.getLong("updatedAtMs"),
                    installStatus = item.getString("installStatus"),
                )
                validateOwnedRecord(record)
                add(record)
            }
        }
    }

    private fun writeRecordsLocked(records: Collection<StandaloneCloneRecord>) {
        val root = JSONObject().apply {
            put("schemaVersion", REGISTRY_SCHEMA)
            put(
                "clones",
                JSONArray().apply {
                    records.forEach { record ->
                        put(
                            JSONObject().apply {
                                record.toMap().forEach { (key, value) ->
                                    put(
                                        key,
                                        when (value) {
                                            null -> JSONObject.NULL
                                            is Collection<*> -> JSONArray(value)
                                            else -> value
                                        },
                                    )
                                }
                            },
                        )
                    }
                },
            )
        }
        val temp = File(registryFile.parentFile, "${registryFile.name}.tmp")
        try {
            FileOutputStream(temp, false).use { output ->
                output.write(root.toString().toByteArray(Charsets.UTF_8))
                output.fd.sync()
            }
            finalizeCloneRegistryFile(temp, registryFile)
        } finally {
            if (temp.exists()) temp.delete()
        }
    }

    private fun requireInside(root: File, child: File) {
        val rootPath = root.canonicalFile.toPath()
        val childPath = child.canonicalFile.toPath()
        require(childPath.startsWith(rootPath)) { "Clone-lab path escaped its private root" }
    }

    companion object {
        private const val REGISTRY_SCHEMA = 1
        private const val ARTIFACT_FILE_NAME = "base.apk"
    }
}
