import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final AppRoom room;

  const ChatScreen({super.key, required this.room});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final displayedMessages = widget.room.messages.reversed.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFEAF3FF),
                  child: Text(
                    widget.room.displayname[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.room.displayname,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Active now',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, color: AppTheme.primaryBlue),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: AppTheme.primaryBlue),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
                itemCount: displayedMessages.length,
                itemBuilder: (context, index) {
                  final event = displayedMessages[index];
                  final olderMessage = index < displayedMessages.length - 1
                      ? displayedMessages[index + 1]
                      : null;
                  final newerMessage = index > 0
                      ? displayedMessages[index - 1]
                      : null;

                  final isFirstInGroup =
                      olderMessage == null ||
                      !_isSameSender(event, olderMessage);
                  final isLastInGroup =
                      newerMessage == null ||
                      !_isSameSender(event, newerMessage);

                  return MessageBubble(
                    event: event,
                    isMe: event.isMe,
                    isMetaAi: false,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                  );
                },
              ),
            ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(
              Icons.add_circle,
              color: AppTheme.primaryBlue,
              size: 28,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(
              Icons.camera_alt,
              color: AppTheme.primaryBlue,
              size: 28,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(
              Icons.image,
              color: AppTheme.primaryBlue,
              size: 28,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.mic, color: AppTheme.primaryBlue, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Aa',
                hintStyle: TextStyle(color: Colors.grey[500]),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                fillColor: const Color(0xFFF0F2F5),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.sentiment_satisfied_alt,
                    color: AppTheme.primaryBlue,
                  ),
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(
              Icons.thumb_up,
              color: AppTheme.primaryBlue,
              size: 28,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Message sent: $text (dummy)')));
      _messageController.clear();
    }
  }

  bool _isSameSender(AppEvent current, AppEvent other) {
    return current.senderId == other.senderId && current.isMe == other.isMe;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
