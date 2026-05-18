import 'package:flutter/material.dart';
import '../utils/bridge_detector.dart';

class _PlatformConfig {
  final String letter;
  final Color color;
  const _PlatformConfig(this.letter, this.color);
}

_PlatformConfig _config(BridgePlatform p) {
  switch (p) {
    case BridgePlatform.discord:
      return const _PlatformConfig('D', Color(0xFF5865F2));
    case BridgePlatform.whatsapp:
      return const _PlatformConfig('W', Color(0xFF25D366));
    case BridgePlatform.telegram:
      return const _PlatformConfig('T', Color(0xFF0088CC));
    case BridgePlatform.signal:
      return const _PlatformConfig('S', Color(0xFF3A76F0));
    case BridgePlatform.slack:
      return const _PlatformConfig('S', Color(0xFF4A154B));
    case BridgePlatform.facebook:
      return const _PlatformConfig('F', Color(0xFF1877F2));
    case BridgePlatform.instagram:
      return const _PlatformConfig('I', Color(0xFFE4405F));
    case BridgePlatform.twitter:
      return const _PlatformConfig('X', Color(0xFF000000));
    case BridgePlatform.googlechat:
      return const _PlatformConfig('G', Color(0xFF00897B));
    case BridgePlatform.linkedin:
      return const _PlatformConfig('L', Color(0xFF0A66C2));
    case BridgePlatform.skype:
      return const _PlatformConfig('S', Color(0xFF00AFF0));
    case BridgePlatform.wechat:
      return const _PlatformConfig('W', Color(0xFF07C160));
    case BridgePlatform.line:
      return const _PlatformConfig('L', Color(0xFF00C300));
    case BridgePlatform.imessage:
      return const _PlatformConfig('i', Color(0xFF34C759));
    case BridgePlatform.sms:
      return const _PlatformConfig('M', Color(0xFF4CAF50));
    case BridgePlatform.irc:
      return const _PlatformConfig('#', Color(0xFFFF9800));
    case BridgePlatform.email:
      return const _PlatformConfig('@', Color(0xFFEA4335));
    case BridgePlatform.rss:
      return const _PlatformConfig('R', Color(0xFFFF9800));
    case BridgePlatform.steam:
      return const _PlatformConfig('S', Color(0xFF1B2838));
    case BridgePlatform.playstation:
      return const _PlatformConfig('P', Color(0xFF003791));
    case BridgePlatform.xbox:
      return const _PlatformConfig('X', Color(0xFF107C10));
    case BridgePlatform.reddit:
      return const _PlatformConfig('R', Color(0xFFFF4500));
    case BridgePlatform.tiktok:
      return const _PlatformConfig('T', Color(0xFF000000));
    case BridgePlatform.teams:
      return const _PlatformConfig('T', Color(0xFF6264A7));
    case BridgePlatform.zoom:
      return const _PlatformConfig('Z', Color(0xFF2D8CFF));
    case BridgePlatform.xmpp:
      return const _PlatformConfig('X', Color(0xFF7B68EE));
    case BridgePlatform.mattermost:
      return const _PlatformConfig('M', Color(0xFF0058CC));
    case BridgePlatform.zulip:
      return const _PlatformConfig('Z', Color(0xFF6495ED));
    case BridgePlatform.gitter:
      return const _PlatformConfig('G', Color(0xFFED1965));
    case BridgePlatform.matrix:
      return const _PlatformConfig('M', Color(0xFF0DBD8B));
    case BridgePlatform.unknown:
      return const _PlatformConfig('?', Colors.grey);
  }
}

/// Small circular badge showing the bridge platform.
class BridgeIcon extends StatelessWidget {
  final BridgePlatform platform;
  final double size;

  const BridgeIcon({
    super.key,
    required this.platform,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (platform == BridgePlatform.unknown) return const SizedBox.shrink();
    final config = _config(platform);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: config.color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          config.letter,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.55,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }
}
