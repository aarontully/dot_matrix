import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dot_matrix/widgets/dot_matrix_loader.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Uint8List? encryptedBytes;
  final String? videoUrl;
  final Map<String, String>? httpHeaders;
  final String? mimetype;

  const VideoPlayerScreen({
    super.key,
    this.encryptedBytes,
    this.videoUrl,
    this.httpHeaders,
    this.mimetype,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _videoPath;

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
        final req = await HttpClient().getUrl(Uri.parse(widget.videoUrl!));
        widget.httpHeaders?.forEach(req.headers.set);
        final res = await req.close();
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
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white54,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
