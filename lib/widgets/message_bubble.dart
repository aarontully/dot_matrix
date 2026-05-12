import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_url_resolver.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    this.isMetaAi = false,
  });

  final AppEvent event;
  final bool isMe;
  final bool isMetaAi;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  @override
  Widget build(BuildContext context) {
    final bubbleFill = _bubbleFill();
    final showAvatar = !isMe && isLastInGroup;
    final topSpacing = isFirstInGroup ? 12.0 : 3.0;
    final bottomSpacing = isLastInGroup ? 4.0 : 0.0;

    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 30,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: showAvatar ? _buildAvatar() : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              child: DecoratedBox(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    event.body,
                    style: TextStyle(
                      color: bubbleFill.textColor,
                      fontSize: 15,
                      height: 1.28,
                    ),
                  ),
                ),
              ),
            ),
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
          radius: 12,
          backgroundColor: const Color(0xFFD8DEE8),
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFFD8DEE8),
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5D6A7C),
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          markAvatarSourceBroken(event.senderAvatarUrl);
          return CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFFD8DEE8),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5D6A7C),
              ),
            ),
          );
        },
      );
    }

    return CircleAvatar(
      radius: 12,
      backgroundColor: const Color(0xFFD8DEE8),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5D6A7C),
        ),
      ),
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

  _BubbleFill _bubbleFill() {
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

      return const _BubbleFill(
        gradient: LinearGradient(
          colors: [Color(0xFF1A8CFF), Color(0xFF0078FF)],
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
}

class _BubbleFill {
  const _BubbleFill({this.color, this.gradient, required this.textColor});

  final Color? color;
  final Gradient? gradient;
  final Color textColor;
}
