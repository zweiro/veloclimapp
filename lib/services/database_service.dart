import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Model class representing a recording session.
class Session {
  final int? id;
  final String name;
  final String filePath;
  final DateTime createdAt;
  final DateTime endedAt;

  Session({
    this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.endedAt,
  });

  /// Convert Session to a Map for database insertion.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'file_path': filePath,
      'created_at': createdAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
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
    );
  }
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
      version: 1,
      onCreate: _createDB,
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
        ended_at TEXT NOT NULL
      )
    ''');
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

  /// Get all sessions ordered by creation date (newest first).
  Future<List<Session>> getAllSessions() async {
    final db = await database;
    final maps = await db.query(
      'sessions',
      orderBy: 'created_at DESC',
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
