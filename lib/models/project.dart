import 'package:flutter/material.dart';

/// A project that time entries can be tagged to (Clockify-style).
class Project {
  final int? id;
  final String name;
  final int color; // ARGB int
  final bool archived;
  final DateTime createdAt;

  const Project({
    this.id,
    required this.name,
    required this.color,
    this.archived = false,
    required this.createdAt,
  });

  Color get colorValue => Color(color);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Project.fromMap(Map<String, Object?> map) => Project(
        id: map['id'] as int?,
        name: map['name'] as String,
        color: map['color'] as int,
        archived: (map['archived'] as int? ?? 0) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  Project copyWith({
    int? id,
    String? name,
    int? color,
    bool? archived,
    DateTime? createdAt,
  }) =>
      Project(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        archived: archived ?? this.archived,
        createdAt: createdAt ?? this.createdAt,
      );
}
