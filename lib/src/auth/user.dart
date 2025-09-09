import 'dart:async';
import 'dart:convert';
import '../gun.dart';
import '../gun_chain.dart';
import '../types/types.dart';
import 'sea.dart';

/// User authentication system for Gun Dart
/// Provides secure user registration, login, and session management
class User {
  final Gun _gun;
  SEAKeyPair? _keyPair;
  String? _alias;
  bool _isAuthenticated = false;
  final StreamController<UserEvent> _eventController =
      StreamController.broadcast();

  User(this._gun);

  /// Current user alias (username)
  String? get alias => _alias;

  /// Whether user is currently authenticated
  bool get isAuthenticated => _isAuthenticated;

  /// Current user's key pair
  SEAKeyPair? get keyPair => _keyPair;

  /// Stream of user authentication events
  Stream<UserEvent> get events => _eventController.stream;

  /// Create a new user account
  Future<UserAccount> create(String alias, String password) async {
    if (alias.isEmpty || password.isEmpty) {
      throw UserException('Alias and password cannot be empty');
    }

    // Check if user already exists
    final existingUser = await _gun.get('~@$alias').once();
    if (existingUser != null) {
      throw UserException('User already exists');
    }

    // Generate key pair
    final keyPair = await SEA.pair();

    // Create user data
    final userData = {
      'alias': alias,
      'pub': keyPair.pub,
      'epub': keyPair.epub,
    };

    // Encrypt private keys with password
    final encryptedAuth = await SEA.encrypt({
      'priv': keyPair.priv,
      'epriv': keyPair.epriv,
    }, password);

    userData['auth'] = encryptedAuth;

    // Store user data
    await _gun.get('~@$alias').put(userData);
    await _gun.get('~${keyPair.pub}').put(userData);

    // Automatically authenticate the newly created user
    _keyPair = keyPair;
    _alias = alias;
    _isAuthenticated = true;

    // Create user account object
    final account = UserAccount(
      alias: alias,
      pub: keyPair.pub,
      epub: keyPair.epub,
    );

    _eventController.add(UserEvent(
      type: UserEventType.created,
      alias: alias,
      account: account,
    ));

    return account;
  }

  /// Authenticate user with alias and password
  Future<UserAccount> auth(String alias, String password) async {
    if (alias.isEmpty || password.isEmpty) {
      throw UserException('Alias and password cannot be empty');
    }

    // Get user data
    final userData = await _gun.get('~@$alias').once() as Map<String, dynamic>?;
    if (userData == null) {
      throw UserException('User not found');
    }

    try {
      // Decrypt authentication data
      final authData = await SEA.decrypt(userData['auth'] as String, password)
          as Map<String, dynamic>;

      // Reconstruct key pair
      _keyPair = SEAKeyPair(
        pub: userData['pub'] as String,
        priv: authData['priv'] as String,
        epub: userData['epub'] as String,
        epriv: authData['epriv'] as String,
      );

      _alias = alias;
      _isAuthenticated = true;

      final account = UserAccount(
        alias: alias,
        pub: _keyPair!.pub,
        epub: _keyPair!.epub,
      );

      _eventController.add(UserEvent(
        type: UserEventType.authenticated,
        alias: alias,
        account: account,
      ));

      return account;
    } catch (e) {
      throw UserException('Invalid password');
    }
  }

  /// Sign out current user
  Future<void> leave() async {
    if (!_isAuthenticated) return;

    final oldAlias = _alias;

    _keyPair = null;
    _alias = null;
    _isAuthenticated = false;

    _eventController.add(UserEvent(
      type: UserEventType.signedOut,
      alias: oldAlias,
    ));
  }

  /// Get user account by alias
  Future<UserAccount?> recall(String alias) async {
    final userData = await _gun.get('~@$alias').once() as Map<String, dynamic>?;
    if (userData == null) return null;

    return UserAccount(
      alias: alias,
      pub: userData['pub'] as String,
      epub: userData['epub'] as String,
    );
  }

  /// Encrypt data for current user
  Future<String> encrypt(dynamic data, [String? forPublicKey]) async {
    if (!_isAuthenticated || _keyPair == null) {
      throw UserException('User not authenticated');
    }

    // Use user's encryption private key as password for now
    // In a full implementation, this would use proper public key encryption
    return await SEA.encrypt(data, _keyPair!.epriv);
  }

  /// Decrypt data for current user
  Future<dynamic> decrypt(String encryptedData) async {
    if (!_isAuthenticated || _keyPair == null) {
      throw UserException('User not authenticated');
    }

    return await SEA.decrypt(encryptedData, _keyPair!.epriv);
  }

  /// Sign data with current user's private key
  Future<String> sign(dynamic data) async {
    if (!_isAuthenticated || _keyPair == null) {
      throw UserException('User not authenticated');
    }

    return await SEA.sign(data, _keyPair!);
  }

  /// Verify signature with public key
  Future<bool> verify(dynamic data, String signature, String publicKey) async {
    return await SEA.verify(data, signature, publicKey);
  }

  /// Change user password
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (!_isAuthenticated || _alias == null) {
      throw UserException('User not authenticated');
    }

    // Re-authenticate with old password to verify
    await auth(_alias!, oldPassword);

    // Encrypt private keys with new password
    final newEncryptedAuth = await SEA.encrypt({
      'priv': _keyPair!.priv,
      'epriv': _keyPair!.epriv,
    }, newPassword);

    // Update user data
    await _gun.get('~@$_alias').get('auth').put(newEncryptedAuth);
    await _gun.get('~${_keyPair!.pub}').get('auth').put(newEncryptedAuth);

    _eventController.add(UserEvent(
      type: UserEventType.passwordChanged,
      alias: _alias,
    ));
  }

  /// Delete user account (irreversible)
  Future<void> delete(String password) async {
    if (!_isAuthenticated || _alias == null) {
      throw UserException('User not authenticated');
    }

    // Re-authenticate to verify password
    await auth(_alias!, password);

    // Delete user data
    await _gun.get('~@$_alias').put(null);
    await _gun.get('~${_keyPair!.pub}').put(null);

    final deletedAlias = _alias;

    // Clear local state
    await leave();

    _eventController.add(UserEvent(
      type: UserEventType.deleted,
      alias: deletedAlias,
    ));
  }

  /// Get user's secure storage reference
  GunChain get storage {
    if (!_isAuthenticated || _keyPair == null) {
      throw UserException('User not authenticated');
    }

    return _gun.get('~${_keyPair!.pub}');
  }

  /// Dispose user resources
  Future<void> dispose() async {
    await _eventController.close();
  }
}

/// User account information
class UserAccount {
  final String alias;
  final String pub;
  final String epub;

  const UserAccount({
    required this.alias,
    required this.pub,
    required this.epub,
  });

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'pub': pub,
        'epub': epub,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        alias: json['alias'] as String,
        pub: json['pub'] as String,
        epub: json['epub'] as String,
      );

  @override
  String toString() =>
      'UserAccount(alias: $alias, pub: ${pub.substring(0, 8)}...)';
}

/// User event types
enum UserEventType {
  created,
  authenticated,
  signedOut,
  passwordChanged,
  deleted,
}

/// User authentication event
class UserEvent {
  final UserEventType type;
  final String? alias;
  final UserAccount? account;
  final DateTime timestamp;

  UserEvent({
    required this.type,
    this.alias,
    this.account,
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'UserEvent(type: $type, alias: $alias)';
}

/// User authentication exception
class UserException implements Exception {
  final String message;

  const UserException(this.message);

  @override
  String toString() => 'UserException: $message';
}
