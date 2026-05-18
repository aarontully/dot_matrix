import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/room_model.dart';
import '../utils/permissions.dart';
import '../utils/bridge_detector.dart';
import '../widgets/bridge_icon.dart';
import '../widgets/message_bubble.dart';
import '../widgets/room_avatar_grid.dart';
import 'app_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final AppRoom room;

  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ScheduledMessage {
  final String text;
  final DateTime sendAt;
  final AppEvent? replyTo;

  _ScheduledMessage({required this.text, required this.sendAt, this.replyTo});
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _audioRecorder = FlutterSoundRecorder();
  final _imagePicker = ImagePicker();
  bool _isTyping = false;
  bool _isAttachmentMenuOpen = false;
  bool _isRecording = false;
  bool _isLoadingHistory = false;
  bool _showScrollToBottom = false;
  File? _recordedAudioFile;
  AppEvent? _replyingToEvent;
  AppEvent? _editingEvent;
  final List<_ScheduledMessage> _scheduledMessages = [];
  Timer? _scheduleTimer;
  final _messageKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      final isTyping = _messageController.text.trim().isNotEmpty;
      if (isTyping != _isTyping) {
        setState(() => _isTyping = isTyping);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markRoomAsRead();
    });
    _audioRecorder.openRecorder();
    _scheduleTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkScheduledMessages(),
    );
    _scrollController.addListener(() {
      final show = _scrollController.position.pixels > 200;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingHistory) {
        _loadMoreHistory();
      }
    });
  }

  /// Opening a chat should advance the read marker so the room list and
  /// notifications match what the user has seen (including when entering via Activity).
  Future<void> _markRoomAsRead() async {
    final auth = Get.find<AuthController>();
    if (auth.state == null) return;
    final client = auth.client;
    final room = client.getRoomById(widget.room.id);
    if (room == null) return;

    try {
      if (room.markedUnread) {
        await room.markUnread(false);
      }

      String? eventId = room.lastEvent?.eventId;
      eventId ??= _latestVisibleMessageEventId();
      if (eventId == null) return;

      await room.setReadMarker(eventId, mRead: eventId);
    } catch (e) {
      debugPrint('Read marker failed: $e');
    }

    if (!mounted) return;
    try {
      await Get.find<RoomController>().refreshRooms();
    } catch (e) {
      debugPrint('Room refresh failed: $e');
    }
  }

  Future<void> _loadMoreHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      await Get.find<RoomController>().requestRoomHistory(widget.room.id);
    } catch (e) {
      debugPrint('History load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  String? _latestVisibleMessageEventId() {
    if (widget.room.messages.isEmpty) return null;
    AppEvent? newest;
    for (final m in widget.room.messages) {
      if (m.rawEvent.status == EventStatus.sending) continue;
      if (newest == null ||
          m.originServerTs.isAfter(newest.originServerTs)) {
        newest = m;
      }
    }
    return newest?.rawEvent.eventId;
  }

  AppRoom? _findLiveRoom() {
    final roomController = Get.find<RoomController>();
    final rooms = roomController.state;
    if (rooms == null) return null;
    try {
      return rooms.firstWhere((r) => r.id == widget.room.id);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leadingWidth: 40,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            RoomAvatarGrid(
              avatarUrl: widget.room.avatarUrl,
              memberAvatarUrls: widget.room.memberAvatarUrls,
              size: 32,
              fallbackInitial: widget.room.displayname.isNotEmpty
                  ? widget.room.displayname[0].toUpperCase()
                  : '?',
              backgroundColor: theme.colorScheme.secondaryContainer,
              fallbackColor: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.room.displayname,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.room.bridgePlatform != BridgePlatform.unknown) ...[
                      const SizedBox(width: 6),
                      BridgeIcon(platform: widget.room.bridgePlatform),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        // TODO: Implement calling & video calls (WebRTC + Matrix signaling).
        // actions: [
        //   IconButton(
        //     icon: Icon(Icons.phone, color: theme.colorScheme.secondary),
        //     onPressed: () {},
        //   ),
        //   IconButton(
        //     icon: Icon(Icons.videocam, color: theme.colorScheme.secondary),
        //     onPressed: () {},
        //   ),
        // ],
      ),
      body: Stack(
        children: [
          if (widget.room.backgroundImageUrl != null)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: widget.room.backgroundImageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (widget.room.backgroundImageUrl != null)
            Positioned.fill(
              child: Container(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.82),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                GetBuilder<RoomController>(
              builder: (roomCtrl) {
                final liveRoom = _findLiveRoom();
                final messages = liveRoom?.messages ?? widget.room.messages;
                final displayedMessages = List<AppEvent>.from(messages)
                  ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
                final isWaitingForKey = messages.any(
                  (event) => event.body == 'Waiting for room key...',
                );

                return Expanded(
                  child: Column(
                    children: [
                      if (isWaitingForKey) _buildRecoveryBanner(theme),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadMoreHistory,
                          child: NotificationListener<ScrollUpdateNotification>(
                            onNotification: (notification) {
                              if (notification.dragDetails != null) {
                                FocusManager.instance.primaryFocus?.unfocus();
                              }
                              return false;
                            },
                            child: ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
                            itemCount: displayedMessages.length +
                                (_isLoadingHistory ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_isLoadingHistory &&
                                  index == displayedMessages.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final event = displayedMessages[index];
                            final olderMessage =
                                index < displayedMessages.length - 1
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

                            // Resolve reply-to event for display
                            AppEvent? replyTarget;
                            if (event.rawEvent.relationshipType ==
                                RelationshipTypes.reply) {
                              final replyId = event.rawEvent.relationshipEventId;
                              if (replyId != null) {
                                replyTarget = displayedMessages.firstWhereOrNull(
                                  (e) => e.rawEvent.eventId == replyId,
                                );
                              }
                            }

                            final key = _messageKeys.putIfAbsent(
                              event.rawEvent.eventId,
                              () => GlobalKey(),
                            );

                            final showDateHeader = index > 0 &&
                                !_isSameDay(
                                  event.originServerTs,
                                  displayedMessages[index - 1].originServerTs,
                                );

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showDateHeader)
                                  _buildDateHeader(event.originServerTs, theme),
                                Container(
                                  key: key,
                                  child: Dismissible(
                                    key: ValueKey('swipe-${event.rawEvent.eventId}'),
                                    direction: event.isMe
                                        ? DismissDirection.endToStart
                                        : DismissDirection.startToEnd,
                                    confirmDismiss: (_) async {
                                      _handleMessageAction(MessageAction.reply, event);
                                      return false;
                                    },
                                    background: Container(
                                      alignment: event.isMe
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      child: Icon(
                                        Icons.reply,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    child: MessageBubble(
                                      event: event,
                                      isMe: event.isMe,
                                      isMetaAi: false,
                                      isFirstInGroup: isFirstInGroup,
                                      isLastInGroup: isLastInGroup,
                                      replyToEvent: replyTarget,
                                      onReplyTap: replyTarget != null
                                          ? (id) => _scrollToEvent(id, displayedMessages)
                                          : null,
                                      onAction: _handleMessageAction,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        ),
                      ),
                    ),
                    ],
                  ),
                );
              },
            ),
            _buildMessageInput(theme),
          ],
        ),
      ),
          if (_showScrollToBottom)
            Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionButton.small(
                heroTag: 'scrollToBottom',
                onPressed: () {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
        ],
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
    final cs = theme.colorScheme;

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypingIndicator(cs),
          if (_scheduledMessages.isNotEmpty) ...[
            _buildScheduledBanner(),
            const SizedBox(height: 8),
          ],
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _buildAttachmentMenu(cs),
            crossFadeState: _isAttachmentMenuOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
          if (_recordedAudioFile != null)
            _AudioPreviewPlayer(
              audioFile: _recordedAudioFile!,
              onSend: _sendPreviewAudio,
              onDiscard: _discardRecording,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildCircleButton(
                  icon: _isAttachmentMenuOpen ? Icons.close : Icons.add,
                  bg: cs.primary,
                  fg: cs.onPrimary,
                  onTap: () => setState(
                    () => _isAttachmentMenuOpen = !_isAttachmentMenuOpen,
                  ),
                ),
                const SizedBox(width: 8),
                _buildCircleButton(
                  icon: Icons.camera_alt_outlined,
                  bg: cs.secondaryContainer,
                  fg: cs.onSecondaryContainer,
                  onTap: _takePhoto,
                ),
                const SizedBox(width: 8),
                _buildCircleButton(
                  icon: Icons.photo_outlined,
                  bg: cs.secondaryContainer,
                  fg: cs.onSecondaryContainer,
                  onTap: _pickGalleryImage,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _replyingToEvent != null || _editingEvent != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              child: _replyingToEvent != null
                                  ? _buildReplyPreview()
                                  : _buildEditPreview(cs),
                            ),
                            Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(20),
                                ),
                              ),
                              child: TextField(
                                controller: _messageController,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                                decoration: InputDecoration(
                                  hintText: 'Message...',
                                  hintStyle: TextStyle(
                                    color: cs.onSurface.withValues(alpha: 0.5),
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      Icons.sentiment_satisfied_outlined,
                                      color: cs.onSurface.withValues(alpha: 0.6),
                                    ),
                                    onPressed: _showEmojiPickerSheet,
                                  ),
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Message...',
                              hintStyle: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.5),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  Icons.sentiment_satisfied_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                ),
                                onPressed: _showEmojiPickerSheet,
                              ),
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                            ),
                          ),
                        ),
                ),
                if (_isTyping) ...[
                  const SizedBox(width: 6),
                  _buildCircleButton(
                    icon: Icons.send,
                    bg: const Color(0xFF00C875),
                    fg: Colors.white,
                    onTap: _sendMessage,
                    onLongPress: _scheduleSend,
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  _buildCircleButton(
                    icon: _isRecording ? Icons.stop : Icons.mic,
                    bg: _isRecording ? Colors.red : cs.tertiaryContainer,
                    fg: _isRecording ? Colors.white : cs.onTertiaryContainer,
                    onTap: _toggleVoiceRecording,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentMenu(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _buildAttachmentChip(
            icon: Icons.insert_drive_file_outlined,
            label: 'File',
            color: const Color(0xFF5E7CF0),
            onTap: _pickAndSendFile,
          ),
          const SizedBox(width: 8),
          _buildAttachmentChip(
            icon: _isRecording ? Icons.stop : Icons.mic,
            label: _isRecording ? 'Recording…' : 'Voice',
            color: _isRecording ? Colors.red : const Color(0xFFE85D75),
            onTap: _toggleVoiceRecording,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: fg, size: 22),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        onPressed: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    final replyTo = _replyingToEvent;
    final editing = _editingEvent;
    setState(() {
      _replyingToEvent = null;
      _editingEvent = null;
    });

    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room == null) {
        if (!mounted) return;
        Get.snackbar('Error', 'Room not found');
        return;
      }
      if (editing != null) {
        await room.sendTextEvent(text, editEventId: editing.rawEvent.eventId);
      } else if (replyTo != null) {
        await room.sendTextEvent(text, inReplyTo: replyTo.rawEvent);
      } else {
        await room.sendTextEvent(text);
      }
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Send failed: $error');
    }
  }

  void _scrollToEvent(String eventId, List<AppEvent> messages) {
    final key = _messageKeys[eventId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      return;
    }
    // Fallback: estimate position from index
    final index = messages.indexWhere((e) => e.rawEvent.eventId == eventId);
    if (index < 0) return;
    final estimatedOffset = index * 80.0;
    _scrollController.animateTo(
      estimatedOffset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _handleMessageAction(MessageAction action, AppEvent event, {String? reaction}) {
    switch (action) {
      case MessageAction.reply:
        setState(() => _replyingToEvent = event);
        break;
      case MessageAction.copy:
        Clipboard.setData(ClipboardData(text: event.body));
        Get.snackbar('', 'Copied', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
        break;
      case MessageAction.forward:
        _showForwardDialog(event);
        break;
      case MessageAction.delete:
        _deleteMessage(event);
        break;
      case MessageAction.translate:
        Get.snackbar('', 'Translation not yet available', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 2));
        break;
      case MessageAction.react:
        final emoji = reaction ?? '❤️';
        _sendReaction(event, emoji);
        break;
      case MessageAction.edit:
        setState(() => _editingEvent = event);
        _messageController.text = event.body;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
        break;
      case MessageAction.more:
        break;
    }
  }

  Future<void> _sendReaction(AppEvent event, String emoji) async {
    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room == null) return;

      final myReactions = event.myReactions;

      // User already has this reaction → unreact (redact it)
      if (myReactions.containsKey(emoji)) {
        await room.redactEvent(myReactions[emoji]!);
        return;
      }

      // User has a different reaction → replace it
      if (myReactions.isNotEmpty) {
        for (final entry in myReactions.entries) {
          await room.redactEvent(entry.value);
        }
      }

      await room.sendReaction(event.rawEvent.eventId, emoji);
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', 'Reaction failed: $e');
      }
    }
  }

  Widget _buildReplyPreview() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyingToEvent!.senderName ?? _replyingToEvent!.senderId,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingToEvent!.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onSurface),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => setState(() => _replyingToEvent = null),
          ),
        ],
      ),
    );
  }

  Widget _buildEditPreview(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: cs.tertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.tertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _editingEvent!.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onSurface),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              setState(() => _editingEvent = null);
              _messageController.clear();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(AppEvent event) async {
    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room == null) return;
      await room.redactEvent(event.rawEvent.eventId);
      if (!mounted) return;
      Get.snackbar('', 'Message deleted', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Delete failed: $error');
    }
  }

  Future<void> _showForwardDialog(AppEvent event) async {
    final roomController = Get.find<RoomController>();
    final rooms = roomController.state;
    if (rooms == null || rooms.isEmpty) {
      Get.snackbar('Error', 'No rooms to forward to');
      return;
    }

    final selected = await showDialog<AppRoom>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Forward to'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rooms.length,
              itemBuilder: (_, i) {
                final r = rooms[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                    child: Text(
                      r.displayname.isNotEmpty ? r.displayname[0].toUpperCase() : '#',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(r.displayname),
                  onTap: () => Navigator.pop(ctx, r),
                );
              },
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(selected.id);
      if (room == null) return;
      await room.sendTextEvent('Forwarded: ${event.body}');
      if (!mounted) return;
      Get.snackbar('', 'Forwarded', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Forward failed: $error');
    }
  }

  Widget _buildTypingIndicator(ColorScheme cs) {
    return GetBuilder<RoomController>(
      builder: (roomCtrl) {
        final liveRoom = _findLiveRoom();
        final room = liveRoom != null
            ? Get.find<AuthController>().client.getRoomById(widget.room.id)
            : null;
        if (room == null) return const SizedBox.shrink();
        final typingUsers = room.typingUsers;
        if (typingUsers.isEmpty) return const SizedBox.shrink();
        final names = typingUsers.map((u) => u.calcDisplayname()).toList();
        String text;
        if (names.length == 1) {
          text = '${names.first} is typing...';
        } else if (names.length == 2) {
          text = '${names.first} and ${names.last} are typing...';
        } else {
          text = '${names.first} and ${names.length - 1} others are typing...';
        }
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScheduledBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scheduled',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 4),
          ..._scheduledMessages.map((sm) {
            final time = DateFormat.jm().format(sm.sendAt);
            return Row(
              children: [
                Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${sm.text} · $time',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _scheduledMessages.remove(sm));
                  },
                  child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _scheduleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (pickedTime == null || !mounted) return;

    final sendAt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (sendAt.isBefore(now)) {
      if (!mounted) return;
      Get.snackbar('Error', 'Scheduled time must be in the future');
      return;
    }

    setState(() {
      _scheduledMessages.add(
        _ScheduledMessage(
          text: text,
          sendAt: sendAt,
          replyTo: _replyingToEvent,
        ),
      );
      _messageController.clear();
      _replyingToEvent = null;
    });

    Get.snackbar(
      '',
      'Message scheduled for ${DateFormat.jm().format(sendAt)}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _checkScheduledMessages() async {
    if (_scheduledMessages.isEmpty) return;
    final now = DateTime.now();
    final due = _scheduledMessages.where((sm) => sm.sendAt.isBefore(now)).toList();

    for (final sm in due) {
      try {
        final client = Get.find<AuthController>().client;
        final room = client.getRoomById(widget.room.id);
        if (room == null) continue;
        if (sm.replyTo != null) {
          await room.sendTextEvent(sm.text, inReplyTo: sm.replyTo!.rawEvent);
        } else {
          await room.sendTextEvent(sm.text);
        }
      } catch (e) {
        debugPrint('Scheduled send failed: $e');
      }
    }

    if (due.isNotEmpty && mounted) {
      setState(() => _scheduledMessages.removeWhere((sm) => sm.sendAt.isBefore(now)));
    }
  }

  Future<void> _takePhoto() async {
    if (!await requestCameraPermission(context)) return;
    try {
      final photo = await _imagePicker.pickImage(source: ImageSource.camera);
      if (photo == null) return;
      await _sendImageFile(File(photo.path), mimeType: photo.mimeType);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Camera error: $error');
    }
  }

  Future<void> _pickGalleryImage() async {
    if (!await requestPhotosPermission(context)) return;
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      await _sendImageFile(File(image.path), mimeType: image.mimeType);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Gallery error: $error');
    }
  }

  Future<void> _sendImageFile(File file, {String? mimeType}) async {
    try {
      if (!await file.exists()) {
        if (!mounted) return;
        Get.snackbar('Error', 'Image file not found');
        return;
      }
      final fileSize = await file.length();
      if (fileSize == 0) {
        if (!mounted) return;
        Get.snackbar('Error', 'Image file is empty');
        return;
      }
      final bytes = await file.readAsBytes();
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room == null) {
        if (!mounted) return;
        Get.snackbar('Error', 'Room not found');
        return;
      }
      final matrixFile = await MatrixImageFile.create(
        bytes: bytes,
        name: file.path.split('/').last,
        mimeType: mimeType,
      );
      await room.sendFileEvent(
        matrixFile,
        shrinkImageMaxDimension: 1600,
      );
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Image send failed: $error');
    }
  }

  Future<void> _pickAndSendFile() async {
    if (!await requestStoragePermission(context)) return;
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        Get.snackbar('Error', 'Could not read file');
        return;
      }

      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room == null) {
        if (!mounted) return;
        Get.snackbar('Error', 'Room not found');
        return;
      }

      final matrixFile = MatrixFile(
        bytes: bytes,
        name: file.name,
      );
      await room.sendFileEvent(matrixFile);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'File send failed: $error');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecording) {
      // Stop recording
      try {
        final path = await _audioRecorder.stopRecorder();
        setState(() => _isRecording = false);
        if (path == null || path.isEmpty) return;
        _recordedAudioFile = File(path);
        setState(() {});
      } catch (error) {
        if (!mounted) return;
        Get.snackbar('Error', 'Recording error: $error');
      }
    } else {
      // Start recording
      if (!await requestMicPermission(context)) return;
      try {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.startRecorder(toFile: path, codec: Codec.aacMP4);
        setState(() => _isRecording = true);
      } catch (error) {
        if (!mounted) return;
        Get.snackbar('Error', 'Recording error: $error');
      }
    }
  }

  Future<void> _discardRecording() async {
    try {
      if (_recordedAudioFile != null &&
          await _recordedAudioFile!.exists()) {
        await _recordedAudioFile!.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete recording: $e');
    }
    setState(() => _recordedAudioFile = null);
  }

  Future<void> _sendPreviewAudio(File file) async {
    setState(() => _recordedAudioFile = null);
    await _sendAudioFile(file);
  }

  Future<void> _sendAudioFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room == null) {
        if (!mounted) return;
        Get.snackbar('Error', 'Room not found');
        return;
      }
      final matrixFile = MatrixAudioFile(
        bytes: bytes,
        name: file.path.split('/').last,
      );
      await room.sendFileEvent(matrixFile);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Audio send failed: $error');
    }
  }

  Future<void> _showEmojiPickerSheet() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return const _EmojiPickerSheet();
      },
    );
    if (emoji != null && emoji.isNotEmpty) {
      setState(() {
        _messageController.text += emoji;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      });
    }
  }

  bool _isSameSender(AppEvent current, AppEvent other) {
    return current.senderId == other.senderId && current.isMe == other.isMe;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateHeader(DateTime date, ThemeData theme) {
    final now = DateTime.now();
    String text;
    if (_isSameDay(date, now)) {
      text = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      text = 'Yesterday';
    } else {
      text = DateFormat.yMMMMd().format(date);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _askDevicesAgain() async {
    try {
      final message = await Get.find<SettingsController>()
          .requestEncryptedHistoryFromVerifiedDevices();
      if (!mounted) return;
      Get.snackbar('', message, snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 2));
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', error.toString());
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
    _audioRecorder.closeRecorder();
    _scheduleTimer?.cancel();
    super.dispose();
  }
}

class _AudioPreviewPlayer extends StatefulWidget {
  final File audioFile;
  final void Function(File file) onSend;
  final VoidCallback onDiscard;

  const _AudioPreviewPlayer({
    required this.audioFile,
    required this.onSend,
    required this.onDiscard,
  });

  @override
  State<_AudioPreviewPlayer> createState() => _AudioPreviewPlayerState();
}

class _AudioPreviewPlayerState extends State<_AudioPreviewPlayer> {
  final _player = ja.AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setAudioSource(
        ja.AudioSource.uri(Uri.file(widget.audioFile.path)),
      );
    } catch (e) {
      debugPrint('Audio preview load error: $e');
    }
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
    });
    _player.processingStateStream.listen((state) {
      if (!mounted) return;
      if (state == ja.ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        setState(() => _isPlaying = false);
      }
    });
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> _send() async {
    await _player.stop();
    widget.onSend(widget.audioFile);
  }

  Future<void> _discard() async {
    await _player.stop();
    widget.onDiscard();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final display =
        '${_duration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${_duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          _buildCircleButton(
            icon: Icons.delete_outline,
            bg: Colors.red,
            fg: Colors.white,
            onTap: _discard,
          ),
          const SizedBox(width: 10),
          Material(
            color: cs.onSurface.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _togglePlay,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: cs.onSurface,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            display,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.8),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0,
                backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(
                  cs.onSurface.withValues(alpha: 0.35),
                ),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildCircleButton(
            icon: Icons.send,
            bg: const Color(0xFF00C875),
            fg: Colors.white,
            onTap: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: fg, size: 22),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        onPressed: onTap,
      ),
    );
  }
}

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet();

  static const List<String> _emojis = [
    '😀', '😂', '🥰', '😍', '😎', '🤔', '😭', '😡',
    '👍', '👎', '👏', '🙌', '🤝', '🙏', '💪', '❤️',
    '🔥', '🎉', '✨', '💯', '😊', '😉', '🤣', '😘',
    '🤗', '🤭', '😴', '😷', '🤢', '🤬', '😱', '🤯',
    '🥳', '😇', '🤠', '🥶', '🥵', '🤡', '👻', '💀',
    '👋', '✋', '🤚', '🖐️', '👌', '🤌', '🤏', '✌️',
    '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '👇',
    '☝️', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏',
    '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳',
    '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻', '👃',
    '🧠', '🫀', '🫁', '🦷', '🦴', '👀', '👁️', '👅',
    '👄', '💋', '🩸', '🎃', '🤖', '👽', '👾', '🤡',
    '💩', '👍', '👎', '👊', '✊', '🤛', '🤜', '👏',
    '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳',
    '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻', '👃',
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
    '🐨', '🐯', '🦁', '🐮', '🐷', '🐽', '🐸', '🐵',
    '🙈', '🙉', '🙊', '🐒', '🐔', '🐧', '🐦', '🐤',
    '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗',
    '🐴', '🦄', '🐝', '🐛', '🦋', '🐌', '🐞', '🐜',
    '🦟', '🦗', '🕷️', '🕸️', '🦂', '🐢', '🐍', '🦎',
    '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀', '🐡',
    '🐠', '🐟', '🐬', '🐳', '🐋', '🦈', '🐊', '🐅',
    '🐆', '🦓', '🦍', '🦧', '🐘', '🦛', '🦏', '🐪',
    '🐫', '🦒', '🦘', '🦬', '🐃', '🐂', '🐄', '🐖',
    '🐏', '🐑', '🦙', '🐐', '🦌', '🐕', '🐩', '🦮',
    '🐕‍🦺', '🐈', '🐈‍⬛', '🐓', '🦃', '🦚', '🦜', '🦢',
    '🦩', '🕊️', '🐇', '🦝', '🦨', '🦡', '🦦', '🦥',
    '🐁', '🐀', '🐿️', '🦔', '🍎', '🍐', '🍊', '🍋',
    '🍌', '🍉', '🍇', '🍓', '🫐', '🍈', '🍒', '🍑',
    '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦',
    '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄',
    '🧅', '🥔', '🍠', '🥐', '🥯', '🍞', '🥖', '🥨',
    '🧀', '🥚', '🍳', '🧈', '🥞', '🧇', '🥓', '🥩',
    '🍗', '🍖', '🌭', '🍔', '🍟', '🍕', '🥪', '🥙',
    '🧆', '🌮', '🌯', '🫔', '🥗', '🥘', '🫕', '🥫',
    '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🦪',
    '🍤', '🍙', '🍚', '🍘', '🍥', '🥠', '🥮', '🍢',
    '🍡', '🍧', '🍨', '🍦', '🥧', '🧁', '🍰', '🎂',
    '🍮', '🍭', '🍬', '🍫', '🍿', '🍩', '🍪', '🌰',
    '🥜', '🍯', '🥛', '🍼', '🫖', '☕', '🍵', '🧃',
    '🥤', '🧋', '🍶', '🍺', '🍻', '🥂', '🍷', '🥃',
    '🍸', '🍹', '🧉', '🍾', '🧊', '🥄', '🍴', '🍽️',
    '🥣', '🥡', '🥢', '🧂', '⚽', '🏀', '🏈', '⚾',
    '🥎', '🎾', '🏐', '🏉', '🥏', '🎱', '🪀', '🏓',
    '🏸', '🏒', '🏑', '🥍', '🏏', '🥅', '⛳', '🪁',
    '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼',
    '🛷', '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️',
    '🤼', '🤸', '⛹️', '🤺', '🤾', '🏌️', '🏇', '🧘',
    '🏄', '🏊', '🤽', '🚴', '🚵', '🎖️', '🏆', '🏅',
    '🥇', '🥈', '🥉', '🎗️', '🏵️', '🎫', '🎟️', '🎪',
    '🤹', '🎭', '🩰', '🎨', '🎬', '🎤', '🎧', '🎼',
    '🎹', '🥁', '🎷', '🎺', '🎸', '🪕', '🎻', '🪗',
    '🎲', '♟️', '🎯', '🎳', '🎮', '🎰', '🧩', '🚗',
    '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒',
    '🚐', '🛻', '🚚', '🚛', '🚜', '🦯', '🦽', '🦼',
    '🛴', '🚲', '🛵', '🏍️', '🛺', '🚨', '🚔', '🚍',
    '🚘', '🚖', '🚡', '🚠', '🚟', '🚃', '🚋', '🚞',
    '🚝', '🚄', '🚅', '🚈', '🚂', '🚆', '🚇', '🚊',
    '🚉', '✈️', '🛫', '🛬', '🛩️', '💺', '🛶', '⛵',
    '🛥️', '🚤', '🛳️', '⛴️', '🚢', '⚓', '🪝', '⛽',
    '🚧', '🚦', '🚥', '🚏', '🗺️', '🗿', '🗽', '🗼',
    '🏰', '🏯', '🏟️', '🎡', '🎢', '🎠', '⛲', '⛱️',
    '🏖️', '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🗻', '🏕️',
    '⛺', '🏠', '🏡', '🏘️', '🏚️', '🏗️', '🏭', '🏢',
    '🏬', '🏣', '🏤', '🏥', '🏦', '🏨', '🏪', '🏫',
    '🏩', '💒', '🏛️', '⛪', '🕌', '🕍', '🛕', '🕋',
    '⛩️', '🛤️', '🛣️', '🗾', '🎑', '🏞️', '🌅', '🌄',
    '🌠', '🎇', '🎆', '🌇', '🌆', '🏙️', '🌃', '🌉',
    '🌌', '🌠', '🥶', '🥵', '🌡️', '☀️', '🌤️', '⛅',
    '🌥️', '☁️', '🌦️', '🌧️', '⛈️', '🌩️', '🌨️', '❄️',
    '☃️', '⛄', '🌬️', '💨', '💧', '☔', '☂️', '🌊',
    '🌫️', '🌪️', '🌀', '🌈', '🌂', '🔥', '💥', '✨',
    '🎊', '🎉', '🎀', '🎁', '🎗️', '🏷️', '🕯️', '💡',
    '🔦', '🏮', '🪔', '📜', '📃', '📄', '📑', '📊',
    '📈', '📉', '🗒️', '🗓️', '📆', '📅', '📇', '🗃️',
    '🗳️', '🗄️', '📋', '📁', '📂', '🗂️', '🗞️', '📰',
    '📓', '📔', '📒', '📕', '📗', '📘', '📙', '📚',
    '📖', '🔖', '🧷', '🔗', '📎', '🖇️', '📐', '📏',
    '🌈', '🎨', '🧵', '🧶', '🪡', '🧷', '🔧', '🔨',
    '🪛', '⛏️', '🪚', '🪓', '🔩', '🦯', '🗜️', '⚙️',
    '🪝', '🧱', '🪨', '🪵', '🛢️', '⛽', '🧨', '🚬',
    '⚰️', '🪦', '🧸', '🪆', '🧩', '🧮', '🪄', '💎',
    '💍', '👑', '💄', '💋', '💌', '📧', '📨', '📩',
    '📤', '📥', '📦', '🏷️', '📪', '📫', '📬', '📭',
    '📮', '🗳️', '✏️', '✒️', '🖋️', '🖊️', '🖌️', '🖍️',
    '📝', '💼', '📁', '📂', '🗂️', '📅', '📆', '🗒️',
    '🗓️', '📇', '🗃️', '🗄️', '📈', '📉', '📊', '📋',
    '📌', '📍', '📎', '🖇️', '📏', '📐', '✂️', '🗃️',
    '📒', '📓', '📔', '📕', '📖', '📗', '📘', '📙',
    '📚', '🔖', '🏷️', '💰', '🪙', '💴', '💵', '💶',
    '💷', '💸', '💳', '🧾', '💹', '💱', '💲', '💰',
    '🔮', '🪄', '🧿', '🧸', '🪆', '🖼️', '🧵', '🧶',
    '🪡', '🎀', '🎗️', '🎁', '🎊', '🎉', '🎈', '🎎',
    '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🥇', '🥈',
    '🥉', '🏆', '🏅', '🎗️', '🎫', '🎟️', '🎪', '🤹',
    '🎭', '🎨', '🩰', '🎬', '🎤', '🎧', '🎼', '🎹',
    '🥁', '🎷', '🎺', '🎸', '🪕', '🎻', '🪗', '🎮',
    '🎰', '🧩', '🎲', '♟️', '🎯', '🎳', '🎱', '🪀',
    '🏓', '🏸', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷',
    '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️', '🤼',
    '🤸', '⛹️', '🤺', '🤾', '🏌️', '🏇', '🧘', '🏄',
    '🏊', '🤽', '🚴', '🚵', '🛀', '🛌', '🧑', '👶',
    '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔', '👩',
    '🧓', '👴', '👵', '🙍', '🙎', '🙅', '🙆', '💁',
    '🙋', '🧏', '🙇', '🤦', '🤷', '💆', '💇', '🚶',
    '🧍', '🧎', '🏃', '💃', '🕺', '👯', '🧖', '🧗',
    '🤺', '🏇', '⛷️', '🏂', '🏌️', '🏄', '🚣', '🏊',
    '⛹️', '🏋️', '🚴', '🚵', '🤸', '🤼', '🤽', '🧘',
    '🛀', '🛌', '👭', '👫', '👬', '💏', '💑', '👪',
    '👨‍👩‍👦', '👨‍👩‍👧', '👨‍👩‍👧‍👦', '👨‍👩‍👦‍👦', '👨‍👩‍👧‍👧',
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.6,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Emoji',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  childAspectRatio: 1.0,
                ),
                itemCount: _emojis.length,
                itemBuilder: (ctx, i) {
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, _emojis[i]),
                    borderRadius: BorderRadius.circular(8),
                    child: Center(
                      child: Text(_emojis[i], style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
