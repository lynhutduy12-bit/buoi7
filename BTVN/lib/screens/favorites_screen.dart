import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/favorite_route.dart';
import '../models/travel_mode.dart';
import '../services/favorite_db.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoriteDb _db = FavoriteDb();
  List<FavoriteRoute> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _db.getAll();
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  Future<void> _delete(FavoriteRoute item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá tuyến đường'),
        content: Text('Xoá "${item.name}" khỏi danh sách yêu thích?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || item.id == null) return;
    await _db.delete(item.id!);
    await _load();
  }

  Future<void> _rename(FavoriteRoute item) async {
    final controller = TextEditingController(text: item.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đổi tên'),
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
    if (name == null || name.trim().isEmpty || item.id == null) return;
    await _db.rename(item.id!, name.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tuyến đường yêu thích')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Chưa có tuyến đường nào.\nTìm đường rồi bấm ☆ để lưu.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final route = item.toRouteResult();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: item.mode.color.withValues(alpha: 0.15),
                        child: Icon(item.mode.icon, color: item.mode.color),
                      ),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.startText} → ${item.endText}\n'
                        '${item.mode.label} · ${route.distanceText} · ${route.durationText} · '
                        '${DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt)}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.pop(context, item),
                      onLongPress: () => _rename(item),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _delete(item),
                      ),
                    );
                  },
                ),
    );
  }
}
