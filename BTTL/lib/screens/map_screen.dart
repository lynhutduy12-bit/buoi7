import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/place_result.dart';
import '../models/route_result.dart';
import '../services/map_api_service.dart';

enum PickTarget { start, end }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(10.7769, 106.7009),
    zoom: 14,
  );

  static const Map<String, String> _categories = {
    'Khách sạn': 'khách sạn',
    'Quán ăn': 'quán ăn',
    'Bệnh viện': 'bệnh viện',
    'Trường học': 'trường học',
    'Cây xăng': 'cây xăng',
    'ATM': 'ATM',
  };

  final Completer<GoogleMapController> _controller = Completer();
  final MapApiService _api = MapApiService();
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _currentPosition;
  LatLng? _startLatLng;
  LatLng? _endLatLng;
  LatLng _cameraCenter = _initialPosition.target;
  PickTarget _pickTarget = PickTarget.end;

  RouteResult? _route;
  List<PlaceResult> _places = [];
  String? _selectedCategory;
  bool _loadingRoute = false;
  bool _loadingPlaces = false;
  bool _panelExpanded = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation(setAsStart: true);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _format(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';

  LatLng? _parseLatLng(String text) {
    final parts = text.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return LatLng(lat, lng);
  }

  Future<LatLng?> _getCurrentLocation({
    bool setAsStart = false,
    bool setAsEnd = false,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showMessage('Vui lòng bật dịch vụ vị trí (GPS)!');
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showMessage('Ứng dụng chưa được cấp quyền vị trí');
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final latLng = LatLng(position.latitude, position.longitude);
      if (!mounted) return latLng;

      setState(() {
        _currentPosition = latLng;
        if (setAsStart) {
          _startLatLng = latLng;
          _startController.text = _format(latLng);
        }
        if (setAsEnd) {
          _endLatLng = latLng;
          _endController.text = _format(latLng);
        }
        _route = null;
      });
      await _moveCamera(latLng);
      return latLng;
    } catch (e) {
      _showMessage('Không lấy được vị trí hiện tại');
      return null;
    }
  }

  Future<void> _moveCamera(LatLng position, {double? zoom}) async {
    final controller = await _controller.future;
    await controller.animateCamera(
      zoom == null
          ? CameraUpdate.newLatLng(position)
          : CameraUpdate.newLatLngZoom(position, zoom),
    );
  }

  Future<void> _fitBounds(List<LatLng> points) async {
    if (points.isEmpty) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    if (minLat == maxLat && minLng == maxLng) {
      await _moveCamera(points.first, zoom: 15);
      return;
    }
    final controller = await _controller.future;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  void _onMapTap(LatLng position) {
    FocusScope.of(context).unfocus();
    final isStart = _pickTarget == PickTarget.start;
    setState(() {
      _route = null;
      if (isStart) {
        _startLatLng = position;
        _startController.text = _format(position);
        _pickTarget = PickTarget.end;
      } else {
        _endLatLng = position;
        _endController.text = _format(position);
      }
    });
    _showMessage(isStart ? 'Đã chọn điểm xuất phát' : 'Đã chọn điểm đích');
  }

  void _setPlaceAsDestination(PlaceResult place) {
    setState(() {
      _endLatLng = place.location;
      _endController.text = _format(place.location);
      _route = null;
    });
    _showMessage('Đã chọn "${place.name}" làm điểm đích');
  }

  Future<void> _findRoute() async {
    FocusScope.of(context).unfocus();

    if (_startController.text.trim().isEmpty ||
        _endController.text.trim().isEmpty) {
      _showMessage('Vui lòng nhập cả hai điểm!');
      return;
    }

    final start = _parseLatLng(_startController.text);
    final end = _parseLatLng(_endController.text);
    if (start == null || end == null) {
      _showMessage('Tọa độ không hợp lệ. Định dạng: lat, lng');
      return;
    }

    setState(() {
      _startLatLng = start;
      _endLatLng = end;
      _loadingRoute = true;
    });

    try {
      final result = await _api.getRoute(start, end);
      if (!mounted) return;
      if (result == null) {
        setState(() => _route = null);
        _showMessage('Không tìm thấy tuyến đường nào!');
        return;
      }
      setState(() {
        _route = result;
        _panelExpanded = false;
      });
      await _fitBounds(result.points);
    } catch (e) {
      _showMessage('Lỗi tìm đường: $e');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _searchPlaces(String query, {String? category}) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loadingPlaces = true;
      _selectedCategory = category;
    });

    try {
      final results = await _api.searchPlaces(query.trim(), _cameraCenter);
      if (!mounted) return;
      setState(() => _places = results);
      if (results.isEmpty) {
        _showMessage('Không tìm thấy địa điểm nào');
      } else {
        _showMessage(
          'Tìm thấy ${results.length} địa điểm. Chạm tên địa điểm để chọn làm điểm đích',
        );
        await _fitBounds(results.map((e) => e.location).toList());
      }
    } catch (e) {
      _showMessage('Lỗi tìm địa điểm: $e');
    } finally {
      if (mounted) setState(() => _loadingPlaces = false);
    }
  }

  void _clearAll() {
    setState(() {
      _route = null;
      _places = [];
      _selectedCategory = null;
      _endLatLng = null;
      _endController.clear();
      _searchController.clear();
      _panelExpanded = true;
    });
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};

    for (int i = 0; i < _places.length; i++) {
      final place = _places[i];
      markers.add(
        Marker(
          markerId: MarkerId('place_$i'),
          position: place.location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: place.name,
            snippet: 'Chạm để chọn làm điểm đích',
            onTap: () => _setPlaceAsDestination(place),
          ),
        ),
      );
    }

    if (_startLatLng != null) {
      final isCurrent = _startLatLng == _currentPosition;
      markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _startLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: isCurrent ? 'Vị trí của bạn' : 'Xuất phát',
          ),
        ),
      );
    }

    if (_endLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _endLatLng!,
          infoWindow: const InfoWindow(title: 'Đích đến'),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    if (_route == null) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _route!.points,
        color: Colors.blue,
        width: 5,
      ),
    };
  }

  Widget _pointField({
    required TextEditingController controller,
    required String label,
    required Color color,
    required VoidCallback onMyLocation,
    required String tooltip,
  }) {
    return Row(
      children: [
        Icon(Icons.place, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        IconButton(
          tooltip: tooltip,
          icon: const Icon(Icons.my_location),
          onPressed: onMyLocation,
        ),
      ],
    );
  }

  Widget _buildRoutePanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        children: [
          _pointField(
            controller: _startController,
            label: 'Điểm xuất phát (lat, lng)',
            color: Colors.green,
            tooltip: 'Lấy vị trí hiện tại làm điểm xuất phát',
            onMyLocation: () => _getCurrentLocation(setAsStart: true),
          ),
          const SizedBox(height: 8),
          _pointField(
            controller: _endController,
            label: 'Điểm đích (lat, lng)',
            color: Colors.red,
            tooltip: 'Lấy vị trí hiện tại làm điểm đích',
            onMyLocation: () => _getCurrentLocation(setAsEnd: true),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Chạm bản đồ:'),
              const SizedBox(width: 6),
              Expanded(
                child: SegmentedButton<PickTarget>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: PickTarget.start,
                      label: Text('Xuất phát'),
                    ),
                    ButtonSegment(
                      value: PickTarget.end,
                      label: Text('Đích'),
                    ),
                  ],
                  selected: {_pickTarget},
                  onSelectionChanged: (s) =>
                      setState(() => _pickTarget = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loadingRoute ? null : _findRoute,
              icon: _loadingRoute
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.directions),
              label: const Text('Tìm đường đi'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (q) => _searchPlaces(q),
            decoration: InputDecoration(
              hintText: 'Tìm địa điểm (khách sạn, quán ăn...)',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loadingPlaces
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => _searchPlaces(_searchController.text),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _categories.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(e.key),
                    selected: _selectedCategory == e.key,
                    onSelected: (_) {
                      _searchController.text = e.value;
                      _searchPlaces(e.value, category: e.key);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfo() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Row(
              children: [
                const Icon(Icons.straighten, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  _route!.distanceText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.orange),
                const SizedBox(width: 6),
                Text(
                  _route!.durationText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Navigator'),
        actions: [
          IconButton(
            tooltip: _panelExpanded ? 'Thu gọn' : 'Mở bảng tìm đường',
            icon: Icon(
              _panelExpanded ? Icons.expand_less : Icons.alt_route,
            ),
            onPressed: () => setState(() => _panelExpanded = !_panelExpanded),
          ),
          IconButton(
            tooltip: 'Xoá đường đi và kết quả tìm kiếm',
            icon: const Icon(Icons.clear_all),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _panelExpanded
                ? _buildRoutePanel()
                : const SizedBox(width: double.infinity),
          ),
          _buildSearchBar(),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _initialPosition,
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) {
                    if (!_controller.isCompleted) {
                      _controller.complete(controller);
                    }
                  },
                  onCameraMove: (position) => _cameraCenter = position.target,
                  onTap: _onMapTap,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                ),
                if (_route != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: _buildRouteInfo(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
