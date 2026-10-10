package io.hiroshimeow.private_vault_mobile

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.android.apksig.ApkSigner
import com.android.apksig.ApkVerifier
import java.io.File
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.Date
import javax.security.auth.x500.X500Principal

internal class StandaloneCloneSignatureException(message: String) : IllegalStateException(message)

internal data class StandaloneCloneSigningResult(
    val signerSha256: String,
    val verifiedSchemes: List<String>,
)

internal class StandaloneCloneSigningStore {
    fun signAndVerify(unsignedApk: File, signedApk: File, alias: String): StandaloneCloneSigningResult {
        require(unsignedApk.isFile) { "Unsigned APK does not exist" }
        require(alias.startsWith(ALIAS_PREFIX)) { "Unexpected clone-lab key alias" }
        val entry = ensurePrivateKeyEntry(alias)
        val certificate = entry.certificate as X509Certificate
        val signerConfig = ApkSigner.SignerConfig.Builder(
            alias,
            entry.privateKey as PrivateKey,
            listOf(certificate),
        ).build()

        signedApk.parentFile?.mkdirs()
        if (signedApk.exists()) signedApk.delete()
        ApkSigner.Builder(listOf(signerConfig))
            .setInputApk(unsignedApk)
            .setOutputApk(signedApk)
            .setV1SigningEnabled(true)
            .setV2SigningEnabled(true)
            .setV3SigningEnabled(true)
            .setV4SigningEnabled(false)
            .setOtherSignersSignaturesPreserved(false)
            .setCreatedBy("Private Vault clone-lab")
            .build()
            .sign()

        val verification = try {
            ApkVerifier.Builder(signedApk).build().verify()
        } catch (error: Exception) {
            signedApk.delete()
            throw StandaloneCloneSignatureException(
                "Signed clone APK could not be verified: ${error.message ?: error::class.java.simpleName}",
            )
        }
        if (!verification.isVerified) {
            signedApk.delete()
            throw StandaloneCloneSignatureException(
                "Signed clone APK failed apksig verification: ${verification.errors.joinToString()}",
            )
        }
        val verifiedCert = verification.signerCertificates.firstOrNull()
        if (verifiedCert == null) {
            signedApk.delete()
            throw StandaloneCloneSignatureException(
                "Signed clone APK has no verified signer certificate",
            )
        }
        val expected = sha256(certificate.encoded)
        val actual = sha256(verifiedCert.encoded)
        if (expected != actual) {
            signedApk.delete()
            throw StandaloneCloneSignatureException(
                "Signed clone APK signer does not match clone-lab key",
            )
        }

        return StandaloneCloneSigningResult(
            signerSha256 = actual,
            verifiedSchemes = buildList {
                if (verification.isVerifiedUsingV1Scheme) add("v1")
                if (verification.isVerifiedUsingV2Scheme) add("v2")
                if (verification.isVerifiedUsingV3Scheme) add("v3")
                if (verification.isVerifiedUsingV31Scheme) add("v3.1")
                if (verification.isVerifiedUsingV4Scheme) add("v4")
            },
        )
    }

    private fun ensurePrivateKeyEntry(alias: String): KeyStore.PrivateKeyEntry {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = keyStore.getEntry(alias, null)
        if (existing != null) {
            check(existing is KeyStore.PrivateKeyEntry) { "Clone-lab alias is not a private key" }
            return existing
        }

        val now = System.currentTimeMillis()
        val serial = BigInteger(1, MessageDigest.getInstance("SHA-256").digest(alias.toByteArray()))
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            KEYSTORE_PROVIDER,
        )
        generator.initialize(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            )
                .setKeySize(KEY_SIZE_BITS)
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .setCertificateSubject(X500Principal("CN=Private Vault Clone Lab"))
                .setCertificateSerialNumber(serial)
                .setCertificateNotBefore(Date(now - ONE_DAY_MS))
                .setCertificateNotAfter(Date(now + CERTIFICATE_LIFETIME_MS))
                .setUserAuthenticationRequired(false)
                .build(),
        )
        generator.generateKeyPair()

        val created = keyStore.getEntry(alias, null)
        check(created is KeyStore.PrivateKeyEntry) { "AndroidKeyStore did not create clone-lab key" }
        return created
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    companion object {
        internal const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        internal const val KEY_SIZE_BITS = 3072
        internal const val ALIAS_PREFIX = "private_vault_clone_lab_"
        private const val ONE_DAY_MS = 24L * 60L * 60L * 1000L
        private const val CERTIFICATE_LIFETIME_MS = 20L * 365L * ONE_DAY_MS
    }
}
