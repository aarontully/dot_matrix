import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

void main() async {
  final url = 'https://matrix.housetully.au/_matrix/media/v3/download/housetully.au/HPdfEBHnzmUYEayGASQyqtuS';
  final res = await http.get(Uri.parse(url));
  print('Status: ' + res.statusCode.toString());
}
