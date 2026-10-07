// Secure Secret Storage and Sharing (SSSS / "4S"): https://spec.matrix.org/v1.11/client-server-api/#secret-storage
//
// matrix-sdk-crypto has no opinion on this — it only deals with key material once you already
// have it. This module is what actually unlocks the account's private cross-signing keys and key
// backup decryption key from server-side account data, so a brand-new device can recover them
// instead of only ever generating fresh (and incompatible) ones.
//
// Every constant and step here is matched byte-for-byte against matrix-js-sdk's own
// implementation, since cluborbit-web already uses it (see chatService.js's setupKeyBackup,
// deriving the recovery key deterministically from the account password) — this has to derive the
// exact same secrets, not a separate 4S setup:
//   node_modules/matrix-js-sdk/src/crypto-api/key-passphrase.ts   (passphrase -> master key: PBKDF2)
//   node_modules/matrix-js-sdk/src/utils/internal/deriveKeys.ts   (master key -> AES/HMAC subkeys: HKDF)
//   node_modules/matrix-js-sdk/src/utils/{encrypt,decrypt}AESSecretStorageItem.ts (AES-CTR + HMAC)
//   node_modules/matrix-js-sdk/src/secret-storage.ts (key check: encrypt 32 zero bytes, secret name "")

use crate::CryptoError;
use aes::Aes256;
use base64::{
    alphabet::STANDARD as STANDARD_ALPHABET,
    engine::{general_purpose::GeneralPurposeConfig, DecodePaddingMode, GeneralPurpose},
    Engine,
};
use ctr::cipher::{KeyIvInit, StreamCipher};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::{Sha256, Sha512};

type Aes256Ctr64BE = ctr::Ctr64BE<Aes256>;

// matrix-js-sdk's own decodeBase64 (src/base64.ts) tolerates both padded and unpadded input
// (`lastChunkHandling: "loose"`) since different secrets in this ecosystem are encoded either way
// (e.g. cross-signing key exports are explicitly unpadded, but encodeBase64's own output — used
// for iv/ciphertext/mac — is padded) — match that leniency instead of requiring one or the other.
const BASE64: GeneralPurpose = GeneralPurpose::new(
    &STANDARD_ALPHABET,
    GeneralPurposeConfig::new().with_decode_padding_mode(DecodePaddingMode::Indifferent),
);

// pub(crate), not pub — this module's API is only ever called from lib.rs's own free functions
// (ssss_derive_master_key etc.), which is what flutter_rust_bridge actually exposes to Dart. A
// plain `pub` here would make flutter_rust_bridge's codegen additionally auto-discover and
// generate a whole separate, redundant Dart binding straight to this module (it scans every `pub`
// item reachable from the crate root, not just ones re-exported through an intentional API).

/// The `{iv, ciphertext, mac}` shape every `m.secret_storage.v1.aes-hmac-sha2`-encrypted value
/// (a stored secret, or a key-info's self-check) uses on the wire — all three base64-encoded.
pub(crate) struct EncryptedPayload {
    pub(crate) iv: String,
    pub(crate) ciphertext: String,
    pub(crate) mac: String,
}

fn base64_decode(s: &str) -> Result<Vec<u8>, CryptoError> {
    BASE64.decode(s).map_err(|e| CryptoError { message: e.to_string() })
}

/// Step 1 of https://spec.matrix.org/v1.11/client-server-api/#deriving-keys-from-passphrases —
/// turns the account password into this account's 32-byte 4S master key, using the iterations/salt
/// published (in the clear — they aren't secret, only the password is) in this account's
/// `m.secret_storage.key.<id>` account data.
pub(crate) fn derive_master_key_from_passphrase(passphrase: &str, salt: &str, iterations: u32) -> [u8; 32] {
    let mut key = [0u8; 32];
    pbkdf2::pbkdf2_hmac::<Sha512>(passphrase.as_bytes(), salt.as_bytes(), iterations, &mut key);
    key
}

/// Step 2 — derives the per-secret AES-256 and HMAC-SHA256 keys from the 4S master key via HKDF,
/// keyed by the secret's own name (e.g. "m.megolm_backup.v1") so every secret gets an independent
/// key even though they all ultimately come from the same master key.
fn derive_sub_keys(master_key: &[u8; 32], name: &str) -> ([u8; 32], [u8; 32]) {
    // 8 zero bytes, matching deriveKeys.ts's `zeroSalt`.
    let hk = Hkdf::<Sha256>::new(Some(&[0u8; 8]), master_key);
    let mut okm = [0u8; 64];
    hk.expand(name.as_bytes(), &mut okm)
        .expect("64 bytes is always a valid HKDF-SHA256 output length");
    let mut aes_key = [0u8; 32];
    let mut hmac_key = [0u8; 32];
    aes_key.copy_from_slice(&okm[..32]);
    hmac_key.copy_from_slice(&okm[32..]);
    (aes_key, hmac_key)
}

fn hmac_tag(hmac_key: &[u8; 32], data: &[u8]) -> Vec<u8> {
    let mut mac =
        Hmac::<Sha256>::new_from_slice(hmac_key).expect("HMAC-SHA256 accepts any key length");
    mac.update(data);
    mac.finalize().into_bytes().to_vec()
}

/// Decrypts one secret-storage item (a stored secret's `content.encrypted.<keyId>` payload),
/// verifying its HMAC first — matches decryptAESSecretStorageItem.ts exactly, including verifying
/// before decrypting (never decrypt un-authenticated ciphertext).
pub(crate) fn decrypt_secret(
    payload: &EncryptedPayload,
    master_key: &[u8; 32],
    name: &str,
) -> Result<String, CryptoError> {
    let (aes_key, hmac_key) = derive_sub_keys(master_key, name);
    let ciphertext = base64_decode(&payload.ciphertext)?;
    let mac = base64_decode(&payload.mac)?;
    let iv = base64_decode(&payload.iv)?;
    if iv.len() != 16 {
        return Err(CryptoError { message: format!("secret {name}: invalid IV length") });
    }

    let mut mac_verifier = Hmac::<Sha256>::new_from_slice(&hmac_key)
        .expect("HMAC-SHA256 accepts any key length");
    mac_verifier.update(&ciphertext);
    mac_verifier
        .verify_slice(&mac)
        .map_err(|_| CryptoError { message: format!("secret {name}: bad MAC — wrong recovery key?") })?;

    let mut iv_arr = [0u8; 16];
    iv_arr.copy_from_slice(&iv);
    let mut cipher = Aes256Ctr64BE::new(&aes_key.into(), &iv_arr.into());
    let mut buf = ciphertext;
    cipher.apply_keystream(&mut buf);
    String::from_utf8(buf).map_err(|e| CryptoError { message: e.to_string() })
}

/// Checks a candidate master key against this account's published key-check (the `iv`/`mac` pair
/// on its `m.secret_storage.key.<id>` account data) — encrypts 32 zero bytes under secret name ""
/// and compares the resulting MAC, exactly like secret-storage.ts's checkKey/calculateKeyCheck.
/// This is the safety gate: if the password (or the account data this session fetched) is wrong,
/// this returns false and the caller no-ops instead of risking anything with a wrong key.
pub(crate) fn check_master_key(master_key: &[u8; 32], check_iv_b64: &str, expected_mac_b64: &str) -> bool {
    let Ok(iv) = base64_decode(check_iv_b64) else { return false };
    if iv.len() != 16 {
        return false;
    }
    let Ok(expected_mac) = base64_decode(expected_mac_b64) else { return false };

    let (aes_key, hmac_key) = derive_sub_keys(master_key, "");
    let mut iv_arr = [0u8; 16];
    iv_arr.copy_from_slice(&iv);
    let mut cipher = Aes256Ctr64BE::new(&aes_key.into(), &iv_arr.into());
    // 32 zero bytes, matching secret-storage.ts's ZERO_STR (32 "\0" characters, i.e. 32 zero bytes
    // once UTF-8 encoded).
    let mut encrypted_zeroes = vec![0u8; 32];
    cipher.apply_keystream(&mut encrypted_zeroes);

    hmac_tag(&hmac_key, &encrypted_zeroes) == expected_mac
}

/// Encrypts one secret-storage item - the inverse of `decrypt_secret`, matching
/// encryptAESSecretStorageItem.ts: a random 16-byte IV with bit 63 cleared (so the 64-bit CTR
/// counter can't overflow into the nonce half), AES-256-CTR, then HMAC-SHA256 over the ciphertext.
pub(crate) fn encrypt_secret(master_key: &[u8; 32], name: &str, plaintext: &[u8]) -> EncryptedPayload {
    use rand::RngCore;
    let (aes_key, hmac_key) = derive_sub_keys(master_key, name);
    let mut iv = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut iv);
    iv[8] &= 0x7f;
    let mut cipher = Aes256Ctr64BE::new(&aes_key.into(), &iv.into());
    let mut buf = plaintext.to_vec();
    cipher.apply_keystream(&mut buf);
    let mac = hmac_tag(&hmac_key, &buf);
    EncryptedPayload {
        iv: BASE64.encode(iv),
        ciphertext: BASE64.encode(&buf),
        mac: BASE64.encode(mac),
    }
}

/// The published key-check for a new 4S key (32 zero bytes encrypted under secret name "") - what
/// `check_master_key` later verifies a derived key against.
pub(crate) fn key_check(master_key: &[u8; 32]) -> EncryptedPayload {
    encrypt_secret(master_key, "", &[0u8; 32])
}

/// A random alphanumeric string, like matrix-js-sdk's randomString (used for 4S key ids / salts).
pub(crate) fn random_string(len: usize) -> String {
    use rand::{distributions::Alphanumeric, Rng};
    rand::thread_rng().sample_iter(&Alphanumeric).take(len).map(char::from).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypt_then_decrypt_round_trips_and_key_check_verifies() {
        let master = derive_master_key_from_passphrase("pw", &random_string(32), 1000);
        let payload = encrypt_secret(&master, "m.megolm_backup.v1", b"secret-value");
        assert_eq!(decrypt_secret(&payload, &master, "m.megolm_backup.v1").unwrap(), "secret-value");
        // Wrong secret name derives different subkeys, so the MAC must fail.
        assert!(decrypt_secret(&payload, &master, "m.cross_signing.master").is_err());

        let check = key_check(&master);
        assert!(check_master_key(&master, &check.iv, &check.mac));
        let other = derive_master_key_from_passphrase("other", "salt", 1000);
        assert!(!check_master_key(&other, &check.iv, &check.mac));
    }
}
