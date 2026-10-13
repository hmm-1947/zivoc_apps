class Lead {
  final String name;
  final String leadName;
  final String companyName;
  final String email;
  final String phone;
  final String status;
  final DateTime? createdAt;

  const Lead({
    required this.name,
    required this.leadName,
    required this.companyName,
    required this.email,
    required this.phone,
    required this.status,
    this.createdAt,
  });

  String get displayName {
    if (leadName.isNotEmpty) return leadName;
    if (companyName.isNotEmpty) return companyName;
    return name;
  }

  factory Lead.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] as String?)?.trim() ?? '';
    final mobile = text('mobile_no');
    return Lead(
      name: text('name'),
      leadName: text('lead_name'),
      companyName: text('company_name'),
      email: text('email_id'),
      phone: mobile.isNotEmpty ? mobile : text('phone'),
      status: text('status'),
      createdAt: DateTime.tryParse(text('creation'))?.toLocal(),
    );
  }
}
