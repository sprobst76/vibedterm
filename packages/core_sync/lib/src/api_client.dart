part of '../core_sync.dart';

/// Low-level HTTP client for the VibedTerm sync server API.
class SyncApiClient {
  SyncApiClient({
    required this.config,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final SyncConfig config;
  final http.Client _http;

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiresAt;

  /// Set authentication tokens.
  void setTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  /// Clear authentication tokens.
  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiresAt = null;
  }

  /// Check if we have valid tokens.
  bool get isAuthenticated => _accessToken != null;

  /// Check if access token is expired or about to expire.
  bool get isTokenExpired {
    if (_tokenExpiresAt == null) return true;
    return DateTime.now().isAfter(_tokenExpiresAt!);
  }

  /// Get the current refresh token.
  String? get refreshToken => _refreshToken;

  Uri _uri(String path) => Uri.parse('${config.serverUrl}$path');

  Map<String, String> _headers({bool auth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (auth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    final body = response.body.isNotEmpty
        ? json.decode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final error = body['error'] as String? ?? 'Unknown error';
    final code = body['code'] as String?;
    throw SyncException(error, code: code, statusCode: response.statusCode);
  }

  // --- Auth Endpoints ---

  /// Register a new user.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
  }) async {
    final response = await _http.post(
      _uri('/api/v1/auth/register'),
      headers: _headers(auth: false),
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );
    return _handleResponse(response);
  }

  /// Login with email and password.
  /// Returns either LoginResponse or TOTPRequiredResponse.
  Future<dynamic> login({
    required String email,
    required String password,
    required String deviceName,
    required String deviceType,
  }) async {
    final response = await _http.post(
      _uri('/api/v1/auth/login'),
      headers: _headers(auth: false),
      body: json.encode({
        'email': email,
        'password': password,
        'device_name': deviceName,
        'device_type': deviceType,
      }),
    );
    final body = await _handleResponse(response);

    if (body['requires_totp'] == true) {
      return TOTPRequiredResponse.fromJson(body);
    }

    final loginResponse = LoginResponse.fromJson(body);
    setTokens(
      accessToken: loginResponse.accessToken,
      refreshToken: loginResponse.refreshToken,
      expiresIn: loginResponse.expiresIn,
    );
    return loginResponse;
  }

  /// Complete login with TOTP code.
  Future<LoginResponse> validateTOTP({
    required String tempToken,
    required String code,
  }) async {
    final response = await _http.post(
      _uri('/api/v1/auth/login/totp'),
      headers: _headers(auth: false),
      body: json.encode({
        'temp_token': tempToken,
        'code': code,
      }),
    );
    final body = await _handleResponse(response);
    final loginResponse = LoginResponse.fromJson(body);
    setTokens(
      accessToken: loginResponse.accessToken,
      refreshToken: loginResponse.refreshToken,
      expiresIn: loginResponse.expiresIn,
    );
    return loginResponse;
  }

  /// Complete login with recovery code.
  Future<Map<String, dynamic>> validateRecovery({
    required String tempToken,
    required String code,
  }) async {
    final response = await _http.post(
      _uri('/api/v1/auth/login/recovery'),
      headers: _headers(auth: false),
      body: json.encode({
        'temp_token': tempToken,
        'code': code,
      }),
    );
    return _handleResponse(response);
  }

  /// Refresh the access token.
  Future<void> refreshAccessToken() async {
    if (_refreshToken == null) {
      throw SyncException('No refresh token available');
    }

    final response = await _http.post(
      _uri('/api/v1/auth/refresh'),
      headers: _headers(auth: false),
      body: json.encode({
        'refresh_token': _refreshToken,
      }),
    );
    final body = await _handleResponse(response);

    _accessToken = body['access_token'] as String;
    final expiresIn = body['expires_in'] as int;
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  /// Logout (revoke refresh token).
  Future<void> logout() async {
    if (_refreshToken == null) return;

    try {
      await _http.post(
        _uri('/api/v1/auth/logout'),
        headers: _headers(auth: false),
        body: json.encode({
          'refresh_token': _refreshToken,
        }),
      );
    } finally {
      clearTokens();
    }
  }

  /// Logout from all devices.
  Future<void> logoutAll() async {
    await _authenticatedRequest(() async {
      final response = await _http.post(
        _uri('/api/v1/auth/logout-all'),
        headers: _headers(),
      );
      await _handleResponse(response);
    });
    clearTokens();
  }

  // --- TOTP Endpoints ---

  /// Setup TOTP for the current user.
  Future<TOTPSetupResponse> setupTOTP() async {
    return _authenticatedRequest(() async {
      final response = await _http.post(
        _uri('/api/v1/totp/setup'),
        headers: _headers(),
      );
      final body = await _handleResponse(response);
      return TOTPSetupResponse.fromJson(body);
    });
  }

  /// Verify and enable TOTP.
  Future<RecoveryCodesResponse> verifyTOTP(String code) async {
    return _authenticatedRequest(() async {
      final response = await _http.post(
        _uri('/api/v1/totp/verify'),
        headers: _headers(),
        body: json.encode({'code': code}),
      );
      final body = await _handleResponse(response);
      return RecoveryCodesResponse.fromJson(body);
    });
  }

  /// Disable TOTP.
  Future<void> disableTOTP({
    required String code,
    required String password,
  }) async {
    return _authenticatedRequest(() async {
      final response = await _http.post(
        _uri('/api/v1/totp/disable'),
        headers: _headers(),
        body: json.encode({
          'code': code,
          'password': password,
        }),
      );
      await _handleResponse(response);
    });
  }

  /// Regenerate recovery codes.
  Future<RecoveryCodesResponse> regenerateRecoveryCodes(String code) async {
    return _authenticatedRequest(() async {
      final response = await _http.post(
        _uri('/api/v1/totp/recovery-codes'),
        headers: _headers(),
        body: json.encode({'code': code}),
      );
      final body = await _handleResponse(response);
      return RecoveryCodesResponse.fromJson(body);
    });
  }

  // --- Vault Endpoints ---

  /// Get vault status.
  Future<VaultStatusResponse> getVaultStatus() async {
    return _authenticatedRequest(() async {
      final response = await _http.get(
        _uri('/api/v1/vault/status'),
        headers: _headers(),
      );
      final body = await _handleResponse(response);
      return VaultStatusResponse.fromJson(body);
    });
  }

  /// Pull vault from server.
  Future<VaultPullResponse> pullVault() async {
    return _authenticatedRequest(() async {
      final response = await _http.get(
        _uri('/api/v1/vault/pull'),
        headers: _headers(),
      );
      final body = await _handleResponse(response);
      return VaultPullResponse.fromJson(body);
    });
  }

  /// Push vault to server.
  /// Throws SyncException with isConflict=true on revision mismatch.
  Future<VaultPushResponse> pushVault({
    required String vaultBlob,
    required int revision,
    required String deviceId,
  }) async {
    return _authenticatedRequest(() async {
      final response = await _http.post(
        _uri('/api/v1/vault/push'),
        headers: _headers(),
        body: json.encode({
          'vault_blob': vaultBlob,
          'revision': revision,
          'device_id': deviceId,
        }),
      );

      if (response.statusCode == 409) {
        // 409 Conflict - server has different revision
        throw SyncException(
          'Vault conflict detected',
          code: 'CONFLICT',
          statusCode: 409,
        );
      }

      final body = await _handleResponse(response);
      return VaultPushResponse.fromJson(body);
    });
  }

  /// Force overwrite vault on server.
  Future<VaultPushResponse> forceOverwriteVault({
    required String vaultBlob,
    required String deviceId,
  }) async {
    return _authenticatedRequest(() async {
      final response = await _http.post(
        _uri('/api/v1/vault/force-overwrite'),
        headers: _headers(),
        body: json.encode({
          'vault_blob': vaultBlob,
          'device_id': deviceId,
          'confirm': true,
        }),
      );
      final body = await _handleResponse(response);
      return VaultPushResponse.fromJson(body);
    });
  }

  /// Get vault sync history.
  Future<List<Map<String, dynamic>>> getVaultHistory() async {
    return _authenticatedRequest(() async {
      final response = await _http.get(
        _uri('/api/v1/vault/history'),
        headers: _headers(),
      );
      final body = await _handleResponse(response);
      return (body['history'] as List).cast<Map<String, dynamic>>();
    });
  }

  // --- Device Endpoints ---

  /// List all devices for the current user.
  Future<List<SyncDevice>> listDevices() async {
    return _authenticatedRequest(() async {
      final response = await _http.get(
        _uri('/api/v1/devices'),
        headers: _headers(),
      );
      final body = await _handleResponse(response);
      final devices = body['devices'] as List;
      return devices
          .map((d) => SyncDevice.fromJson(d as Map<String, dynamic>))
          .toList();
    });
  }

  /// Get current device info.
  Future<SyncDevice> getCurrentDevice() async {
    return _authenticatedRequest(() async {
      final response = await _http.get(
        _uri('/api/v1/devices/current'),
        headers: _headers(),
      );
      final body = await _handleResponse(response);
      return SyncDevice.fromJson(body);
    });
  }

  /// Rename a device.
  Future<void> renameDevice(String deviceId, String name) async {
    return _authenticatedRequest(() async {
      final response = await _http.put(
        _uri('/api/v1/devices/$deviceId'),
        headers: _headers(),
        body: json.encode({'name': name}),
      );
      await _handleResponse(response);
    });
  }

  /// Delete a device.
  Future<void> deleteDevice(String deviceId) async {
    return _authenticatedRequest(() async {
      final response = await _http.delete(
        _uri('/api/v1/devices/$deviceId'),
        headers: _headers(),
      );
      await _handleResponse(response);
    });
  }

  /// Execute an authenticated request with automatic token refresh.
  Future<T> _authenticatedRequest<T>(Future<T> Function() request) async {
    if (!isAuthenticated) {
      throw SyncException('Not authenticated');
    }

    // Refresh token if expired
    if (isTokenExpired && _refreshToken != null) {
      try {
        await refreshAccessToken();
      } on SyncException {
        clearTokens();
        rethrow;
      }
    }

    try {
      return await request();
    } on SyncException catch (e) {
      // If unauthorized, try to refresh and retry once
      if (e.isUnauthorized && _refreshToken != null) {
        try {
          await refreshAccessToken();
          return await request();
        } on SyncException {
          clearTokens();
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// Close the HTTP client.
  void dispose() {
    _http.close();
  }
}
