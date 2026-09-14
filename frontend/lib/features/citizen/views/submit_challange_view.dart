import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stt_record/stt_record.dart';

import '../../../core/routes/app_routes.dart' show Routes;
import '../../../theme/app_colors.dart';
import '../../../widgets/ui.dart' show AppCard, PageFrame;
import '../controllers/citizen_controller.dart';

enum _VoiceField { title, description, additional }

class _VoiceAttachment {
  const _VoiceAttachment({
    required this.path,
    required this.field,
    required this.transcript,
    required this.createdAt,
  });

  final String path;
  final _VoiceField field;
  final String transcript;
  final DateTime createdAt;

  String get label {
    switch (field) {
      case _VoiceField.title:
        return 'Title voice note';

      case _VoiceField.description:
        return 'Description voice note';

      case _VoiceField.additional:
        return 'Additional information voice note';
    }
  }
}

class SubmitChallengeView extends ConsumerStatefulWidget {
  const SubmitChallengeView({super.key});

  @override
  ConsumerState<SubmitChallengeView> createState() =>
      _SubmitChallengeViewState();
}

class _SubmitChallengeViewState extends ConsumerState<SubmitChallengeView> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _additionalController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final Geocoding _geocoding = Geocoding();
  final SttRecord _stt = SttRecord();
  final AudioPlayer _audioPlayer = AudioPlayer();

  String _category = 'Water Management';

  final List<String> _categories = [
    'Water Management',
    'Waste Management',
    'Agriculture',
    'Infrastructure',
    'Healthcare',
    'Education',
    'Other',
  ];

  double? _latitude;
  double? _longitude;

  bool _isGettingLocation = false;

  bool _isCheckingDuplicates = false;

  XFile? _selectedMedia;
  String? _mediaType;

  bool _isPickingMedia = false;

  final List<_VoiceAttachment> _voiceAttachments = [];

  StreamSubscription? _voiceTranscriptSubscription;
  StreamSubscription? _playerCompleteSubscription;

  bool _isVoiceRecording = false;
  bool _isStartingVoice = false;

  _VoiceField? _activeVoiceField;

  String _voiceBaseText = '';
  String _liveVoiceTranscript = '';

  String? _playingVoicePath;

  @override
  void initState() {
    super.initState();

    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _playingVoicePath = null;
      });
    });
  }

  @override
  void dispose() {
    _voiceTranscriptSubscription?.cancel();
    _playerCompleteSubscription?.cancel();

    if (_isVoiceRecording) {
      _stt.cancel();
    }

    _audioPlayer.dispose();

    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _additionalController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submissionState = ref.watch(citizenControllerProvider);

    final isSubmitting = submissionState.isLoading;

    return PageFrame(
      title: 'Submit Challenge',
      color: AppColors.citizen,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
          children: [
            _buildHero(),

            const SizedBox(height: 26),

            // ==================================================
            // TITLE
            // ==================================================
            _sectionTitle(
              'Challenge title',
              'Type it or tap the microphone and describe it in your own words.',
            ),

            const SizedBox(height: 10),

            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: _inputDecoration(
                hint: 'e.g. Water shortage in Ward 12',
                icon: Icons.title_rounded,
              ).copyWith(suffixIcon: _voiceButton(_VoiceField.title)),
              validator: (value) {
                final text = value?.trim() ?? '';

                if (text.isEmpty) {
                  return 'Please enter a title';
                }

                if (text.length < 5) {
                  return 'Please add a little more detail';
                }

                return null;
              },
            ),

            if (_activeVoiceField == _VoiceField.title && _isVoiceRecording)
              _voiceRecordingIndicator('Listening and writing your title...'),

            _buildVoiceAttachments(_VoiceField.title),

            const SizedBox(height: 20),

            // ==================================================
            // CATEGORY
            // ==================================================
            _sectionTitle(
              'Category',
              'Choose the area that best matches the challenge.',
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 9,
              children: _categories.map((item) {
                final selected = item == _category;

                return ChoiceChip(
                  label: Text(item),
                  selected: selected,
                  showCheckmark: false,
                  avatar: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: 17,
                          color: AppColors.citizen,
                        )
                      : null,
                  onSelected: (_) {
                    setState(() {
                      _category = item;
                    });
                  },
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.citizen
                        : const Color(0xFF475467),
                  ),
                  selectedColor: AppColors.citizen.withOpacity(.10),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: selected
                        ? AppColors.citizen.withOpacity(.40)
                        : const Color(0xFFD9E0EA),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 26),

            // ==================================================
            // DESCRIPTION
            // ==================================================
            _sectionTitle(
              'Describe the issue',
              'Write or speak what is happening, who is affected, and why it needs attention.',
            ),

            const SizedBox(height: 10),

            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 4,
              maxLines: 7,
              maxLength: 600,
              decoration: _inputDecoration(
                hint:
                    'Describe what you have observed and why it needs attention...',
                icon: Icons.notes_rounded,
                alignTop: true,
              ).copyWith(suffixIcon: _voiceButton(_VoiceField.description)),
              validator: (value) {
                final text = value?.trim() ?? '';

                if (text.isEmpty) {
                  return 'Please describe the challenge';
                }

                if (text.length < 15) {
                  return 'Please provide a little more detail';
                }

                return null;
              },
            ),

            if (_activeVoiceField == _VoiceField.description &&
                _isVoiceRecording)
              _voiceRecordingIndicator(
                'Listening and writing your description...',
              ),

            _buildVoiceAttachments(_VoiceField.description),

            const SizedBox(height: 20),

            // ==================================================
            // LOCATION
            // ==================================================
            _sectionTitle(
              'Location',
              'Enter the place manually or use your current location.',
            ),

            const SizedBox(height: 10),

            TextFormField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_latitude != null || _longitude != null) {
                  setState(() {
                    _latitude = null;
                    _longitude = null;
                  });
                }
              },
              decoration:
                  _inputDecoration(
                    hint: 'City, district or area',
                    icon: Icons.location_on_outlined,
                  ).copyWith(
                    suffixIcon: _isGettingLocation
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Use current location',
                            onPressed: _getCurrentLocation,
                            icon: Icon(
                              Icons.my_location_rounded,
                              color: AppColors.citizen,
                            ),
                          ),
                  ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a location';
                }

                return null;
              },
            ),

            if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppColors.citizen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Location detected successfully',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.citizen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 26),

            // ==================================================
            // MEDIA
            // ==================================================
            _sectionTitle(
              'Add evidence',
              'Add a photo or video to help others understand the issue.',
              optional: true,
            ),

            const SizedBox(height: 12),

            _buildMediaCard(),

            const SizedBox(height: 26),

            // ==================================================
            // ADDITIONAL INFORMATION
            // ==================================================
            _sectionTitle(
              'Anything else?',
              'Type or speak any other useful information.',
              optional: true,
            ),

            const SizedBox(height: 10),

            TextFormField(
              controller: _additionalController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 5,
              maxLength: 300,
              decoration: _inputDecoration(
                hint:
                    'Nearby landmark, previous complaints, best time to visit...',
                icon: Icons.info_outline_rounded,
                alignTop: true,
              ).copyWith(suffixIcon: _voiceButton(_VoiceField.additional)),
            ),

            if (_activeVoiceField == _VoiceField.additional &&
                _isVoiceRecording)
              _voiceRecordingIndicator('Listening...'),

            _buildVoiceAttachments(_VoiceField.additional),

            const SizedBox(height: 28),

            // ==================================================
            // ATTACHMENT SUMMARY
            // ==================================================
            if (_selectedMedia != null || _voiceAttachments.isNotEmpty)
              _buildAttachmentSummary(),

            if (_selectedMedia != null || _voiceAttachments.isNotEmpty)
              const SizedBox(height: 18),

            _buildInfoBox(),

            const SizedBox(height: 22),

            // ==================================================
            // SUBMIT
            // ==================================================
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed:
                    isSubmitting || _isVoiceRecording || _isCheckingDuplicates
                    ? null
                    : _submit,
                icon: isSubmitting || _isCheckingDuplicates
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _isVoiceRecording
                      ? 'Finish voice recording first'
                      : _isCheckingDuplicates
                      ? 'Checking for similar reports...'
                      : isSubmitting
                      ? 'Submitting...'
                      : 'Submit Challenge',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.citizen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),

            if (submissionState.hasError) ...[
              const SizedBox(height: 12),
              Text(
                submissionState.error.toString().replaceFirst(
                  'Exception: ',
                  '',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SUBMIT WITH RIVERPOD
  // ============================================================

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_isVoiceRecording) {
      _showError('Please finish your voice recording before submitting.');

      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final voiceFiles = _voiceAttachments.map((voice) {
      return VoiceUploadInput(
        file: File(voice.path),
        field: voice.field.name,
        transcript: voice.transcript,
      );
    }).toList();

    // Offer the citizen an existing report of the same problem first.
    final proceed = await _confirmNotDuplicate();

    if (!proceed || !mounted) return;

    final challenge = await ref
        .read(citizenControllerProvider.notifier)
        .submitChallenge(
          title: _titleController.text.trim(),

          description: _descriptionController.text.trim(),

          category: _category,

          location: _locationController.text.trim(),

          additionalInfo: _additionalController.text.trim(),

          latitude: _latitude,

          longitude: _longitude,

          mediaFile: _selectedMedia == null ? null : File(_selectedMedia!.path),

          mediaType: _mediaType,

          voiceFiles: voiceFiles,
        );

    if (!mounted) return;

    if (challenge == null) {
      final state = ref.read(citizenControllerProvider);

      if (state.hasError) {
        _showError(state.error.toString().replaceFirst('Exception: ', ''));
      }

      return;
    }

    Navigator.pushNamed(context, Routes.success, arguments: challenge);

    ref.read(citizenControllerProvider.notifier).reset();
  }

  // ============================================================
  // DUPLICATE CHECK
  // ============================================================

  Future<bool> _confirmNotDuplicate() async {
    setState(() {
      _isCheckingDuplicates = true;
    });

    final check = await ref
        .read(citizenControllerProvider.notifier)
        .checkDuplicates(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          additionalInfo: _additionalController.text.trim(),
          category: _category,
          location: _locationController.text.trim(),
        );

    if (!mounted) return false;

    setState(() {
      _isCheckingDuplicates = false;
    });

    final match = check?.bestMatch;

    // No answer from the AI service is never a reason to block a report.
    if (check == null || !check.isDuplicate || match == null) return true;

    final submitAnyway = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.content_copy_rounded, color: Color(0xFFB54708)),
        title: const Text('This may already be reported'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Someone has reported a very similar problem:'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${match.scorePercent}% similar'
                    '${match.sameLocation ? ' · same area' : ''}'
                    ' · ${match.status}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'If it is the same problem, you do not need to report it again. '
              'If yours is different, submit it anyway.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Review my report'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.citizen),
            child: const Text('Submit anyway'),
          ),
        ],
      ),
    );

    return submitAnyway ?? false;
  }

  // ============================================================
  // VOICE - START
  // ============================================================

  Future<void> _startVoiceRecording(_VoiceField field) async {
    FocusScope.of(context).unfocus();

    if (_isVoiceRecording) {
      await _stopVoiceRecording();
    }

    if (!mounted) return;

    setState(() {
      _isStartingVoice = true;
    });

    try {
      final hasPermission = await _stt.requestPermission();

      if (!hasPermission) {
        if (!mounted) return;

        _showError(
          'Microphone and speech recognition permission are required.',
        );

        return;
      }

      final controller = _controllerForVoiceField(field);

      await _voiceTranscriptSubscription?.cancel();

      _activeVoiceField = field;

      _voiceBaseText = controller.text.trim();

      _liveVoiceTranscript = '';

      _voiceTranscriptSubscription = _stt.transcripts.listen(
        (event) {
          if (!mounted || _activeVoiceField != field) {
            return;
          }

          final transcript = event.text.trim();

          if (transcript.isEmpty) {
            return;
          }

          _liveVoiceTranscript = transcript;

          _applyTranscriptToField(field, transcript);
        },
        onError: (error) {
          if (!mounted) return;

          _showError('Speech recognition failed. Please try again.');
        },
      );

      await _stt.start(localeId: 'en-IN', partialResults: true);

      if (!mounted) return;

      setState(() {
        _isVoiceRecording = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _activeVoiceField = null;
        _isVoiceRecording = false;
      });

      _showError('Unable to start voice input.');
    } finally {
      if (mounted) {
        setState(() {
          _isStartingVoice = false;
        });
      }
    }
  }

  void _applyTranscriptToField(_VoiceField field, String transcript) {
    final controller = _controllerForVoiceField(field);

    var combined = _voiceBaseText.isEmpty
        ? transcript
        : '$_voiceBaseText $transcript';

    final maxLength = _maxLengthForVoiceField(field);

    if (combined.length > maxLength) {
      combined = combined.substring(0, maxLength);
    }

    controller.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );

    setState(() {});
  }

  Future<void> _stopVoiceRecording() async {
    if (!_isVoiceRecording || _activeVoiceField == null) {
      return;
    }

    final field = _activeVoiceField!;

    try {
      final result = await _stt.stop();

      await _voiceTranscriptSubscription?.cancel();

      _voiceTranscriptSubscription = null;

      String? permanentAudioPath;

      if (result.audioPath.isNotEmpty) {
        permanentAudioPath = await _persistVoiceFile(result.audioPath, field);
      }

      if (permanentAudioPath != null) {
        _voiceAttachments.add(
          _VoiceAttachment(
            path: permanentAudioPath,
            field: field,
            transcript: _liveVoiceTranscript,
            createdAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _isVoiceRecording = false;
        _activeVoiceField = null;
        _voiceBaseText = '';
        _liveVoiceTranscript = '';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isVoiceRecording = false;
        _activeVoiceField = null;
      });

      _showError('Unable to save your voice recording.');
    }
  }

  Future<String> _persistVoiceFile(
    String temporaryPath,
    _VoiceField field,
  ) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();

    final voiceDirectory = Directory(
      '${documentsDirectory.path}'
      '${Platform.pathSeparator}'
      'challenge_voice_notes',
    );

    if (!await voiceDirectory.exists()) {
      await voiceDirectory.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final fieldName = switch (field) {
      _VoiceField.title => 'title',
      _VoiceField.description => 'description',
      _VoiceField.additional => 'additional',
    };

    final permanentPath =
        '${voiceDirectory.path}'
        '${Platform.pathSeparator}'
        '${fieldName}_$timestamp.wav';

    final source = File(temporaryPath);

    final copied = await source.copy(permanentPath);

    return copied.path;
  }

  Future<void> _toggleVoicePlayback(_VoiceAttachment attachment) async {
    try {
      if (_playingVoicePath == attachment.path) {
        await _audioPlayer.stop();

        if (!mounted) return;

        setState(() {
          _playingVoicePath = null;
        });

        return;
      }

      await _audioPlayer.stop();

      await _audioPlayer.play(DeviceFileSource(attachment.path));

      if (!mounted) return;

      setState(() {
        _playingVoicePath = attachment.path;
      });
    } catch (e) {
      if (!mounted) return;

      _showError('Unable to play this recording.');
    }
  }

  Future<void> _deleteVoiceAttachment(_VoiceAttachment attachment) async {
    try {
      if (_playingVoicePath == attachment.path) {
        await _audioPlayer.stop();

        _playingVoicePath = null;
      }

      final file = File(attachment.path);

      if (await file.exists()) {
        await file.delete();
      }

      if (!mounted) return;

      setState(() {
        _voiceAttachments.remove(attachment);
      });
    } catch (e) {
      if (!mounted) return;

      _showError('Unable to delete this recording.');
    }
  }

  Widget _voiceButton(_VoiceField field) {
    final isRecordingThisField =
        _activeVoiceField == field && _isVoiceRecording;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: isRecordingThisField
            ? Colors.red.withOpacity(.10)
            : AppColors.citizen.withOpacity(.08),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: isRecordingThisField
              ? 'Stop recording'
              : 'Speak instead of typing',
          onPressed: _isStartingVoice
              ? null
              : () {
                  if (isRecordingThisField) {
                    _stopVoiceRecording();
                  } else {
                    _startVoiceRecording(field);
                  }
                },
          icon: _isStartingVoice && _activeVoiceField == field
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isRecordingThisField
                      ? Icons.stop_rounded
                      : Icons.mic_none_rounded,
                  color: isRecordingThisField
                      ? Colors.redAccent
                      : AppColors.citizen,
                ),
        ),
      ),
    );
  }

  Widget _voiceRecordingIndicator(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475467),
              ),
            ),
          ),

          TextButton.icon(
            onPressed: _stopVoiceRecording,
            icon: const Icon(Icons.stop_rounded, size: 17),
            label: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceAttachments(_VoiceField field) {
    final items = _voiceAttachments
        .where((item) => item.field == field)
        .toList();

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _voiceAttachmentTile(item),
            ),
        ],
      ),
    );
  }

  Widget _voiceAttachmentTile(_VoiceAttachment item) {
    final isPlaying = _playingVoicePath == item.path;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.citizen.withOpacity(.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.citizen.withOpacity(.14)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => _toggleVoicePlayback(item),
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.citizen.withOpacity(.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: AppColors.citizen,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.transcript.trim().isEmpty
                      ? 'Audio recording saved'
                      : item.transcript,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Delete voice note',
            onPressed: () => _deleteVoiceAttachment(item),
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }

  TextEditingController _controllerForVoiceField(_VoiceField field) {
    switch (field) {
      case _VoiceField.title:
        return _titleController;

      case _VoiceField.description:
        return _descriptionController;

      case _VoiceField.additional:
        return _additionalController;
    }
  }

  int _maxLengthForVoiceField(_VoiceField field) {
    switch (field) {
      case _VoiceField.title:
        return 80;

      case _VoiceField.description:
        return 600;

      case _VoiceField.additional:
        return 300;
    }
  }

  // ============================================================
  // CURRENT LOCATION
  // ============================================================

  Future<void> _getCurrentLocation() async {
    FocusScope.of(context).unfocus();

    if (_isGettingLocation) {
      return;
    }

    setState(() {
      _isGettingLocation = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        _showLocationServiceDialog();

        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;

        _showError('Location permission is required to detect your location.');

        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        _showLocationSettingsDialog();

        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _latitude = position.latitude;

      _longitude = position.longitude;

      try {
        final placemarks = await _geocoding.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;

          final parts = <String>[
            if ((place.subLocality ?? '').trim().isNotEmpty)
              place.subLocality!.trim(),

            if ((place.locality ?? '').trim().isNotEmpty)
              place.locality!.trim(),

            if ((place.subAdministrativeArea ?? '').trim().isNotEmpty)
              place.subAdministrativeArea!.trim(),

            if ((place.administrativeArea ?? '').trim().isNotEmpty)
              place.administrativeArea!.trim(),
          ];

          final uniqueParts = <String>[];

          for (final part in parts) {
            final exists = uniqueParts.any(
              (existing) => existing.toLowerCase() == part.toLowerCase(),
            );

            if (!exists) {
              uniqueParts.add(part);
            }
          }

          if (!mounted) return;

          setState(() {
            _locationController.text = uniqueParts.isNotEmpty
                ? uniqueParts.join(', ')
                : '${position.latitude.toStringAsFixed(5)}, '
                      '${position.longitude.toStringAsFixed(5)}';
          });
        } else {
          if (!mounted) return;

          setState(() {
            _locationController.text =
                '${position.latitude.toStringAsFixed(5)}, '
                '${position.longitude.toStringAsFixed(5)}';
          });
        }
      } catch (_) {
        if (!mounted) return;

        setState(() {
          _locationController.text =
              '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)}';
        });
      }
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to detect your location. Please enter it manually or try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Turn on location'),
          content: const Text(
            'Location services are currently turned off. Please enable GPS to use your current location.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                await Geolocator.openLocationSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showLocationSettingsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Location permission needed'),
          content: const Text(
            'Location permission has been permanently disabled. Enable it from your device settings.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                await Geolocator.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // MEDIA
  // ============================================================

  Widget _buildMediaCard() {
    if (_isPickingMedia) {
      return AppCard(
        child: const SizedBox(
          height: 70,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_selectedMedia == null) {
      return AppCard(
        onTap: () => _showMediaOptions(context),
        child: Row(
          children: [
            _mediaIcon(Icons.add_photo_alternate_outlined),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add photo or video',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Camera or gallery',
                    style: TextStyle(color: Color(0xFF667085), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 15,
              color: Color(0xFF98A2B3),
            ),
          ],
        ),
      );
    }

    return AppCard(
      onTap: () => _showMediaOptions(context),
      child: Column(
        children: [
          if (_mediaType == 'Photo')
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_selectedMedia!.path),
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),

          if (_mediaType == 'Photo') const SizedBox(height: 12),

          Row(
            children: [
              _mediaIcon(
                _mediaType == 'Video'
                    ? Icons.videocam_rounded
                    : Icons.image_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mediaType == 'Video'
                          ? 'Video selected'
                          : 'Photo selected',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _selectedMedia!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove attachment',
                onPressed: _removeMedia,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFF667085),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMediaOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add evidence',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),

                const SizedBox(height: 4),

                const Text(
                  'Take something now or choose it from your device.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: _mediaAction(
                        icon: Icons.camera_alt_outlined,
                        label: 'Take Photo',
                        onTap: () {
                          Navigator.pop(sheetContext);

                          _pickImage(ImageSource.camera);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _mediaAction(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: () {
                          Navigator.pop(sheetContext);

                          _pickImage(ImageSource.gallery);
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _mediaAction(
                        icon: Icons.videocam_outlined,
                        label: 'Record Video',
                        onTap: () {
                          Navigator.pop(sheetContext);

                          _pickVideo(ImageSource.camera);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _mediaAction(
                        icon: Icons.video_library_outlined,
                        label: 'Video Gallery',
                        onTap: () {
                          Navigator.pop(sheetContext);

                          _pickVideo(ImageSource.gallery);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _isPickingMedia = true;
    });

    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );

      if (file == null) {
        return;
      }

      final persisted = await _persistPickedMedia(file, 'Photo');

      if (!mounted) return;

      setState(() {
        _selectedMedia = persisted;
        _mediaType = 'Photo';
      });
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to select the photo. Please check camera/photo permissions.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingMedia = false;
        });
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    setState(() {
      _isPickingMedia = true;
    });

    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 2),
      );

      if (file == null) {
        return;
      }

      final persisted = await _persistPickedMedia(file, 'Video');

      if (!mounted) return;

      setState(() {
        _selectedMedia = persisted;
        _mediaType = 'Video';
      });
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to select the video. Please check camera/photo permissions.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingMedia = false;
        });
      }
    }
  }

  Future<XFile> _persistPickedMedia(XFile pickedFile, String type) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();

    final mediaDirectory = Directory(
      '${documentsDirectory.path}'
      '${Platform.pathSeparator}'
      'challenge_media',
    );

    if (!await mediaDirectory.exists()) {
      await mediaDirectory.create(recursive: true);
    }

    final source = File(pickedFile.path);

    var extension = '';

    final fileName = pickedFile.path.split(Platform.pathSeparator).last;

    if (fileName.contains('.')) {
      extension = '.${fileName.split('.').last}';
    }

    if (extension.isEmpty) {
      extension = type == 'Photo' ? '.jpg' : '.mp4';
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final destination =
        '${mediaDirectory.path}'
        '${Platform.pathSeparator}'
        '${type.toLowerCase()}_$timestamp$extension';

    final copiedFile = await source.copy(destination);

    return XFile(copiedFile.path);
  }

  Future<void> _removeMedia() async {
    final current = _selectedMedia;

    setState(() {
      _selectedMedia = null;
      _mediaType = null;
    });

    if (current == null) {
      return;
    }

    try {
      final file = File(current.path);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  // ============================================================
  // UI HELPERS
  // ============================================================

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.citizen.withOpacity(.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.citizen.withOpacity(.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.campaign_rounded,
              color: AppColors.citizen,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tell us what needs attention',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  'Type it, speak it, add evidence, and share the exact location.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentSummary() {
    final voiceCount = _voiceAttachments.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.citizen.withOpacity(.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.citizen.withOpacity(.10)),
      ),
      child: Row(
        children: [
          Icon(Icons.attach_file_rounded, color: AppColors.citizen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                if (_selectedMedia != null) '1 ${_mediaType?.toLowerCase()}',
                if (voiceCount > 0)
                  '$voiceCount voice ${voiceCount == 1 ? 'recording' : 'recordings'}',
              ].join(' • '),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const Icon(
            Icons.cloud_upload_outlined,
            size: 19,
            color: Color(0xFF667085),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 19,
            color: Color(0xFF667085),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Please make sure the description, location and attached evidence are accurate before submitting.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFF667085),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: AppColors.citizen, size: 27),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle, {bool optional = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF182230),
              ),
            ),
            if (optional) ...[
              const SizedBox(width: 7),
              const Text(
                'Optional',
                style: TextStyle(fontSize: 11, color: Color(0xFF98A2B3)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: Color(0xFF667085),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    bool alignTop = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDE3EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.citizen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  Widget _mediaIcon(IconData icon) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.citizen.withOpacity(.10),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: AppColors.citizen),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
