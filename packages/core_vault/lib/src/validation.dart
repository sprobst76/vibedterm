import 'exceptions.dart';
import 'models.dart';

void validateHost(VaultHost host, {Set<String>? identityIds}) {
  if (host.id.isEmpty) {
    throw VaultValidationException('Host id is required.');
  }
  if (host.label.isEmpty) {
    throw VaultValidationException('Host label is required.');
  }
  if (host.hostname.isEmpty) {
    throw VaultValidationException('Host hostname is required.');
  }
  if (host.port <= 0 || host.port > 65535) {
    throw VaultValidationException('Host port must be between 1 and 65535.');
  }
  if (host.username.isEmpty) {
    throw VaultValidationException('Host username is required.');
  }
  if (host.identityId != null &&
      identityIds != null &&
      !identityIds.contains(host.identityId)) {
    throw VaultValidationException(
      'Host identityId does not match any identity.',
    );
  }
}

void validateIdentity(VaultIdentity identity) {
  if (identity.id.isEmpty) {
    throw VaultValidationException('Identity id is required.');
  }
  if (identity.name.isEmpty) {
    throw VaultValidationException('Identity name is required.');
  }
  if (identity.type.isEmpty) {
    throw VaultValidationException('Identity type is required.');
  }
  if (identity.privateKey.isEmpty) {
    throw VaultValidationException('Identity privateKey is required.');
  }
  if (!looksLikePem(identity.privateKey)) {
    throw VaultValidationException('Identity privateKey must be PEM/OpenSSH formatted.');
  }
}

void validateSnippet(VaultSnippet snippet) {
  if (snippet.id.isEmpty) {
    throw VaultValidationException('Snippet id is required.');
  }
  if (snippet.title.isEmpty) {
    throw VaultValidationException('Snippet title is required.');
  }
  if (snippet.content.isEmpty) {
    throw VaultValidationException('Snippet content is required.');
  }
}

void checkDuplicates(Iterable<String> values, String label) {
  final seen = <String>{};
  for (final v in values) {
    if (seen.contains(v)) {
      throw VaultValidationException('$label duplicates are not allowed.');
    }
    seen.add(v);
  }
}

bool looksLikePem(String key) {
  final trimmed = key.trim();
  if (!trimmed.startsWith('-----BEGIN') ||
      !trimmed.contains('PRIVATE KEY') ||
      !trimmed.contains('-----END')) {
    return false;
  }
  final lines = trimmed.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  if (lines.length < 3) {
    return false;
  }
  final start = lines.first;
  final end = lines.last;
  if (!start.startsWith('-----BEGIN') || !end.startsWith('-----END')) {
    return false;
  }
  final body = lines
      .skip(1)
      .take(lines.length - 2)
      .join();
  // Basic base64 sanity: length divisible by 4 and only valid chars.
  final base64Pattern = RegExp(r'^[A-Za-z0-9+/=\r\n]+$');
  if (!base64Pattern.hasMatch(body)) {
    return false;
  }
  return body.length >= 16 && body.length % 4 == 0;
}
