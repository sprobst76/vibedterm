/// Cloud sync library for VibedTerm SSH client.
///
/// This library provides secure vault synchronization with a backend server,
/// including user authentication, device management, and conflict resolution.
///
/// ## Features
///
/// - **User authentication**: Register, login, logout with JWT tokens
/// - **Two-factor auth (TOTP)**: Optional 2FA with recovery codes
/// - **Device management**: Track and manage sync devices
/// - **Vault sync**: Push/pull encrypted vault data with revision tracking
/// - **Conflict detection**: Automatic detection of conflicting changes
/// - **Auto-sync**: Optional periodic background synchronization
///
/// ## Architecture
///
/// The sync system follows a zero-knowledge design:
/// - Vault data is encrypted client-side before upload
/// - Server only stores opaque encrypted blobs
/// - Revision numbers enable conflict detection without decryption
///
/// ## Usage
///
/// ```dart
/// // Create services
/// final apiClient = SyncApiClient(baseUrl: 'https://sync.example.com');
/// final authService = AuthService(apiClient: apiClient);
/// final syncService = SyncService(apiClient: apiClient, authService: authService);
///
/// // Initialize from stored tokens
/// await authService.init();
///
/// // Login if needed
/// if (!authService.isAuthenticated) {
///   await authService.login(
///     email: 'user@example.com',
///     password: 'password',
///     deviceName: 'My Device',
///     deviceType: 'android',
///   );
/// }
///
/// // Sync vault
/// final result = await syncService.sync(
///   getLocalVault: () async => base64Encode(encryptedVaultBytes),
///   loadServerVault: (blob, revision) async {
///     final bytes = base64Decode(blob);
///     // Decrypt and load vault...
///   },
/// );
/// ```
///
/// ## Error Handling
///
/// All API errors are wrapped in [SyncException] with:
/// - [SyncException.message]: Human-readable error description
/// - [SyncException.code]: Server error code (e.g., "CONFLICT", "TOKEN_EXPIRED")
/// - [SyncException.statusCode]: HTTP status code
///
/// Common error checks:
/// - `isConflict`: Server has conflicting changes
/// - `isUnauthorized`: Token expired or invalid
/// - `isPendingApproval`: Account awaiting admin approval
library core_sync;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

part 'src/api_client.dart';
part 'src/models.dart';
part 'src/auth_service.dart';
part 'src/sync_service.dart';
part 'src/sync_config.dart';
