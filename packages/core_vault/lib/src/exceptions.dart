/// Exception thrown when vault operations fail.
///
/// This includes decryption failures, file I/O errors, and format violations.
class VaultException implements Exception {
  /// Creates a vault exception with the given [message].
  VaultException(this.message);
  final String message;

  @override
  String toString() => 'VaultException: $message';
}

/// Exception thrown when vault data fails validation.
///
/// This includes missing required fields, invalid references, and constraint
/// violations like duplicate IDs.
class VaultValidationException extends VaultException {
  /// Creates a validation exception with the given [message].
  VaultValidationException(super.message);
}
