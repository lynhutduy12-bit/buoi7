import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/place_result.dart';
import '../models/route_result.dart';

class MapApiException implements Exception {
  final String message;
  MapApiException(this.message);

  @override
  String toString() => message;
}

class MapApiService {
  final String apiKey;

  MapApiService({this.apiKey = AppConfig.apiKey});

  Future<RouteResult?> getRoute(LatLng origin, LatLng destination) async {
    try {
      return await _directionsApi(origin, destination);
    } on MapApiException catch (e) {
      if (!e.message.contains('REQUEST_DENIED') &&
          !e.message.contains('legacy')) {
        rethrow;
      }
      return await _routesApi(origin, destination);
    }
  }

  Future<RouteResult?> _directionsApi(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=driving&language=vi&key=$apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw MapApiException('Lỗi khi gọi API: ${response.statusCode}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final status = data['status'] as String? ?? '';

    if (status == 'ZERO_RESULTS') return null;
    if (status != 'OK') {
      throw MapApiException('$status ${data['error_message'] ?? ''}'.trim());
    }

    final route = data['routes'][0];
    final leg = route['legs'][0];
    return RouteResult(
      points: decodePolyline(route['overview_polyline']['points']),
      distanceText: leg['distance']['text'],
      durationText: leg['duration']['text'],
    );
  }

  Future<RouteResult?> _routesApi(LatLng origin, LatLng destination) async {
    final response = await http.post(
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
      },
      body: jsonEncode({
        'origin': {
          'location': {
            'latLng': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            },
          },
        },
        'destination': {
          'location': {
            'latLng': {
              'latitude': destination.latitude,
              'longitude': destination.longitude,
            },
          },
        },
        'travelMode': 'DRIVE',
        'languageCode': 'vi',
      }),
    );

    final Map<String, dynamic> data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final message = data['error']?['message'] ?? response.statusCode;
      throw MapApiException('Lỗi Routes API: $message');
    }

    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes[0];
    final meters = (route['distanceMeters'] ?? 0) as num;
    final seconds =
        int.tryParse((route['duration'] ?? '0s').toString().replaceAll('s', '')) ??
            0;

    return RouteResult(
      points: decodePolyline(route['polyline']['encodedPolyline']),
      distanceText: formatDistance(meters),
      durationText: formatDuration(seconds),
    );
  }

  Future<List<PlaceResult>> searchPlaces(String query, LatLng center) async {
    try {
      return await _placesNew(query, center);
    } on MapApiException {
      return await _placesLegacy(query, center);
    }
  }

  Future<List<PlaceResult>> _placesNew(String query, LatLng center) async {
    final response = await http.post(
      Uri.parse('https://places.googleapis.com/v1/places:searchText'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'places.displayName,places.formattedAddress,places.location',
      },
      body: jsonEncode({
        'textQuery': query,
        'languageCode': 'vi',
        'maxResultCount': 20,
        'locationBias': {
          'circle': {
            'center': {
              'latitude': center.latitude,
              'longitude': center.longitude,
            },
            'radius': 5000.0,
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      throw MapApiException('Places API (New): ${response.statusCode}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final places = (data['places'] as List?) ?? [];
    return places.map((p) {
      return PlaceResult(
        name: p['displayName']?['text'] ?? 'Không tên',
        address: p['formattedAddress'] ?? '',
        location: LatLng(
          (p['location']['latitude'] as num).toDouble(),
          (p['location']['longitude'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  Future<List<PlaceResult>> _placesLegacy(String query, LatLng center) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json'
      '?query=${Uri.encodeComponent(query)}'
      '&location=${center.latitude},${center.longitude}'
      '&radius=5000&language=vi&key=$apiKey',
    );

    final response = await http.get(url);
    final Map<String, dynamic> data = jsonDecode(response.body);
    final status = data['status'] as String? ?? '';

    if (status == 'ZERO_RESULTS') return [];
    if (status != 'OK') {
      throw MapApiException('$status ${data['error_message'] ?? ''}'.trim());
    }

    final results = data['results'] as List;
    return results.map((p) {
      final loc = p['geometry']['location'];
      return PlaceResult(
        name: p['name'] ?? 'Không tên',
        address: p['formatted_address'] ?? '',
        location: LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  static String formatDistance(num meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String formatDuration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes phút';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h giờ' : '$h giờ $m phút';
  }

  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    final int len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}
