import 'package:matrix/matrix.dart';
void main() {
  final client = Client('test');
  print(client.onLoginStateChanged);
}
