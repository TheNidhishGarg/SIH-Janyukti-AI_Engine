import 'package:cloud_firestore/cloud_firestore.dart';

/// An industry partner's offer of support for a project.
///
/// Stored in the top-level `industryInterests` collection, one document per
/// partner organisation per project, so a partner can revise its offer
/// without creating duplicates.
class IndustryInterest {
  const IndustryInterest({
    required this.id,
    required this.projectId,
    required this.organizationId,
    required this.userUid,
    this.projectName = '',
    this.universityName = '',
    this.organizationName = '',
    this.userName = '',
    this.support = const [],
    this.message = '',
    this.status = 'Pending',
    this.createdAt,
  });

  static const supportOptions = [
    'Funding',
    'Technology Support',
    'Prototype Support',
    'Field Testing Support',
    'Mentorship',
    'Pilot Site',
  ];

  static String docId(String projectId, String organizationId) =>
      '${projectId}_$organizationId';

  final String id;
  final String projectId;
  final String projectName;
  final String universityName;
  final String organizationId;
  final String organizationName;
  final String userUid;
  final String userName;
  final List<String> support;
  final String message;
  final String status;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
    'projectId': projectId,
    'projectName': projectName,
    'universityName': universityName,
    'organizationId': organizationId,
    'organizationName': organizationName,
    'userUid': userUid,
    'userName': userName,
    'support': support,
    'message': message,
    'status': status,
  };

  factory IndustryInterest.fromMap(String id, Map<String, dynamic> map) {
    final rawSupport = map['support'];
    final created = map['createdAt'];
    return IndustryInterest(
      id: id,
      projectId: map['projectId']?.toString() ?? '',
      projectName: map['projectName']?.toString() ?? '',
      universityName: map['universityName']?.toString() ?? '',
      organizationId: map['organizationId']?.toString() ?? '',
      organizationName: map['organizationName']?.toString() ?? '',
      userUid: map['userUid']?.toString() ?? '',
      userName: map['userName']?.toString() ?? '',
      support: rawSupport is List
          ? rawSupport.map((x) => x.toString()).toList()
          : const [],
      message: map['message']?.toString() ?? '',
      status: map['status']?.toString() ?? 'Pending',
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}
