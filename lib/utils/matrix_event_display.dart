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
    return body == EventTypes.Message ? 'Message' : body;
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
  return localizedBody;
}
