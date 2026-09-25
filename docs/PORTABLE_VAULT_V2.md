# Portable Vault V2

Portable Vault V2 is the byte-stable cross-device format for PIN-selected vault identities.

## Key schedule

- PIN encoding: UTF-8 decimal digits, length 4..12.
- KDF: Argon2id v1.3, Argon2 version field `0x13`.
- Salt/domain bytes: UTF-8 `PrivateVaultPortableV2`, one NUL byte, then UTF-8 `argon2id`.
- Argon2 optional secret: empty.
- Argon2 associated data: empty.
- Memory: 19,456 KiB.
- Iterations: 2.
- Parallelism: 1.
- Root output: 64 bytes.
- AES key: root bytes `[0..32)`.
- Namespace seed: root bytes `[32..64)`.
- Namespace digest: SHA-256(UTF-8 `PrivateVaultPortableV2/namespace` || namespace seed).
- Namespace ID: first 16 digest bytes, lowercase hexadecimal (32 characters).

Known-answer vector:

```text
PIN                    = 0000
root64                 = e98c61d8c24120f797656808294c79371e7347c80de28f60f1954298af40be83679f6369c91d584d62e84e2993f728f29e5b9d12a70cfd4068c625f9d5ace073
aes256_key             = e98c61d8c24120f797656808294c79371e7347c80de28f60f1954298af40be83
namespace_id           = d784d2608b4851dd0826bccaf69d7fa6
```

Changing any value above is a new key-schedule/profile and must not be shipped as the same V2 profile.

Compatibility note: earlier V2 envelope experiments in this repository were development-only and were not production-wired as the released portable storage path. This document defines the frozen Portable Vault V2 interoperability profile. Legacy V1 app-private data is handled separately by the explicit copy-only migration flow.

## Object envelope

All integers are unsigned big-endian. Header length is exactly 22 bytes.

| Offset | Size | Field | V2 value |
|---:|---:|---|---:|
| 0 | 4 | magic | ASCII `PV2O` |
| 4 | 1 | format version | 2 |
| 5 | 1 | KDF id | 1 = Argon2id |
| 6 | 4 | KDF memory KiB | 19456 |
| 10 | 4 | KDF iterations | 2 |
| 14 | 1 | KDF parallelism | 1 |
| 15 | 1 | root key bytes | 64 |
| 16 | 1 | cipher id | 1 = AES-256-GCM |
| 17 | 1 | cipher key bytes | 32 |
| 18 | 1 | nonce bytes | 12 |
| 19 | 1 | tag bytes | 16 |
| 20 | 1 | namespace scheme | 1 |
| 21 | 1 | key-schedule version | 1 |

Disk bytes are:

```text
header[22] || nonce[12] || tag[16] || ciphertext[n]
```

The complete 22-byte header is AES-GCM AAD. A header/profile mutation therefore fails authentication or profile validation.

## Authenticated plaintext

Before encryption:

```text
metadata_length_u32_be || metadata_utf8_json || payload
```

Metadata keys:

- `v`: integer 2.
- `name`: authenticated logical object name. Payload `.pvb` uses `<object_id>.bin`; listing sidecar `.pvm` uses `<object_id>.meta`; thumbnail cache `.pvt` uses `<object_id>.thumb`. The repository verifies the expected role/name pairing.
- `type`: media type.
- `created`: UTC Unix epoch milliseconds.
- `namespace`: 32-character namespace ID; repository verifies it equals the open PIN session namespace.

Object ID and namespace identity are therefore inside the authenticated plaintext. Renaming an object file or moving a decryptable object into another namespace is rejected.

## Namespace layout

```text
<selected portable root>/
  <namespace_id>/
    catalog.pvc
    objects/
      <object_id>.pvb
      # legacy readers may also encounter <object_id>.pvm/.pvt
    cache/
      thumbnails/
        <object_id>.pvt
```

`<object_id>.pvb` is the sole authoritative encrypted payload object for new writes. Its authenticated V2 metadata already contains media type, creation time, namespace, and logical name, so new objects do not require a per-object `.pvm` listing sidecar. Legacy encrypted `.pvm` sidecars under `objects/` remain readable as a compatibility cache, but they are never authoritative and are not recreated for new objects.

`catalog.pvc` is one encrypted, reconstructible namespace catalog containing only object ID, media type, and creation time. It exists to avoid decrypting large payloads during listing. The repository reconciles it against actual `.pvb` filenames and rebuilds missing/stale entries from authenticated payloads or legacy `.pvm` cache data; catalog failure must never delete or hide an existing payload.

`cache/thumbnails/<object_id>.pvt` is an optional, reconstructible encrypted media-thumbnail cache for image and video tiles. It uses the same V2 envelope/profile with authenticated `name = <object_id>.thumb`, `type = image/jpeg`, the same namespace and creation time, and a bounded JPEG thumbnail payload. Legacy `objects/<object_id>.pvt` thumbnails remain readable. Missing, corrupt, unsupported, or orphan thumbnail cache data may be deleted/rebuilt without changing the authoritative `.pvb` payload.

Multiple PIN identities coexist under one selected portable root. Switching PIN selects another namespace; it does not re-key or delete prior namespaces.

## Portability and threat model

- No Android Keystore secret participates in V2 derivation.
- Same root + same PIN reproduces the same namespace and decryption key on another implementation.
- Short PIN offline brute force is an accepted product tradeoff.
- Android storage uses SAF document-tree access; `MANAGE_EXTERNAL_STORAGE` is not required.
- Decrypted session key material exists only in process memory and is discarded on lock, panic lock, PIN switch, or app disposal.