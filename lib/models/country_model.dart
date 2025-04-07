class CountryResponse {
  final bool success;
  final String content;

  CountryResponse({required this.success, required this.content});

  factory CountryResponse.fromJson(Map<String, dynamic> json) {
    return CountryResponse(
      success: json['success'] ?? false,
      content: json['content'] ?? '',
    );
  }
}