import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/cloudinary_service.dart';

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final cloudinaryServiceProvider = Provider<CloudinaryService>((ref) {
  const cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'dpnawkd7i',
  );

  const uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'pzr05f28',
  );

  if (cloudName.isEmpty || uploadPreset.isEmpty) {
    throw Exception(
      'Cloudinary configuration missing. '
      'Provide CLOUDINARY_CLOUD_NAME and '
      'CLOUDINARY_UPLOAD_PRESET.',
    );
  }

  return CloudinaryService(cloudName: cloudName, uploadPreset: uploadPreset);
});
