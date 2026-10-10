package io.hiroshimeow.private_vault_mobile

import java.security.MessageDigest

internal data class StandaloneCloneManifestFacts(
    val hasSplitMetadata: Boolean = false,
    val hasSharedUserId: Boolean = false,
    val hasUnsafeProviderAuthority: Boolean = false,
    val hasUnsafeAbsoluteProcess: Boolean = false,
    val hasUnsafeTaskAffinity: Boolean = false,
    val hasUnsafePermissionReference: Boolean = false,
    val hasUnsafeTargetPackage: Boolean = false,
    val hasVerifiedAppLink: Boolean = false,
    val hasCustomDeepLink: Boolean = false,
    val hasGoogleIdentityBinding: Boolean = false,
    val hasSignatureBoundPermission: Boolean = false,
    val hasHardcodedApplicationId: Boolean = false,
    val hasUnsafeArchiveEntry: Boolean = false,
)

internal data class StandaloneCloneCompatibility(
    val blockers: List<String>,
    val warnings: List<String> = emptyList(),
) {
    val supported: Boolean get() = blockers.isEmpty()
}

internal object StandaloneClonePolicy {
    private val packageSegment = Regex("[A-Za-z_][A-Za-z0-9_]*")

    fun deriveClonePackage(sourcePackage: String, sourceSignerSha256: String): String {
        val digest = identityDigest(sourcePackage, sourceSignerSha256)
        val candidate = "$sourcePackage.pvclone.c${digest.take(12)}"
        return if (candidate.length <= MAX_PACKAGE_LENGTH && isValidPackage(candidate)) {
            candidate
        } else {
            "io.hiroshimeow.pvclone.c${digest.take(24)}"
        }
    }

    fun deriveSigningAlias(sourcePackage: String, sourceSignerSha256: String): String =
        "private_vault_clone_lab_${identityDigest(sourcePackage, sourceSignerSha256).take(24)}"

    fun deriveCloneId(sourcePackage: String, sourceSignerSha256: String): String =
        identityDigest(sourcePackage, sourceSignerSha256).take(24)

    fun expandComponentName(sourcePackage: String, declaredName: String): String = when {
        declaredName.startsWith(".") -> sourcePackage + declaredName
        '.' !in declaredName -> "$sourcePackage.$declaredName"
        else -> declaredName
    }

    fun rewritePackageDerivedName(
        sourcePackage: String,
        clonePackage: String,
        value: String,
    ): String? = when {
        value == sourcePackage -> clonePackage
        value.startsWith("$sourcePackage.") -> clonePackage + value.removePrefix(sourcePackage)
        else -> null
    }

    fun matchesExpectedSingleSigner(
        expectedSha256: String,
        currentSignerSha256: Collection<String>,
    ): Boolean {
        if (currentSignerSha256.size != 1) return false
        val expected = normalizeSha256(expectedSha256) ?: return false
        val current = normalizeSha256(currentSignerSha256.single()) ?: return false
        return expected == current
    }

    fun rewriteAuthorities(
        sourcePackage: String,
        clonePackage: String,
        authorities: String,
    ): String? {
        val parts = authorities.split(';')
        if (parts.any { it.isBlank() }) return null
        val rewritten = parts.map { part ->
            rewritePackageDerivedName(sourcePackage, clonePackage, part.trim()) ?: return null
        }
        return rewritten.joinToString(";")
    }

    fun classifyArchive(
        entries: Collection<String>,
        manifestFacts: StandaloneCloneManifestFacts,
    ): StandaloneCloneCompatibility {
        val blockers = linkedSetOf<String>()
        if (entries.any(::isUnsafeArchivePath) || manifestFacts.hasUnsafeArchiveEntry) {
            blockers += "unsafe_archive_entry"
        }
        if (entries.any { entry ->
                val normalized = entry.replace('\\', '/').lowercase()
                normalized.startsWith("lib/") && normalized.endsWith(".so")
            }
        ) {
            blockers += "native_libs_unsupported"
        }
        if (manifestFacts.hasSplitMetadata) blockers += "split_apk_unsupported"
        if (manifestFacts.hasSharedUserId) blockers += "shared_uid_unsupported"
        if (manifestFacts.hasUnsafeProviderAuthority) blockers += "provider_authority_unsupported"
        if (manifestFacts.hasUnsafeAbsoluteProcess) blockers += "absolute_process_unsupported"
        if (manifestFacts.hasUnsafeTaskAffinity) blockers += "task_affinity_unsupported"
        if (manifestFacts.hasUnsafePermissionReference) blockers += "permission_reference_unsupported"
        if (manifestFacts.hasUnsafeTargetPackage) blockers += "target_package_unsupported"
        if (manifestFacts.hasVerifiedAppLink) blockers += "verified_app_link_unsupported"
        if (manifestFacts.hasGoogleIdentityBinding) blockers += "google_identity_bound_unsupported"
        if (manifestFacts.hasSignatureBoundPermission) blockers += "signature_permission_unsupported"
        if (manifestFacts.hasHardcodedApplicationId) blockers += "hardcoded_application_id_unsupported"
        val warnings = linkedSetOf<String>()
        if (manifestFacts.hasCustomDeepLink && !manifestFacts.hasVerifiedAppLink) {
            warnings += "deep_link_degraded"
        }
        return StandaloneCloneCompatibility(
            blockers = blockers.toList(),
            warnings = warnings.toList(),
        )
    }

    fun isUnsafeArchivePath(entryName: String): Boolean {
        val normalized = entryName.replace('\\', '/')
        if (normalized.startsWith('/') || Regex("^[A-Za-z]:/").containsMatchIn(normalized)) {
            return true
        }
        var depth = 0
        for (segment in normalized.split('/')) {
            when (segment) {
                "", "." -> Unit
                ".." -> {
                    depth--
                    if (depth < 0) return true
                }
                else -> depth++
            }
        }
        return false
    }

    private fun identityDigest(sourcePackage: String, sourceSignerSha256: String): String {
        val canonicalSigner = sourceSignerSha256
            .lowercase()
            .replace(Regex("[^0-9a-f]"), "")
        val bytes = "$sourcePackage\n$canonicalSigner".toByteArray(Charsets.UTF_8)
        return MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
    }

    private fun normalizeSha256(value: String): String? {
        val normalized = value.lowercase().replace(Regex("[^0-9a-f]"), "")
        return normalized.takeIf { it.length == 64 }
    }

    private fun isValidPackage(value: String): Boolean {
        val parts = value.split('.')
        return parts.size >= 2 && parts.all(packageSegment::matches)
    }

    private const val MAX_PACKAGE_LENGTH = 255
}
