class DiaryEntry {
  const DiaryEntry({
    this.id,
    required this.recordedAt,
    required this.mood,
    this.symptoms = const [],
    this.note,
  });

  final int? id;
  final DateTime recordedAt;
  final int mood;
  final List<String> symptoms;
  final String? note;

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: json['id'] as int,
    recordedAt: DateTime.parse(json['recorded_at'] as String),
    mood: json['mood'] as int,
    symptoms: List<String>.from(json['symptoms'] as List),
    note: json['note'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'mood': mood,
    'symptoms': symptoms,
    'note': note,
  };
}

class Clinician {
  const Clinician({required this.id, required this.name, required this.practice});

  final int id;
  final String name;
  final String practice;

  factory Clinician.fromJson(Map<String, dynamic> json) => Clinician(
    id: json['id'] as int,
    name: json['name'] as String,
    practice: json['practice'] as String,
  );
}

/// A patient's consent for one doctor to read a period of their diary.
class Share {
  const Share({
    required this.id,
    required this.clinicianId,
    required this.fromDate,
    required this.toDate,
    required this.includeNotes,
    required this.createdAt,
    this.revokedAt,
  });

  final int id;
  final int clinicianId;

  /// Inclusive calendar days, as local dates without a time.
  final DateTime fromDate;
  final DateTime toDate;
  final bool includeNotes;
  final DateTime createdAt;
  final DateTime? revokedAt;

  bool get isActive => revokedAt == null;

  factory Share.fromJson(Map<String, dynamic> json) => Share(
    id: json['id'] as int,
    clinicianId: json['clinician_id'] as int,
    fromDate: DateTime.parse(json['from_date'] as String),
    toDate: DateTime.parse(json['to_date'] as String),
    includeNotes: json['include_notes'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
    revokedAt: json['revoked_at'] == null ? null : DateTime.parse(json['revoked_at'] as String),
  );
}

/// One time a doctor opened the diary.
class AccessRecord {
  const AccessRecord({
    required this.clinicianId,
    required this.clinicianName,
    required this.accessedAt,
    required this.entryIds,
  });

  final int clinicianId;
  final String clinicianName;
  final DateTime accessedAt;
  final List<int> entryIds;

  factory AccessRecord.fromJson(Map<String, dynamic> json) => AccessRecord(
    clinicianId: json['clinician_id'] as int,
    clinicianName: json['clinician_name'] as String,
    accessedAt: DateTime.parse(json['accessed_at'] as String),
    entryIds: List<int>.from(json['entry_ids'] as List),
  );
}
