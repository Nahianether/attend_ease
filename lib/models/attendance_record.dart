/// A single attendance check-in / check-out event.
class AttendanceRecord {
  final int? id;
  final String name;
  final String type; // 'in' or 'out'
  final DateTime timestamp;
  final String note;

  const AttendanceRecord({
    this.id,
    required this.name,
    required this.type,
    required this.timestamp,
    this.note = '',
  });

  bool get isCheckIn => type == 'in';

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'note': note,
      };

  factory AttendanceRecord.fromMap(Map<String, Object?> map) =>
      AttendanceRecord(
        id: map['id'] as int?,
        name: map['name'] as String,
        type: map['type'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        note: (map['note'] as String?) ?? '',
      );

  AttendanceRecord copyWith({int? id}) => AttendanceRecord(
        id: id ?? this.id,
        name: name,
        type: type,
        timestamp: timestamp,
        note: note,
      );
}
