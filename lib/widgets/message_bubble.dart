import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dot_matrix/widgets/dot_matrix_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:photo_view/photo_view.dart';

import '../controllers/auth_controller.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_url_resolver.dart';
import '../utils/matrix_media_uri.dart';
import '../utils/video_thumbnail_helper.dart';
import '../screens/video_player_screen.dart';

enum MessageAction {
  reply,
  copy,
  forward,
  more,
  react,
  delete,
  translate,
  edit,
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    this.isMetaAi = false,
    this.showReadReceipts = false,
    this.replyToEvent,
    this.onReplyTap,
    this.onAction,
  });

  final AppEvent event;
  final bool isMe;
  final bool isMetaAi;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool showReadReceipts;
  final AppEvent? replyToEvent;
  final void Function(String eventId)? onReplyTap;
  final void Function(MessageAction action, AppEvent event, {String? reaction})?
  onAction;

  bool get _isVisualMedia {
    final renderEvent = event.displayEvent;
    final type = renderEvent.messageType;
    if (type == MessageTypes.Image ||
        type == MessageTypes.Video ||
        type == MessageTypes.Sticker) {
      return true;
    }
    final hasUrl =
        renderEvent.content['url'] is String ||
        renderEvent.content['file'] is Map;
    if (type == MessageTypes.File || hasUrl) {
      final info = renderEvent.content['info'];
      if (info is Map) {
        final mime = (info['mimetype'] as String?)?.toLowerCase() ?? '';
        if (mime.startsWith('image/') || mime.startsWith('video/')) return true;
      }
    }
    // Check processed body and raw content fields; some bridges use
    // custom msgtypes that don't hit the first check above.
    final candidates = [
      event.body,
      renderEvent.content['body'],
      renderEvent.content['filename'],
      renderEvent.content['name'],
    ].whereType<String>().map((s) => s.toLowerCase().trim());

    for (final text in candidates) {
      if (text.endsWith('.jpg') ||
          text.endsWith('.jpeg') ||
          text.endsWith('.png') ||
          text.endsWith('.gif') ||
          text.endsWith('.webp') ||
          text.endsWith('.bmp') ||
          text.endsWith('.heic') ||
          text.endsWith('.mp4') ||
          text.endsWith('.mov') ||
          text.endsWith('.avi') ||
          text.endsWith('.mkv') ||
          text.endsWith('.webm')) {
        return true;
      }
      if (RegExp(
        r'\.\s*(?:jpg|jpeg|png|gif|webp|bmp|heic|mp4|mov|avi|mkv|webm)\b',
      ).hasMatch(text)) {
        return true;
      }
      if (RegExp(
        r'https?://[^\s]+\.(?:jpg|jpeg|png|gif|webp|bmp|heic|mp4|mov|avi|mkv|webm)',
      ).hasMatch(text)) {
        return true;
      }
    }
    // Brute-force: some bridges stash the filename or URL in an arbitrary key.
    final extPattern = RegExp(
      r'\.(?:jpg|jpeg|png|gif|webp|bmp|heic|mp4|mov|avi|mkv|webm)\b',
    );
    final urlPattern = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+\.(?:jpg|jpeg|png|gif|webp|bmp|heic|mp4|mov|avi|mkv|webm)',
    );
    for (final value in renderEvent.content.values) {
      if (value is String) {
        final v = value.toLowerCase();
        if (extPattern.hasMatch(v) || urlPattern.hasMatch(v)) {
          return true;
        }
      } else if (value is Map) {
        for (final nested in value.values) {
          if (nested is String) {
            final v = nested.toLowerCase();
            if (extPattern.hasMatch(v) || urlPattern.hasMatch(v)) {
              return true;
            }
          }
        }
      }
    }
    // Some bridges (e.g. Google Messages) embed image bytes in base64.
    final rawDebug = renderEvent.content['fi.mau.gmessages.raw_debug_data'];
    if (rawDebug is String && rawDebug.isNotEmpty) {
      if (rawDebug.contains('/9j/') ||
          rawDebug.contains('iVBORw0KGgo') ||
          rawDebug.contains('R0lGOD') ||
          rawDebug.contains('UklGR')) {
        return true;
      }
    }
    return false;
  }

  bool get _isAudio {
    final type = event.displayEvent.messageType;
    return type == MessageTypes.Audio;
  }

  bool get _isRedacted => event.rawEvent.redactedBecause != null;

  Widget? _buildReplyReference(_BubbleFill bubbleFill) {
    final target = replyToEvent;
    final tap = onReplyTap;
    if (target == null) return null;
    final accent = isMe ? bubbleFill.textColor : const Color(0xFF00C875);
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? bubbleFill.color?.withValues(alpha: 0.5)
            : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  target.senderName ?? target.senderId,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  target.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: bubbleFill.textColor.withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (tap == null) return child;
    return GestureDetector(
      onTap: () => tap(target.rawEvent.eventId),
      child: child,
    );
  }

  Widget _buildContent(BuildContext context, _BubbleFill bubbleFill) {
    final replyRef = _buildReplyReference(bubbleFill);

    debugPrint(
      '[MessageBubble._buildContent] eventId=${event.rawEvent.eventId} '
      'msgtype=${event.displayEvent.messageType} body="${event.body}" '
      '_isVisualMedia=$_isVisualMedia _isAudio=$_isAudio',
    );

    if (_isVisualMedia) {
      final media = ClipRRect(
        borderRadius: _borderRadius(),
        child: _MediaAttachmentBubble(
          event: event,
          textColor: bubbleFill.textColor,
          onImageTap: (provider, bytes, url) =>
              _showFullScreenImage(context, provider, bytes: bytes, url: url),
        ),
      );
      if (replyRef == null) return media;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 4), child: replyRef),
          media,
        ],
      );
    }

    if (_isAudio) {
      final audio = _AudioAttachmentBubble(
        event: event,
        textColor: bubbleFill.textColor,
        bubbleColor: bubbleFill.color,
        borderRadius: _borderRadius(),
      );
      if (replyRef == null) return audio;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 4), child: replyRef),
          audio,
        ],
      );
    }

    // Text message
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bubbleFill.color,
        gradient: bubbleFill.gradient,
        borderRadius: _borderRadius(),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (replyRef != null) ...[replyRef, const SizedBox(height: 8)],
            _isRedacted
                ? Text(
                    event.body,
                    style: TextStyle(
                      color: bubbleFill.textColor,
                      fontSize: 15,
                      height: 1.28,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Linkify(
                    text: event.body,
                    style: TextStyle(
                      color: bubbleFill.textColor,
                      fontSize: 15,
                      height: 1.28,
                    ),
                    linkStyle: TextStyle(
                      color: bubbleFill.textColor,
                      fontSize: 15,
                      height: 1.28,
                      decoration: TextDecoration.underline,
                    ),
                    onOpen: (link) async {
                      final uri = Uri.tryParse(link.url);
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.jm().format(event.originServerTs),
                    style: TextStyle(
                      fontSize: 10,
                      color: bubbleFill.textColor.withValues(alpha: 0.5),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    Icon(
                      event.rawEvent.status == EventStatus.sending
                          ? Icons.access_time
                          : (event.rawEvent.status == EventStatus.sent ||
                                event.rawEvent.status == EventStatus.synced)
                          ? Icons.done_all
                          : Icons.error_outline,
                      size: 14,
                      color: bubbleFill.textColor.withValues(alpha: 0.5),
                    ),
                    if (event.isEdited) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Edited',
                        style: TextStyle(
                          color: bubbleFill.textColor.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(
    BuildContext context,
    ImageProvider imageProvider, {
    Uint8List? bytes,
    String? url,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          Future<void> downloadImage() async {
            try {
              Uint8List? imageBytes = bytes;
              if (imageBytes == null && url != null) {
                final req = await HttpClient().getUrl(Uri.parse(url));
                final client = Get.find<AuthController>().client;
                if (client.accessToken != null) {
                  req.headers.set(
                    'Authorization',
                    'Bearer ${client.accessToken}',
                  );
                }
                final res = await req.close();
                imageBytes = Uint8List.fromList(
                  await res.expand((x) => x).toList(),
                );
              }
              if (imageBytes != null) {
                final tempDir = await getTemporaryDirectory();
                final tempFile = File(
                  '${tempDir.path}/dm_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
                );
                await tempFile.writeAsBytes(imageBytes);
                await Gal.putImage(tempFile.path);
              } else {
                throw Exception('No image data');
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved to gallery')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
              }
            }
          }

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
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  onPressed: downloadImage,
                ),
              ],
            ),
            body: Center(
              child: PhotoView(
                imageProvider: imageProvider,
                minScale: PhotoViewComputedScale.contained * 0.8,
                maxScale: PhotoViewComputedScale.covered * 2,
                heroAttributes: PhotoViewHeroAttributes(
                  tag: event.rawEvent.eventId,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleFill = _bubbleFill(context);
    final showAvatar = !isMe && isFirstInGroup;
    final topSpacing = isFirstInGroup ? 8.0 : 2.0;
    final bottomSpacing = isLastInGroup ? 3.0 : 0.0;

    final readReceiptWidgets = _buildReadReceipts(context);

    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisAlignment: isMe
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe) ...[const SizedBox(width: 36)],
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                      ),
                      child: GestureDetector(
                        onLongPress: onAction != null
                            ? () {
                                HapticFeedback.mediumImpact();
                                _showActionSheet(context);
                              }
                            : null,
                        onDoubleTap: onAction != null
                            ? () {
                                HapticFeedback.lightImpact();
                                onAction!.call(
                                  MessageAction.react,
                                  event,
                                  reaction: '❤️',
                                );
                              }
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildContent(context, bubbleFill),
                            if (event.reactions.isNotEmpty)
                              Transform.translate(
                                offset: const Offset(0, -10),
                                child: _buildReactions(context),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (showAvatar)
                Positioned(top: -4, left: 14, child: _buildAvatar()),
            ],
          ),
          if (isMe && showReadReceipts && readReceiptWidgets != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 2),
              child: readReceiptWidgets,
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final displayName = event.senderName?.isNotEmpty == true
        ? event.senderName!
        : (event.senderId.isEmpty ? '?' : event.senderId.replaceAll('@', ''));
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final client = Get.find<AuthController>().client;
    final avatarImageUrl = resolveAvatarImageUrl(
      event.senderAvatarUrl,
      client,
      size: 48,
    );

    if (avatarImageUrl != null) {
      return CachedNetworkImage(
        imageUrl: avatarImageUrl,
        httpHeaders: {
          if (client.accessToken != null)
            'Authorization': 'Bearer ${client.accessToken}',
        },
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFD8DEE8),
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFD8DEE8),
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5D6A7C),
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          markAvatarSourceBroken(event.senderAvatarUrl);
          return CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFD8DEE8),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5D6A7C),
              ),
            ),
          );
        },
      );
    }

    return CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFFD8DEE8),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5D6A7C),
        ),
      ),
    );
  }

  Widget? _buildReadReceipts(BuildContext context) {
    final receipts = event.rawEvent.receipts;
    final client = Get.find<AuthController>().client;
    final ownUserId = client.userID;

    final otherReaders = receipts.where((r) => r.user.id != ownUserId).toList();

    if (otherReaders.isEmpty) return null;

    const maxAvatars = 3;
    const avatarSize = 14.0;
    const overlap = 4.0;

    Widget buildReaderAvatar(Receipt receipt, {double? size}) {
      final s = size ?? avatarSize;
      final user = receipt.user;
      final displayName = user.displayName ?? user.id;
      final initial = displayName.isNotEmpty
          ? displayName[0].toUpperCase()
          : '?';
      final avatarImageUrl = resolveAvatarImageUrl(
        user.avatarUrl,
        client,
        size: (s * 2).toInt(),
      );

      final avatarWidget = avatarImageUrl != null
          ? CachedNetworkImage(
              imageUrl: avatarImageUrl,
              httpHeaders: {
                if (client.accessToken != null)
                  'Authorization': 'Bearer ${client.accessToken}',
              },
              imageBuilder: (context, imageProvider) => Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                  ),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              placeholder: (context, url) => _buildInitialCircle(initial, s),
              errorWidget: (context, url, error) {
                markAvatarSourceBroken(user.avatarUrl);
                return _buildInitialCircle(initial, s);
              },
            )
          : _buildInitialCircle(initial, s);

      return avatarWidget;
    }

    final visibleReaders = otherReaders.take(maxAvatars).toList();
    final remaining = otherReaders.length - maxAvatars;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < visibleReaders.length; i++)
          Transform.translate(
            offset: Offset(-i * overlap, 0),
            child: buildReaderAvatar(visibleReaders[i]),
          ),
        if (remaining > 0)
          Transform.translate(
            offset: Offset(-visibleReaders.length * overlap, 0),
            child: Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Center(
                child: Text(
                  '+$remaining',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitialCircle(String initial, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF5AA7FF),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Wrap(
        spacing: 4,
        children: event.reactions.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value;
          final isMine = event.myReactions.containsKey(emoji);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAction != null
                  ? () => onAction!.call(
                      MessageAction.react,
                      event,
                      reaction: emoji,
                    )
                  : null,
              onLongPress: () => _showReactionsSheet(context, emoji),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isMine
                      ? cs.secondaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isMine
                        ? cs.secondary
                        : cs.outlineVariant.withValues(alpha: 0.3),
                    width: isMine ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 13)),
                    if (count > 1) ...[
                      const SizedBox(width: 2),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isMine ? cs.secondary : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showReactionsSheet(BuildContext context, String selectedEmoji) {
    final client = Get.find<AuthController>().client;
    final userId = client.userID;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _ReactionsSheet(
          event: event,
          selectedEmoji: selectedEmoji,
          userId: userId,
          client: client,
          onAction: onAction,
        );
      },
    );
  }

  BorderRadius _borderRadius() {
    const large = Radius.circular(20);
    const grouped = Radius.circular(10);
    const tail = Radius.circular(6);

    if (isMe) {
      return BorderRadius.only(
        topLeft: isFirstInGroup ? large : grouped,
        topRight: isFirstInGroup ? large : grouped,
        bottomLeft: isLastInGroup ? large : grouped,
        bottomRight: isLastInGroup ? tail : grouped,
      );
    }

    return BorderRadius.only(
      topLeft: isFirstInGroup ? large : grouped,
      topRight: isFirstInGroup ? large : grouped,
      bottomLeft: isLastInGroup ? tail : grouped,
      bottomRight: isLastInGroup ? large : grouped,
    );
  }

  _BubbleFill _bubbleFill(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_isRedacted) {
      return const _BubbleFill(
        color: Colors.transparent,
        textColor: Color(0xFF9CA3AF),
      );
    }

    if (isMe) {
      if (isMetaAi) {
        return const _BubbleFill(
          gradient: LinearGradient(
            colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          textColor: Colors.white,
        );
      }

      return _BubbleFill(
        gradient: LinearGradient(
          colors: [
            HSLColor.fromColor(primary).withLightness(0.55).toColor(),
            primary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        textColor: Colors.white,
      );
    }

    return const _BubbleFill(
      color: AppTheme.messageGray,
      textColor: Color(0xFF121417),
    );
  }

  void _showActionSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final quickReactions = ['❤️', '👍', '😂', '😮', '😢', '😡'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick reactions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ...quickReactions.map((emoji) {
                      final isSelected = event.myReactions.containsKey(emoji);
                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          HapticFeedback.lightImpact();
                          onAction?.call(
                            MessageAction.react,
                            event,
                            reaction: emoji,
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: isSelected
                              ? BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                )
                              : null,
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      );
                    }),
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _showEmojiPicker(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add,
                          size: 28,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Actions
                _ActionButton(
                  icon: Icons.reply_outlined,
                  label: 'Reply',
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.lightImpact();
                    onAction?.call(MessageAction.reply, event);
                  },
                ),
                _ActionButton(
                  icon: Icons.copy_outlined,
                  label: 'Copy',
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.lightImpact();
                    onAction?.call(MessageAction.copy, event);
                  },
                ),
                _ActionButton(
                  icon: Icons.forward_outlined,
                  label: 'Forward',
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.lightImpact();
                    onAction?.call(MessageAction.forward, event);
                  },
                ),
                if (isMe && !_isRedacted && !_isVisualMedia && !_isAudio)
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    onTap: () {
                      Navigator.pop(ctx);
                      HapticFeedback.lightImpact();
                      onAction?.call(MessageAction.edit, event);
                    },
                  ),
                _ActionButton(
                  icon: Icons.more_horiz,
                  label: 'More',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMoreSheet(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMoreSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: Icons.translate_outlined,
                  label: 'Translate',
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.lightImpact();
                    onAction?.call(MessageAction.translate, event);
                  },
                ),
                if (isMe)
                  _ActionButton(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    iconColor: cs.error,
                    textColor: cs.error,
                    onTap: () {
                      Navigator.pop(ctx);
                      HapticFeedback.mediumImpact();
                      onAction?.call(MessageAction.delete, event);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEmojiPicker(BuildContext context) async {
    const emojis = [
      '😀',
      '😂',
      '🥰',
      '😍',
      '😎',
      '🤔',
      '😭',
      '😡',
      '👍',
      '👎',
      '👏',
      '🙌',
      '🤝',
      '🙏',
      '💪',
      '❤️',
      '🔥',
      '🎉',
      '✨',
      '💯',
      '😊',
      '😉',
      '🤣',
      '😘',
      '🤗',
      '🤭',
      '😴',
      '😷',
      '🤢',
      '🤬',
      '😱',
      '🤯',
      '🥳',
      '😇',
      '🤠',
      '🥶',
      '🥵',
      '🤡',
      '👻',
      '💀',
      '👋',
      '✋',
      '🤚',
      '🖐️',
      '👌',
      '🤌',
      '🤏',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '👇',
      '☝️',
      '👍',
      '👎',
      '✊',
      '👊',
      '🤛',
      '🤜',
      '👏',
      '🙌',
      '👐',
      '🤲',
      '🤝',
      '🙏',
      '✍️',
      '💅',
      '🤳',
      '💪',
      '🦾',
      '🦿',
      '🦵',
      '🦶',
      '👂',
      '🦻',
      '👃',
      '🧠',
      '🫀',
      '🫁',
      '🦷',
      '🦴',
      '👀',
      '👁️',
      '👅',
      '👄',
      '💋',
      '🩸',
      '🎃',
      '🤖',
      '👽',
      '👾',
      '🤡',
      '💩',
      '👍',
      '👎',
      '👊',
      '✊',
      '🤛',
      '🤜',
      '👏',
      '🙌',
      '👐',
      '🤲',
      '🤝',
      '🙏',
      '✍️',
      '💅',
      '🤳',
      '💪',
      '🦾',
      '🦿',
      '🦵',
      '🦶',
      '👂',
      '🦻',
      '👃',
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐽',
      '🐸',
      '🐵',
      '🙈',
      '🙉',
      '🙊',
      '🐒',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🐣',
      '🐥',
      '🦆',
      '🦅',
      '🦉',
      '🦇',
      '🐺',
      '🐗',
      '🐴',
      '🦄',
      '🐝',
      '🐛',
      '🦋',
      '🐌',
      '🐞',
      '🐜',
      '🦟',
      '🦗',
      '🕷️',
      '🕸️',
      '🦂',
      '🐢',
      '🐍',
      '🦎',
      '🦖',
      '🦕',
      '🐙',
      '🦑',
      '🦐',
      '🦞',
      '🦀',
      '🐡',
      '🐠',
      '🐟',
      '🐬',
      '🐳',
      '🐋',
      '🦈',
      '🐊',
      '🐅',
      '🐆',
      '🦓',
      '🦍',
      '🦧',
      '🐘',
      '🦛',
      '🦏',
      '🐪',
      '🐫',
      '🦒',
      '🦘',
      '🦬',
      '🐃',
      '🐂',
      '🐄',
      '🐖',
      '🐏',
      '🐑',
      '🦙',
      '🐐',
      '🦌',
      '🐕',
      '🐩',
      '🦮',
      '🐕‍🦺',
      '🐈',
      '🐈‍⬛',
      '🐓',
      '🦃',
      '🦚',
      '🦜',
      '🦢',
      '🦩',
      '🕊️',
      '🐇',
      '🦝',
      '🦨',
      '🦡',
      '🦦',
      '🦥',
      '🐁',
      '🐀',
      '🐿️',
      '🦔',
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍈',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🍆',
      '🥑',
      '🥦',
      '🥬',
      '🥒',
      '🌶️',
      '🫑',
      '🌽',
      '🥕',
      '🫒',
      '🧄',
      '🧅',
      '🥔',
      '🍠',
      '🥐',
      '🥯',
      '🍞',
      '🥖',
      '🥨',
      '🧀',
      '🥚',
      '🍳',
      '🧈',
      '🥞',
      '🧇',
      '🥓',
      '🥩',
      '🍗',
      '🍖',
      '🌭',
      '🍔',
      '🍟',
      '🍕',
      '🥪',
      '🥙',
      '🧆',
      '🌮',
      '🌯',
      '🫔',
      '🥗',
      '🥘',
      '🫕',
      '🥫',
      '🍝',
      '🍜',
      '🍲',
      '🍛',
      '🍣',
      '🍱',
      '🥟',
      '🦪',
      '🍤',
      '🍙',
      '🍚',
      '🍘',
      '🍥',
      '🥠',
      '🥮',
      '🍢',
      '🍡',
      '🍧',
      '🍨',
      '🍦',
      '🥧',
      '🧁',
      '🍰',
      '🎂',
      '🍮',
      '🍭',
      '🍬',
      '🍫',
      '🍿',
      '🍩',
      '🍪',
      '🌰',
      '🥜',
      '🍯',
      '🥛',
      '🍼',
      '🫖',
      '☕',
      '🍵',
      '🧃',
      '🥤',
      '🧋',
      '🍶',
      '🍺',
      '🍻',
      '🥂',
      '🍷',
      '🥃',
      '🍸',
      '🍹',
      '🧉',
      '🍾',
      '🧊',
      '🥄',
      '🍴',
      '🍽️',
      '🥣',
      '🥡',
      '🥢',
      '🧂',
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🥎',
      '🎾',
      '🏐',
      '🏉',
      '🥏',
      '🎱',
      '🪀',
      '🏓',
      '🏸',
      '🏒',
      '🏑',
      '🥍',
      '🏏',
      '🥅',
      '⛳',
      '🪁',
      '🏹',
      '🎣',
      '🤿',
      '🥊',
      '🥋',
      '🎽',
      '🛹',
      '🛼',
      '🛷',
      '⛸️',
      '🥌',
      '🎿',
      '⛷️',
      '🏂',
      '🪂',
      '🏋️',
      '🤼',
      '🤸',
      '⛹️',
      '🤺',
      '🤾',
      '🏌️',
      '🏇',
      '🧘',
      '🏄',
      '🏊',
      '🤽',
      '🚴',
      '🚵',
      '🎖️',
      '🏆',
      '🏅',
      '🥇',
      '🥈',
      '🥉',
      '🎗️',
      '🏵️',
      '🎫',
      '🎟️',
      '🎪',
      '🤹',
      '🎭',
      '🩰',
      '🎨',
      '🎬',
      '🎤',
      '🎧',
      '🎼',
      '🎹',
      '🥁',
      '🎷',
      '🎺',
      '🎸',
      '🪕',
      '🎻',
      '🪗',
      '🎲',
      '♟️',
      '🎯',
      '🎳',
      '🎮',
      '🎰',
      '🧩',
      '🚗',
      '🚕',
      '🚙',
      '🚌',
      '🚎',
      '🏎️',
      '🚓',
      '🚑',
      '🚒',
      '🚐',
      '🛻',
      '🚚',
      '🚛',
      '🚜',
      '🦯',
      '🦽',
      '🦼',
      '🛴',
      '🚲',
      '🛵',
      '🏍️',
      '🛺',
      '🚨',
      '🚔',
      '🚍',
      '🚘',
      '🚖',
      '🚡',
      '🚠',
      '🚟',
      '🚃',
      '🚋',
      '🚞',
      '🚝',
      '🚄',
      '🚅',
      '🚈',
      '🚂',
      '🚆',
      '🚇',
      '🚊',
      '🚉',
      '✈️',
      '🛫',
      '🛬',
      '🛩️',
      '💺',
      '🛶',
      '⛵',
      '🛥️',
      '🚤',
      '🛳️',
      '⛴️',
      '🚢',
      '⚓',
      '🪝',
      '⛽',
      '🚧',
      '🚦',
      '🚥',
      '🚏',
      '🗺️',
      '🗿',
      '🗽',
      '🗼',
      '🏰',
      '🏯',
      '🏟️',
      '🎡',
      '🎢',
      '🎠',
      '⛲',
      '⛱️',
      '🏖️',
      '🏝️',
      '🏜️',
      '🌋',
      '⛰️',
      '🏔️',
      '🗻',
      '🏕️',
      '⛺',
      '🏠',
      '🏡',
      '🏘️',
      '🏚️',
      '🏗️',
      '🏭',
      '🏢',
      '🏬',
      '🏣',
      '🏤',
      '🏥',
      '🏦',
      '🏨',
      '🏪',
      '🏫',
      '🏩',
      '💒',
      '🏛️',
      '⛪',
      '🕌',
      '🕍',
      '🛕',
      '🕋',
      '⛩️',
      '🛤️',
      '🛣️',
      '🗾',
      '🎑',
      '🏞️',
      '🌅',
      '🌄',
      '🌠',
      '🎇',
      '🎆',
      '🌇',
      '🌆',
      '🏙️',
      '🌃',
      '🌉',
      '🌌',
      '🌠',
      '🥶',
      '🥵',
      '🌡️',
      '☀️',
      '🌤️',
      '⛅',
      '🌥️',
      '☁️',
      '🌦️',
      '🌧️',
      '⛈️',
      '🌩️',
      '🌨️',
      '❄️',
      '☃️',
      '⛄',
      '🌬️',
      '💨',
      '💧',
      '☔',
      '☂️',
      '🌊',
      '🌫️',
      '🌪️',
      '🌀',
      '🌈',
      '🌂',
      '🔥',
      '💥',
      '✨',
      '🎊',
      '🎉',
      '🎀',
      '🎁',
      '🎗️',
      '🏷️',
      '🕯️',
      '💡',
      '🔦',
      '🏮',
      '🪔',
      '📜',
      '📃',
      '📄',
      '📑',
      '📊',
      '📈',
      '📉',
      '🗒️',
      '🗓️',
      '📆',
      '📅',
      '📇',
      '🗃️',
      '🗳️',
      '🗄️',
      '📋',
      '📁',
      '📂',
      '🗂️',
      '🗞️',
      '📰',
      '📓',
      '📔',
      '📒',
      '📕',
      '📗',
      '📘',
      '📙',
      '📚',
      '📖',
      '🔖',
      '🧷',
      '🔗',
      '📎',
      '🖇️',
      '📐',
      '📏',
      '🌈',
      '🎨',
      '🧵',
      '🧶',
      '🪡',
      '🧷',
      '🔧',
      '🔨',
      '🪛',
      '⛏️',
      '🪚',
      '🪓',
      '🔩',
      '🦯',
      '🗜️',
      '⚙️',
      '🪝',
      '🧱',
      '🪨',
      '🪵',
      '🛢️',
      '⛽',
      '🧨',
      '🚬',
      '⚰️',
      '🪦',
      '🧸',
      '🪆',
      '🖼️',
      '🧵',
      '🧶',
      '🪡',
      '🎀',
      '🎗️',
      '🎁',
      '🎊',
      '🎉',
      '🎈',
      '🎎',
      '🏆',
      '🥇',
      '🥈',
      '🥉',
      '🏅',
      '🎖️',
      '🎫',
      '🎟️',
      '🎪',
      '🤹',
      '🎭',
      '🎨',
      '🩰',
      '🎬',
      '🎤',
      '🎧',
      '🎼',
      '🎹',
      '🥁',
      '🎷',
      '🎺',
      '🎸',
      '🪕',
      '🎻',
      '🪗',
      '🎲',
      '♟️',
      '🎯',
      '🎳',
      '🎱',
      '🪀',
      '🏓',
      '🏸',
      '🥊',
      '🥋',
      '🎽',
      '🛹',
      '🛼',
      '🛷',
      '⛸️',
      '🥌',
      '🎿',
      '⛷️',
      '🏂',
      '🪂',
      '🏋️',
      '🤼',
      '🤸',
      '⛹️',
      '🤺',
      '🤾',
      '🏌️',
      '🏇',
      '🧘',
      '🏄',
      '🏊',
      '🤽',
      '🚴',
      '🚵',
      '🛀',
      '🛌',
      '🧑',
      '👶',
      '🧒',
      '👦',
      '👧',
      '🧑',
      '👱',
      '👨',
      '🧔',
      '👩',
      '🧓',
      '👴',
      '👵',
      '🙍',
      '🙎',
      '🙅',
      '🙆',
      '💁',
      '🙋',
      '🧏',
      '🙇',
      '🤦',
      '🤷',
      '💆',
      '💇',
      '🚶',
      '🧍',
      '🧎',
      '🏃',
      '💃',
      '🕺',
      '👯',
      '🧖',
      '🧗',
      '🤺',
      '🏇',
      '⛷️',
      '🏂',
      '🏌️',
      '🏄',
      '🚣',
      '🏊',
      '⛹️',
      '🏋️',
      '🚴',
      '🚵',
      '🤸',
      '🤼',
      '🤽',
      '🧘',
      '🛀',
      '🛌',
      '👭',
      '👫',
      '👬',
      '💏',
      '💑',
      '👪',
      '👨‍👩‍👦',
      '👨‍👩‍👧',
      '👨‍👩‍👧‍👦',
      '👨‍👩‍👦‍👦',
      '👨‍👩‍👧‍👧',
    ];

    final emoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.6,
          expand: false,
          builder: (ctx2, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Emoji',
                        style: Theme.of(ctx2).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx2),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          childAspectRatio: 1.0,
                        ),
                    itemCount: emojis.length,
                    itemBuilder: (ctx2, i) {
                      return InkWell(
                        onTap: () => Navigator.pop(ctx2, emojis[i]),
                        borderRadius: BorderRadius.circular(8),
                        child: Center(
                          child: Text(
                            emojis[i],
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (emoji != null && emoji.isNotEmpty) {
      onAction?.call(MessageAction.react, event, reaction: emoji);
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? cs.onSurface, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: textColor ?? cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleFill {
  const _BubbleFill({this.color, this.gradient, required this.textColor});

  final Color? color;
  final Gradient? gradient;
  final Color textColor;
}

class _MediaAttachmentBubble extends StatefulWidget {
  final AppEvent event;
  final Color textColor;
  final void Function(
    ImageProvider imageProvider,
    Uint8List? bytes,
    String? url,
  )?
  onImageTap;

  const _MediaAttachmentBubble({
    required this.event,
    required this.textColor,
    this.onImageTap,
  });

  @override
  _MediaAttachmentBubbleState createState() => _MediaAttachmentBubbleState();
}

class _MediaAttachmentBubbleState extends State<_MediaAttachmentBubble> {
  Event get _renderEvent => widget.event.displayEvent;

  /// HTTP URLs to try in order (unencrypted media only).
  List<String> _previewUrlCandidates = const [];
  int _previewCandidateIndex = 0;

  /// Full-resolution URL for the lightbox (unencrypted).
  String? _fullImageUrl;

  /// Decrypted attachment bytes (encrypted rooms); preview is shown in-bubble.
  Uint8List? _decryptedPreviewBytes;
  Uint8List? _decryptedFullBytes;
  String? _error;
  bool _isLoading = true;
  bool _advancePreviewFromErrorScheduled = false;
  double? _bridgeImageWidth;
  double? _bridgeImageHeight;
  bool _usedBridgeFallback = false;

  int _countOccurrences(String haystack, String needle) {
    var count = 0;
    var index = haystack.indexOf(needle);
    while (index != -1) {
      count++;
      index = haystack.indexOf(needle, index + 1);
    }
    return count;
  }

  /// Some bridges (e.g. Google Messages) embed the image as base64 inside
  /// a custom content key rather than using an mxc URL.
  Future<Uint8List?> _extractBridgeImageBytes(
    Map<String, Object?> content,
  ) async {
    final rawDebug = content['fi.mau.gmessages.raw_debug_data'];
    if (rawDebug is! String || rawDebug.isEmpty) return null;

    const signatures = ['/9j/', 'iVBORw0KGgo', 'R0lGOD', 'UklGR'];
    final candidateStarts = <int>{};
    for (final signature in signatures) {
      var start = rawDebug.indexOf(signature);
      while (start != -1) {
        candidateStarts.add(start);
        start = rawDebug.indexOf(signature, start + 1);
      }
    }

    try {
      if (candidateStarts.isEmpty) {
        return base64Decode(rawDebug);
      }

      Uint8List? bestBytes;
      var bestArea = -1;
      var bestLength = -1;

      for (final start in candidateStarts.toList()..sort()) {
        try {
          final bytes = base64Decode(rawDebug.substring(start));
          final decoded = await decodeImageFromList(bytes);
          final area = decoded.width * decoded.height;
          if (area > bestArea ||
              (area == bestArea && bytes.length > bestLength)) {
            bestBytes = bytes;
            bestArea = area;
            bestLength = bytes.length;
          }
        } catch (_) {
          // Ignore invalid candidates and continue.
        }
      }

      if (bestBytes != null) {
        debugPrint(
          '[_MediaAttachmentBubble.bridge] eventId=${widget.event.rawEvent.eventId} '
          'candidates=${candidateStarts.length} '
          'gifMarkers=${_countOccurrences(rawDebug, 'R0lGOD')} '
          'pickedArea=$bestArea pickedBytes=$bestLength',
        );
        return bestBytes;
      }

      return base64Decode(rawDebug);
    } catch (_) {
      return null;
    }
  }

  bool _isGoogleMessagesBridgeEvent(Event ev) {
    return ev.content['fi.mau.gmessages.raw_debug_data'] is String;
  }

  String? _findAttachmentUrl(Event ev) {
    // Prefer the SDK getter which handles encrypted/unencrypted properly
    try {
      final sdkUrl = ev.attachmentMxcUrl?.toString();
      if (sdkUrl != null && sdkUrl.isNotEmpty) return sdkUrl;
    } catch (_) {}

    // Fallback to raw content; accept any non-empty URL string
    final url = ev.content['url'];
    if (url is String && url.trim().isNotEmpty) return url.trim();
    final file = ev.content['file'];
    if (file is Map) {
      final fileUrl = file['url'];
      if (fileUrl is String && fileUrl.trim().isNotEmpty) return fileUrl.trim();
    }
    // Some bridges (e.g. Google Images) put the URL inside info
    final info = ev.content['info'];
    if (info is Map) {
      final infoUrl = info['url'];
      if (infoUrl is String && infoUrl.trim().isNotEmpty) return infoUrl.trim();
    }
    return null;
  }

  String? _findLooseHttpUrl(Event ev) {
    // Fallback: any URL-looking string in the body or formatted_body
    for (final field in ['body', 'formatted_body']) {
      final text = ev.content[field];
      if (text is String) {
        // If HTML, strip tags first
        final plain = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
        final match = RegExp(
          r'https?://[^\s<>"{}|\\^`\[\]]+',
        ).firstMatch(plain);
        if (match != null) return match.group(0);
      }
    }
    // Brute-force: scan every nested string value for a URL.
    final urlPattern = RegExp(r'https?://[^\s<>"{}|\\^`\[\]]+');
    for (final value in ev.content.values) {
      if (value is String) {
        final plain = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
        final match = urlPattern.firstMatch(plain);
        if (match != null) return match.group(0);
      } else if (value is Map) {
        for (final nested in value.values) {
          if (nested is String) {
            final plain = nested.replaceAll(RegExp(r'<[^>]+>'), ' ');
            final match = urlPattern.firstMatch(plain);
            if (match != null) return match.group(0);
          }
        }
      }
    }
    return null;
  }

  bool get _isGif {
    final info = _renderEvent.content['info'];
    if (info is Map) {
      final mime = (info['mimetype'] as String?)?.toLowerCase() ?? '';
      if (mime.contains('gif')) return true;
    }
    // Some bridges omit the mimetype; fall back to the body.
    return widget.event.body.toLowerCase().endsWith('.gif');
  }

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didUpdateWidget(_MediaAttachmentBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEv = oldWidget.event.displayEvent;
    final newEv = widget.event.displayEvent;
    if (oldEv.eventId != newEv.eventId ||
        oldEv.content.toString() != newEv.content.toString()) {
      _previewUrlCandidates = const [];
      _previewCandidateIndex = 0;
      _decryptedPreviewBytes = null;
      _decryptedFullBytes = null;
      _bridgeImageWidth = null;
      _bridgeImageHeight = null;
      _usedBridgeFallback = false;
      _error = null;
      _isLoading = true;
      _loadMedia();
    }
  }

  Future<void> _loadMedia() async {
    try {
      final client = Get.find<AuthController>().client;
      final ev = _renderEvent;

      debugPrint(
        '[_MediaAttachmentBubble] eventId=${widget.event.rawEvent.eventId} '
        'renderEventId=${ev.eventId} '
        'type=${ev.type} msgtype=${ev.messageType} '
        'content=${ev.content}',
      );

      final primaryUrl = _findAttachmentUrl(ev);
      final looseUrl = _isGoogleMessagesBridgeEvent(ev)
          ? null
          : _findLooseHttpUrl(ev);
      final mxcUrl = primaryUrl ?? looseUrl;
      final bridgeBytes = await _extractBridgeImageBytes(ev.content);

      final hasMediaUrl = mxcUrl != null || ev.thumbnailMxcUrl != null;
      final hasBridgeImage = bridgeBytes != null;

      if (!hasMediaUrl && !ev.hasAttachment && !hasBridgeImage) {
        if (ev.status == EventStatus.sending) {
          // Still uploading; leave spinner running until didUpdateWidget
          // re-triggers once the content is populated.
          return;
        }
        if (mounted) {
          setState(() {
            _error = 'Media unavailable';
            _isLoading = false;
          });
        }
        return;
      }

      // Google Messages bridge events can carry a tiny embedded preview image
      // in `raw_debug_data` alongside the real Matrix media attachment. Only
      // use the embedded bytes when there is no normal attachment to fetch.
      if (hasBridgeImage && !hasMediaUrl && !ev.hasAttachment) {
        try {
          final decoded = await decodeImageFromList(bridgeBytes);
          _bridgeImageWidth = decoded.width.toDouble();
          _bridgeImageHeight = decoded.height.toDouble();
        } catch (_) {
          // Leave dimensions null; aspect ratio will fall back to 1.0.
        }
        if (mounted) {
          setState(() {
            _decryptedPreviewBytes = bridgeBytes;
            _decryptedFullBytes = bridgeBytes;
            _usedBridgeFallback = true;
            _isLoading = false;
          });
        }
        return;
      }

      if (ev.isAttachmentEncrypted) {
        Future<Uint8List> matrixMediaGet(Uri url) async {
          final fixed = withMatrixMediaAllowRedirect(
            upgradeMatrixMediaV3UrlToClientV1(url),
          );
          final headers = <String, String>{};
          if (client.accessToken != null) {
            headers['Authorization'] = 'Bearer ${client.accessToken}';
          }
          final res = await client.httpClient.get(fixed, headers: headers);
          return res.bodyBytes;
        }

        try {
          final mainFile = await ev.downloadAndDecryptAttachment(
            getThumbnail: false,
            downloadCallback: matrixMediaGet,
          );
          final isVideo = _renderEvent.messageType == MessageTypes.Video;
          Uint8List? previewBytes;
          if (ev.hasThumbnail && !_isGif) {
            try {
              final thumb = await ev.downloadAndDecryptAttachment(
                getThumbnail: true,
                downloadCallback: matrixMediaGet,
              );
              previewBytes = thumb.bytes;
            } catch (_) {
              // Thumbnail decrypt failed; will show placeholder for video.
            }
          }
          if (previewBytes == null && isVideo) {
            previewBytes = await generateVideoThumbnailBytesFromBytes(
              mainFile.bytes,
              fileName: widget.event.body,
            );
          }
          if (mounted) {
            setState(() {
              _decryptedPreviewBytes =
                  previewBytes ?? (isVideo ? null : mainFile.bytes);
              _decryptedFullBytes = mainFile.bytes;
              _usedBridgeFallback = false;
              _isLoading = false;
            });
          }
          return;
        } catch (_) {
          // Decryption failed; fall through to unencrypted URL path
          // in case the event is not actually encrypted.
        }
      }

      final previewCandidates = <String>[];
      final mainMxc = primaryUrl ?? looseUrl;
      final isVideo = _renderEvent.messageType == MessageTypes.Video;
      String? thumbMxc;
      try {
        thumbMxc = ev.thumbnailMxcUrl?.toString();
      } catch (_) {
        thumbMxc = null;
      }

      void addThumbnail(String? mxc) {
        if (mxc == null || !mxc.startsWith('mxc://')) return;
        final mxcUri = Uri.parse(mxc);
        final urls = [
          withMatrixMediaAllowRedirect(
            mxcToClientV1MediaThumbnail(
              mxcUri,
              client,
              width: 250,
              height: 250,
              method: ThumbnailMethod.scale,
            ),
          ).toString(),
          withMatrixMediaAllowRedirect(
            mxcUri.getThumbnail(
              client,
              width: 250,
              height: 250,
              method: ThumbnailMethod.scale,
            ),
          ).toString(),
        ];
        for (final u in urls) {
          if (u.isNotEmpty && !previewCandidates.contains(u)) {
            previewCandidates.add(u);
          }
        }
      }

      if (mainMxc != null && mainMxc.isNotEmpty) {
        if (mainMxc.startsWith('mxc://')) {
          try {
            final mainUri = Uri.parse(mainMxc);
            final v1Uri = mxcToClientV1MediaDownload(mainUri, client);
            final dlV1 = v1Uri.toString().isNotEmpty
                ? withMatrixMediaAllowRedirect(v1Uri).toString()
                : '';
            final v3Uri = mainUri.getDownloadLink(client);
            final dlV3 = v3Uri.toString().isNotEmpty
                ? withMatrixMediaAllowRedirect(v3Uri).toString()
                : '';
            _fullImageUrl = dlV1.isNotEmpty ? dlV1 : dlV3;

            // Videos need a real thumbnail/poster. Let the full video URL be
            // used for playback, not for image decoding in the bubble.
            if (!isVideo) {
              for (final u in [dlV1, dlV3]) {
                if (u.isNotEmpty && !previewCandidates.contains(u)) {
                  previewCandidates.add(u);
                }
              }
            }
          } catch (_) {
            // URL generation failed; continue to try thumbnails or fall back.
          }
        } else {
          // Non-mxc URL (e.g., HTTP); use directly
          _fullImageUrl = mainMxc;
          if (!isVideo) {
            previewCandidates.add(mainMxc);
          }
        }
      }

      // Add thumbnail fallbacks after full URLs so they are tried last.
      if (!_isGif) {
        addThumbnail(mainMxc);
        if (thumbMxc != null && thumbMxc != mainMxc) {
          addThumbnail(thumbMxc);
        }
      }

      if (_fullImageUrl != null &&
          _fullImageUrl!.isNotEmpty &&
          !isVideo &&
          !previewCandidates.contains(_fullImageUrl)) {
        previewCandidates.add(_fullImageUrl!);
      }

      if (previewCandidates.isNotEmpty) {
        if (mounted) {
          setState(() {
            _previewUrlCandidates = previewCandidates;
            _previewCandidateIndex = 0;
            _usedBridgeFallback = false;
            _isLoading = false;
          });
        }
      } else if (isVideo &&
          _fullImageUrl != null &&
          _fullImageUrl!.isNotEmpty) {
        if (mounted) {
          setState(() {
            _previewUrlCandidates = const [];
            _previewCandidateIndex = 0;
            _usedBridgeFallback = false;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Media unavailable';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Media unavailable';
          _isLoading = false;
        });
      }
    }
  }

  void _openVideo(
    BuildContext context, {
    Uint8List? decryptedBytes,
    String? videoUrl,
  }) {
    final client = Get.find<AuthController>().client;
    final ev = _renderEvent;
    final info = ev.content['info'];
    final mimetype = info is Map ? info['mimetype'] as String? : null;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          encryptedBytes: decryptedBytes,
          videoUrl: videoUrl,
          httpHeaders: client.accessToken != null
              ? {'Authorization': 'Bearer ${client.accessToken}'}
              : null,
          mimetype: mimetype,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _FilePlaceholder(
        textColor: widget.textColor,
        filename: widget.event.body,
        error: _error!,
      );
    }

    final isVideo = _renderEvent.messageType == MessageTypes.Video;

    double aspectRatio = 1.0;
    try {
      // Prefer actual decoded bridge image dimensions.
      if (_bridgeImageWidth != null &&
          _bridgeImageHeight != null &&
          _bridgeImageHeight! > 0) {
        aspectRatio = _bridgeImageWidth! / _bridgeImageHeight!;
      } else {
        final content = _renderEvent.content;
        final info = content['info'];
        if (info is Map) {
          final width = info['w'] as num?;
          final height = info['h'] as num?;
          if (width != null && height != null && height > 0) {
            aspectRatio = width / height;
          }
        }
      }
    } catch (_) {
      // Ignore errors in aspect ratio calculation
    }

    const maxImageWidth = 250.0;
    const maxImageHeight = 250.0;

    double displayWidth = maxImageWidth;
    double displayHeight = maxImageWidth / aspectRatio;

    if (displayHeight > maxImageHeight) {
      displayHeight = maxImageHeight;
      displayWidth = maxImageHeight * aspectRatio;
    }

    // For bridge-embedded images, don't upscale beyond native resolution.
    if (_usedBridgeFallback &&
        _bridgeImageWidth != null &&
        _bridgeImageHeight != null) {
      displayWidth = math.min(displayWidth, _bridgeImageWidth!);
      displayHeight = math.min(displayHeight, _bridgeImageHeight!);
    }

    if (_isLoading) {
      return const SizedBox(
        width: 150,
        height: 150,
        child: Center(child: DotMatrixLoader(size: 24, dotSize: 3)),
      );
    }

    if (_decryptedPreviewBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: isVideo
              ? () => _openVideo(context, decryptedBytes: _decryptedFullBytes)
              : () {
                  if (widget.onImageTap != null &&
                      _decryptedFullBytes != null) {
                    widget.onImageTap!(
                      MemoryImage(_decryptedFullBytes!),
                      _decryptedFullBytes,
                      null,
                    );
                  }
                },
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Image.memory(
                    _decryptedPreviewBytes!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.black,
                      child: Center(
                        child: Icon(
                          isVideo
                              ? Icons.play_circle_filled
                              : Icons.broken_image,
                          color: isVideo
                              ? Colors.white70
                              : widget.textColor.withValues(alpha: 0.5),
                          size: isVideo ? 48 : 32,
                        ),
                      ),
                    ),
                  ),
                ),
                if (isVideo)
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      DateFormat.jm().format(widget.event.originServerTs),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_decryptedFullBytes != null && isVideo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => _openVideo(context, decryptedBytes: _decryptedFullBytes),
          child: Container(
            width: displayWidth,
            height: displayHeight,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                Icons.play_circle_filled,
                color: Colors.white70,
                size: 48,
              ),
            ),
          ),
        ),
      );
    }

    if (_previewUrlCandidates.isEmpty) {
      if (isVideo && _fullImageUrl != null && _fullImageUrl!.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: () => _openVideo(context, videoUrl: _fullImageUrl),
            child: Container(
              width: displayWidth,
              height: displayHeight,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        DateFormat.jm().format(widget.event.originServerTs),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image,
              color: widget.textColor.withValues(alpha: 0.7),
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Media unavailable',
                style: TextStyle(
                  color: widget.textColor.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final client = Get.find<AuthController>().client;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: isVideo
            ? () => _openVideo(context, videoUrl: _fullImageUrl)
            : () {
                if (widget.onImageTap != null) {
                  final openUrl =
                      _fullImageUrl ??
                      _previewUrlCandidates[_previewCandidateIndex];
                  widget.onImageTap!(
                    CachedNetworkImageProvider(
                      openUrl,
                      headers: {
                        if (client.accessToken != null)
                          'Authorization': 'Bearer ${client.accessToken}',
                      },
                    ),
                    null,
                    openUrl,
                  );
                }
              },
        child: Container(
          width: displayWidth,
          height: displayHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.textColor.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CachedNetworkImage(
                  key: ValueKey(_previewUrlCandidates[_previewCandidateIndex]),
                  imageUrl: _previewUrlCandidates[_previewCandidateIndex],
                  httpHeaders: {
                    if (client.accessToken != null)
                      'Authorization': 'Bearer ${client.accessToken}',
                  },
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Center(
                    child: DotMatrixLoader(
                      size: 24,
                      dotSize: 3,
                      color: widget.textColor,
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    final hasNext =
                        _previewCandidateIndex <
                        _previewUrlCandidates.length - 1;
                    if (hasNext && !_advancePreviewFromErrorScheduled) {
                      _advancePreviewFromErrorScheduled = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _previewCandidateIndex++;
                          _advancePreviewFromErrorScheduled = false;
                        });
                      });
                      return Center(
                        child: DotMatrixLoader(
                          size: 24,
                          dotSize: 3,
                          color: widget.textColor,
                        ),
                      );
                    }
                    if (isVideo) {
                      return const Center(
                        child: Icon(
                          Icons.play_circle_filled,
                          color: Colors.white70,
                          size: 48,
                        ),
                      );
                    }
                    return _FilePlaceholder(
                      textColor: widget.textColor,
                      filename: widget.event.body,
                    );
                  },
                ),
              ),
              if (isVideo)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat.jm().format(widget.event.originServerTs),
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilePlaceholder extends StatelessWidget {
  final Color textColor;
  final String filename;
  final String? error;

  const _FilePlaceholder({
    required this.textColor,
    required this.filename,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            color: textColor.withValues(alpha: 0.6),
            size: 24,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio message bubble with inline play/pause, progress, and duration.
class _AudioAttachmentBubble extends StatefulWidget {
  final AppEvent event;
  final Color textColor;
  final Color? bubbleColor;
  final BorderRadius borderRadius;

  const _AudioAttachmentBubble({
    required this.event,
    required this.textColor,
    this.bubbleColor,
    required this.borderRadius,
  });

  @override
  State<_AudioAttachmentBubble> createState() => _AudioAttachmentBubbleState();
}

class _AudioAttachmentBubbleState extends State<_AudioAttachmentBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _hasError = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  String? _findMxcUrl(Event ev) {
    final url = ev.content['url'];
    if (url is String && url.startsWith('mxc://')) return url;
    final file = ev.content['file'];
    if (file is Map) {
      final fileUrl = file['url'];
      if (fileUrl is String && fileUrl.startsWith('mxc://')) return fileUrl;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _subscribeToPlayer();
    _prepareAudio();
  }

  @override
  void didUpdateWidget(_AudioAttachmentBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEv = oldWidget.event.rawEvent;
    final newEv = widget.event.rawEvent;
    if (oldEv.eventId != newEv.eventId ||
        oldEv.content.toString() != newEv.content.toString()) {
      _hasError = false;
      _isLoading = true;
      _player.stop();
      _prepareAudio();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _subscribeToPlayer() {
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
    });
    _player.processingStateStream.listen((state) {
      if (!mounted) return;
      if (state == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        setState(() => _isPlaying = false);
      }
    });
  }

  Future<void> _prepareAudio() async {
    try {
      final client = Get.find<AuthController>().client;
      final ev = widget.event.rawEvent;

      if (!ev.hasAttachment) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
        return;
      }

      if (ev.isAttachmentEncrypted) {
        await _prepareEncryptedAudio(client, ev);
      } else {
        await _prepareUnencryptedAudio(client, ev);
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

  Future<void> _prepareEncryptedAudio(Client client, Event ev) async {
    Future<Uint8List> matrixMediaGet(Uri url) async {
      final fixed = withMatrixMediaAllowRedirect(
        upgradeMatrixMediaV3UrlToClientV1(url),
      );
      final headers = <String, String>{};
      if (client.accessToken != null) {
        headers['Authorization'] = 'Bearer ${client.accessToken}';
      }
      final res = await client.httpClient.get(fixed, headers: headers);
      return res.bodyBytes;
    }

    final file = await ev.downloadAndDecryptAttachment(
      getThumbnail: false,
      downloadCallback: matrixMediaGet,
    );

    final tempDir = await getTemporaryDirectory();
    final info = ev.content['info'];
    final ext = _extensionFromMimetype(
      info is Map ? info['mimetype'] as String? : null,
    );
    final tempFile = File('${tempDir.path}/audio_${ev.eventId}$ext');
    await tempFile.writeAsBytes(file.bytes);

    await _player.setAudioSource(AudioSource.uri(Uri.file(tempFile.path)));
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _prepareUnencryptedAudio(Client client, Event ev) async {
    final mxc = _findMxcUrl(ev);
    if (mxc == null) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
      return;
    }

    final mxcUri = Uri.parse(mxc);
    final url = withMatrixMediaAllowRedirect(
      mxcToClientV1MediaDownload(mxcUri, client),
    ).toString();

    final headers = <String, String>{};
    if (client.accessToken != null) {
      headers['Authorization'] = 'Bearer ${client.accessToken}';
    }

    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(url), headers: headers),
    );
    if (mounted) setState(() => _isLoading = false);
  }

  String _extensionFromMimetype(String? mimetype) {
    if (mimetype == null) return '.audio';
    final mime = mimetype.toLowerCase();
    if (mime.contains('ogg')) return '.ogg';
    if (mime.contains('mp4') || mime.contains('m4a')) return '.m4a';
    if (mime.contains('mpeg') || mime.contains('mp3')) return '.mp3';
    if (mime.contains('wav')) return '.wav';
    if (mime.contains('flac')) return '.flac';
    return '.audio';
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Container(
        color: widget.bubbleColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 36, height: 36, child: _buildPlayButton()),
                const SizedBox(width: 10),
                Flexible(child: _buildProgressArea()),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                DateFormat.jm().format(widget.event.originServerTs),
                style: TextStyle(
                  fontSize: 10,
                  color: widget.textColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: DotMatrixLoader(size: 20, dotSize: 3, color: widget.textColor),
        ),
      );
    }

    if (_hasError) {
      return Icon(
        Icons.error_outline,
        color: widget.textColor.withValues(alpha: 0.6),
        size: 24,
      );
    }

    return Material(
      color: widget.textColor.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _togglePlay,
        child: Center(
          child: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            color: widget.textColor,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressArea() {
    if (_hasError) {
      return Text(
        'Audio unavailable',
        style: TextStyle(
          color: widget.textColor.withValues(alpha: 0.7),
          fontSize: 13,
        ),
      );
    }

    final maxMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoading)
          SizedBox(
            width: double.infinity,
            height: 16,
            child: LinearProgressIndicator(
              backgroundColor: widget.textColor.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(
                widget.textColor.withValues(alpha: 0.4),
              ),
              minHeight: 3,
            ),
          )
        else
          SizedBox(
            height: 16,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: widget.textColor,
                inactiveTrackColor: widget.textColor.withValues(alpha: 0.25),
                thumbColor: widget.textColor,
              ),
              child: Slider(
                value: maxMs > 0 ? posMs.clamp(0, maxMs).toDouble() : 0,
                max: maxMs > 0 ? maxMs.toDouble() : 1,
                onChanged: _isLoading
                    ? null
                    : (v) => _player.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
          ),
        const SizedBox(height: 2),
        Text(
          _isLoading
              ? 'Loading...'
              : '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
          style: TextStyle(
            color: widget.textColor.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet showing who reacted with which emoji.
class _ReactionsSheet extends StatefulWidget {
  final AppEvent event;
  final String selectedEmoji;
  final String? userId;
  final Client client;
  final void Function(MessageAction action, AppEvent event, {String? reaction})?
  onAction;

  const _ReactionsSheet({
    required this.event,
    required this.selectedEmoji,
    required this.userId,
    required this.client,
    this.onAction,
  });

  @override
  State<_ReactionsSheet> createState() => _ReactionsSheetState();
}

class _ReactionsSheetState extends State<_ReactionsSheet> {
  late String _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.selectedEmoji;
  }

  Map<String, List<ReactionSender>> get _visibleSenders {
    if (_filter == 'ALL') return widget.event.reactionSenders;
    final filtered = widget.event.reactionSenders[_filter];
    return filtered == null ? {} : {_filter: filtered};
  }

  Widget _buildReactorRow(ReactionSender sender, String emoji) {
    final isMe = sender.id == widget.userId;
    final name = sender.name ?? sender.id.replaceAll('@', '');
    final resolvedAvatar = sender.avatarUrl != null
        ? resolveAvatarImageUrl(sender.avatarUrl!, widget.client, size: 48)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFD8DEE8),
            backgroundImage: resolvedAvatar != null
                ? CachedNetworkImageProvider(resolvedAvatar)
                : null,
            child: resolvedAvatar == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5D6A7C),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isMe)
                  const Text(
                    'Tap to remove',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          Text(emoji, style: const TextStyle(fontSize: 22)),
        ],
      ),
    );
  }

  Widget _buildTab(String label, String emoji, int count) {
    final isSelected = _filter == emoji;
    return GestureDetector(
      onTap: () => setState(() => _filter = emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty)
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            if (label.isNotEmpty && emoji.isNotEmpty) const SizedBox(width: 4),
            if (emoji.isNotEmpty)
              Text(emoji, style: const TextStyle(fontSize: 14)),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allCount = widget.event.reactions.values.fold(0, (a, b) => a + b);
    final senders = _visibleSenders;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Reactions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: senders.length,
              itemBuilder: (_, i) {
                final emoji = senders.keys.elementAt(i);
                final list = senders[emoji]!;
                return Column(
                  children: list
                      .map((s) => _buildReactorRow(s, emoji))
                      .toList(),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildTab('ALL', '', allCount),
                ...widget.event.reactions.entries.map(
                  (e) => _buildTab('', e.key, e.value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
