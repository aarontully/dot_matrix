import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'auth_provider.dart';
import '../models/room_model.dart';

final roomsProvider = FutureProvider<List<AppRoom>>((ref) async {
  final auth = ref.watch(authProvider.notifier);
  if (auth.isDummy) {
    // Dummy data
    return [
      AppRoom(
        id: 'room1',
        displayname: 'General Chat',
        lastMessage: 'Hey everyone!',
        messages: [
          AppEvent(senderId: 'user1', body: 'Hello!', originServerTs: DateTime.now().subtract(const Duration(minutes: 10)), isMe: false),
          AppEvent(senderId: 'dummy_user', body: 'Hi there!', originServerTs: DateTime.now().subtract(const Duration(minutes: 5)), isMe: true),
          AppEvent(senderId: 'user1', body: 'How are you?', originServerTs: DateTime.now().subtract(const Duration(minutes: 2)), isMe: false),
        ],
      ),
      AppRoom(
        id: 'room2',
        displayname: 'Work Team',
        lastMessage: 'Meeting at 3 PM',
        messages: [
          AppEvent(senderId: 'user2', body: 'Meeting at 3 PM', originServerTs: DateTime.now().subtract(const Duration(hours: 1)), isMe: false),
          AppEvent(senderId: 'dummy_user', body: 'Got it!', originServerTs: DateTime.now().subtract(const Duration(minutes: 30)), isMe: true),
        ],
      ),
      AppRoom(
        id: 'room3',
        displayname: 'John Doe',
        lastMessage: 'See you tomorrow!',
        messages: [
          AppEvent(senderId: 'john_doe', body: 'Hey, how was your day?', originServerTs: DateTime.now().subtract(const Duration(hours: 2)), isMe: false),
          AppEvent(senderId: 'dummy_user', body: 'It was good, thanks! Busy with work.', originServerTs: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)), isMe: true),
          AppEvent(senderId: 'john_doe', body: 'Same here. See you tomorrow!', originServerTs: DateTime.now().subtract(const Duration(minutes: 30)), isMe: false),
        ],
      ),
    ];
  } else {
    final client = auth.client;
    await client.roomsLoading;
    return client.rooms.where((room) => room.membership == Membership.join).map((room) => AppRoom(
      id: room.id,
      displayname: room.getLocalizedDisplayname(),
      lastMessage: room.lastEvent?.body,
      messages: [], // For real, would load
    )).toList();
  }
});