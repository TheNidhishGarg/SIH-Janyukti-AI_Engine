import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../apis/admin_api.dart';
import '../../../models/user_model.dart';

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi());

/// Approved organisations by type: {'university': n, 'industry': n}.
final organizationCountsProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) {
      return ref.watch(adminApiProvider).watchOrganizationCounts();
    });

final pendingRegistrationsProvider =
    StreamProvider.autoDispose<List<UserModel>>((ref) {
      return ref.watch(adminApiProvider).watchPendingRegistrations();
    });
