import 'dart:typed_data';

import 'crypto.dart';
import 'exceptions.dart';
import 'models.dart';

// Magic bytes identifying a VibedTerm vault file (ASCII "VBT1")
const _magic = [0x56, 0x42, 0x54, 0x31];

// Fixed portion of header before variable-length nonce
const _headerFixedBytes = 36;

// Bytes used to store payload length in header
const _payloadLengthBytes = 4;

// Default salt length for KDF (128 bits)
const defaultSaltLength = 16;

/// Binary header for vault files containing encryption metadata.
///
/// The header stores all parameters needed to derive the encryption key and
/// decrypt the payload. It is stored unencrypted at the beginning of the vault
/// file and is authenticated as additional data (AAD) during encryption.
class VaultHeader {
  const VaultHeader({
    required this.version,
    required this.kdf,
    required this.kdfMemoryKiB,
    required this.kdfIterations,
    required this.kdfParallelism,
    required this.kdfSalt,
    required this.cipher,
    required this.nonce,
    required this.payloadLength,
  });

  final int version;
  final KdfKind kdf;
  final int kdfMemoryKiB;
  final int kdfIterations;
  final int kdfParallelism;
  final List<int> kdfSalt;
  final CipherKind cipher;
  final List<int> nonce;
  final int payloadLength;

  int get encodedLength => _headerFixedBytes + nonce.length + _payloadLengthBytes;

  VaultHeader copyWith({
    List<int>? nonce,
    int? payloadLength,
  }) {
    return VaultHeader(
      version: version,
      kdf: kdf,
      kdfMemoryKiB: kdfMemoryKiB,
      kdfIterations: kdfIterations,
      kdfParallelism: kdfParallelism,
      kdfSalt: kdfSalt,
      cipher: cipher,
      nonce: nonce ?? this.nonce,
      payloadLength: payloadLength ?? this.payloadLength,
    );
  }

  Uint8List toBytes() {
    final bytes = Uint8List(encodedLength);
    final view = ByteData.view(bytes.buffer);

    bytes.setAll(0, _magic);
    view.setUint8(4, version);
    view.setUint8(5, kdfToId(kdf));
    view.setUint32(6, kdfMemoryKiB, Endian.little);
    view.setUint32(10, kdfIterations, Endian.little);
    view.setUint32(14, kdfParallelism, Endian.little);
    if (kdfSalt.length != defaultSaltLength) {
      throw VaultException('kdfSalt must be $defaultSaltLength bytes.');
    }
    bytes.setAll(18, kdfSalt);
    view.setUint8(34, cipherToId(cipher));
    view.setUint8(35, nonce.length);
    bytes.setAll(36, nonce);
    view.setUint32(36 + nonce.length, payloadLength, Endian.little);
    return bytes;
  }

  static VaultHeader parse(Uint8List bytes) {
    if (bytes.length < _headerFixedBytes + _payloadLengthBytes) {
      throw VaultException('Header too short.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw VaultException('Invalid magic header.');
      }
    }
    final view = ByteData.view(bytes.buffer);
    final version = view.getUint8(4);
    final kdfId = view.getUint8(5);
    final kdf = kdfFromId(kdfId);
    final kdfMemoryKiB = view.getUint32(6, Endian.little);
    final kdfIterations = view.getUint32(10, Endian.little);
    final kdfParallelism = view.getUint32(14, Endian.little);
    final salt = bytes.sublist(18, 34);
    if (salt.length != defaultSaltLength) {
      throw VaultException('Invalid salt length.');
    }
    final cipherId = view.getUint8(34);
    final cipher = cipherFromId(cipherId);
    final nonceLength = view.getUint8(35);
    final headerLength = _headerFixedBytes + nonceLength + _payloadLengthBytes;
    if (bytes.length < headerLength) {
      throw VaultException('Header truncated.');
    }
    final nonce = bytes.sublist(36, 36 + nonceLength);
    final payloadLength =
        view.getUint32(36 + nonceLength, Endian.little);
    return VaultHeader(
      version: version,
      kdf: kdf,
      kdfMemoryKiB: kdfMemoryKiB,
      kdfIterations: kdfIterations,
      kdfParallelism: kdfParallelism,
      kdfSalt: List<int>.unmodifiable(salt),
      cipher: cipher,
      nonce: List<int>.unmodifiable(nonce),
      payloadLength: payloadLength,
    );
  }
}
