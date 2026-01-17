part of '../core_sync.dart';

/// Authentication state.
enum AuthState {
  /// Not logged in
  unauthenticated,

  /// Login in progress
  authenticating,

  /// Logged in
  authenticated,

  /// TOTP required to complete login
  totpRequired,

  /// Account pending admin approval
  pendingApproval,

  /// Account blocked
  blocked,

  /// Error occurred
  error,
}

/// Current authentication status.
@immutable
class AuthStatus {
  const AuthStatus({
    required this.state,
    this.user,
    this.deviceId,
    this.tempToken,
    this.errorMessage,
  });

  final AuthState state;
  final SyncUser? user;
  final String? deviceId;
  final String? tempToken;
  final String? errorMessage;

  bool get isAuthenticated => state == AuthState.authenticated;

  AuthStatus copyWith({
    AuthState? state,
    SyncUser? user,
    String? deviceId,
    String? tempToken,
    String? errorMessage,
  }) {
    return AuthStatus(
      state: state ?? this.state,
      user: user ?? this.user,
      deviceId: deviceId ?? this.deviceId,
      tempToken: tempToken,
      errorMessage: errorMessage,
    );
  }

  static const unauthenticated = AuthStatus(state: AuthState.unauthenticated);
}

/// Manages authentication with the sync server.
class AuthService {
  AuthService({
    required SyncApiClient apiClient,
    FlutterSecureStorage? secureStorage,
  })  : _api = apiClient,
        _storage = secureStorage ?? const FlutterSecureStorage();

  final SyncApiClient _api;
  final FlutterSecureStorage _storage;

  static const _refreshTokenKey = 'vibedterm.sync.refreshToken';
  static const _accessTokenKey = 'vibedterm.sync.accessToken';
  static const _userEmailKey = 'vibedterm.sync.userEmail';
  static const _deviceIdKey = 'vibedterm.sync.deviceId';

  final _statusController = StreamController<AuthStatus>.broadcast();
  AuthStatus _status = AuthStatus.unauthenticated;

  /// Stream of authentication status changes.
  Stream<AuthStatus> get statusStream => _statusController.stream;

  /// Current authentication status.
  AuthStatus get status => _status;

  /// Current user if authenticated.
  SyncUser? get currentUser => _status.user;

  /// Current device ID if authenticated.
  String? get deviceId => _status.deviceId;

  /// Whether the user is authenticated.
  bool get isAuthenticated => _status.isAuthenticated;

  void _updateStatus(AuthStatus status) {
    _status = status;
    _statusController.add(status);
  }

  /// Initialize authentication from stored tokens.
  Future<void> init() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final accessToken = await _storage.read(key: _accessTokenKey);
    final storedDeviceId = await _storage.read(key: _deviceIdKey);

    if (refreshToken != null && accessToken != null) {
      // Try to restore session
      _api.setTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresIn: 0, // Will trigger refresh
      );

      try {
        // Refresh to get a new valid token
        await _api.refreshAccessToken();

        // Get current device info to verify session
        final device = await _api.getCurrentDevice();

        _updateStatus(AuthStatus(
          state: AuthState.authenticated,
          deviceId: device.id.isNotEmpty ? device.id : storedDeviceId,
        ));

        // Save refreshed token
        await _storage.write(
          key: _accessTokenKey,
          value: _api._accessToken,
        );
      } on SyncException catch (e) {
        // Session expired or invalid
        await _clearStoredTokens();
        if (e.isPendingApproval) {
          _updateStatus(const AuthStatus(state: AuthState.pendingApproval));
        } else if (e.isAccountBlocked) {
          _updateStatus(const AuthStatus(state: AuthState.blocked));
        } else {
          _updateStatus(AuthStatus.unauthenticated);
        }
      }
    }
  }

  /// Register a new account.
  Future<void> register({
    required String email,
    required String password,
  }) async {
    _updateStatus(const AuthStatus(state: AuthState.authenticating));

    try {
      await _api.register(email: email, password: password);
      _updateStatus(const AuthStatus(state: AuthState.pendingApproval));
    } on SyncException catch (e) {
      _updateStatus(AuthStatus(
        state: AuthState.error,
        errorMessage: e.message,
      ));
      rethrow;
    }
  }

  /// Login with email and password.
  Future<void> login({
    required String email,
    required String password,
    required String deviceName,
    required String deviceType,
  }) async {
    _updateStatus(const AuthStatus(state: AuthState.authenticating));

    try {
      final result = await _api.login(
        email: email,
        password: password,
        deviceName: deviceName,
        deviceType: deviceType,
      );

      if (result is TOTPRequiredResponse) {
        _updateStatus(AuthStatus(
          state: AuthState.totpRequired,
          tempToken: result.tempToken,
        ));
      } else if (result is LoginResponse) {
        await _handleLoginSuccess(result);
      }
    } on SyncException catch (e) {
      if (e.isPendingApproval) {
        _updateStatus(const AuthStatus(state: AuthState.pendingApproval));
      } else if (e.isAccountBlocked) {
        _updateStatus(const AuthStatus(state: AuthState.blocked));
      } else {
        _updateStatus(AuthStatus(
          state: AuthState.error,
          errorMessage: e.message,
        ));
      }
      rethrow;
    }
  }

  /// Complete login with TOTP code.
  Future<void> verifyTOTP(String code) async {
    if (_status.tempToken == null) {
      throw SyncException('No TOTP session active');
    }

    _updateStatus(_status.copyWith(state: AuthState.authenticating));

    try {
      final result = await _api.validateTOTP(
        tempToken: _status.tempToken!,
        code: code,
      );
      await _handleLoginSuccess(result);
    } on SyncException catch (e) {
      _updateStatus(AuthStatus(
        state: AuthState.totpRequired,
        tempToken: _status.tempToken,
        errorMessage: e.message,
      ));
      rethrow;
    }
  }

  /// Complete login with recovery code.
  Future<void> verifyRecoveryCode(String code) async {
    if (_status.tempToken == null) {
      throw SyncException('No recovery session active');
    }

    try {
      await _api.validateRecovery(
        tempToken: _status.tempToken!,
        code: code,
      );
      // Recovery code accepted - user needs to login again
      _updateStatus(AuthStatus.unauthenticated);
    } on SyncException catch (e) {
      _updateStatus(AuthStatus(
        state: AuthState.totpRequired,
        tempToken: _status.tempToken,
        errorMessage: e.message,
      ));
      rethrow;
    }
  }

  Future<void> _handleLoginSuccess(LoginResponse response) async {
    // Store tokens securely
    await _storage.write(key: _refreshTokenKey, value: response.refreshToken);
    await _storage.write(key: _accessTokenKey, value: response.accessToken);
    await _storage.write(key: _userEmailKey, value: response.user.email);
    await _storage.write(key: _deviceIdKey, value: response.deviceId);

    _updateStatus(AuthStatus(
      state: AuthState.authenticated,
      user: response.user,
      deviceId: response.deviceId,
    ));
  }

  /// Logout from the current device.
  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      await _clearStoredTokens();
      _updateStatus(AuthStatus.unauthenticated);
    }
  }

  /// Logout from all devices.
  Future<void> logoutAll() async {
    try {
      await _api.logoutAll();
    } finally {
      await _clearStoredTokens();
      _updateStatus(AuthStatus.unauthenticated);
    }
  }

  Future<void> _clearStoredTokens() async {
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _deviceIdKey);
  }

  // --- TOTP Management ---

  /// Setup TOTP for the current user.
  Future<TOTPSetupResponse> setupTOTP() async {
    return _api.setupTOTP();
  }

  /// Verify and enable TOTP.
  Future<RecoveryCodesResponse> enableTOTP(String code) async {
    return _api.verifyTOTP(code);
  }

  /// Disable TOTP.
  Future<void> disableTOTP({
    required String code,
    required String password,
  }) async {
    return _api.disableTOTP(code: code, password: password);
  }

  /// Regenerate recovery codes.
  Future<RecoveryCodesResponse> regenerateRecoveryCodes(String code) async {
    return _api.regenerateRecoveryCodes(code);
  }

  // --- Device Management ---

  /// List all devices.
  Future<List<SyncDevice>> listDevices() async {
    return _api.listDevices();
  }

  /// Get current device info.
  Future<SyncDevice> getCurrentDevice() async {
    return _api.getCurrentDevice();
  }

  /// Rename a device.
  Future<void> renameDevice(String deviceId, String name) async {
    return _api.renameDevice(deviceId, name);
  }

  /// Delete a device (logout from that device).
  Future<void> deleteDevice(String deviceId) async {
    return _api.deleteDevice(deviceId);
  }

  /// Dispose resources.
  void dispose() {
    _statusController.close();
  }
}
