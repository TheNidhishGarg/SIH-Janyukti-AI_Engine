// lib/apis/notification_api.dart — new file.

import 'api_client.dart';

class AppNotification {
  AppNotification(this.id, this.title, this.body, this.kind, this.isRead, this.target, this.at);
  final String id, title, body, kind;
  final bool isRead;
  final Map<String, dynamic>? target;
  final DateTime at;

  /// Deep-link target, e.g. {"type": "challenge", "id": "CH-2026-00124"}.
  String? get targetId => target?['id'] as String?;
  String? get targetType => target?['type'] as String?;

  static AppNotification fromJson(Map<String, dynamic> j) => AppNotification(
        j['id'] as String,
        j['title'] as String,
        j['body'] as String? ?? '',
        j['kind'] as String? ?? 'info',
        j['is_read'] as bool? ?? false,
        (j['target'] as Map?)?.cast<String, dynamic>(),
        DateTime.parse(j['created_at'] as String),
      );
}

class NotificationApi {
  final _api = ApiClient.instance;

  Future<List<AppNotification>> list({bool unreadOnly = false}) async {
    final rows = await _api.get('/notifications', query: {'unread_only': unreadOnly}) as List;
    return rows.map((n) => AppNotification.fromJson(n as Map<String, dynamic>)).toList();
  }

  Future<int> unreadCount() async {
    final data = await _api.get('/notifications/unread-count') as Map<String, dynamic>;
    return data['unread'] as int? ?? 0;
  }

  Future<void> markRead(String id) => _api.post('/notifications/$id/read');

  Future<void> markAllRead() => _api.post('/notifications/read-all');
}
