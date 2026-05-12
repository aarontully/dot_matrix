import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_url_resolver.dart';
import '../widgets/message_bubble.dart';
import 'app_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final AppRoom room;

  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      final isTyping = _messageController.text.trim().isNotEmpty;
      if (isTyping != _isTyping) {
        setState(() {
          _isTyping = isTyping;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedMessages = List<AppEvent>.from(widget.room.messages)
      ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    final theme = Theme.of(context);
    final client = Get.find<AuthController>().client;
    final avatarImageUrl = resolveAvatarImageUrl(
      widget.room.avatarUrl,
      client,
      size: 64,
    );
    final isWaitingForKey = widget.room.messages.any(
      (event) => event.body == 'Waiting for room key...',
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
                if (avatarImageUrl != null)
                  CachedNetworkImage(
                    imageUrl: avatarImageUrl,
                    httpHeaders: {
                      if (client.accessToken != null)
                        'Authorization': 'Bearer ${client.accessToken}',
                    },
                    imageBuilder: (context, imageProvider) => CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFEAF3FF),
                      backgroundImage: imageProvider,
                    ),
                    placeholder: (context, url) => CircleAvatar(
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
                    errorWidget: (context, url, error) {
                      markAvatarSourceBroken(widget.room.avatarUrl);
                      return CircleAvatar(
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
                      );
                    },
                  )
                else
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Active now',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.54,
                      ),
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
            if (isWaitingForKey) _buildRecoveryBanner(theme),
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
            _buildMessageInput(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFD7AC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.key_outlined, color: Color(0xFFC96A12)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This chat is still waiting on a room key',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Ask another verified device again, or open recovery tools if this is a new device.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _askDevicesAgain,
                icon: const Icon(Icons.devices_outlined),
                label: const Text('Ask devices again'),
              ),
              OutlinedButton.icon(
                onPressed: _openRecoveryTools,
                icon: const Icon(Icons.tune),
                label: const Text('Open recovery tools'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.black87,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                Icons.add,
                color: isDark ? Colors.black : Colors.white,
                size: 24,
              ),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (_isTyping) ...[
            const SizedBox(width: 12),
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF00C875), // Bright green
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(),
                onPressed: _sendMessage,
              ),
            ),
          ],
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

  Future<void> _askDevicesAgain() async {
    try {
      final message = await Get.find<SettingsController>()
          .requestEncryptedHistoryFromVerifiedDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _openRecoveryTools() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
