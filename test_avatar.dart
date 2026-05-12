import 'package:matrix/matrix.dart';

void main() {
  final client = Client('test');
  client.homeserver = Uri.parse('https://matrix.org');
  final room = Room(id: 'test', client: client);
  print(room.avatar);
}
