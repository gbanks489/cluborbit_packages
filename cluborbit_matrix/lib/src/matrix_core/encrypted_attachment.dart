/// The Matrix spec's `EncryptedFile` shape (the `content.file` field of an encrypted
/// `m.room.message` attachment) — see https://spec.matrix.org/v1.11/client-server-api/#sending-encrypted-attachments.
/// Mirrors cluborbit-web's own `content.file` shape byte-for-byte, since interoperating with it
/// (not a separate/incompatible scheme) is the whole point.
class EncryptedFileInfo {
  const EncryptedFileInfo({
    required this.url,
    required this.keyBase64,
    required this.ivBase64,
    this.sha256Base64,
  });

  /// The mxc:// URI pointing at the encrypted ciphertext on the media repo.
  final String url;

  /// The AES-256 key, urlsafe unpadded base64 (the JWK `k` field).
  final String keyBase64;

  /// The 128-bit AES-CTR counter block, unpadded base64.
  final String ivBase64;

  /// SHA-256 of the ciphertext, unpadded base64 — verified before decrypting when present.
  final String? sha256Base64;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'v': 'v2',
    'key': <String, dynamic>{
      'kty': 'oct',
      'key_ops': <String>['encrypt', 'decrypt'],
      'alg': 'A256CTR',
      'k': keyBase64,
      'ext': true,
    },
    'iv': ivBase64,
    if (sha256Base64 != null)
      'hashes': <String, dynamic>{'sha256': sha256Base64},
  };

  /// Parses a raw `content.file` map — null if it isn't a well-formed `EncryptedFile` (missing
  /// url/key/iv), which callers should treat as "this message has no usable encrypted attachment"
  /// rather than throwing.
  static EncryptedFileInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final url = json['url'] as String?;
    final key = json['key'];
    final keyBase64 = key is Map ? key['k'] as String? : null;
    final ivBase64 = json['iv'] as String?;
    if (url == null || url.isEmpty || keyBase64 == null || ivBase64 == null)
      return null;
    final hashes = json['hashes'];
    final sha256Base64 = hashes is Map ? hashes['sha256'] as String? : null;
    return EncryptedFileInfo(
      url: url,
      keyBase64: keyBase64,
      ivBase64: ivBase64,
      sha256Base64: sha256Base64,
    );
  }
}
