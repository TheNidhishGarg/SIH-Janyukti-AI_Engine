import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class CloudinaryAsset {
  const CloudinaryAsset({
    required this.url,
    required this.publicId,
    required this.resourceType,
    required this.format,
    required this.bytes,
    this.duration,
  });

  final String url;
  final String publicId;
  final String resourceType;
  final String format;
  final int bytes;
  final double? duration;

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'publicId': publicId,
      'resourceType': resourceType,
      'format': format,
      'bytes': bytes,
      if (duration != null) 'duration': duration,
    };
  }
}

class CloudinaryService {
  CloudinaryService({required this.cloudName, required this.uploadPreset});

  final String cloudName;
  final String uploadPreset;

  Future<CloudinaryAsset> uploadFile({
    required File file,
    required String folder,
  }) async {
    if (!await file.exists()) {
      throw Exception('File does not exist: ${file.path}');
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/'
      '$cloudName/auto/upload',
    );

    final request = http.MultipartRequest('POST', uri);

    request.fields.addAll({'upload_preset': uploadPreset, 'folder': folder});

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send().timeout(
      const Duration(minutes: 5),
    );

    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw Exception(
        'Cloudinary upload failed '
        '(${streamedResponse.statusCode}): '
        '$responseBody',
      );
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;

    final secureUrl = json['secure_url'] as String?;

    if (secureUrl == null || secureUrl.isEmpty) {
      throw Exception('Cloudinary did not return secure_url');
    }

    return CloudinaryAsset(
      url: secureUrl,
      publicId: json['public_id']?.toString() ?? '',
      resourceType: json['resource_type']?.toString() ?? '',
      format: json['format']?.toString() ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toDouble(),
    );
  }
}
