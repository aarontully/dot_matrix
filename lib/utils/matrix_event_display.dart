import 'package:matrix/matrix.dart';

const MatrixDefaultLocalizations _fallbackLocalizations =
    MatrixDefaultLocalizations();

String matrixEventDisplayText(Event event, {Timeline? timeline}) {
  final displayEvent = timeline == null
      ? event
      : event.getDisplayEvent(timeline);

  if (displayEvent.redactedBecause != null) {
    return 'Message deleted';
  }

  if (displayEvent.messageType == MessageTypes.BadEncrypted) {
    return displayEvent.content['can_request_session'] == true
        ? 'Waiting for room key...'
        : 'Encrypted message';
  }

  if (displayEvent.type == EventTypes.Message) {
    final body = displayEvent.calcUnlocalizedBody(
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
      removeMarkdown: true,
    );
    final normalizedBody = _normalizeMentionText(displayEvent, body);
    return normalizedBody == EventTypes.Message ? 'Message' : normalizedBody;
  }

  final localizedBody = displayEvent.calcLocalizedBodyFallback(
    _fallbackLocalizations,
    hideReply: true,
    hideEdit: true,
    plaintextBody: true,
    removeMarkdown: true,
  );
  if (localizedBody == EventTypes.Encrypted ||
      localizedBody == 'Unknown event ${EventTypes.Encrypted}') {
    return 'Encrypted message';
  }
  return _normalizeMentionText(displayEvent, localizedBody);
}

String _normalizeMentionText(Event event, String text) {
  if (!text.contains('@')) return text;

  final replacements = <String, String>{};
  for (final user in event.room.getParticipants()) {
    final displayName = user.calcDisplayname().trim();
    if (displayName.isEmpty) continue;

    final visibleMention = '@$displayName';
    replacements[user.id] = visibleMention;
    for (final fragment in user.mentionFragments) {
      replacements.putIfAbsent(fragment, () => visibleMention);
    }
  }

  if (replacements.isEmpty) return text;

  return text.replaceAllMapped(
    RegExp(r'(^|[\s(])([^\s()]+)'),
    (match) {
      final prefix = match.group(1) ?? '';
      final token = match.group(2) ?? '';
      final tokenMatch = RegExp(r'^(.*?)([).,!?:;]+)?$').firstMatch(token);
      final core = tokenMatch?.group(1) ?? token;
      final suffix = tokenMatch?.group(2) ?? '';
      final replacement = replacements[core];
      if (replacement == null) {
        return '$prefix$token';
      }
      return '$prefix$replacement$suffix';
    },
  );
}
