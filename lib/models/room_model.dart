import 'package:matrix/matrix.dart';
import '../utils/bridge_detector.dart';

class AppReactionActivity {
  final String senderId;
  final String? senderName;
  final String emoji;
  final String targetMessageBody;
  final DateTime timestamp;

  AppReactionActivity({
    required this.senderId,
    this.senderName,
    required this.emoji,
    required this.targetMessageBody,
    required this.timestamp,
  });
}

class AppRoom {
  final String id;
  final String displayname;
  final String? lastMessage;
  final DateTime? lastEventTs;
  final bool hasUnread;

  /// Best-effort count for the list badge: server [notificationCount], or 1 when
  /// the room has new messages / marked unread but the count is zero.
  int get unreadCount => _unreadCount ?? 0;
  final int? _unreadCount;
  final List<AppEvent> messages;
  final Uri? avatarUrl;
  final List<Uri> memberAvatarUrls;
  final String? backgroundImageUrl;
  final bool isGroup;
  final List<String> spaceParentIds;
  final AppReactionActivity? latestReactionActivity;
  final BridgePlatform bridgePlatform;

  AppRoom({
    required this.id,
    required this.displayname,
    this.lastMessage,
    this.lastEventTs,
    this.hasUnread = false,
    int? unreadCount,
    required this.messages,
    this.avatarUrl,
    this.memberAvatarUrls = const [],
    this.backgroundImageUrl,
    this.isGroup = false,
    this.spaceParentIds = const [],
    this.latestReactionActivity,
    this.bridgePlatform = BridgePlatform.unknown,
  }) : _unreadCount = unreadCount;
}

class ReactionSender {
  final String id;
  final String? name;
  final Uri? avatarUrl;

  const ReactionSender({required this.id, this.name, this.avatarUrl});
}

class AppEvent {
  final String senderId;
  final String? senderName;
  final Uri? senderAvatarUrl;
  final String body;
  final DateTime originServerTs;
  final bool isMe;
  final Event rawEvent;
  final Event displayEvent;

  /// Map of reaction emoji to count for this message.
  final Map<String, int> reactions;

  /// Map of reaction emoji to the current user's reaction eventId for toggling.
  final Map<String, String> myReactions;

  /// Map of reaction emoji to list of sender info.
  final Map<String, List<ReactionSender>> reactionSenders;

  /// Whether this message has been edited.
  final bool isEdited;

  AppEvent({
    required this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    required this.body,
    required this.originServerTs,
    required this.isMe,
    required this.rawEvent,
    Event? displayEvent,
    this.reactions = const {},
    this.myReactions = const {},
    this.reactionSenders = const {},
    this.isEdited = false,
  }) : displayEvent = displayEvent ?? rawEvent;
}
