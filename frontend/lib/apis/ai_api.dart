import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/providers/instance_providers.dart';
import '../models/ai_analysis.dart';
import '../models/challenge_model.dart';
import '../models/organization_model.dart';

// ============================================================
// PROVIDER
// ============================================================

final aiApiProvider = Provider<AiApi>((ref) {
  final api = AiApi(auth: ref.watch(firebaseAuthProvider));
  ref.onDispose(api.close);
  return api;
});

// ============================================================
// ERRORS
// ============================================================

class AiApiException implements Exception {
  const AiApiException(this.message, {this.statusCode});

  final String message;

  /// Null when the backend could not be reached at all.
  final int? statusCode;

  bool get isUnreachable => statusCode == null;

  @override
  String toString() => message;
}

// ============================================================
// AI API
//
// HTTP client for the JanYukti AI backend. Firestore stays the source of
// truth: callers take these results and store them on Firestore documents.
// Every call carries the signed-in user's Firebase ID token, which the backend
// verifies when FIREBASE_AUTH_MODE=required.
// ============================================================

class AiApi {
  AiApi({required FirebaseAuth auth, http.Client? client, String? baseUrl})
    : _auth = auth,
      _client = client ?? http.Client(),
      baseUrl = (baseUrl ?? ApiConfig.aiBaseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      );

  final FirebaseAuth _auth;
  final http.Client _client;
  final String baseUrl;

  void close() => _client.close();

  Future<bool> isReachable() async {
    try {
      await _send('GET', '/ai/status');
      return true;
    } on AiApiException {
      return false;
    }
  }

  /// Full analysis of a saved challenge. The backend also adds it to its
  /// duplicate index, keyed by the Firestore document id.
  Future<AiAnalysis> analyze(Challenge challenge) async {
    final json = await _send(
      'POST',
      '/ai/analyze',
      body: {
        'challengeId': challenge.id,
        'title': challenge.title,
        'description': challenge.description,
        'additionalInfo': challenge.additionalInfo,
        'category': challenge.category,
        'location': challenge.location,
        'status': challenge.status,
        'submittedByUid': challenge.submittedById,
      },
      timeout: ApiConfig.analyzeTimeout,
    );
    return AiAnalysis.fromMap(json);
  }

  /// Check a draft for existing reports of the same problem before it is
  /// submitted. Nothing is stored.
  Future<DuplicateCheck> checkDuplicates({
    required String title,
    required String description,
    String additionalInfo = '',
    String category = '',
    String location = '',
    String? excludeChallengeId,
  }) async {
    final json = await _send(
      'POST',
      '/ai/duplicates',
      body: {
        'title': title,
        'description': description,
        'additionalInfo': additionalInfo,
        'category': category,
        'location': location,
        if (excludeChallengeId != null)
          'excludeChallengeId': excludeChallengeId,
      },
    );
    return DuplicateCheck.fromMap(json);
  }

  /// Rank the approved university organisations for a challenge.
  Future<MatchResult> matchOrganizations({
    required Challenge challenge,
    required List<OrganizationModel> organizations,
    int topK = 5,
    int directoryK = 3,
  }) async {
    final json = await _send(
      'POST',
      '/ai/match',
      body: {
        'challengeId': challenge.id,
        'title': challenge.title,
        'description': challenge.description,
        'additionalInfo': challenge.additionalInfo,
        'category': challenge.category,
        'location': challenge.location,
        'organizations': [
          for (final org in organizations)
            {
              'id': org.id,
              'name': org.name,
              'city': org.city,
              'state': org.state,
              'type': org.category ?? '',
            },
        ],
        'topK': topK,
        'directoryK': directoryK,
      },
      timeout: ApiConfig.analyzeTimeout,
    );
    return MatchResult.fromMap(json);
  }

  static const _syncLimit = 2000;

  Future<void> syncIndex(List<Challenge> challenges, {bool prune = false}) async {
    if (challenges.isEmpty) return;
    final batch = challenges.take(_syncLimit).toList();
    await _send(
      'POST',
      '/ai/index/sync',
      body: {
        // Pruning removes anything missing from the batch, so only allow it
        // when the batch really is the complete list.
        'prune': prune && challenges.length <= _syncLimit,
        'challenges': [
          for (final c in batch)
            {
              'id': c.id,
              'title': c.title,
              'description': c.description,
              'additionalInfo': c.additionalInfo,
              'category': c.category,
              'location': c.location,
              'status': c.status,
              'submittedByUid': c.submittedById,
            },
        ],
      },
      timeout: ApiConfig.analyzeTimeout,
    );
  }

  /// Keep the index status in step so rejected or duplicate challenges stop
  /// being offered as the original report.
  Future<void> updateIndexStatus(String challengeId, String status) async {
    await _send(
      'PATCH',
      '/ai/index/${Uri.encodeComponent(challengeId)}',
      body: {'status': status},
    );
  }

  // ============================================================
  // TRANSPORT
  // ============================================================

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final token = await user.getIdToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {
        // The backend decides whether a token is required; send anyway and
        // let it answer 401 if so.
      }
    }
    return headers;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = ApiConfig.quickTimeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response response;

    try {
      final headers = await _headers();
      final encoded = body == null ? null : jsonEncode(body);
      final Future<http.Response> request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'PATCH' => _client.patch(uri, headers: headers, body: encoded),
        _ => _client.post(uri, headers: headers, body: encoded),
      };
      response = await request.timeout(timeout);
    } on TimeoutException {
      throw AiApiException(
        'The AI service at $baseUrl did not respond in time.',
      );
    } on SocketException {
      throw AiApiException('Cannot reach the AI service at $baseUrl.');
    } on http.ClientException catch (error) {
      throw AiApiException(
        'Cannot reach the AI service at $baseUrl (${error.message}).',
      );
    }

    final text = utf8.decode(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiApiException(
        _errorMessage(text, response.statusCode),
        statusCode: response.statusCode,
      );
    }

    if (text.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};
  }

  static String _errorMessage(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          final first = detail.first as Map;
          return 'The AI service rejected the request: '
              '${first['msg'] ?? 'invalid input'}';
        }
      }
    } catch (_) {
      // Not JSON; fall through to the generic message.
    }
    if (statusCode == 401) {
      return 'The AI service did not accept your sign-in. Sign in again.';
    }
    return 'The AI service returned an error ($statusCode).';
  }
}

// ============================================================
// INDEX SYNC
//
// Challenges created before the AI service existed, or edited since, are
// unknown to its duplicate index. The admin dashboard already streams every
// challenge, so it pushes the list whenever the text or status of anything
// changes. Best effort: a failed sync only weakens duplicate detection.
// ============================================================

class AiIndexSync {
  const AiIndexSync._();

  static String? _lastSignature;
  static bool _running = false;

  static Future<void> maybeSync(AiApi api, List<Challenge> challenges) async {
    if (_running || challenges.isEmpty) return;

    final signature = _signature(challenges);
    if (signature == _lastSignature) return;

    _running = true;
    try {
      await api.syncIndex(challenges, prune: true);
      _lastSignature = signature;
    } catch (_) {
      // Leave the signature unchanged so the next snapshot retries.
    } finally {
      _running = false;
    }
  }

  static String _signature(List<Challenge> challenges) {
    var hash = challenges.length;
    for (final c in challenges) {
      hash = Object.hash(
        hash,
        c.id,
        c.status,
        c.title,
        c.description,
        c.additionalInfo,
        c.category,
        c.location,
      );
    }
    return '$hash';
  }
}
