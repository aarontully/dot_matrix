import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../utils/avatar_url_resolver.dart';

/// Displays a circular avatar for a room.
/// If the room has an explicit [avatarUrl], it shows that.
/// Otherwise it shows a 2×2 grid of up to 4 member avatars,
/// with a "+N" overlay if there are more than 4.
class RoomAvatarGrid extends StatelessWidget {
  final Uri? avatarUrl;
  final List<Uri> memberAvatarUrls;
  final double size;
  final String fallbackInitial;
  final Color? backgroundColor;
  final Color? fallbackColor;

  const RoomAvatarGrid({
    super.key,
    this.avatarUrl,
    this.memberAvatarUrls = const [],
    required this.size,
    required this.fallbackInitial,
    this.backgroundColor,
    this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final client = Get.find<AuthController>().client;
    final cs = Theme.of(context).colorScheme;

    // If the room has its own avatar, use it directly
    if (avatarUrl != null) {
      final resolved = resolveAvatarImageUrl(
        avatarUrl,
        client,
        size: size.toInt() * 2,
      );
      if (resolved != null) {
        return _buildCircleAvatar(
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: resolved,
              httpHeaders: {
                if (client.accessToken != null)
                  'Authorization': 'Bearer ${client.accessToken}',
              },
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => _fallbackAvatar(cs),
              errorWidget: (_, __, ___) {
                markAvatarSourceBroken(avatarUrl);
                return _fallbackAvatar(cs);
              },
            ),
          ),
        );
      }
    }

    // If we have member avatars, build the 2×2 grid
    if (memberAvatarUrls.isNotEmpty) {
      return _buildCircleAvatar(
        child: ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: _MemberAvatarGrid(
              urls: memberAvatarUrls,
              size: size,
              client: client,
            ),
          ),
        ),
      );
    }

    // Fallback to initial letter
    return _fallbackAvatar(cs);
  }

  Widget _buildCircleAvatar({required Widget child}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? const Color(0xFFEAF3FF),
      ),
      child: child,
    );
  }

  Widget _fallbackAvatar(ColorScheme cs) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? cs.primaryContainer,
      ),
      child: Center(
        child: Text(
          fallbackInitial.isNotEmpty ? fallbackInitial[0].toUpperCase() : '#',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: fallbackColor ?? cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _MemberAvatarGrid extends StatelessWidget {
  final List<Uri> urls;
  final double size;
  final dynamic client;

  const _MemberAvatarGrid({
    required this.urls,
    required this.size,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    final count = urls.length;
    final cellSize = size / 2;
    final showOverlay = count > 4;
    final displayUrls = showOverlay ? urls.sublist(0, 4) : urls;

    return Stack(
      children: [
        Column(
          children: [
            Row(
              children: [
                _avatarCell(displayUrls, 0, cellSize),
                _avatarCell(displayUrls, 1, cellSize),
              ],
            ),
            Row(
              children: [
                _avatarCell(displayUrls, 2, cellSize),
                _avatarCell(displayUrls, 3, cellSize),
              ],
            ),
          ],
        ),
        if (showOverlay)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: cellSize,
              height: cellSize,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(size / 2),
                ),
              ),
              child: Center(
                child: Text(
                  '+${count - 3}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: cellSize * 0.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatarCell(List<Uri> list, int index, double cellSize) {
    if (index >= list.length) {
      return Container(
        width: cellSize,
        height: cellSize,
        color: const Color(0xFFE8ECF1),
      );
    }
    final resolved = resolveAvatarImageUrl(list[index], client, size: cellSize.toInt() * 2);
    if (resolved == null) {
      return Container(
        width: cellSize,
        height: cellSize,
        color: const Color(0xFFD8DEE8),
      );
    }
    return SizedBox(
      width: cellSize,
      height: cellSize,
      child: CachedNetworkImage(
        imageUrl: resolved,
        httpHeaders: {
          if (client.accessToken != null)
            'Authorization': 'Bearer ${client.accessToken}',
        },
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) {
          markAvatarSourceBroken(list[index]);
          return Container(color: const Color(0xFFD8DEE8));
        },
      ),
    );
  }
}
