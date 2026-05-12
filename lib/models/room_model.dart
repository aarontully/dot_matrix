class AppRoom {
  final String id;
  final String displayname;
  final String? lastMessage;
  final DateTime? lastEventTs;
  final bool hasUnread;
  final List<AppEvent> messages;
  final Uri? avatarUrl;

  AppRoom({
    required this.id,
    required this.displayname,
    this.lastMessage,
    this.lastEventTs,
    this.hasUnread = false,
    required this.messages,
    this.avatarUrl,
  });
}

class AppEvent {
  final String senderId;
  final String? senderName;
  final Uri? senderAvatarUrl;
  final String body;
  final DateTime originServerTs;
  final bool isMe;

  AppEvent({
    required this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    required this.body,
    required this.originServerTs,
    required this.isMe,
  });
}