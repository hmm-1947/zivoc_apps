import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/sales_summary.dart';
import 'auth_service.dart';

class OrderException implements Exception {
  final String message;
  const OrderException(this.message);

  @override
  String toString() => message;
}

class NewLead {
  final String firstName;
  final String middleName;
  final String lastName;
  final String organization;
  final String jobTitle;
  final String mobile;

  const NewLead({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.organization,
    required this.jobTitle,
    required this.mobile,
  });

  Map<String, String> toJson() => {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'company_name': organization,
        'job_title': jobTitle,
        'mobile_no': mobile,
      };
}

class OrderService {
  static const _timeout = Duration(seconds: 20);

  static Future<Map<String, dynamic>> send(Future<http.Response> Function() call, String fallback) async {
    final http.Response response;
    try {
      response = await call().timeout(_timeout);
    } on SocketException {
      throw const OrderException('Cannot reach the server.');
    } on TimeoutException {
      throw const OrderException('The server took too long to respond.');
    } on http.ClientException {
      throw const OrderException('Cannot reach the server.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw OrderException('Unexpected response from the server (${response.statusCode}).');
    }

    final message = body['message'];
    final data = message is Map<String, dynamic> ? message : body;

    if (response.statusCode != 200 || data['ok'] != true) {
      throw OrderException(data['message'] as String? ?? fallback);
    }
    return data;
  }

  static Future<List<Product>> fetchProducts(AuthService auth) async {
    final data = await send(
      () => http.get(
        Env.uri('/api/method/custom_layer.orders.get_products'),
        headers: auth.authHeaders(),
      ),
      'Could not load products.',
    );
    final list = data['items'] as List<dynamic>? ?? const [];
    return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Order>> fetchOrders(AuthService auth) async {
    final data = await send(
      () => http.get(
        Env.uri('/api/method/custom_layer.orders.get_my_orders'),
        headers: auth.authHeaders(),
      ),
      'Could not load orders.',
    );
    final list = data['orders'] as List<dynamic>? ?? const [];
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<SalesSummary> fetchSummary(AuthService auth) async {
    final data = await send(
      () => http.get(
        Env.uri('/api/method/custom_layer.commission.get_commission'),
        headers: auth.authHeaders(),
      ),
      'Could not load sales summary.',
    );
    return SalesSummary.fromJson(data);
  }

  static Future<String> createOrder(
    AuthService auth, {
    required List<String> items,
    String? lead,
    NewLead? newLead,
  }) async {
    final data = await send(
      () => http.post(
        Env.uri('/api/method/custom_layer.orders.create_order'),
        headers: {...auth.authHeaders(post: true), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'items': items,
          if (lead != null) 'lead': lead,
          if (newLead != null) 'new_lead': newLead.toJson(),
        }),
      ),
      'Could not create the order.',
    );
    return data['order'] as String? ?? '';
  }
}
