class Task {
  final int id;
  final String title;
  final String description;
  final DateTime? createdAt;

  const Task({
    required this.id,
    required this.title,
    required this.description,
    this.createdAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '')?.toLocal(),
    );
  }
}
