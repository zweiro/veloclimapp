import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Model class representing a recording session.
class Session {
  final int? id;
  final String name;
  final String filePath;
  final DateTime createdAt;
  final DateTime endedAt;
  final bool synced;

  Session({
    this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.endedAt,
    this.synced = false,
  });

  /// Convert Session to a Map for database insertion.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'file_path': filePath,
      'created_at': createdAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'synced': synced ? 1 : 0,
    };
  }

  /// Create a Session from a database Map.
  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as int?,
      name: map['name'] as String,
      filePath: map['file_path'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      endedAt: DateTime.parse(map['ended_at'] as String),
      synced: (map['synced'] as int?) == 1,
    );
  }

  /// Create a copy of this session with updated fields.
  Session copyWith({
    int? id,
    String? name,
    String? filePath,
    DateTime? createdAt,
    DateTime? endedAt,
    bool? synced,
  }) {
    return Session(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
      synced: synced ?? this.synced,
    );
  }

  /// Get the filename from the file path.
  String get fileName => filePath.split('/').last;

  /// Get the duration of the session.
  Duration get duration => endedAt.difference(createdAt);
}

/// Singleton service for database operations.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  /// Get the database instance, initializing if necessary.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('veloclimapp.db');
    return _database!;
  }

  /// Initialize the database.
  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  /// Create the database tables.
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        ended_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Upgrade the database schema.
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE sessions ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
    }
  }

  /// Insert a new session into the database.
  Future<int> insertSession(Session session) async {
    final db = await database;
    return await db.insert(
      'sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all sessions with optional filtering and sorting.
  Future<List<Session>> getAllSessions({
    bool? syncedFilter,
    bool newestFirst = true,
  }) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;

    if (syncedFilter != null) {
      where = 'synced = ?';
      whereArgs = [syncedFilter ? 1 : 0];
    }

    final maps = await db.query(
      'sessions',
      where: where,
      whereArgs: whereArgs,
      orderBy: newestFirst ? 'created_at DESC' : 'created_at ASC',
    );
    return maps.map((map) => Session.fromMap(map)).toList();
  }

  /// Get a session by its ID.
  Future<Session?> getSessionById(int id) async {
    final db = await database;
    final maps = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Session.fromMap(maps.first);
  }

  /// Get a session by its file path.
  Future<Session?> getSessionByFilePath(String filePath) async {
    final db = await database;
    final maps = await db.query(
      'sessions',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
    if (maps.isEmpty) return null;
    return Session.fromMap(maps.first);
  }

  /// Update an existing session.
  Future<int> updateSession(Session session) async {
    final db = await database;
    return await db.update(
      'sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// Mark a session as synced.
  Future<int> markSessionAsSynced(int id) async {
    final db = await database;
    return await db.update(
      'sessions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a session by its ID.
  Future<int> deleteSession(int id) async {
    final db = await database;
    return await db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a session by its file path.
  Future<int> deleteSessionByFilePath(String filePath) async {
    final db = await database;
    return await db.delete(
      'sessions',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }
}
