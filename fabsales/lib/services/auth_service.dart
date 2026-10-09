import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';

enum AuthStatus { checking, signedOut, signedIn }

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  static const _timeout = Duration(seconds: 15);
  static const _keySid = 'erp_sid';
  static const _keyCsrf = 'erp_csrf';
  static const _keyUser = 'erp_user';
  static const _keyName = 'erp_full_name';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthStatus _status = AuthStatus.checking;
  String? _sid;
  String? _csrf;
  String? _user;
  String? _fullName;

  AuthStatus get status => _status;
  String? get user => _user;
  String? get fullName => _fullName;
  String? get sid => _sid;

  Map<String, String> authHeaders({bool post = false}) {
    return {
      'Accept': 'application/json',
      if (Env.siteName.isNotEmpty) 'X-Frappe-Site-Name': Env.siteName,
      if (_sid != null) 'Cookie': 'sid=$_sid',
      if (post && _csrf != null) 'X-Frappe-CSRF-Token': _csrf!,
    };
  }

  Future<void> restore() async {
    _sid = await _storage.read(key: _keySid);
    _csrf = await _storage.read(key: _keyCsrf);
    _user = await _storage.read(key: _keyUser);
    _fullName = await _storage.read(key: _keyName);

    if (_sid == null || _user == null) {
      await _clear();
      return;
    }

    try {
      final response = await http
          .get(
            Env.uri('/api/method/custom_layer.drawing_auth.me'),
            headers: authHeaders(),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = _message(response);
        if (data['ok'] == true) {
          _csrf = data['csrf_token'] as String? ?? _csrf;
          _fullName = data['full_name'] as String? ?? _fullName;
          await _persist();
          _status = AuthStatus.signedIn;
          notifyListeners();
          return;
        }
      }

      await _clear();
    } on SocketException {
      _status = AuthStatus.signedIn;
      notifyListeners();
    } on TimeoutException {
      _status = AuthStatus.signedIn;
      notifyListeners();
    } on http.ClientException {
      _status = AuthStatus.signedIn;
      notifyListeners();
    } on FormatException {
      await _clear();
    }
  }

  Future<void> login(String username, String password) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Env.uri('/api/method/custom_layer.drawing_auth.login'),
            headers: authHeaders(),
            body: {'usr': username.trim(), 'pwd': password},
          )
          .timeout(_timeout);
    } on SocketException {
      throw const AuthException('Cannot reach the server. Check your connection and the server address.');
    } on TimeoutException {
      throw const AuthException('The server took too long to respond.');
    } on http.ClientException {
      throw const AuthException('Cannot reach the server. Check your connection and the server address.');
    }

    Map<String, dynamic> data;
    try {
      data = _message(response);
    } on FormatException {
      throw AuthException('Unexpected response from the server (${response.statusCode}).');
    }

    if (response.statusCode != 200 || data['ok'] != true) {
      throw AuthException(data['message'] as String? ?? 'Login failed.');
    }

    final newSid = data['sid'] as String;
    final allowed = await _hasAllowedRole(newSid);
    if (!allowed) {
      try {
        await http
            .post(
              Env.uri('/api/method/custom_layer.drawing_auth.logout'),
              headers: {
                'Accept': 'application/json',
                if (Env.siteName.isNotEmpty) 'X-Frappe-Site-Name': Env.siteName,
                'Cookie': 'sid=$newSid',
                if (data['csrf_token'] != null) 'X-Frappe-CSRF-Token': data['csrf_token'] as String,
              },
            )
            .timeout(_timeout);
      } catch (_) {}
      throw const AuthException('Only fabricators and salesmen can sign in.');
    }

    _sid = newSid;
    _csrf = data['csrf_token'] as String?;
    _user = data['user'] as String;
    _fullName = data['full_name'] as String? ?? _user;
    await _persist();
    _status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> logout() async {
    final headers = authHeaders(post: true);
    await _clear();
    try {
      await http
          .post(
            Env.uri('/api/method/custom_layer.drawing_auth.logout'),
            headers: headers,
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<bool> _hasAllowedRole(String sid) async {
    final http.Response response;
    try {
      response = await http
          .get(
            Env.uri('/api/method/frappe.core.doctype.user.user.get_roles'),
            headers: {
              'Accept': 'application/json',
              if (Env.siteName.isNotEmpty) 'X-Frappe-Site-Name': Env.siteName,
              'Cookie': 'sid=$sid',
            },
          )
          .timeout(_timeout);
    } on SocketException {
      throw const AuthException('Cannot reach the server. Check your connection and the server address.');
    } on TimeoutException {
      throw const AuthException('The server took too long to respond.');
    } on http.ClientException {
      throw const AuthException('Cannot reach the server. Check your connection and the server address.');
    }

    if (response.statusCode != 200) {
      throw AuthException('Could not verify your role (${response.statusCode}).');
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final roles = decoded is Map ? decoded['message'] : null;
      if (roles is! List) return false;
      final allowed = Env.allowedRoles.toSet();
      return roles.any((r) => allowed.contains(r.toString()));
    } on FormatException {
      throw const AuthException('Could not verify your role.');
    }
  }
  Map<String, dynamic> _message(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      if (message is Map<String, dynamic>) return message;
      return decoded;
    }
    throw const FormatException('Unexpected payload');
  }

  Future<void> _persist() async {
    await _storage.write(key: _keySid, value: _sid);
    await _storage.write(key: _keyCsrf, value: _csrf);
    await _storage.write(key: _keyUser, value: _user);
    await _storage.write(key: _keyName, value: _fullName);
  }

  Future<void> _clear() async {
    _sid = null;
    _csrf = null;
    _user = null;
    _fullName = null;
    await _storage.delete(key: _keySid);
    await _storage.delete(key: _keyCsrf);
    await _storage.delete(key: _keyUser);
    await _storage.delete(key: _keyName);
    _status = AuthStatus.signedOut;
    notifyListeners();
  }
}
