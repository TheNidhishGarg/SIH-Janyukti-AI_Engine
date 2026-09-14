import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../apis/projects_api.dart';
import '../../../models/challenge_model.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart';
import '../../common/ai_widgets.dart';
import '../controllers/citizen_controller.dart';

class TrackChallengeView extends ConsumerWidget {
  const TrackChallengeView({super.key, required this.challengeId});

  final String challengeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ============================================================
    // DIRECT REAL-TIME FIRESTORE DOCUMENT
    // ============================================================

    final challengeAsync = ref.watch(challengeStreamProvider(challengeId));

    return PageFrame(
      title: 'Track Challenge',
      color: AppColors.citizen,
      child: challengeAsync.when(
        loading: () {
          return const Center(child: CircularProgressIndicator());
        },

        error: (error, stackTrace) {
          return _ErrorState(
            message: error.toString().replaceFirst('Exception: ', ''),
            onRetry: () {
              ref.invalidate(challengeStreamProvider(challengeId));
            },
          );
        },

        data: (challenge) {
          if (challenge == null) {
            return const Center(child: Text('Challenge not found'));
          }

          return _ChallengeContent(
            challenge: challenge,
            onRefresh: () async {
              ref.invalidate(challengeStreamProvider(challengeId));

              await ref.read(challengeStreamProvider(challengeId).future);
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// CONTENT
// ============================================================

class _ChallengeContent extends StatelessWidget {
  const _ChallengeContent({required this.challenge, required this.onRefresh});

  final Challenge challenge;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final timeline = _timelineForChallenge(challenge);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
        children: [
          // ======================================================
          // LIVE BADGE
          // ======================================================
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'Live updates',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ======================================================
          // HEADER
          // ======================================================
          _ChallengeHeader(challenge: challenge),

          const SizedBox(height: 20),

          // ======================================================
          // AI ANALYSIS
          // ======================================================
          AiInsightCard(challenge: challenge, accent: AppColors.citizen),

          if (challenge.isAssigned) ...[
            const SizedBox(height: 14),
            _AssignmentCard(challenge: challenge),
          ],

          const SizedBox(height: 20),

          // ======================================================
          // PROGRESS
          // ======================================================
          _ProgressCard(
            status: challenge.statusLabel,
            activeStep: timeline.activeStep,
            totalSteps: timeline.items.length,
            percent: challenge.hasProject ? challenge.progress : null,
          ),

          const SizedBox(height: 24),

          _sectionTitle(
            'Challenge Journey',
            'Updates appear automatically when the challenge status changes.',
          ),

          const SizedBox(height: 10),

          AppCard(
            child: Timeline(
              items: timeline.items,
              active: timeline.activeStep,
              color: AppColors.citizen,
            ),
          ),

          if (challenge.hasProject) ...[
            const SizedBox(height: 20),
            _ProjectProgressCard(projectId: challenge.projectId!),
          ],

          const SizedBox(height: 26),

          // ======================================================
          // ACTUAL EVIDENCE
          // ======================================================
          if (challenge.media.isNotEmpty ||
              challenge.voiceNotes.isNotEmpty) ...[
            _sectionTitle(
              'Evidence',
              'Photos, videos and voice recordings submitted with this challenge.',
            ),

            const SizedBox(height: 12),

            _EvidenceSection(challenge: challenge),

            const SizedBox(height: 26),
          ],

          // ======================================================
          // DETAILS
          // ======================================================
          _sectionTitle(
            'Challenge Details',
            'Information submitted by the citizen.',
          ),

          const SizedBox(height: 12),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  icon: Icons.category_outlined,
                  title: 'Category',
                  value: challenge.category,
                ),

                const Divider(height: 28),

                _DetailRow(
                  icon: Icons.location_on_outlined,
                  title: 'Location',
                  value: challenge.location,
                ),

                if (challenge.latitude != null &&
                    challenge.longitude != null) ...[
                  const Divider(height: 28),
                  _DetailRow(
                    icon: Icons.my_location_rounded,
                    title: 'Coordinates',
                    value:
                        '${challenge.latitude!.toStringAsFixed(5)}, '
                        '${challenge.longitude!.toStringAsFixed(5)}',
                  ),
                ],

                const Divider(height: 28),

                _DetailRow(
                  icon: Icons.description_outlined,
                  title: 'Description',
                  value: challenge.description,
                ),

                if (challenge.additionalInfo.trim().isNotEmpty) ...[
                  const Divider(height: 28),
                  _DetailRow(
                    icon: Icons.info_outline_rounded,
                    title: 'Additional Information',
                    value: challenge.additionalInfo,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ======================================================
          // SUBMISSION DETAILS
          // ======================================================
          AppCard(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  title: 'Submitted',
                  value: _formatDate(challenge.createdAt),
                ),

                const SizedBox(height: 15),

                _InfoRow(
                  icon: Icons.update_rounded,
                  title: 'Last Updated',
                  value: _formatDate(challenge.updatedAt),
                ),

                const SizedBox(height: 15),

                _InfoRow(
                  icon: Icons.flag_outlined,
                  title: 'Priority',
                  value: challenge.effectivePriority,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ACTUAL CLOUDINARY EVIDENCE
// ============================================================

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ========================================================
        // IMAGE / VIDEO
        // ========================================================
        for (final media in challenge.media) ...[
          _MediaCard(media: media),

          const SizedBox(height: 12),
        ],

        // ========================================================
        // VOICE RECORDINGS
        // ========================================================
        for (final voice in challenge.voiceNotes) ...[
          _VoiceNoteCard(voice: voice),

          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ============================================================
// MEDIA CARD
// ============================================================

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.media});

  final ChallengeMedia media;

  @override
  Widget build(BuildContext context) {
    final type = media.type.toLowerCase();

    final isImage =
        type == 'photo' ||
        type == 'image' ||
        media.resourceType.toLowerCase() == 'image';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E7EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isImage)
            _CloudinaryImage(url: media.url)
          else
            _CloudinaryVideo(url: media.url),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  isImage ? Icons.image_outlined : Icons.videocam_outlined,
                  color: AppColors.citizen,
                  size: 20,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    isImage ? 'Photo evidence' : 'Video evidence',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                if (media.format.isNotEmpty)
                  Text(
                    media.format.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CLOUDINARY IMAGE
// ============================================================

class _CloudinaryImage extends StatelessWidget {
  const _CloudinaryImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: double.infinity,
      height: 230,
      fit: BoxFit.cover,

      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }

        return const SizedBox(
          height: 230,
          child: Center(child: CircularProgressIndicator()),
        );
      },

      errorBuilder: (context, error, stackTrace) {
        return const SizedBox(
          height: 180,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  size: 38,
                  color: AppColors.muted,
                ),
                SizedBox(height: 8),
                Text(
                  'Unable to load image',
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// CLOUDINARY VIDEO PLAYER
// ============================================================

class _CloudinaryVideo extends StatefulWidget {
  const _CloudinaryVideo({required this.url});

  final String url;

  @override
  State<_CloudinaryVideo> createState() => _CloudinaryVideoState();
}

class _CloudinaryVideoState extends State<_CloudinaryVideo> {
  late final VideoPlayerController _controller;

  bool _ready = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();

      if (!mounted) return;

      setState(() {
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _ready = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),

              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ],
          ),
        ),

        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ],
    );
  }
}

// ============================================================
// VOICE NOTE - CLOUDINARY AUDIO
// ============================================================

class _VoiceNoteCard extends StatefulWidget {
  const _VoiceNoteCard({required this.voice});

  final ChallengeVoiceNote voice;

  @override
  State<_VoiceNoteCard> createState() => _VoiceNoteCardState();
}

class _VoiceNoteCardState extends State<_VoiceNoteCard> {
  final AudioPlayer _player = AudioPlayer();

  bool _playing = false;

  @override
  void initState() {
    super.initState();

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _playing = false;
      });
    });
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();

        if (!mounted) return;

        setState(() {
          _playing = false;
        });

        return;
      }

      await _player.play(UrlSource(widget.voice.url));

      if (!mounted) return;

      setState(() {
        _playing = true;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = widget.voice;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.citizen.withOpacity(.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppColors.citizen,
                size: 27,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _voiceTitle(voice.field),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 5),

                if (voice.transcript.trim().isNotEmpty)
                  Text(
                    voice.transcript,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),

                if (voice.duration != null) ...[
                  const SizedBox(height: 5),

                  Text(
                    '${voice.duration!.toStringAsFixed(1)} sec',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _voiceTitle(String field) {
    switch (field) {
      case 'title':
        return 'Title voice note';

      case 'description':
        return 'Description voice note';

      case 'additional':
        return 'Additional information voice note';

      default:
        return 'Voice note';
    }
  }
}

// ============================================================
// HEADER
// ============================================================

class _ChallengeHeader extends StatelessWidget {
  const _ChallengeHeader({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(challenge.status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${challenge.id}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  challenge.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            challenge.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),

          const SizedBox(height: 11),

          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 17,
                color: AppColors.citizen,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  challenge.location,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.citizen.withOpacity(.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              challenge.category,
              style: TextStyle(
                color: AppColors.citizen,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _statusColor(String status) {
    final value = status.toLowerCase();

    if (value.contains('resolved') ||
        value.contains('completed') ||
        value.contains('deployed')) {
      return Colors.green;
    }

    if (value.contains('review') || value.contains('assigned')) {
      return Colors.orange;
    }

    if (value.contains('reject')) {
      return Colors.red;
    }

    return AppColors.citizen;
  }
}

// ============================================================
// PROGRESS
// ============================================================

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.status,
    required this.activeStep,
    required this.totalSteps,
    this.percent,
  });

  final String status;
  final int activeStep;
  final int totalSteps;

  /// Real project progress once a university is delivering; otherwise the
  /// bar follows the journey steps.
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final explicit = percent;
    final progress = explicit != null
        ? explicit / 100
        : (activeStep + 1) / totalSteps;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.citizen.withOpacity(.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: AppColors.citizen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.line,
              color: AppColors.citizen,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TIMELINE
// ============================================================

// ============================================================
// DETAILS
// ============================================================

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.citizen, size: 21),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.title,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.citizen, size: 19),

        const SizedBox(width: 10),

        Expanded(
          child: Text(title, style: const TextStyle(color: AppColors.muted)),
        ),

        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ============================================================
// HELPERS
// ============================================================

_TimelineData _timelineForChallenge(Challenge challenge) {
  final value = challenge.status.trim().toLowerCase();

  if (value == 'duplicate' || value == 'rejected') {
    final items = [
      'Submitted',
      'Under Review',
      value == 'duplicate'
          ? 'Merged with an existing report'
          : 'Not taken forward',
    ];
    return _TimelineData(
      items: [for (final item in items) _timelineLabel(challenge, item)],
      activeStep: 2,
    );
  }

  const items = [
    'Submitted',
    'Under Review',
    'Assigned to University',
    'In Progress',
    'Solution Deployed',
    'Resolved',
  ];

  var active = 0;

  if (value == 'under review') {
    active = 1;
  } else if (value.startsWith('assigned')) {
    active = 2;
  } else if (value == 'in progress') {
    active = 3;
  } else if (value == 'solution deployed' || value == 'deployed') {
    active = 4;
  } else if (value == 'resolved' || value == 'completed') {
    active = 5;
  }

  return _TimelineData(
    items: [for (final item in items) _timelineLabel(challenge, item)],
    activeStep: active,
  );
}

/// Adds when each step actually happened, from the status history.
String _timelineLabel(Challenge challenge, String item) {
  final assignedName = challenge.assignedUniversityName;
  final label = item == 'Assigned to University' && assignedName != null
      ? 'Assigned to $assignedName'
      : item;

  final prefix = switch (item) {
    'Under Review' => 'AI analysis complete',
    'Assigned to University' => 'Assigned to',
    'Merged with an existing report' => 'Merged',
    'Not taken forward' => 'Rejected',
    _ => item,
  };

  final event = challenge.latestEvent(prefix);
  return event == null ? label : '$label  ·  ${_shortDate(event.at)}';
}

String _shortDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${months[date.month - 1]}, $hour:$minute';
}

Widget _sectionTitle(String title, String subtitle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.title,
        ),
      ),

      const SizedBox(height: 3),

      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: AppColors.muted,
        ),
      ),
    ],
  );
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');

  final month = date.month.toString().padLeft(2, '0');

  final hour = date.hour.toString().padLeft(2, '0');

  final minute = date.minute.toString().padLeft(2, '0');

  return '$day/$month/${date.year} $hour:$minute';
}

class _TimelineData {
  const _TimelineData({required this.items, required this.activeStep});

  final List<String> items;
  final int activeStep;
}

// ============================================================
// ASSIGNMENT
// ============================================================

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final department = challenge.assignedDepartment;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.citizen.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.school_rounded, color: AppColors.citizen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Being handled by',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  challenge.assignedUniversityName ?? 'A partner university',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (department != null)
                  Text(
                    department,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                if (challenge.matchScore != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Matched by AI on expertise, focus area, capacity and location',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.citizen,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PROJECT PROGRESS
// ============================================================

class _ProjectProgressCard extends ConsumerWidget {
  const _ProjectProgressCard({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectStreamProvider(projectId)).asData?.value;
    if (project == null) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.engineering_rounded, color: AppColors.citizen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${project.progress}%',
                style: const TextStyle(
                  color: AppColors.citizen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            project.mentor.isEmpty
                ? project.universityName
                : '${project.universityName} · Mentor: ${project.mentor}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Timeline(
            items: project.milestoneNames,
            active: project.isCompleted
                ? project.milestones.length
                : project.activeMilestone,
            color: AppColors.citizen,
          ),
          if (project.hasImpactReport) ...[
            const SizedBox(height: 10),
            Text(
              'Impact: ${project.peopleImpacted} people. ${project.impactSummary}',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// ERROR
// ============================================================

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: AppColors.muted,
            ),

            const SizedBox(height: 12),

            Text(message, textAlign: TextAlign.center),

            const SizedBox(height: 15),

            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
