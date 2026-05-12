void main() {
  String _cleanRoomName(String name) {
    var prefix = '';
    var content = name;
    if (name.startsWith('Group with ')) {
      prefix = 'Group with ';
      content = name.substring('Group with '.length);
    }
    
    var parts = content.split(',').map((p) => p.trim()).toList();
    parts.removeWhere((part) => part.toLowerCase().contains('bot'));
    
    var cleaned = parts.join(', ').trim();
    if (prefix.isNotEmpty && cleaned.isNotEmpty) {
      cleaned = prefix + cleaned;
    }
    
    if (cleaned.isEmpty || cleaned == 'Group with') {
      return 'Empty Group';
    }
    
    return cleaned;
  }

  print(_cleanRoomName("Group with Meta bridge bot, Sam Rus"));
  print(_cleanRoomName("Group with Sam Rus, Meta bridge bot"));
  print(_cleanRoomName("Group with Meta bridge bot"));
  print(_cleanRoomName("Meta bridge bot, Sam Rus"));
  print(_cleanRoomName("Sam Rus, Meta bridge bot"));
  print(_cleanRoomName("Meta bridge bot"));
  print(_cleanRoomName("Alice, metabot, Bob"));
  print(_cleanRoomName("Abbot, Bob"));
}
