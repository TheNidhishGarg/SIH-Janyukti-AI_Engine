import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_role.dart';
import '../../../widgets/intputs/custom_otp.dart';
import '../controllers/auth_controller.dart';

class OtpView extends ConsumerStatefulWidget {
  const OtpView({super.key, this.verificationId, this.phoneNumber});
  final String? verificationId;
  final String? phoneNumber;
  @override
  ConsumerState<OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends ConsumerState<OtpView> {
  String code = '';
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final ready = widget.verificationId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 34),
              const Icon(
                Icons.verified_user_outlined,
                size: 72,
                color: Color(0xFF218C4A),
              ),
              const SizedBox(height: 18),
              const Text(
                'Verify your mobile number',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                ready
                    ? 'Enter the OTP sent to ${widget.phoneNumber}.'
                    : 'Start phone sign-in again to request an OTP.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              if (ready)
                CustomOtp(onCompleted: (value) => setState(() => code = value)),
              if (auth.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    auth.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: !ready || auth.isLoading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF218C4A),
                    foregroundColor: Colors.white,
                  ),
                  child: auth.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Verify & Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verify() async {
    final verified = await ref
        .read(authControllerProvider)
        .verifyCitizenOtp(widget.verificationId!, code);
    if (verified && mounted) {
      ref.read(authControllerProvider).openDashboard(context, UserRole.citizen);
    }
  }
}
