import 'dart:convert';

enum MeasurementType { polygon, circle }

class Measurement {
  final String id;
  final String name;
  final MeasurementType type;
  final double areaM2;
  final double perimeterM;
  final DateTime createdAt;
  // For polygon
  final List<Map<String, double>>? points;
  // For circle
  final double? centerLat;
  final double? centerLng;
  final double? radiusM;

  Measurement({
    required this.id,
    required this.name,
    required this.type,
    required this.areaM2,
    required this.perimeterM,
    required this.createdAt,
    this.points,
    this.centerLat,
    this.centerLng,
    this.radiusM,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'areaM2': areaM2,
        'perimeterM': perimeterM,
        'createdAt': createdAt.toIso8601String(),
        'points': points,
        'centerLat': centerLat,
        'centerLng': centerLng,
        'radiusM': radiusM,
      };

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
        id: json['id'],
        name: json['name'],
        type: MeasurementType.values.firstWhere((e) => e.name == json['type']),
        areaM2: (json['areaM2'] as num).toDouble(),
        perimeterM: (json['perimeterM'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt']),
        points: json['points'] != null
            ? List<Map<String, double>>.from(
                (json['points'] as List)
                    .map((e) => Map<String, double>.from(e as Map)),
              )
            : null,
        centerLat: json['centerLat'] != null
            ? (json['centerLat'] as num).toDouble()
            : null,
        centerLng: json['centerLng'] != null
            ? (json['centerLng'] as num).toDouble()
            : null,
        radiusM:
            json['radiusM'] != null ? (json['radiusM'] as num).toDouble() : null,
      );

  String toJsonString() => jsonEncode(toJson());

  factory Measurement.fromJsonString(String s) =>
      Measurement.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

