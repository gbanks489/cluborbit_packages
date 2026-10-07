// Media attachment encryption/decryption per the Matrix spec's "Sending encrypted attachments":
// https://spec.matrix.org/v1.11/client-server-api/#sending-encrypted-attachments
// AES-256-CTR with a single-use key, a 128-bit counter block made of an 8-byte random nonce
// followed by 8 zero bytes, and a SHA-256 hash of the ciphertext for tamper detection.
//
// Matched byte-for-byte against cluborbit-web's src/lib/attachmentCrypto.js — that's the client
// this needs to interoperate with (a photo sent from web must decrypt correctly here, and a photo
// sent from here must decrypt correctly on web), not a separate/incompatible scheme.

use crate::CryptoError;
use aes::Aes256;
use base64::{
    alphabet::{STANDARD as STANDARD_ALPHABET, URL_SAFE as URL_SAFE_ALPHABET},
    engine::{general_purpose::GeneralPurposeConfig, DecodePaddingMode, GeneralPurpose},
    Engine,
};
use ctr::cipher::{KeyIvInit, StreamCipher};
use rand::RngCore;
use sha2::{Digest, Sha256};

type Aes256Ctr64BE = ctr::Ctr64BE<Aes256>;

// Unpadded on encode (per spec: "encoded as unpadded base64" for iv/hashes, "urlsafe unpadded
// base64" for the JWK key); tolerant of either padded or unpadded, urlsafe or standard input on
// decode — matching attachmentCrypto.js's own leniency there, since a real-world attachment could
// have been produced by some other spec-compliant Matrix client, not just this app's own encoder.
const STANDARD_CODEC: GeneralPurpose = GeneralPurpose::new(
    &STANDARD_ALPHABET,
    GeneralPurposeConfig::new()
        .with_encode_padding(false)
        .with_decode_padding_mode(DecodePaddingMode::Indifferent),
);
const URL_SAFE_CODEC: GeneralPurpose = GeneralPurpose::new(
    &URL_SAFE_ALPHABET,
    GeneralPurposeConfig::new()
        .with_encode_padding(false)
        .with_decode_padding_mode(DecodePaddingMode::Indifferent),
);

fn to_base64(bytes: &[u8], url_safe: bool) -> String {
    if url_safe { URL_SAFE_CODEC.encode(bytes) } else { STANDARD_CODEC.encode(bytes) }
}

fn from_base64(s: &str) -> Result<Vec<u8>, CryptoError> {
    // Normalize urlsafe characters to standard ones first, so this one decoder accepts both
    // alphabets regardless of which field (key vs iv/hash) it's reading — same approach as
    // attachmentCrypto.js's fromBase64.
    let normalized: String =
        s.chars().map(|c| match c { '-' => '+', '_' => '/', other => other }).collect();
    STANDARD_CODEC.decode(normalized).map_err(|e| CryptoError { message: e.to_string() })
}

// Named distinctly from lib.rs's public, FRB-exposed `EncryptedAttachment` (even though this one
// is only pub(crate)) — flutter_rust_bridge's codegen matches types by short name across the whole
// crate when scanning for what to bind, and two same-named structs (regardless of visibility)
// makes it warn and pick one at random instead of reliably picking the public one.
pub(crate) struct AttachmentEncryptionOutput {
    pub(crate) ciphertext: Vec<u8>,
    /// The AES-256 key, urlsafe unpadded base64 (the JWK `k` field).
    pub(crate) key_base64: String,
    /// The 128-bit counter block, unpadded base64.
    pub(crate) iv_base64: String,
    /// SHA-256 of the ciphertext, unpadded base64.
    pub(crate) sha256_base64: String,
}

/// Encrypts a plaintext attachment, generating a fresh single-use key and IV.
pub(crate) fn encrypt_attachment(plaintext: &[u8]) -> AttachmentEncryptionOutput {
    let mut rng = rand::thread_rng();

    let mut key = [0u8; 32];
    rng.fill_bytes(&mut key);

    // 128-bit counter block: 8 random bytes (the per-file nonce) followed by 8 zero bytes (the
    // counter, starting at 0) — an IV must never repeat for the same key, which a single-use
    // random key per file already guarantees, but this layout matches the spec (and every other
    // Matrix client) byte-for-byte regardless.
    let mut iv = [0u8; 16];
    rng.fill_bytes(&mut iv[..8]);

    let mut cipher = Aes256Ctr64BE::new(&key.into(), &iv.into());
    let mut ciphertext = plaintext.to_vec();
    cipher.apply_keystream(&mut ciphertext);

    let hash = Sha256::digest(&ciphertext);

    AttachmentEncryptionOutput {
        ciphertext,
        key_base64: to_base64(&key, true),
        iv_base64: to_base64(&iv, false),
        sha256_base64: to_base64(&hash, false),
    }
}

/// Decrypts a ciphertext attachment given its key/iv (and, if known, the expected SHA-256 hash to
/// verify against before decrypting — never skip this when the sender provided one).
pub(crate) fn decrypt_attachment(
    ciphertext: &[u8],
    key_base64: &str,
    iv_base64: &str,
    expected_sha256_base64: Option<&str>,
) -> Result<Vec<u8>, CryptoError> {
    if let Some(expected) = expected_sha256_base64 {
        let expected_bytes = from_base64(expected)?;
        let actual_bytes = Sha256::digest(ciphertext);
        if actual_bytes.as_slice() != expected_bytes.as_slice() {
            return Err(CryptoError {
                message: "Attachment failed integrity check (SHA-256 mismatch)".to_string(),
            });
        }
    }

    let key_bytes = from_base64(key_base64)?;
    let key: [u8; 32] = key_bytes
        .try_into()
        .map_err(|_| CryptoError { message: "Attachment key must be 32 bytes".to_string() })?;
    let iv_bytes = from_base64(iv_base64)?;
    let iv: [u8; 16] = iv_bytes
        .try_into()
        .map_err(|_| CryptoError { message: "Attachment IV must be 16 bytes".to_string() })?;

    let mut cipher = Aes256Ctr64BE::new(&key.into(), &iv.into());
    let mut plaintext = ciphertext.to_vec();
    cipher.apply_keystream(&mut plaintext);
    Ok(plaintext)
}
