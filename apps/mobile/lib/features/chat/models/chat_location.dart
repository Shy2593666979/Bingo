class ChatLocation {
  const ChatLocation(
      {required this.name,
      required this.address,
      this.province = '',
      this.city = '',
      this.district = '',
      this.longitude,
      this.latitude,
      this.source = 'poi',
      this.precision = 'point',
      this.accuracyMeters});
  final String name;
  final String address;
  final String province;
  final String city;
  final String district;
  final double? longitude;
  final double? latitude;
  final String source;
  final String precision;
  final double? accuracyMeters;
  bool get hasCoordinates => longitude != null && latitude != null;
  String get region => province + (city == province ? '' : city) + district;
  ChatLocation asRegion() => ChatLocation(
      name: region,
      address: region,
      province: province,
      city: city,
      district: district,
      source: 'user_shared_region',
      precision: 'district');
  ChatLocation withSource(String value,
          {String? label, String? precision, double? accuracy}) =>
      ChatLocation(
          name: label ?? name,
          address: address,
          province: province,
          city: city,
          district: district,
          longitude: longitude,
          latitude: latitude,
          source: value,
          precision: precision ?? this.precision,
          accuracyMeters: accuracy);
  factory ChatLocation.fromJson(Map<String, dynamic> json) => ChatLocation(
      name: json['name'] as String,
      address: json['address'] as String,
      province: json['province'] as String? ?? '',
      city: json['city'] as String? ?? '',
      district: json['district'] as String? ?? '',
      longitude: (json['longitude'] as num?)?.toDouble(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      source: json['source'] as String? ?? 'poi',
      precision: json['precision'] as String? ?? 'point',
      accuracyMeters: (json['accuracy_m'] as num?)?.toDouble());
  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'province': province,
        'city': city,
        'district': district,
        'source': source,
        'precision': precision,
        'coordinate_system': 'GCJ-02',
        if (longitude != null) 'longitude': longitude,
        if (latitude != null) 'latitude': latitude,
        if (accuracyMeters != null) 'accuracy_m': accuracyMeters,
      };
}
