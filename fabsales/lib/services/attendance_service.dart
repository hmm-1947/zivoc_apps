import 'package:http/http.dart' as http;
import 'dart:convert';

import '../config/env.dart';
import 'auth_service.dart';
import 'order_service.dart';

class AttendanceStatus {
  final String date;
  final String? status;
  final String? lastTime;
  final String? firstIn;

  const AttendanceStatus({required this.date, this.status, this.lastTime, this.firstIn});

  bool get isIn => status == 'IN';
  bool get isOut => status == 'OUT';

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) {
    return AttendanceStatus(
      date: json['date'] as String? ?? '',
      status: json['status'] as String?,
      lastTime: json['last_time'] as String?,
      firstIn: json['first_in'] as String?,
    );
  }
}

class AttendanceService {
  static Future<AttendanceStatus> fetch(AuthService auth) async {
    final data = await OrderService.send(
      () => http.get(
        Env.uri('/api/method/custom_layer.attendance.get_attendance'),
        headers: auth.authHeaders(),
      ),
      'Could not load attendance.',
    );
    return AttendanceStatus.fromJson(data);
  }

  static Future<AttendanceStatus> mark(AuthService auth, String logType) async {
    final data = await OrderService.send(
      () => http.post(
        Env.uri('/api/method/custom_layer.attendance.mark_attendance'),
        headers: {...auth.authHeaders(post: true), 'Content-Type': 'application/json'},
        body: jsonEncode({'log_type': logType}),
      ),
      'Could not update attendance.',
    );
    return AttendanceStatus.fromJson(data);
  }
}
