import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dot_matrix/widgets/dot_matrix_loader.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

import '../utils/pinned_http_client.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Uint8List? encryptedBytes;
  final String? videoUrl;
  final String? mimetype;

  const VideoPlayerScreen({
    super.key,
    this.encryptedBytes,
    this.videoUrl,
    this.mimetype,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  static const MethodChannel _videoChannel = MethodChannel('dot_matrix/video');

  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _videoPath;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      File? tempFile;
      final tempDir = await getTemporaryDirectory();
      final ext = _extensionFromMimetype(widget.mimetype);
      final ts = DateTime.now().millisecondsSinceEpoch;

      if (widget.encryptedBytes != null) {
        tempFile = File('${tempDir.path}/video_$ts$ext');
        await tempFile.writeAsBytes(widget.encryptedBytes!);
      } else if (widget.videoUrl != null) {
        tempFile = File('${tempDir.path}/video_$ts$ext');
        final videoUri = Uri.parse(widget.videoUrl!);
        final req = await createPinnedIoHttpClient().getUrl(videoUri);
        final res = await req.close();
        final effectiveUri = res.redirects.isNotEmpty
            ? res.redirects.last.location
            : videoUri;
        await validatePinnedTlsCertificate(effectiveUri, res.certificate);
        await res.pipe(tempFile.openWrite());
      } else {
        throw Exception('No video source provided');
      }

      _videoPath = tempFile.path;
      _controller = VideoPlayerController.file(tempFile);
      _controller!.addListener(_onControllerUpdate);
      await _controller!.initialize();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (_controller == null) return;
    final error = _controller!.value.errorDescription;
    if (error != null && error.isNotEmpty && mounted && !_hasError) {
      setState(() => _hasError = true);
    }
  }

  String _extensionFromMimetype(String? mimetype) {
    if (mimetype == null) return '.mp4';
    final mime = mimetype.toLowerCase();
    if (mime.contains('3gp')) return '.3gp';
    if (mime.contains('mp4')) return '.mp4';
    if (mime.contains('webm')) return '.webm';
    if (mime.contains('mov')) return '.mov';
    if (mime.contains('mkv')) return '.mkv';
    if (mime.contains('avi')) return '.avi';
    return '.mp4';
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openExternal() async {
    final url = widget.videoUrl;
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final path = _videoPath;
    if (path != null) {
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _saveVideo(BuildContext context) async {
    final path = _videoPath;
    if (path == null) return;
    try {
      await Gal.putVideo(path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to gallery')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  void _togglePlay() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.setPlaybackSpeed(speed);
    if (mounted) {
      setState(() => _playbackSpeed = speed);
    }
  }

  Future<void> _seekRelative(Duration offset) async {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.value.position;
    final duration = controller.value.duration;
    var target = current + offset;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (target > duration) {
      target = duration;
    }
    await controller.seekTo(target);
  }

  Future<void> _enterPictureInPicture(BuildContext context) async {
    if (!Platform.isAndroid || _controller == null) {
      return;
    }
    final size = _controller!.value.size;
    try {
      final entered = await _videoChannel.invokeMethod<bool>(
        'enterPictureInPicture',
        <String, int>{
          'aspectRatioX': size.width.round().clamp(1, 10000),
          'aspectRatioY': size.height.round().clamp(1, 10000),
        },
      );
      if (entered != true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Picture-in-picture is unavailable')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Picture-in-picture failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<double>(
            tooltip: 'Playback speed',
            initialValue: _playbackSpeed,
            onSelected: _setPlaybackSpeed,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0.75, child: Text('0.75x')),
              PopupMenuItem(value: 1.0, child: Text('1.0x')),
              PopupMenuItem(value: 1.25, child: Text('1.25x')),
              PopupMenuItem(value: 1.5, child: Text('1.5x')),
              PopupMenuItem(value: 2.0, child: Text('2.0x')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  '${_playbackSpeed.toStringAsFixed(_playbackSpeed == 1 ? 0 : 2).replaceAll(RegExp(r'\\.00$'), '')}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              onPressed: _controller == null ? null : () => _enterPictureInPicture(context),
            ),
          if (_videoPath != null)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: () => _saveVideo(context),
            ),
        ],
      ),
      body: Center(
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const DotMatrixLoader(color: Colors.white);
    }
    if (_hasError || _controller == null || !_controller!.value.isInitialized) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          const Text('Unable to play video', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open with external player'),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor: Colors.white,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller!),
            if (!_controller!.value.isPlaying)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white54,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () => _seekRelative(const Duration(seconds: -10)),
                          icon: const Icon(Icons.replay_10, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: _togglePlay,
                          icon: Icon(
                            _controller!.value.isPlaying
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _seekRelative(const Duration(seconds: 10)),
                          icon: const Icon(Icons.forward_10, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
