import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';

class UserModel {
  const UserModel({
    required this.uid,
    required this.role,
    this.fullName = '',
    this.email = '',
    this.phone,
    this.status = 'pending',
    this.organizationId,
    this.designation,
    this.city,
    this.state,
    this.createdAt,
    this.updatedAt,
    this.rejectionReason,
  });
  final String uid, fullName, email, status;
  final UserRole role;
  final String? phone,
      organizationId,
      designation,
      city,
      state,
      rejectionReason;
  final DateTime? createdAt, updatedAt;
  String? get phoneNumber => phone;
  bool get isActive => status == 'active';
  static DateTime? date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;
  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    final role = UserRoleX.fromStorageKey(data['role'] as String?);
    if (role == null) throw const FormatException('Invalid account role.');
    return UserModel(
      uid: uid,
      role: role,
      fullName: data['fullName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: (data['phone'] ?? data['phoneNumber']) as String?,
      status: data['status'] as String? ?? 'pending',
      organizationId: data['organizationId'] as String?,
      designation: data['designation'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      createdAt: date(data['createdAt']),
      updatedAt: date(data['updatedAt']),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
  Map<String, dynamic> toMap() => {
    'uid': uid,
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'role': role.name,
    'status': status,
    'organizationId': organizationId,
    'designation': designation,
    'city': city,
    'state': state,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
  };
  UserModel copyWith({
    String? fullName,
    String? phone,
    String? status,
    String? designation,
  }) => UserModel(
    uid: uid,
    role: role,
    fullName: fullName ?? this.fullName,
    email: email,
    phone: phone ?? this.phone,
    status: status ?? this.status,
    organizationId: organizationId,
    designation: designation ?? this.designation,
    city: city,
    state: state,
    createdAt: createdAt,
    updatedAt: updatedAt,
    rejectionReason: rejectionReason,
  );
}
