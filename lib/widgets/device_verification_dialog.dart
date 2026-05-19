import 'dart:async';

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
  Timer? _timeoutTimer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    widget.request.onUpdate = _onUpdate;
    _startTimeout();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    widget.request.onUpdate = null;
    super.dispose();
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      if (widget.request.isDone) return;
      setState(() => _timedOut = true);
    });
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    if (widget.request.isDone) {
      _timeoutTimer?.cancel();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
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

  Future<void> _acceptChoice() async {
    try {
      await widget.request.acceptVerification();
    } catch (_) {}
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
            if (_timedOut && !isDone) ...[
              const Icon(Icons.timer_off, color: Colors.orange),
              const SizedBox(height: 8),
              const Text(
                'Timed out waiting for the other device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange),
              ),
            ],
            if (isDone && state != KeyVerificationState.done) ...[
              const Icon(Icons.error, color: Colors.red),
              const SizedBox(height: 8),
              Text(
                widget.request.canceledReason ?? 'Verification failed.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],
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
        ] else if (state == KeyVerificationState.askChoice) ...[
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _acceptChoice,
            child: const Text('Continue'),
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
        ] else if (isDone || _timedOut) ...[
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
