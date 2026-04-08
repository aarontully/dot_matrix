import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import 'chat_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: roomsAsync.when(
        data: (rooms) => ListView.builder(
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = rooms[index];
            return ListTile(
              leading: CircleAvatar(
                child: Text(room.displayname[0].toUpperCase()),
              ),
              title: Text(room.displayname),
              subtitle: Text(room.lastMessage ?? 'No messages'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateRoomDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateRoomDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Room'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Room Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                // For dummy, just add to list, but since provider, hard. For now, show snackbar
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Room "$name" created (dummy)')),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}