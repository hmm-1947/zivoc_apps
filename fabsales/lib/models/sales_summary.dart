class SalesSummary {
  final double target;
  final double achieved;
  final double earned;

  const SalesSummary({required this.target, required this.achieved, required this.earned});

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return SalesSummary(
      target: number('target'),
      achieved: number('achieved'),
      earned: number('earned'),
    );
  }
}
