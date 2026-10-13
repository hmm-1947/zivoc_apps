import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../models/lead.dart';
import 'auth_service.dart';

class LeadException implements Exception {
  final String message;
  const LeadException(this.message);

  @override
  String toString() => message;
}

class LeadService {
  static const _timeout = Duration(seconds: 15);

  static Future<List<Lead>> fetch(AuthService auth) async {
    final http.Response response;
    try {
      response = await http
          .get(
            Env.uri('/api/method/custom_layer.drawing_auth.get_leads'),
            headers: auth.authHeaders(),
          )
          .timeout(_timeout);
    } on SocketException {
      throw const LeadException('Cannot reach the server.');
    } on TimeoutException {
      throw const LeadException('The server took too long to respond.');
    } on http.ClientException {
      throw const LeadException('Cannot reach the server.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw LeadException('Unexpected response from the server (${response.statusCode}).');
    }

    final message = body['message'];
    final data = message is Map<String, dynamic> ? message : body;

    if (response.statusCode != 200 || data['ok'] != true) {
      throw LeadException(data['message'] as String? ?? 'Could not load leads.');
    }

    final list = (data['leads'] as List<dynamic>? ?? const []);
    return list.map((e) => Lead.fromJson(e as Map<String, dynamic>)).toList();
  }
}
