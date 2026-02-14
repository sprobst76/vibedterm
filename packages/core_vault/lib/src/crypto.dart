import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'exceptions.dart';
import 'models.dart';

// Derived key length (256 bits)
const defaultKeyLength = 32;

int kdfToId(KdfKind kind) {
  switch (kind) {
    case KdfKind.argon2id:
      return 0x01;
    case KdfKind.scrypt:
      return 0x02;
  }
}

KdfKind kdfFromId(int id) {
  switch (id) {
    case 0x01:
      return KdfKind.argon2id;
    case 0x02:
      return KdfKind.scrypt;
    default:
      throw VaultException('Unsupported KDF id: $id');
  }
}

int cipherToId(CipherKind kind) {
  switch (kind) {
    case CipherKind.xchacha20Poly1305:
      return 0x01;
    case CipherKind.aes256Gcm:
      return 0x02;
  }
}

CipherKind cipherFromId(int id) {
  switch (id) {
    case 0x01:
      return CipherKind.xchacha20Poly1305;
    case 0x02:
      return CipherKind.aes256Gcm;
    default:
      throw VaultException('Unsupported cipher id: $id');
  }
}

Future<SecretKey> deriveKey({
  required String password,
  required KdfKind kind,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
  required List<int> salt,
}) async {
  switch (kind) {
    case KdfKind.argon2id:
      final kdf = Argon2id(
        parallelism: parallelism,
        memory: memoryKiB,
        iterations: iterations,
        hashLength: defaultKeyLength,
      );
      return kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
    case KdfKind.scrypt:
      throw VaultException('scrypt is not implemented.');
  }
}

Cipher cipherForKind(CipherKind kind) {
  switch (kind) {
    case CipherKind.xchacha20Poly1305:
      return Xchacha20.poly1305Aead();
    case CipherKind.aes256Gcm:
      return AesGcm.with256bits();
  }
}

String nowIso() => DateTime.now().toUtc().toIso8601String();
