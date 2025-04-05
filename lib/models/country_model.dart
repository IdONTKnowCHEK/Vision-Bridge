class CountryResponse {
  final bool success;
  final String mappingCountry;

  CountryResponse({required this.success, required this.mappingCountry});

  factory CountryResponse.fromJson(Map<String, dynamic> json) {
    return CountryResponse(
      success: json['Success'] ?? false,
      mappingCountry: json['MappingCountry'] ?? '',
    );
  }
}