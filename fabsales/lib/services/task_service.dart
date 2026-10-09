import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../models/task.dart';

class TaskException implements Exception {
  final String message;
  const TaskException(this.message);

  @override
  String toString() => message;
}

class TaskService {
  static const _timeout = Duration(seconds: 15);

  static Future<List<Task>> fetch(String sid) async {
    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${Env.tasksBaseUrl}/api/tasks'),
            headers: {'Accept': 'application/json', 'X-ERP-SID': sid},
          )
          .timeout(_timeout);
    } on SocketException {
      throw const TaskException('Cannot reach the task server.');
    } on TimeoutException {
      throw const TaskException('The task server took too long to respond.');
    } on http.ClientException {
      throw const TaskException('Cannot reach the task server.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw TaskException('Unexpected response from the task server (${response.statusCode}).');
    }

    if (response.statusCode != 200) {
      throw TaskException(body['message'] as String? ?? 'Could not load tasks.');
    }

    final list = (body['tasks'] as List<dynamic>? ?? const []);
    return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }
}
