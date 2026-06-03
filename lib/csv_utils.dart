import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

const List<String> csvHeaders = [
  'Timestamp',
  'Temperature',
  'Humidity',
  'Latitude',
  'Longitude',
  'Accuracy',
];

const int csvColumnCount = 6;

final RegExp iso8601Pattern = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');

Future<void> ensureCsvHeader(String? csvFilePath) async {
  if (csvFilePath == null) return;

  final file = File(csvFilePath);
  if (!await file.exists() || (await file.readAsString()).trim().isEmpty) {
    final csvString = const ListToCsvConverter().convert([csvHeaders]);
    await file.writeAsString('$csvString\n', mode: FileMode.write);
    debugPrint('CSV header ensured.');
  }
}

Future<bool> appendToCsv(List<dynamic> row, String? csvFilePath) async {
  if (csvFilePath == null) return false;

  if (row.length != csvColumnCount) {
    debugPrint('CSV ERROR: Invalid row length ${row.length}, expected $csvColumnCount.');
    return false;
  }

  final timestamp = row[0]?.toString() ?? '';
  if (!iso8601Pattern.hasMatch(timestamp)) {
    debugPrint('CSV ERROR: Invalid timestamp format "$timestamp".');
    return false;
  }

  final file = File(csvFilePath);
  final csvString = const ListToCsvConverter().convert([row]).trim();

  if (csvString.isEmpty) {
    debugPrint('CSV ERROR: Empty row generated.');
    return false;
  }

  try {
    final sink = file.openWrite(mode: FileMode.append);
    sink.writeln(csvString);
    await sink.flush();
    await sink.close();
    return true;
  } catch (e) {
    debugPrint('CSV ERROR: Failed to write row: $e');
    return false;
  }
}
