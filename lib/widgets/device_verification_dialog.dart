import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';

class DeviceVerificationDialog extends StatefulWidget {
  final KeyVerification request;

  const DeviceVerificationDialog({super.key, required this.request});

  @override
  State<DeviceVerificationDialog> createState() =>
      _DeviceVerificationDialogState();
}

class _DeviceVerificationDialogState extends State<DeviceVerificationDialog> {
  @override
  void initState() {
    super.initState();
    widget.request.onUpdate = _onUpdate;
  }

  @override
  void dispose() {
    widget.request.onUpdate = null;
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _acceptIncoming() async {
    try {
      await widget.request.acceptVerification();
    } catch (_) {}
  }

  Future<void> _rejectIncoming() async {
    try {
      await widget.request.rejectVerification();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _acceptSas() async {
    try {
      await widget.request.acceptSas();
    } catch (_) {}
  }

  Future<void> _rejectSas() async {
    try {
      await widget.request.rejectSas();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    try {
      await widget.request.cancel('m.user');
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  String _stateMessage(KeyVerificationState state) {
    switch (state) {
      case KeyVerificationState.askAccept:
        return 'Another device wants to verify this session.';
      case KeyVerificationState.waitingAccept:
        return 'Waiting for the other device to accept...';
      case KeyVerificationState.askSas:
        return 'Compare the emojis below with your other device.';
      case KeyVerificationState.waitingSas:
        return 'Waiting for the other device to confirm...';
      case KeyVerificationState.done:
        return 'Device verified successfully!';
      case KeyVerificationState.error:
        final reason = widget.request.canceledReason ?? 'Verification failed.';
        return 'Verification failed: $reason';
      case KeyVerificationState.askChoice:
        return 'Choose a verification method...';
      case KeyVerificationState.askSSSS:
        return 'Secure backup key needed. Use recovery tools instead.';
      case KeyVerificationState.showQRSuccess:
        return 'QR code verified!';
      case KeyVerificationState.confirmQRScan:
        return 'Confirm QR scan...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.request.state;
    final isDone = widget.request.isDone;
    final emojis = state == KeyVerificationState.askSas
        ? widget.request.sasEmojis
        : <KeyVerificationEmoji>[];

    return AlertDialog(
      title: const Text('Verify Device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _stateMessage(state),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (emojis.isNotEmpty) ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: emojis
                    .map((e) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(e.emoji, style: const TextStyle(fontSize: 32)),
                            Text(
                              e.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (isDone && state != KeyVerificationState.done)
              const Icon(Icons.error, color: Colors.red),
            if (state == KeyVerificationState.done)
              const Icon(Icons.check_circle, color: Colors.green),
          ],
        ),
      ),
      actions: [
        if (state == KeyVerificationState.askAccept) ...[
          TextButton(
            onPressed: _rejectIncoming,
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: _acceptIncoming,
            child: const Text('Accept'),
          ),
        ] else if (state == KeyVerificationState.askSas) ...[
          TextButton(
            onPressed: _rejectSas,
            child: const Text("Don't match"),
          ),
          FilledButton(
            onPressed: _acceptSas,
            child: const Text('They match'),
          ),
        ] else if (isDone) ...[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ] else ...[
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ],
    );
  }
}
