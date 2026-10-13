import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/lead.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/sales_summary.dart';
import '../models/task.dart';
import 'auth_service.dart';
import 'lead_service.dart';
import 'order_service.dart';
import 'task_service.dart';

class DataStore extends ChangeNotifier with WidgetsBindingObserver {
  DataStore(this._auth, {this.pollInterval = const Duration(seconds: 20)});

  final AuthService _auth;
  final Duration pollInterval;

  List<Task>? tasks;
  List<Lead>? leads;
  String? tasksError;
  String? leadsError;
  List<Product>? products;
  String? productsError;
  List<Order>? orders;
  String? ordersError;
  SalesSummary? summary;

  Timer? _timer;
  Future<void>? _inflight;
  bool _disposed = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    refresh();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() {
    return _inflight ??= Future.wait([_loadTasks(), _loadLeads(), _loadProducts(), _loadOrders(), _loadSummary()])
        .then((_) {})
        .whenComplete(() => _inflight = null);
  }

  Future<void> _loadTasks() async {
    try {
      tasks = await TaskService.fetch(_auth.sid ?? '');
      tasksError = null;
    } catch (e) {
      tasksError = e.toString();
    }
    _notify();
  }

  Future<void> _loadLeads() async {
    try {
      leads = await LeadService.fetch(_auth);
      leadsError = null;
    } catch (e) {
      leadsError = e.toString();
    }
    _notify();
  }

  Future<void> _loadSummary() async {
    try {
      summary = await OrderService.fetchSummary(_auth);
    } catch (_) {}
    _notify();
  }

  Future<void> _loadOrders() async {
    try {
      orders = await OrderService.fetchOrders(_auth);
      ordersError = null;
    } catch (e) {
      ordersError = e.toString();
    }
    _notify();
  }

  Future<void> _loadProducts() async {
    try {
      products = await OrderService.fetchProducts(_auth);
      productsError = null;
    } catch (e) {
      productsError = e.toString();
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
