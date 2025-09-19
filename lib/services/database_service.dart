import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/audio_capture.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'zamio_captures.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE audio_captures (
        id TEXT PRIMARY KEY,
        station_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        captured_at INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        file_size_bytes INTEGER NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_retry_at INTEGER,
        error_message TEXT,
        metadata TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
        updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_captures_status ON audio_captures(status)');
    await db.execute('CREATE INDEX idx_captures_station ON audio_captures(station_id)');
    await db.execute('CREATE INDEX idx_captures_captured_at ON audio_captures(captured_at)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database schema upgrades here
    if (oldVersion < 2) {
      // Example: Add new column in version 2
      // await db.execute('ALTER TABLE audio_captures ADD COLUMN new_column TEXT');
    }
  }

  // CRUD operations for AudioCapture

  Future<String> insertCapture(AudioCapture capture) async {
    final db = await database;
    final map = capture.toMap();
    map['created_at'] = DateTime.now().millisecondsSinceEpoch;
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    
    await db.insert('audio_captures', map);
    return capture.id;
  }

  Future<AudioCapture?> getCaptureById(String id) async {
    final db = await database;
    final maps = await db.query(
      'audio_captures',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return AudioCapture.fromMap(maps.first);
  }

  Future<List<AudioCapture>> getAllCaptures({
    CaptureStatus? status,
    String? stationId,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];
    
    if (status != null) {
      whereClause += 'status = ?';
      whereArgs.add(status.name);
    }
    
    if (stationId != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'station_id = ?';
      whereArgs.add(stationId);
    }

    final maps = await db.query(
      'audio_captures',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'captured_at DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((map) => AudioCapture.fromMap(map)).toList();
  }

  Future<List<AudioCapture>> getPendingCaptures({String? stationId}) async {
    final db = await database;
    
    String whereClause = 'status IN (?, ?)';
    List<dynamic> whereArgs = [CaptureStatus.pending.name, CaptureStatus.retrying.name];
    
    if (stationId != null) {
      whereClause += ' AND station_id = ?';
      whereArgs.add(stationId);
    }

    final maps = await db.query(
      'audio_captures',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'captured_at ASC', // Process oldest first
    );

    return maps.map((map) => AudioCapture.fromMap(map)).toList();
  }

  Future<List<AudioCapture>> getFailedCaptures({String? stationId}) async {
    return getAllCaptures(status: CaptureStatus.failed, stationId: stationId);
  }

  Future<int> updateCapture(AudioCapture capture) async {
    final db = await database;
    final map = capture.toMap();
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    
    return await db.update(
      'audio_captures',
      map,
      where: 'id = ?',
      whereArgs: [capture.id],
    );
  }

  Future<int> updateCaptureStatus(String id, CaptureStatus status, {String? errorMessage}) async {
    final db = await database;
    
    final updateMap = {
      'status': status.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    
    if (errorMessage != null) {
      updateMap['error_message'] = errorMessage;
    }
    
    if (status == CaptureStatus.retrying) {
      updateMap['last_retry_at'] = DateTime.now().millisecondsSinceEpoch;
    }
    
    return await db.update(
      'audio_captures',
      updateMap,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> incrementRetryCount(String id) async {
    final db = await database;
    
    return await db.rawUpdate(
      'UPDATE audio_captures SET retry_count = retry_count + 1, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<int> deleteCapture(String id) async {
    final db = await database;
    return await db.delete(
      'audio_captures',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCompletedCaptures({String? stationId, DateTime? olderThan}) async {
    final db = await database;
    
    String whereClause = 'status = ?';
    List<dynamic> whereArgs = [CaptureStatus.completed.name];
    
    if (stationId != null) {
      whereClause += ' AND station_id = ?';
      whereArgs.add(stationId);
    }
    
    if (olderThan != null) {
      whereClause += ' AND captured_at < ?';
      whereArgs.add(olderThan.millisecondsSinceEpoch);
    }
    
    return await db.delete(
      'audio_captures',
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  // Statistics and monitoring

  Future<Map<String, int>> getCaptureStats({String? stationId}) async {
    final db = await database;
    
    String whereClause = stationId != null ? 'WHERE station_id = ?' : '';
    List<dynamic> whereArgs = stationId != null ? [stationId] : [];
    
    final result = await db.rawQuery('''
      SELECT 
        status,
        COUNT(*) as count
      FROM audio_captures 
      $whereClause
      GROUP BY status
    ''', whereArgs);

    final stats = <String, int>{};
    for (final row in result) {
      stats[row['status'] as String] = row['count'] as int;
    }
    
    return stats;
  }

  Future<int> getTotalStorageUsed({String? stationId}) async {
    final db = await database;
    
    String whereClause = stationId != null ? 'WHERE station_id = ?' : '';
    List<dynamic> whereArgs = stationId != null ? [stationId] : [];
    
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(file_size_bytes), 0) as total_size
      FROM audio_captures 
      $whereClause
    ''', whereArgs);

    return result.first['total_size'] as int;
  }

  Future<void> cleanupOldCaptures({
    required int maxAgeHours,
    String? stationId,
  }) async {
    final cutoffTime = DateTime.now().subtract(Duration(hours: maxAgeHours));
    
    await deleteCompletedCaptures(
      stationId: stationId,
      olderThan: cutoffTime,
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}