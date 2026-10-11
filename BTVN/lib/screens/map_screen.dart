import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/favorite_route.dart';
import '../models/place_result.dart';
import '../models/route_result.dart';
import '../models/travel_mode.dart';
import '../services/favorite_db.dart';
import '../services/map_api_service.dart';
import 'favorites_screen.dart';

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
  final FavoriteDb _favoriteDb = FavoriteDb();
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _currentPosition;
  LatLng? _startLatLng;
  LatLng? _endLatLng;
  String _resolvedStartText = '';
  String _resolvedEndText = '';
  LatLng _cameraCenter = _initialPosition.target;
  PickTarget _pickTarget = PickTarget.end;
  TravelMode _mode = TravelMode.car;

  List<RouteResult> _routes = [];
  int _selectedRoute = 0;
  List<PlaceResult> _places = [];
  String? _selectedCategory;
  bool _loadingRoute = false;
  bool _loadingPlaces = false;
  bool _panelExpanded = true;

  RouteResult? get _route =>
      _routes.isEmpty ? null : _routes[min(_selectedRoute, _routes.length - 1)];

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

  void _clearRoutes() {
    _routes = [];
    _selectedRoute = 0;
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
          _resolvedStartText = _startController.text;
        }
        if (setAsEnd) {
          _endLatLng = latLng;
          _endController.text = _format(latLng);
          _resolvedEndText = _endController.text;
        }
        _clearRoutes();
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
      _clearRoutes();
      if (isStart) {
        _startLatLng = position;
        _startController.text = _format(position);
        _resolvedStartText = _startController.text;
        _pickTarget = PickTarget.end;
      } else {
        _endLatLng = position;
        _endController.text = _format(position);
        _resolvedEndText = _endController.text;
      }
    });
    _showMessage(isStart ? 'Đã chọn điểm xuất phát' : 'Đã chọn điểm đích');
  }

  void _setPlaceAsDestination(PlaceResult place) {
    setState(() {
      _endLatLng = place.location;
      _endController.text = place.name;
      _resolvedEndText = place.name;
      _clearRoutes();
    });
    _showMessage('Đã chọn "${place.name}" làm điểm đích');
  }

  Future<LatLng?> _resolvePoint(
    TextEditingController controller,
    LatLng? current,
    String resolvedText,
    String label,
  ) async {
    final text = controller.text.trim();
    if (text.isEmpty) return null;

    final parsed = _parseLatLng(text);
    if (parsed != null) return parsed;

    if (current != null && text == resolvedText) return current;

    final result = await _api.geocode(text);
    if (result == null) {
      throw MapApiException('Không tìm thấy địa chỉ $label: "$text"');
    }
    controller.text = result.address;
    return result.location;
  }

  Future<bool> _resolveBothPoints() async {
    if (_startController.text.trim().isEmpty ||
        _endController.text.trim().isEmpty) {
      _showMessage('Vui lòng nhập cả hai điểm!');
      return false;
    }

    final start = await _resolvePoint(
      _startController,
      _startLatLng,
      _resolvedStartText,
      'xuất phát',
    );
    final end = await _resolvePoint(
      _endController,
      _endLatLng,
      _resolvedEndText,
      'đích',
    );
    if (start == null || end == null) {
      _showMessage('Điểm nhập không hợp lệ');
      return false;
    }

    setState(() {
      _startLatLng = start;
      _endLatLng = end;
      _resolvedStartText = _startController.text.trim();
      _resolvedEndText = _endController.text.trim();
    });
    return true;
  }

  Future<void> _findRoute() async {
    FocusScope.of(context).unfocus();
    setState(() => _loadingRoute = true);

    try {
      if (!await _resolveBothPoints()) return;

      final routes = await _api.getRoutes(_startLatLng!, _endLatLng!, _mode);
      if (!mounted) return;
      if (routes.isEmpty) {
        setState(_clearRoutes);
        _showMessage(
          'Không tìm thấy tuyến đường ${_mode.label.toLowerCase()} nào!',
        );
        return;
      }
      setState(() {
        _routes = routes;
        _selectedRoute = 0;
        _panelExpanded = false;
      });
      if (routes.length > 1) {
        _showMessage(
          'Có ${routes.length} tuyến, đang hiển thị tuyến tối ưu. Chạm đường xám để xem tuyến khác',
        );
      }
      await _fitBounds([_startLatLng!, _endLatLng!, ...routes.first.points]);
    } catch (e) {
      _showMessage('Lỗi tìm đường: $e');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _compareModes() async {
    FocusScope.of(context).unfocus();
    setState(() => _loadingRoute = true);

    final Map<TravelMode, List<RouteResult>> results = {};
    final Map<TravelMode, String> errors = {};

    try {
      if (!await _resolveBothPoints()) return;

      await Future.wait(
        TravelMode.values.map((mode) async {
          try {
            results[mode] = await _api.getRoutes(
              _startLatLng!,
              _endLatLng!,
              mode,
            );
          } catch (e) {
            errors[mode] = e.toString();
          }
        }),
      );
    } catch (e) {
      _showMessage('Lỗi: $e');
      return;
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }

    if (!mounted) return;

    int? fastest;
    for (final list in results.values) {
      if (list.isEmpty) continue;
      final s = list.first.durationSeconds;
      if (fastest == null || s < fastest) fastest = s;
    }

    final chosen = await showModalBottomSheet<TravelMode>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Tuyến tối ưu theo phương tiện',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ...TravelMode.values.map((mode) {
                  final list = results[mode];
                  final best =
                      (list == null || list.isEmpty) ? null : list.first;
                  final isFastest =
                      best != null && best.durationSeconds == fastest;
                  return ListTile(
                    leading: Icon(mode.icon, color: mode.color),
                    title: Text(mode.label),
                    subtitle: Text(
                      best != null
                          ? '${best.distanceText} · ${best.durationText}'
                              '${list!.length > 1 ? ' · ${list.length} tuyến' : ''}'
                          : errors[mode] != null
                          ? 'Lỗi: ${errors[mode]}'
                          : 'Không có tuyến đường',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing:
                        isFastest
                            ? const Chip(
                              label: Text('Nhanh nhất'),
                              visualDensity: VisualDensity.compact,
                            )
                            : null,
                    enabled: best != null,
                    onTap: () => Navigator.pop(sheetContext, mode),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );

    if (chosen == null || !mounted) return;
    final routes = results[chosen]!;
    setState(() {
      _mode = chosen;
      _routes = routes;
      _selectedRoute = 0;
      _panelExpanded = false;
    });
    await _fitBounds([_startLatLng!, _endLatLng!, ...routes.first.points]);
  }

  Future<void> _saveFavorite() async {
    final route = _route;
    if (route == null || _startLatLng == null || _endLatLng == null) return;

    String shorten(String s) => s.length > 30 ? '${s.substring(0, 30)}…' : s;
    final controller = TextEditingController(
      text:
          '${shorten(_startController.text)} → ${shorten(_endController.text)}',
    );

    final name = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Lưu vào yêu thích'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Tên tuyến đường'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Huỷ'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text('Lưu'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;

    await _favoriteDb.insert(
      FavoriteRoute(
        name: name.trim(),
        startText: _startController.text.trim(),
        endText: _endController.text.trim(),
        start: _startLatLng!,
        end: _endLatLng!,
        mode: route.mode,
        distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
        polyline: route.encodedPolyline,
        createdAt: DateTime.now(),
      ),
    );
    _showMessage('Đã lưu "${name.trim()}" vào yêu thích');
  }

  Future<void> _openFavorites() async {
    final fav = await Navigator.push<FavoriteRoute>(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );
    if (fav == null || !mounted) return;

    final route = fav.toRouteResult();
    setState(() {
      _startLatLng = fav.start;
      _endLatLng = fav.end;
      _startController.text = fav.startText;
      _endController.text = fav.endText;
      _resolvedStartText = fav.startText;
      _resolvedEndText = fav.endText;
      _mode = fav.mode;
      _routes = [route];
      _selectedRoute = 0;
      _places = [];
      _panelExpanded = false;
    });
    _showMessage('Đã mở "${fav.name}"');
    await _fitBounds([fav.start, fav.end, ...route.points]);
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
      _clearRoutes();
      _places = [];
      _selectedCategory = null;
      _endLatLng = null;
      _endController.clear();
      _resolvedEndText = '';
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
            snippet: _startController.text,
          ),
        ),
      );
    }

    if (_endLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _endLatLng!,
          infoWindow: InfoWindow(
            title: 'Đích đến',
            snippet: _endController.text,
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    final lines = <Polyline>{};
    for (int i = 0; i < _routes.length; i++) {
      final selected = i == _selectedRoute;
      final route = _routes[i];
      lines.add(
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: route.points,
          color: selected ? route.mode.color : Colors.grey,
          width: selected ? 6 : 4,
          zIndex: selected ? 2 : 1,
          patterns:
              route.mode == TravelMode.walk
                  ? [PatternItem.dot, PatternItem.gap(10)]
                  : const [],
          consumeTapEvents: !selected,
          onTap: selected ? null : () => setState(() => _selectedRoute = i),
        ),
      );
    }
    return lines;
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
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: label,
              hintText: 'VD: 227 Nguyễn Văn Cừ, TP.HCM',
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
            label: 'Xuất phát (địa chỉ hoặc lat, lng)',
            color: Colors.green,
            tooltip: 'Lấy vị trí hiện tại làm điểm xuất phát',
            onMyLocation: () => _getCurrentLocation(setAsStart: true),
          ),
          const SizedBox(height: 8),
          _pointField(
            controller: _endController,
            label: 'Đích (địa chỉ hoặc lat, lng)',
            color: Colors.red,
            tooltip: 'Lấy vị trí hiện tại làm điểm đích',
            onMyLocation: () => _getCurrentLocation(setAsEnd: true),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<TravelMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments:
                  TravelMode.values
                      .map(
                        (m) => ButtonSegment(
                          value: m,
                          icon: Icon(m.icon),
                          label: Text(m.label),
                        ),
                      )
                      .toList(),
              selected: {_mode},
              onSelectionChanged:
                  (s) => setState(() {
                    _mode = s.first;
                    _clearRoutes();
                  }),
            ),
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
                    ButtonSegment(value: PickTarget.end, label: Text('Đích')),
                  ],
                  selected: {_pickTarget},
                  onSelectionChanged:
                      (s) => setState(() => _pickTarget = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loadingRoute ? null : _findRoute,
                  icon:
                      _loadingRoute
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.directions),
                  label: const Text('Tìm đường đi'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loadingRoute ? null : _compareModes,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('So sánh'),
              ),
            ],
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
              suffixIcon:
                  _loadingPlaces
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
              children:
                  _categories.entries.map((e) {
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
    final route = _route!;
    final isOptimal = _selectedRoute == 0;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(route.mode.icon, color: route.mode.color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${route.distanceText} · ${route.durationText}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    [
                      route.mode.label,
                      if (_routes.length > 1)
                        isOptimal
                            ? 'Tuyến tối ưu (1/${_routes.length})'
                            : 'Tuyến ${_selectedRoute + 1}/${_routes.length}',
                      if (route.summary.isNotEmpty) 'qua ${route.summary}',
                    ].join(' · '),
                    style: TextStyle(color: Colors.grey.shade700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Lưu vào yêu thích',
              icon: const Icon(Icons.star_border, color: Colors.amber),
              onPressed: _saveFavorite,
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
            tooltip: 'Tuyến đường yêu thích',
            icon: const Icon(Icons.favorite),
            onPressed: _openFavorites,
          ),
          IconButton(
            tooltip: _panelExpanded ? 'Thu gọn' : 'Mở bảng tìm đường',
            icon: Icon(_panelExpanded ? Icons.expand_less : Icons.alt_route),
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
            child:
                _panelExpanded
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
