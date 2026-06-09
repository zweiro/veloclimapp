import 'package:flutter/material.dart';

/// A widget that displays CSV log data in a scrollable table format.
class LogTable extends StatelessWidget {
  /// List of CSV lines, including the header as the first line.
  final List<String> csvLines;

  const LogTable({super.key, required this.csvLines});

  /// Formats ISO 8601 timestamp to display date and time on separate lines.
  /// Example: "2026-06-28T16:13:24.500" → "28/06/2026" + "16:13:24.5"
  Widget _buildDateCell(String isoTimestamp) {
    try {
      final dateTime = DateTime.parse(isoTimestamp);
      final date = '${dateTime.day.toString().padLeft(2, '0')}/'
          '${dateTime.month.toString().padLeft(2, '0')}/'
          '${dateTime.year}';
      final time = '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}:'
          '${dateTime.second.toString().padLeft(2, '0')}.'
          '${(dateTime.millisecond ~/ 100)}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(date),
          Text(time),
        ],
      );
    } catch (_) {
      return Text(isoTimestamp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
          columns: [
            DataColumn(
              label: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                ),
                child: Container(
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: const Text('Date'),
                ),
              ),
            ),
            const DataColumn(label: Text('Temp')),
            const DataColumn(label: Text('Hum')),
            const DataColumn(label: Text('Lat')),
            const DataColumn(label: Text('Lon')),
            // Custom header cell with rounded top-right corner
            DataColumn(
              label: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                ),
                child: Container(
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: const Text('Acc'),
                ),
              ),
            ),
          ],
          rows: csvLines
              .skip(1) // Skip header row
              .where((line) => line.trim().isNotEmpty)
              .toList()
              .reversed // Show latest entries first
              .map((line) {
                final cells = line.split(',');
                // Ensure there are at least 6 cells per row
                while (cells.length < 6) {
                  cells.add('--');
                }
                return DataRow(
                  cells: [
                    DataCell(_buildDateCell(cells[0])),
                    DataCell(
                      Text(
                        cells[1],
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[2],
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[3],
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[4],
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                    ),
                    DataCell(
                      Text(
                        cells[5],
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                );
              })
              .toList(),
        ),
      ),
    );
  }
}
