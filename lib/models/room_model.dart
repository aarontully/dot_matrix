class AppRoom {
  final String id;
  final String displayname;
  final String? lastMessage;
  final bool hasUnread;
  final List<AppEvent> messages;

  AppRoom({
    required this.id,
    required this.displayname,
    this.lastMessage,
    this.hasUnread = false,
    required this.messages,
  });
}

class AppEvent {
  final String senderId;
  final String body;
  final DateTime originServerTs;
  final bool isMe;

  AppEvent({
    required this.senderId,
    required this.body,
    required this.originServerTs,
    required this.isMe,
  });
}