import 'package:cloud_firestore/cloud_firestore.dart';

/// A message in a project's collaboration chat (`projects/{id}/messages`).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String senderUid;
  final String senderName;

  /// citizen, university, industry or admin.
  final String senderRole;
  final String text;
  final DateTime createdAt;

  /// The client's clock keeps ordering stable while a write is still pending;
  /// a server timestamp reads as null until the server confirms it.
  Map<String, dynamic> toMap() => {
    'senderUid': senderUid,
    'senderName': senderName,
    'senderRole': senderRole,
    'text': text,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    final created = map['createdAt'];
    return ChatMessage(
      id: id,
      senderUid: map['senderUid']?.toString() ?? '',
      senderName: map['senderName']?.toString() ?? '',
      senderRole: map['senderRole']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
    );
  }
}
