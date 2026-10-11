import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/place_result.dart';
import '../models/route_result.dart';
import '../models/travel_mode.dart';

class MapApiException implements Exception {
  final String message;
  MapApiException(this.message);

  @override
  String toString() => message;
}

class GeocodeResult {
  final LatLng location;
  final String address;

  GeocodeResult(this.location, this.address);
}

class MapApiService {
  final String apiKey;

  MapApiService({this.apiKey = AppConfig.apiKey});

  Future<List<RouteResult>> getRoutes(
    LatLng origin,
    LatLng destination,
    TravelMode mode,
  ) async {
    final List<RouteResult> routes;
    if (mode == TravelMode.motorbike) {
      routes = await _tryBoth(
        () => _routesApi(origin, destination, mode),
        () => _directionsApi(origin, destination, mode),
      );
    } else {
      routes = await _tryBoth(
        () => _directionsApi(origin, destination, mode),
        () => _routesApi(origin, destination, mode),
      );
    }
    routes.sort((a, b) {
      final byTime = a.durationSeconds.compareTo(b.durationSeconds);
      return byTime != 0 ? byTime : a.distanceMeters.compareTo(b.distanceMeters);
    });
    return routes;
  }

  Future<List<RouteResult>> _tryBoth(
    Future<List<RouteResult>> Function() first,
    Future<List<RouteResult>> Function() second,
  ) async {
    try {
      return await first();
    } on MapApiException catch (e1) {
      try {
        return await second();
      } on MapApiException catch (e2) {
        throw MapApiException('$e1 | $e2');
      }
    }
  }

  Future<List<RouteResult>> _directionsApi(
    LatLng origin,
    LatLng destination,
    TravelMode mode,
  ) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=${mode.directionsMode}'
      '&alternatives=true&language=vi&key=$apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw MapApiException('Directions API: ${response.statusCode}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final status = data['status'] as String? ?? '';
    if (status == 'ZERO_RESULTS') return [];
    if (status != 'OK') {
      throw MapApiException(
        'Directions API: $status ${data['error_message'] ?? ''}'.trim(),
      );
    }

    final routes = data['routes'] as List;
    return routes.map((route) {
      final leg = route['legs'][0];
      final encoded = route['overview_polyline']['points'] as String;
      return RouteResult(
        points: decodePolyline(encoded),
        encodedPolyline: encoded,
        distanceMeters: (leg['distance']['value'] as num).toInt(),
        durationSeconds: (leg['duration']['value'] as num).toInt(),
        mode: mode,
        summary: route['summary'] ?? '',
      );
    }).toList();
  }

  Future<List<RouteResult>> _routesApi(
    LatLng origin,
    LatLng destination,
    TravelMode mode,
  ) async {
    final response = await http.post(
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.description',
      },
      body: jsonEncode({
        'origin': _waypoint(origin),
        'destination': _waypoint(destination),
        'travelMode': mode.routesMode,
        'computeAlternativeRoutes': true,
        'languageCode': 'vi',
      }),
    );

    final Map<String, dynamic> data =
        response.body.isEmpty ? {} : jsonDecode(response.body);
    if (response.statusCode != 200) {
      final message = data['error']?['message'] ?? response.statusCode;
      throw MapApiException('Routes API: $message');
    }

    final routes = (data['routes'] as List?) ?? [];
    return routes.map((route) {
      final encoded = route['polyline']['encodedPolyline'] as String;
      final seconds = int.tryParse(
            (route['duration'] ?? '0s').toString().replaceAll('s', ''),
          ) ??
          0;
      return RouteResult(
        points: decodePolyline(encoded),
        encodedPolyline: encoded,
        distanceMeters: ((route['distanceMeters'] ?? 0) as num).toInt(),
        durationSeconds: seconds,
        mode: mode,
        summary: route['description'] ?? '',
      );
    }).toList();
  }

  Map<String, dynamic> _waypoint(LatLng p) => {
        'location': {
          'latLng': {'latitude': p.latitude, 'longitude': p.longitude},
        },
      };

  Future<GeocodeResult?> geocode(String address) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(address)}'
        '&region=vn&language=vi&key=$apiKey',
      );
      final response = await http.get(url);
      final Map<String, dynamic> data = jsonDecode(response.body);
      final status = data['status'] as String? ?? '';

      if (status == 'ZERO_RESULTS') return null;
      if (status != 'OK') {
        throw MapApiException(
          'Geocoding API: $status ${data['error_message'] ?? ''}'.trim(),
        );
      }

      final first = data['results'][0];
      final loc = first['geometry']['location'];
      return GeocodeResult(
        LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()),
        first['formatted_address'] ?? address,
      );
    } on MapApiException {
      final places = await _placesNew(address, null);
      if (places.isEmpty) return null;
      return GeocodeResult(places.first.location, places.first.address);
    }
  }

  Future<List<PlaceResult>> searchPlaces(String query, LatLng center) async {
    try {
      return await _placesNew(query, center);
    } on MapApiException {
      return await _placesLegacy(query, center);
    }
  }

  Future<List<PlaceResult>> _placesNew(String query, LatLng? center) async {
    final body = <String, dynamic>{
      'textQuery': query,
      'languageCode': 'vi',
      'regionCode': 'VN',
      'maxResultCount': 20,
    };
    if (center != null) {
      body['locationBias'] = {
        'circle': {
          'center': {
            'latitude': center.latitude,
            'longitude': center.longitude,
          },
          'radius': 5000.0,
        },
      };
    }

    final response = await http.post(
      Uri.parse('https://places.googleapis.com/v1/places:searchText'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'places.displayName,places.formattedAddress,places.location',
      },
      body: jsonEncode(body),
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
      throw MapApiException(
        'Places API: $status ${data['error_message'] ?? ''}'.trim(),
      );
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
