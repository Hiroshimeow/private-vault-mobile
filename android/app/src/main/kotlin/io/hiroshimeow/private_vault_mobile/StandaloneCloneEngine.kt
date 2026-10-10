package io.hiroshimeow.private_vault_mobile

import com.android.apksig.ApkVerifier
import com.reandroid.apk.ApkModule
import com.reandroid.arsc.chunk.xml.AndroidManifestBlock
import com.reandroid.arsc.chunk.xml.ResXmlElement
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipFile

internal data class StandaloneCloneInspection(
    val compatibility: StandaloneCloneCompatibility,
    val sourcePackage: String? = null,
    val sourceSignerSha256: String? = null,
    val clonePackage: String? = null,
    val cloneId: String? = null,
    val signingAlias: String? = null,
    val versionCode: Int? = null,
    val versionName: String? = null,
    val sourceSignatureSchemes: List<String> = emptyList(),
) {
    val supported: Boolean get() = compatibility.supported
}

internal class StandaloneCloneEngine {
    fun inspect(sourceFile: File, originalDisplayName: String): StandaloneCloneInspection {
        val extensionBlocker = archiveExtensionBlocker(originalDisplayName)
        if (extensionBlocker != null) {
            return unsupported(extensionBlocker)
        }
        if (!sourceFile.isFile) return unsupported("source_apk_unavailable")

        val entries = try {
            ZipFile(sourceFile).use { zip -> zip.entries().asSequence().map { it.name }.toList() }
        } catch (_: Exception) {
            return unsupported("malformed_apk_unsupported")
        }
        if (entries.none { it == "AndroidManifest.xml" }) {
            val blocker = if (entries.any { it.endsWith(".apk", ignoreCase = true) } ||
                entries.any { it == "toc.pb" }
            ) {
                "split_container_unsupported"
            } else {
                "malformed_apk_unsupported"
            }
            return unsupported(blocker)
        }

        val verifierResult = try {
            ApkVerifier.Builder(sourceFile).build().verify()
        } catch (_: Exception) {
            return unsupported("source_signature_invalid")
        }
        if (!verifierResult.isVerified || verifierResult.signerCertificates.isEmpty()) {
            return unsupported("source_signature_invalid")
        }
        if (verifierResult.signerCertificates.size != 1) {
            return unsupported("source_multi_signer_unsupported")
        }
        val signerSha256 = sourceSignerSha256(
            verifierResult.signerCertificates.map { certificate -> certificate.encoded },
        ) ?: return unsupported("source_signature_invalid")
        val sourceSchemes = buildList {
            if (verifierResult.isVerifiedUsingV1Scheme) add("v1")
            if (verifierResult.isVerifiedUsingV2Scheme) add("v2")
            if (verifierResult.isVerifiedUsingV3Scheme) add("v3")
            if (verifierResult.isVerifiedUsingV31Scheme) add("v3.1")
            if (verifierResult.isVerifiedUsingV4Scheme) add("v4")
        }

        return try {
            ApkModule.loadApkFile(sourceFile).use { module ->
                val manifest = module.androidManifestBlock
                    ?: return unsupported("manifest_missing")
                val sourcePackage = manifest.packageName
                    ?.takeIf { it.isNotBlank() }
                    ?: return unsupported("manifest_package_missing")
                val needles = GOOGLE_IDENTITY_MARKERS + sourcePackage
                val dexHits = mutableSetOf<String>()
                for (dex in module.listDexFiles()) {
                    dex.openStream().use { input ->
                        dexHits += scanAsciiLiterals(input, needles)
                    }
                }
                val manifestGoogleIdentity = allElements(manifest).any { element ->
                    element.getAttributes().asSequence().any { attribute ->
                        val value = attribute.valueAsString.orEmpty().lowercase(Locale.ROOT)
                        GOOGLE_IDENTITY_MARKERS.any { marker -> value.contains(marker) }
                    }
                }
                val facts = inspectManifestFacts(
                    manifest = manifest,
                    sourcePackage = sourcePackage,
                    hasHardcodedApplicationId = sourcePackage in dexHits,
                    hasGoogleIdentityBinding = manifestGoogleIdentity ||
                        GOOGLE_IDENTITY_MARKERS.any(dexHits::contains),
                )
                val compatibility = StandaloneClonePolicy.classifyArchive(entries, facts)
                val clonePackage = StandaloneClonePolicy.deriveClonePackage(sourcePackage, signerSha256)
                StandaloneCloneInspection(
                    compatibility = compatibility,
                    sourcePackage = sourcePackage,
                    sourceSignerSha256 = signerSha256,
                    clonePackage = clonePackage,
                    cloneId = StandaloneClonePolicy.deriveCloneId(sourcePackage, signerSha256),
                    signingAlias = StandaloneClonePolicy.deriveSigningAlias(sourcePackage, signerSha256),
                    versionCode = manifest.versionCode,
                    versionName = manifest.versionName,
                    sourceSignatureSchemes = sourceSchemes,
                )
            }
        } catch (_: Exception) {
            unsupported("apk_parse_failed")
        }
    }

    fun transform(
        sourceFile: File,
        inspection: StandaloneCloneInspection,
        unsignedOutput: File,
    ) {
        require(inspection.supported) { "Unsupported APK cannot be transformed" }
        val sourcePackage = requireNotNull(inspection.sourcePackage)
        val clonePackage = requireNotNull(inspection.clonePackage)
        val dexBefore = zipEntryDigests(sourceFile) { name -> isDexEntry(name) }
        require(dexBefore.isNotEmpty()) { "APK contains no classes*.dex payload" }

        unsignedOutput.parentFile?.mkdirs()
        if (unsignedOutput.exists()) unsignedOutput.delete()
        ApkModule.loadApkFile(sourceFile).use { module ->
            check(module.packageName == sourcePackage) { "Source package changed during clone build" }
            rewriteModuleForClone(module, sourcePackage, clonePackage)
            module.apkSignatureBlock = null
            val signatureAliases = module.inputSources
                .map { it.alias }
                .filter(::isJarSignatureEntry)
            signatureAliases.forEach(module::removeInputSource)
            module.writeApk(unsignedOutput)
        }

        val dexAfter = zipEntryDigests(unsignedOutput) { name -> isDexEntry(name) }
        check(dexBefore == dexAfter) { "Clone transform changed DEX payloads" }
        validateTransformedApk(unsignedOutput, sourcePackage, clonePackage)
    }

    companion object {
        private val COMPONENT_TAGS = setOf(
            "application",
            "activity",
            "activity-alias",
            "service",
            "receiver",
            "provider",
            "instrumentation",
        )
        private val GOOGLE_IDENTITY_MARKERS = listOf(
            "com.google.firebase",
            "com.google.android.play.core.integrity",
            "com.google.android.gms.auth",
            "com.google.android.gms.common.api",
            "com.google.android.gms.safetynet",
        )

        internal fun inspectManifestFacts(
            manifest: AndroidManifestBlock,
            sourcePackage: String,
            hasHardcodedApplicationId: Boolean,
            hasGoogleIdentityBinding: Boolean,
        ): StandaloneCloneManifestFacts {
            var unsafeAuthority = false
            var unsafeProcess = false
            var unsafeTaskAffinity = false
            var unsafePermissionReference = false
            var unsafeTargetPackage = false
            var verifiedAppLink = false
            var customDeepLink = false
            var signaturePermission = false
            var splitMetadata = manifest.isSplit
            val manifestRoot = manifest.manifestElement
            if (manifestRoot != null) {
                val splitNames = setOf(
                    "split",
                    "isFeatureSplit",
                    "isSplitRequired",
                    "requiredSplitTypes",
                    "splitTypes",
                    "isolatedSplits",
                )
                splitMetadata = splitMetadata || manifestRoot.getAttributes().asSequence()
                    .any { it.name in splitNames }
            }

            val elements = allElements(manifest)
            val declaredPermissions = elements.asSequence()
                .filter { it.name == "permission" }
                .mapNotNull { it.searchAttributeByName("name")?.valueAsString }
                .filter { it.isNotBlank() }
                .toSet()

            for (element in elements) {
                when (element.name) {
                    "provider" -> {
                        val authorities = element.searchAttributeByName("authorities")
                            ?.valueAsString
                            .orEmpty()
                        if (authorities.isBlank() ||
                            StandaloneClonePolicy.rewriteAuthorities(
                                sourcePackage,
                                "placeholder.clone",
                                authorities,
                            ) == null
                        ) {
                            unsafeAuthority = true
                        }
                    }
                    "permission" -> {
                        val permissionName = element.searchAttributeByName("name")
                            ?.valueAsString
                            .orEmpty()
                        if (permissionName.isNotBlank() &&
                            StandaloneClonePolicy.rewritePackageDerivedName(
                                sourcePackage,
                                "placeholder.clone",
                                permissionName,
                            ) == null
                        ) {
                            unsafeAuthority = true
                        }
                        val protection = element.searchAttributeByName("protectionLevel")
                        if (protection != null) {
                            val text = protection.valueAsString.orEmpty().lowercase(Locale.ROOT)
                            val base = protection.data and 0x0f
                            if ("signature" in text || base == 2 || base == 3) {
                                signaturePermission = true
                            }
                        }
                    }
                    "intent-filter" -> {
                        val autoVerify = element.searchAttributeByName("autoVerify")
                        if (autoVerify != null && runCatching { autoVerify.valueAsBoolean }.getOrDefault(false)) {
                            verifiedAppLink = true
                        }
                        if (isCustomDeepLinkIntentFilter(element)) {
                            customDeepLink = true
                        }
                    }
                }

                for (attributeName in permissionReferenceAttributeNames(element.name)) {
                    val permission = element.searchAttributeByName(attributeName)?.valueAsString
                    if (!permission.isNullOrBlank() &&
                        StandaloneClonePolicy.rewritePackageDerivedName(
                            sourcePackage,
                            "placeholder.clone",
                            permission,
                        ) != null && permission !in declaredPermissions
                    ) {
                        unsafePermissionReference = true
                    }
                }

                val targetPackage = element.searchAttributeByName("targetPackage")?.valueAsString
                if (!targetPackage.isNullOrBlank() &&
                    StandaloneClonePolicy.rewritePackageDerivedName(
                        sourcePackage,
                        "placeholder.clone",
                        targetPackage,
                    ) == null
                ) {
                    unsafeTargetPackage = true
                }

                val process = element.searchAttributeByName("process")?.valueAsString
                if (!process.isNullOrBlank() && !process.startsWith(":")) {
                    if (StandaloneClonePolicy.rewritePackageDerivedName(
                            sourcePackage,
                            "placeholder.clone",
                            process,
                        ) == null
                    ) {
                        unsafeProcess = true
                    }
                }
                val affinity = element.searchAttributeByName("taskAffinity")?.valueAsString
                if (!affinity.isNullOrEmpty() &&
                    StandaloneClonePolicy.rewritePackageDerivedName(
                        sourcePackage,
                        "placeholder.clone",
                        affinity,
                    ) == null
                ) {
                    unsafeTaskAffinity = true
                }
            }

            val sharedUserId = manifestRoot
                ?.searchAttributeByName("sharedUserId")
                ?.valueAsString
                ?.isNotBlank() == true

            return StandaloneCloneManifestFacts(
                hasSplitMetadata = splitMetadata,
                hasSharedUserId = sharedUserId,
                hasUnsafeProviderAuthority = unsafeAuthority,
                hasUnsafeAbsoluteProcess = unsafeProcess,
                hasUnsafeTaskAffinity = unsafeTaskAffinity,
                hasUnsafePermissionReference = unsafePermissionReference,
                hasUnsafeTargetPackage = unsafeTargetPackage,
                hasVerifiedAppLink = verifiedAppLink,
                hasCustomDeepLink = customDeepLink,
                hasGoogleIdentityBinding = hasGoogleIdentityBinding,
                hasSignatureBoundPermission = signaturePermission,
                hasHardcodedApplicationId = hasHardcodedApplicationId,
            )
        }

        internal fun rewriteModuleForClone(
            module: ApkModule,
            sourcePackage: String,
            clonePackage: String,
        ) {
            val manifest = module.androidManifestBlock
                ?: throw IllegalStateException("AndroidManifest.xml is unavailable")
            check(manifest.packageName == sourcePackage)

            for (element in allElements(manifest)) {
                if (element.name in COMPONENT_TAGS) {
                    val name = element.searchAttributeByName("name")?.valueAsString
                    if (!name.isNullOrBlank()) {
                        element.searchAttributeByName("name")
                            .setValueAsString(
                                StandaloneClonePolicy.expandComponentName(sourcePackage, name),
                            )
                    }
                }
                if (element.name == "activity-alias") {
                    val target = element.searchAttributeByName("targetActivity")?.valueAsString
                    if (!target.isNullOrBlank()) {
                        element.searchAttributeByName("targetActivity")
                            .setValueAsString(
                                StandaloneClonePolicy.expandComponentName(sourcePackage, target),
                            )
                    }
                }
                if (element.name == "provider") {
                    val authorities = element.searchAttributeByName("authorities")?.valueAsString
                    if (!authorities.isNullOrBlank()) {
                        val rewritten = StandaloneClonePolicy.rewriteAuthorities(
                            sourcePackage,
                            clonePackage,
                            authorities,
                        ) ?: throw IllegalStateException("Provider authority is not package-derived")
                        element.searchAttributeByName("authorities").setValueAsString(rewritten)
                    }
                }

                rewriteGlobalAttribute(element, "process", sourcePackage, clonePackage, allowPrivate = true)
                rewriteGlobalAttribute(element, "taskAffinity", sourcePackage, clonePackage, allowEmpty = true)
                rewriteGlobalAttribute(element, "targetPackage", sourcePackage, clonePackage)
            }

            val declaredPermissionRewrites = mutableMapOf<String, String>()
            for (permission in allElements(manifest).filter { it.name == "permission" }) {
                val attribute = permission.searchAttributeByName("name") ?: continue
                val old = attribute.valueAsString ?: continue
                val rewritten = StandaloneClonePolicy.rewritePackageDerivedName(
                    sourcePackage,
                    clonePackage,
                    old,
                ) ?: throw IllegalStateException("Permission name is not package-derived")
                attribute.setValueAsString(rewritten)
                declaredPermissionRewrites[old] = rewritten
            }
            val rewrittenElements = allElements(manifest)
            for (usesPermission in rewrittenElements.filter { it.name == "uses-permission" }) {
                val attribute = usesPermission.searchAttributeByName("name") ?: continue
                val old = attribute.valueAsString ?: continue
                declaredPermissionRewrites[old]?.let(attribute::setValueAsString)
            }
            for (element in rewrittenElements) {
                for (attributeName in permissionReferenceAttributeNames(element.name)) {
                    val attribute = element.searchAttributeByName(attributeName) ?: continue
                    val old = attribute.valueAsString ?: continue
                    val rewritten = declaredPermissionRewrites[old]
                    if (rewritten != null) {
                        attribute.setValueAsString(rewritten)
                    } else if (StandaloneClonePolicy.rewritePackageDerivedName(
                            sourcePackage,
                            clonePackage,
                            old,
                        ) != null
                    ) {
                        throw IllegalStateException(
                            "$attributeName permission reference is package-derived but not declaration-backed",
                        )
                    }
                }
            }

            module.setPackageName(clonePackage)
            if (module.hasTableBlock()) {
                val localPackages = module.tableBlock.listPackages().toList()
                check(localPackages.size <= 1) {
                    "Multi-package resources.arsc is outside the Phase-1 clone contract"
                }
                localPackages.singleOrNull()?.name = clonePackage
            }
            manifest.refreshFull()
            if (module.hasTableBlock()) module.refreshTable()
        }

        internal fun validateTransformedApk(
            transformedApk: File,
            sourcePackage: String,
            clonePackage: String,
        ) {
            ApkModule.loadApkFile(transformedApk).use { module ->
                val manifest = module.androidManifestBlock
                    ?: throw IllegalStateException("Transformed AndroidManifest.xml is unavailable")
                check(module.packageName == clonePackage) { "Transformed APK package is not clone identity" }
                check(manifest.packageName == clonePackage) { "Transformed manifest package is not clone identity" }
                if (module.hasTableBlock()) {
                    val resourcePackages = module.tableBlock.listPackages().toList()
                    check(resourcePackages.size <= 1) { "Transformed resources contain multiple packages" }
                    resourcePackages.singleOrNull()?.let { resourcePackage ->
                        check(resourcePackage.name == clonePackage) {
                            "Transformed resource package is not clone identity"
                        }
                    }
                }

                for (element in allElements(manifest)) {
                    if (element.name == "provider") {
                        val authorities = element.searchAttributeByName("authorities")?.valueAsString.orEmpty()
                        check(authorities.isNotBlank() &&
                            StandaloneClonePolicy.rewriteAuthorities(
                                clonePackage,
                                clonePackage,
                                authorities,
                            ) != null
                        ) { "Transformed provider authority is not clone-derived" }
                    }
                    if (element.name == "permission") {
                        val permission = element.searchAttributeByName("name")?.valueAsString.orEmpty()
                        check(permission.isNotBlank() && isPackageDerived(clonePackage, permission)) {
                            "Transformed permission declaration is not clone-derived"
                        }
                    }
                    if (element.name == "uses-permission") {
                        val permission = element.searchAttributeByName("name")?.valueAsString
                        check(!isUnrewrittenSourceDerived(sourcePackage, clonePackage, permission)) {
                            "Source-derived uses-permission remained after transform"
                        }
                    }
                    for (attributeName in permissionReferenceAttributeNames(element.name)) {
                        val permission = element.searchAttributeByName(attributeName)?.valueAsString
                        check(!isUnrewrittenSourceDerived(sourcePackage, clonePackage, permission)) {
                            "Source-derived $attributeName permission remained after transform"
                        }
                    }

                    val process = element.searchAttributeByName("process")?.valueAsString
                    if (!process.isNullOrBlank() && !process.startsWith(":")) {
                        check(isPackageDerived(clonePackage, process)) {
                            "Transformed absolute process is not clone-derived"
                        }
                    }
                    val affinity = element.searchAttributeByName("taskAffinity")?.valueAsString
                    if (!affinity.isNullOrEmpty()) {
                        check(isPackageDerived(clonePackage, affinity)) {
                            "Transformed task affinity is not clone-derived"
                        }
                    }
                    val targetPackage = element.searchAttributeByName("targetPackage")?.valueAsString
                    if (!targetPackage.isNullOrBlank()) {
                        check(isPackageDerived(clonePackage, targetPackage)) {
                            "Transformed target package is not clone-derived"
                        }
                    }
                }
            }
        }

        internal fun sourceSignerSha256(currentSignerCertificates: Collection<ByteArray>): String? =
            currentSignerCertificates.singleOrNull()?.let(::sha256)

        private fun isPackageDerived(packageName: String, value: String?): Boolean =
            !value.isNullOrBlank() &&
                StandaloneClonePolicy.rewritePackageDerivedName(packageName, packageName, value) != null

        private fun isUnrewrittenSourceDerived(
            sourcePackage: String,
            clonePackage: String,
            value: String?,
        ): Boolean = isPackageDerived(sourcePackage, value) && !isPackageDerived(clonePackage, value)

        private fun permissionReferenceAttributeNames(elementName: String): List<String> = when (elementName) {
            "application", "activity", "activity-alias", "service", "receiver" -> listOf("permission")
            "provider" -> listOf("permission", "readPermission", "writePermission")
            else -> emptyList()
        }

        private fun isCustomDeepLinkIntentFilter(element: ResXmlElement): Boolean {
            val hasView = element.listElements("action").any { action ->
                action.searchAttributeByName("name")?.valueAsString == "android.intent.action.VIEW"
            }
            val hasBrowsable = element.listElements("category").any { category ->
                category.searchAttributeByName("name")?.valueAsString == "android.intent.category.BROWSABLE"
            }
            if (!hasView || !hasBrowsable) return false
            return element.listElements("data").any { data ->
                val scheme = data.searchAttributeByName("scheme")?.valueAsString
                    ?.lowercase(Locale.ROOT)
                !scheme.isNullOrBlank() && scheme != "http" && scheme != "https"
            }
        }

        internal fun containsAsciiLiteral(bytes: ByteArray, literal: String): Boolean {
            if (literal.isEmpty()) return true
            val needle = literal.toByteArray(Charsets.US_ASCII)
            if (needle.size > bytes.size) return false
            outer@ for (start in 0..bytes.size - needle.size) {
                for (offset in needle.indices) {
                    if (bytes[start + offset] != needle[offset]) continue@outer
                }
                return true
            }
            return false
        }

        private fun rewriteGlobalAttribute(
            element: ResXmlElement,
            attributeName: String,
            sourcePackage: String,
            clonePackage: String,
            allowPrivate: Boolean = false,
            allowEmpty: Boolean = false,
        ) {
            val attribute = element.searchAttributeByName(attributeName) ?: return
            val value = attribute.valueAsString ?: return
            if ((allowEmpty && value.isEmpty()) || (allowPrivate && value.startsWith(":"))) return
            val rewritten = StandaloneClonePolicy.rewritePackageDerivedName(
                sourcePackage,
                clonePackage,
                value,
            ) ?: throw IllegalStateException("$attributeName is not package-derived")
            attribute.setValueAsString(rewritten)
        }

        private fun allElements(manifest: AndroidManifestBlock): List<ResXmlElement> {
            val root = manifest.manifestElement ?: return emptyList()
            val result = mutableListOf(root)
            @Suppress("UNCHECKED_CAST")
            val iterator = root.recursiveElements() as Iterator<ResXmlElement>
            while (iterator.hasNext()) result += iterator.next()
            return result
        }

        private fun archiveExtensionBlocker(displayName: String): String? {
            val lower = displayName.lowercase(Locale.ROOT)
            return when {
                lower.endsWith(".aab") -> "app_bundle_unsupported"
                lower.endsWith(".apkm") || lower.endsWith(".xapk") || lower.endsWith(".apks") ->
                    "split_container_unsupported"
                lower.endsWith(".apk") -> null
                else -> "unsupported_archive_format"
            }
        }

        private fun unsupported(blocker: String): StandaloneCloneInspection =
            StandaloneCloneInspection(
                compatibility = StandaloneCloneCompatibility(blockers = listOf(blocker)),
            )

        private fun isJarSignatureEntry(alias: String): Boolean {
            val upper = alias.replace('\\', '/').uppercase(Locale.ROOT)
            if (!upper.startsWith("META-INF/")) return false
            return upper == "META-INF/MANIFEST.MF" ||
                upper.endsWith(".SF") || upper.endsWith(".RSA") ||
                upper.endsWith(".DSA") || upper.endsWith(".EC")
        }

        internal fun isDexEntry(name: String): Boolean =
            Regex("^classes(?:[2-9]|[1-9][0-9]+)?\\.dex$")
                .matches(name.replace('\\', '/'))

        private fun zipEntryDigests(file: File, accept: (String) -> Boolean): Map<String, String> =
            ZipFile(file).use { zip ->
                zip.entries().asSequence()
                    .filter { !it.isDirectory && accept(it.name) }
                    .associate { entry ->
                        entry.name to zip.getInputStream(entry).use { input -> sha256(input) }
                    }
            }

        private fun scanAsciiLiterals(input: InputStream, literals: Collection<String>): Set<String> {
            val needles = literals.distinct().associateWith { it.toByteArray(Charsets.US_ASCII) }
            if (needles.isEmpty()) return emptySet()
            val maxNeedle = needles.values.maxOf { it.size }.coerceAtLeast(1)
            val buffer = ByteArray(64 * 1024)
            var carry = ByteArray(0)
            val hits = mutableSetOf<String>()
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                val chunk = ByteArray(carry.size + count)
                carry.copyInto(chunk)
                buffer.copyInto(chunk, carry.size, 0, count)
                for ((literal, needle) in needles) {
                    if (literal !in hits && containsBytes(chunk, needle)) hits += literal
                }
                if (hits.size == needles.size) break
                val keep = (maxNeedle - 1).coerceAtMost(chunk.size)
                carry = chunk.copyOfRange(chunk.size - keep, chunk.size)
            }
            return hits
        }

        private fun containsBytes(haystack: ByteArray, needle: ByteArray): Boolean {
            if (needle.isEmpty()) return true
            if (needle.size > haystack.size) return false
            outer@ for (start in 0..haystack.size - needle.size) {
                for (offset in needle.indices) {
                    if (haystack[start + offset] != needle[offset]) continue@outer
                }
                return true
            }
            return false
        }

        private fun sha256(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

        private fun sha256(input: InputStream): String {
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
            return digest.digest()
                .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        }
    }
}
