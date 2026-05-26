import 'package:matrix/matrix.dart';

const MatrixDefaultLocalizations _fallbackLocalizations =
    MatrixDefaultLocalizations();

String matrixEventDisplayText(Event event, {Timeline? timeline}) {
  final displayEvent = timeline == null
      ? event
      : event.getDisplayEvent(timeline);

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

  final replacements = <_MentionReplacement>[];
  for (final user in event.room.getParticipants()) {
    final displayName = user.calcDisplayname().trim();
    if (displayName.isEmpty) continue;

    final visibleMention = '@$displayName';
    replacements.add(_MentionReplacement(user.id, visibleMention));
    for (final fragment in user.mentionFragments) {
      replacements.add(_MentionReplacement(fragment, visibleMention));
    }
  }

  if (replacements.isEmpty) return text;

  final uniqueReplacements = <String, _MentionReplacement>{};
  for (final replacement in replacements) {
    uniqueReplacements.putIfAbsent(replacement.source, () => replacement);
  }

  final orderedReplacements = uniqueReplacements.values.toList()
    ..sort((a, b) => b.source.length.compareTo(a.source.length));

  var normalized = text;
  for (final replacement in orderedReplacements) {
    final pattern =
        '(^|[\\s(])${RegExp.escape(replacement.source)}'
        '(?![^\\s).,!?:;])';
    normalized = normalized.replaceAllMapped(
      RegExp(pattern),
      (match) => '${match.group(1)!}${replacement.visibleText}',
    );
  }
  return normalized;
}

class _MentionReplacement {
  const _MentionReplacement(this.source, this.visibleText);

  final String source;
  final String visibleText;
}
