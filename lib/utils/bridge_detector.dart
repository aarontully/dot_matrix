/// Bridge platforms that can be linked to Matrix.
enum BridgePlatform {
  discord,
  whatsapp,
  telegram,
  signal,
  slack,
  facebook,
  instagram,
  twitter,
  googlechat,
  linkedin,
  skype,
  wechat,
  line,
  imessage,
  sms,
  irc,
  email,
  rss,
  steam,
  playstation,
  xbox,
  reddit,
  tiktok,
  teams,
  zoom,
  xmpp,
  mattermost,
  zulip,
  gitter,
  matrix,
  unknown,
}

class BridgeDetector {
  /// Detects the bridge platform from a Matrix user ID or display name.
  static BridgePlatform detectFromUserId(String userId) {
    final lower = userId.toLowerCase();
    // Exclude bridge bots from detection
    if (lower.contains('bot') && !lower.contains('abot')) return BridgePlatform.unknown;

    if (lower.contains('discord')) return BridgePlatform.discord;
    if (lower.contains('whatsapp')) return BridgePlatform.whatsapp;
    if (lower.contains('telegram')) return BridgePlatform.telegram;
    if (lower.contains('signal')) return BridgePlatform.signal;
    if (lower.contains('slack')) return BridgePlatform.slack;
    if (lower.contains('facebook') || lower.contains('messenger')) return BridgePlatform.facebook;
    if (lower.contains('instagram')) return BridgePlatform.instagram;
    if (lower.contains('twitter') || lower.contains('x_')) return BridgePlatform.twitter;
    if (lower.contains('googlechat') || lower.contains('google_chat')) return BridgePlatform.googlechat;
    if (lower.contains('linkedin')) return BridgePlatform.linkedin;
    if (lower.contains('skype')) return BridgePlatform.skype;
    if (lower.contains('wechat') || lower.contains('weixin')) return BridgePlatform.wechat;
    if (RegExp(r'\bline\b').hasMatch(lower) || lower.contains('_line_')) return BridgePlatform.line;
    if (lower.contains('imessage') || lower.contains('ios_message')) return BridgePlatform.imessage;
    if (lower.contains('_sms_') || lower.contains('text_message')) return BridgePlatform.sms;
    if (lower.contains('_irc_') || lower.contains('irc_')) return BridgePlatform.irc;
    if (lower.contains('email') || lower.contains('_mail_')) return BridgePlatform.email;
    if (lower.contains('rss') || lower.contains('feed_')) return BridgePlatform.rss;
    if (lower.contains('steam')) return BridgePlatform.steam;
    if (lower.contains('playstation') || lower.contains('psn')) return BridgePlatform.playstation;
    if (lower.contains('xbox')) return BridgePlatform.xbox;
    if (lower.contains('reddit')) return BridgePlatform.reddit;
    if (lower.contains('tiktok')) return BridgePlatform.tiktok;
    if (lower.contains('teams') || lower.contains('msteams')) return BridgePlatform.teams;
    if (lower.contains('zoom')) return BridgePlatform.zoom;
    if (lower.contains('xmpp') || lower.contains('jabber')) return BridgePlatform.xmpp;
    if (lower.contains('mattermost')) return BridgePlatform.mattermost;
    if (lower.contains('zulip')) return BridgePlatform.zulip;
    if (lower.contains('gitter')) return BridgePlatform.gitter;
    if (lower.contains('matrix')) return BridgePlatform.matrix;
    return BridgePlatform.unknown;
  }

  /// Detect from a list of member user IDs, excluding the current user.
  static BridgePlatform detectFromMembers(List<String> memberIds, String myUserId) {
    for (final id in memberIds) {
      if (id == myUserId) continue;
      final platform = detectFromUserId(id);
      if (platform != BridgePlatform.unknown) return platform;
    }
    return BridgePlatform.unknown;
  }
}
