import 'package:matrix/matrix.dart';
import '../utils/bridge_detector.dart';

final RegExp _mediaExtensionPattern = RegExp(
  r'\.(?:jpg|jpeg|png|gif|webp|bmp|heic|mp4|mov|avi|mkv|webm)\b',
);
final RegExp _mediaFilenamePattern = RegExp(
  r'^[^\n]+\.(?:jpg|jpeg|png|gif|webp|bmp|heic|mp4|mov|avi|mkv|webm)$',
  caseSensitive: false,
);
final RegExp _mediaUrlPattern = RegExp(
  r'https?://[^\s<>"{}|\\^`\[\]]+\.(?:jpg|jpeg|png|gif|webp|bmp|heic|mp4|mov|avi|mkv|webm)',
);

bool _eventHasVisualMedia(Event renderEvent, String body) {
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

  final candidates = [
    body,
    renderEvent.content['body'],
    renderEvent.content['filename'],
    renderEvent.content['name'],
  ].whereType<String>().map((s) => s.toLowerCase().trim());

  for (final text in candidates) {
    if (_mediaExtensionPattern.hasMatch(text) ||
        _mediaUrlPattern.hasMatch(text)) {
      return true;
    }
  }

  for (final value in renderEvent.content.values) {
    if (value is String) {
      final normalized = value.toLowerCase();
      if (_mediaExtensionPattern.hasMatch(normalized) ||
          _mediaUrlPattern.hasMatch(normalized)) {
        return true;
      }
    } else if (value is Map) {
      for (final nested in value.values) {
        if (nested is String) {
          final normalized = nested.toLowerCase();
          if (_mediaExtensionPattern.hasMatch(normalized) ||
              _mediaUrlPattern.hasMatch(normalized)) {
            return true;
          }
        }
      }
    }
  }

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

String? _eventMediaCaption(Event renderEvent, String body, bool isVisualMedia) {
  if (!isVisualMedia) return null;

  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty ||
      trimmedBody == 'Waiting for room key...' ||
      trimmedBody == 'Encrypted message') {
    return null;
  }

  final normalized = trimmedBody.toLowerCase();
  final filenameCandidates = <String>{
    for (final value in [
      renderEvent.content['filename'],
      renderEvent.content['name'],
    ])
      if (value is String && value.trim().isNotEmpty)
        value.trim().toLowerCase(),
  };

  if (filenameCandidates.contains(normalized) ||
      _mediaFilenamePattern.hasMatch(trimmedBody)) {
    return null;
  }

  return trimmedBody;
}

bool _eventIsWaitingForRoomKey(Event renderEvent, String body) {
  if (renderEvent.messageType == MessageTypes.BadEncrypted) {
    return renderEvent.content['can_request_session'] == true;
  }
  return body == 'Waiting for room key...';
}

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
  final bool isVisualMedia;
  final bool isAudio;
  final String? mediaCaption;
  final bool isWaitingForRoomKey;

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
    bool? isVisualMedia,
    bool? isAudio,
    String? mediaCaption,
    bool? isWaitingForRoomKey,
  }) : displayEvent = displayEvent ?? rawEvent,
       isVisualMedia =
           isVisualMedia ??
           _eventHasVisualMedia(displayEvent ?? rawEvent, body),
       isAudio =
           isAudio ??
           (displayEvent ?? rawEvent).messageType == MessageTypes.Audio,
       mediaCaption =
           mediaCaption ??
           _eventMediaCaption(
             displayEvent ?? rawEvent,
             body,
             isVisualMedia ??
                 _eventHasVisualMedia(displayEvent ?? rawEvent, body),
           ),
       isWaitingForRoomKey =
           isWaitingForRoomKey ??
           _eventIsWaitingForRoomKey(displayEvent ?? rawEvent, body);
}
