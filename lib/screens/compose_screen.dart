import 'package:flutter/material.dart';
import 'package:dot_matrix/widgets/dot_matrix_loader.dart';
import 'package:get/get.dart';
import 'package:matrix/matrix.dart';

import '../controllers/auth_controller.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../utils/matrix_event_display.dart';
import 'chat_screen.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _userIdController = TextEditingController();
  bool _isCreatingRoom = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Get.isDarkMode;
    final backgroundColor = isDark
        ? AppTheme.darkBackground
        : const Color(0xFFF7F8FC);
    final cardColor = isDark ? AppTheme.darkSurface : Colors.white;
    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appBarForeground),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New Message'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start a Chat',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a Matrix User ID to start a direct message.',
                style: TextStyle(
                  fontSize: 15,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.18 : 0.04,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _userIdController,
                      decoration: const InputDecoration(
                        labelText: 'User ID',
                        hintText: '@username:homeserver.org',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _startChat(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isCreatingRoom ? null : _startChat,
                        icon: _isCreatingRoom
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: DotMatrixLoader(
                                  size: 20,
                                  dotSize: 3,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.chat_bubble_outline),
                        label: Text(
                          _isCreatingRoom ? 'Creating...' : 'Start Chat',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startChat() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      Get.snackbar('Error', 'Please enter a User ID');
      return;
    }

    setState(() {
      _isCreatingRoom = true;
    });

    try {
      final auth = Get.find<AuthController>();
      final client = auth.client;

      // Check if an existing direct chat with this user already exists
      final existingRoomId = client.getDirectChatFromUserId(userId);
      if (existingRoomId != null) {
        final room = client.getRoomById(existingRoomId);
        if (room != null && room.membership == Membership.join) {
          if (!mounted) return;
          final appRoom = AppRoom(
            id: room.id,
            displayname: room.getLocalizedDisplayname(),
            lastMessage: room.lastEvent == null
                ? null
                : matrixEventDisplayText(room.lastEvent!),
            messages: [],
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(room: appRoom)),
          );
          return;
        }
      }

      // No existing chat found; create a new one
      final roomId = await client.createRoom(
        invite: [userId],
        isDirect: true,
        preset: CreateRoomPreset.trustedPrivateChat,
      );

      // Wait for the room to appear in the client's room list
      await client.roomsLoading;
      final room = client.getRoomById(roomId);

      if (!mounted) return;

      if (room != null) {
        final appRoom = AppRoom(
          id: room.id,
          displayname: room.getLocalizedDisplayname(),
          lastMessage: room.lastEvent == null
              ? null
              : matrixEventDisplayText(room.lastEvent!),
          messages: [],
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(room: appRoom)),
        );
      } else {
        Get.snackbar('', 'Room created, but could not be loaded immediately.');
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingRoom = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }
}
