import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get baseUrl {
    final raw = (dotenv.maybeGet('ERP_BASE_URL') ?? '').trim();
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static String get siteName => (dotenv.maybeGet('ERP_SITE_NAME') ?? '').trim();

  static String get tasksBaseUrl {
    final raw = (dotenv.maybeGet('TASKS_API_URL') ?? '').trim();
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static List<String> get allowedRoles =>
      (dotenv.maybeGet('TASK_ROLES') ?? 'Fabricator,Sales User')
          .split(',')
          .map((r) => r.trim())
          .where((r) => r.isNotEmpty)
          .toList();

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
}
