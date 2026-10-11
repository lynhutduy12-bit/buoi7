import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/favorite_route.dart';

class FavoriteDb {
  FavoriteDb._internal();
  static final FavoriteDb _instance = FavoriteDb._internal();
  factory FavoriteDb() => _instance;

  static const String _table = 'favorite_routes';
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'map_navigator.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            start_text TEXT NOT NULL,
            end_text TEXT NOT NULL,
            start_lat REAL NOT NULL,
            start_lng REAL NOT NULL,
            end_lat REAL NOT NULL,
            end_lng REAL NOT NULL,
            mode TEXT NOT NULL,
            distance INTEGER NOT NULL,
            duration INTEGER NOT NULL,
            polyline TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<int> insert(FavoriteRoute route) async {
    final db = await database;
    final map = route.toMap()..remove('id');
    return db.insert(_table, map);
  }

  Future<List<FavoriteRoute>> getAll() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'created_at DESC');
    return rows.map(FavoriteRoute.fromMap).toList();
  }

  Future<int> rename(int id, String name) async {
    final db = await database;
    return db.update(
      _table,
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    final db = await database;
    return db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
