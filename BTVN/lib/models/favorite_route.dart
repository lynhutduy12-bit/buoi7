import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/map_api_service.dart';
import 'route_result.dart';
import 'travel_mode.dart';

class FavoriteRoute {
  final int? id;
  final String name;
  final String startText;
  final String endText;
  final LatLng start;
  final LatLng end;
  final TravelMode mode;
  final int distanceMeters;
  final int durationSeconds;
  final String polyline;
  final DateTime createdAt;

  FavoriteRoute({
    this.id,
    required this.name,
    required this.startText,
    required this.endText,
    required this.start,
    required this.end,
    required this.mode,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
    required this.createdAt,
  });

  RouteResult toRouteResult() {
    return RouteResult(
      points: MapApiService.decodePolyline(polyline),
      encodedPolyline: polyline,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      mode: mode,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'start_text': startText,
      'end_text': endText,
      'start_lat': start.latitude,
      'start_lng': start.longitude,
      'end_lat': end.latitude,
      'end_lng': end.longitude,
      'mode': mode.name,
      'distance': distanceMeters,
      'duration': durationSeconds,
      'polyline': polyline,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static FavoriteRoute fromMap(Map<String, Object?> map) {
    return FavoriteRoute(
      id: map['id'] as int?,
      name: map['name'] as String,
      startText: map['start_text'] as String,
      endText: map['end_text'] as String,
      start: LatLng(
        (map['start_lat'] as num).toDouble(),
        (map['start_lng'] as num).toDouble(),
      ),
      end: LatLng(
        (map['end_lat'] as num).toDouble(),
        (map['end_lng'] as num).toDouble(),
      ),
      mode: TravelModeInfo.fromName(map['mode'] as String),
      distanceMeters: (map['distance'] as num).toInt(),
      durationSeconds: (map['duration'] as num).toInt(),
      polyline: map['polyline'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
