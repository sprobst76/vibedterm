part of '../core_sync.dart';

/// Exception thrown when API operations fail.
class SyncException implements Exception {
  SyncException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409 || code == 'CONFLICT';
  bool get isPendingApproval => code == 'PENDING_APPROVAL';
  bool get isAccountBlocked => code == 'ACCOUNT_BLOCKED';
  bool get isTokenExpired => code == 'TOKEN_EXPIRED';

  @override
  String toString() => 'SyncException: $message (code: $code, status: $statusCode)';
}

// --- Auth Models ---

/// User information from the server.
@immutable
class SyncUser {
  const SyncUser({
    required this.id,
    required this.email,
    required this.isApproved,
    required this.isAdmin,
    required this.isBlocked,
    required this.totpEnabled,
    required this.createdAt,
    this.lastLoginAt,
  });

  final String id;
  final String email;
  final bool isApproved;
  final bool isAdmin;
  final bool isBlocked;
  final bool totpEnabled;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  factory SyncUser.fromJson(Map<String, dynamic> json) {
    return SyncUser(
      id: json['id'] as String,
      email: json['email'] as String,
      isApproved: json['is_approved'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      isBlocked: json['is_blocked'] as bool? ?? false,
      totpEnabled: json['totp_enabled'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
    );
  }
}

/// Response from successful login.
@immutable
class LoginResponse {
  const LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
    required this.deviceId,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final SyncUser user;
  final String deviceId;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int,
      user: SyncUser.fromJson(json['user'] as Map<String, dynamic>),
      deviceId: json['device_id'] as String,
    );
  }
}

/// Response when TOTP is required during login.
@immutable
class TOTPRequiredResponse {
  const TOTPRequiredResponse({
    required this.tempToken,
  });

  final String tempToken;

  factory TOTPRequiredResponse.fromJson(Map<String, dynamic> json) {
    return TOTPRequiredResponse(
      tempToken: json['temp_token'] as String,
    );
  }
}

/// Response from TOTP setup.
@immutable
class TOTPSetupResponse {
  const TOTPSetupResponse({
    required this.secret,
    required this.qrCodeUrl,
    required this.issuer,
  });

  final String secret;
  final String qrCodeUrl;
  final String issuer;

  factory TOTPSetupResponse.fromJson(Map<String, dynamic> json) {
    return TOTPSetupResponse(
      secret: json['secret'] as String,
      qrCodeUrl: json['qr_code_url'] as String,
      issuer: json['issuer'] as String,
    );
  }
}

/// Recovery codes response.
@immutable
class RecoveryCodesResponse {
  const RecoveryCodesResponse({required this.codes});

  final List<String> codes;

  factory RecoveryCodesResponse.fromJson(Map<String, dynamic> json) {
    return RecoveryCodesResponse(
      codes: (json['codes'] as List).cast<String>(),
    );
  }
}

// --- Vault Sync Models ---

/// Vault status from server.
@immutable
class VaultStatusResponse {
  const VaultStatusResponse({
    required this.hasVault,
    required this.revision,
    required this.updatedAt,
  });

  final bool hasVault;
  final int revision;
  final DateTime? updatedAt;

  factory VaultStatusResponse.fromJson(Map<String, dynamic> json) {
    final updatedAt = json['updated_at'] as int?;
    return VaultStatusResponse(
      hasVault: json['has_vault'] as bool,
      revision: json['revision'] as int,
      updatedAt: updatedAt != null && updatedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000)
          : null,
    );
  }
}

/// Vault data pulled from server.
@immutable
class VaultPullResponse {
  const VaultPullResponse({
    required this.vaultBlob,
    required this.revision,
    required this.updatedAt,
    this.updatedByDevice,
  });

  /// Base64-encoded encrypted vault blob
  final String vaultBlob;
  final int revision;
  final DateTime updatedAt;
  final String? updatedByDevice;

  factory VaultPullResponse.fromJson(Map<String, dynamic> json) {
    return VaultPullResponse(
      vaultBlob: json['vault_blob'] as String,
      revision: json['revision'] as int,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updated_at'] as int) * 1000,
      ),
      updatedByDevice: json['updated_by_device'] as String?,
    );
  }
}

/// Response from vault push.
@immutable
class VaultPushResponse {
  const VaultPushResponse({
    required this.status,
    required this.revision,
    required this.timestamp,
  });

  final String status;
  final int revision;
  final DateTime timestamp;

  factory VaultPushResponse.fromJson(Map<String, dynamic> json) {
    return VaultPushResponse(
      status: json['status'] as String,
      revision: json['revision'] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as int) * 1000,
      ),
    );
  }
}

/// Conflict response from vault push.
@immutable
class VaultConflictResponse {
  const VaultConflictResponse({
    required this.localRevision,
    required this.serverRevision,
    required this.serverDeviceId,
    required this.serverUpdatedAt,
  });

  final int localRevision;
  final int serverRevision;
  final String serverDeviceId;
  final DateTime serverUpdatedAt;

  factory VaultConflictResponse.fromJson(Map<String, dynamic> json) {
    return VaultConflictResponse(
      localRevision: json['local_revision'] as int,
      serverRevision: json['server_revision'] as int,
      serverDeviceId: json['server_device_id'] as String? ?? '',
      serverUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['server_updated_at'] as int) * 1000,
      ),
    );
  }
}

// --- Device Models ---

/// Device information from server.
@immutable
class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    this.deviceModel,
    this.appVersion,
    this.lastSyncAt,
    required this.createdAt,
  });

  final String id;
  final String deviceName;
  final String deviceType;
  final String? deviceModel;
  final String? appVersion;
  final DateTime? lastSyncAt;
  final DateTime createdAt;

  factory SyncDevice.fromJson(Map<String, dynamic> json) {
    return SyncDevice(
      id: json['id'] as String,
      deviceName: json['device_name'] as String,
      deviceType: json['device_type'] as String,
      deviceModel: json['device_model'] as String?,
      appVersion: json['app_version'] as String?,
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.parse(json['last_sync_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
