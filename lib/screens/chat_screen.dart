import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:dot_matrix/widgets/dot_matrix_loader.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:record/record.dart';

import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../models/room_model.dart';
import '../services/push_notification_service.dart';
import '../utils/bridge_detector.dart';
import '../utils/current_session_trust.dart';
import '../utils/permissions.dart';
import '../utils/video_thumbnail_helper.dart';
import '../widgets/bridge_icon.dart';
import '../widgets/message_bubble.dart';
import '../widgets/room_avatar_grid.dart';
import 'encryption_settings_screen.dart';
import 'room_details_screen.dart';

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

class _ResolvedTimelineView {
  const _ResolvedTimelineView({
    required this.displayedMessages,
    required this.replyTargetsByEventId,
    required this.lastReadOutgoingEventId,
    required this.isWaitingForKey,
  });

  final List<AppEvent> displayedMessages;
  final Map<String, AppEvent?> replyTargetsByEventId;
  final String? lastReadOutgoingEventId;
  final bool isWaitingForKey;
}

class _MentionQuery {
  const _MentionQuery({required this.start, required this.query});

  final int start;
  final String query;
}

class _ChatScreenState extends State<ChatScreen> {
  static const double _historyPrefetchThreshold = 600;
  static const int _historyBatchSize = 40;
  static const double _pickedImageMaxDimension = 2048;
  static const int _pickedImageQuality = 85;
  static const int _previewDecodeSize = 180;
  static const String _settingsBoxName = 'dot_matrix_settings';
  static final DateFormat _dateHeaderFormat = DateFormat.yMMMMd();

  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();
  final _imagePicker = ImagePicker();
  bool _isTyping = false;
  bool _isAttachmentMenuOpen = false;
  bool _isMessageFieldFocused = false;
  bool _isRecording = false;
  bool _isLoadingHistory = false;
  bool _typingNotificationActive = false;
  final List<XFile> _pendingImages = [];
  File? _recordedAudioFile;
  AppEvent? _replyingToEvent;
  AppEvent? _editingEvent;
  final List<_ScheduledMessage> _scheduledMessages = [];
  Timer? _scheduleTimer;
  Timer? _typingHeartbeatTimer;
  final _messageKeys = <String, GlobalKey>{};
  List<AppEvent>? _cachedTimelineSourceMessages;
  String? _cachedTimelineOwnUserId;
  _ResolvedTimelineView? _cachedTimelineView;
  List<User> _mentionableUsers = const [];
  List<User> _mentionSuggestions = const [];
  int? _activeMentionStart;
  String _activeMentionQuery = '';
  bool _isLoadingMentionSuggestions = false;
  int _mentionLookupToken = 0;

  @override
  void initState() {
    super.initState();
    PushNotificationService().setActiveRoom(widget.room.id);
    _messageController.addListener(_handleComposerChanged);
    _messageFocusNode.addListener(() {
      final focused = _messageFocusNode.hasFocus;
      if (focused && _isAttachmentMenuOpen) {
        setState(() => _isAttachmentMenuOpen = false);
      }
      if (!focused) {
        _clearMentionSuggestions();
      }
      if (focused != _isMessageFieldFocused) {
        setState(() => _isMessageFieldFocused = focused);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markRoomAsRead();
      _scheduleHistoryPrefetchCheck();
    });
    // AudioRecorder initialized on first use
    _scheduleTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkScheduledMessages(),
    );
    _scrollController.addListener(() {
      _maybeLoadMoreHistory();
    });
    unawaited(_loadScheduledMessages());
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
    if (_isLoadingHistory) return;
    final roomController = Get.find<RoomController>();
    if (!roomController.canRequestRoomHistory(widget.room.id)) return;

    setState(() => _isLoadingHistory = true);
    try {
      await roomController.requestRoomHistory(
        widget.room.id,
        historyCount: _historyBatchSize,
      );
    } catch (e) {
      debugPrint('History load failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
        _scheduleHistoryPrefetchCheck();
      }
    }
  }

  bool _isNearHistoryEdge([ScrollMetrics? metrics]) {
    final activeMetrics =
        metrics ??
        (_scrollController.hasClients ? _scrollController.position : null);
    if (activeMetrics == null) return false;
    final triggerOffset =
        activeMetrics.maxScrollExtent - _historyPrefetchThreshold;
    return activeMetrics.pixels >= (triggerOffset < 0 ? 0 : triggerOffset);
  }

  void _maybeLoadMoreHistory([ScrollMetrics? metrics]) {
    if (_isLoadingHistory) return;
    if (!_isNearHistoryEdge(metrics)) return;
    _loadMoreHistory();
  }

  void _scheduleHistoryPrefetchCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeLoadMoreHistory();
    });
  }

  String? _latestVisibleMessageEventId() {
    if (widget.room.messages.isEmpty) return null;
    AppEvent? newest;
    for (final m in widget.room.messages) {
      if (m.rawEvent.status == EventStatus.sending) continue;
      if (newest == null || m.originServerTs.isAfter(newest.originServerTs)) {
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

  _ResolvedTimelineView _resolveTimelineView(
    List<AppEvent> messages,
    String? ownUserId,
  ) {
    if (identical(messages, _cachedTimelineSourceMessages) &&
        ownUserId == _cachedTimelineOwnUserId &&
        _cachedTimelineView != null) {
      return _cachedTimelineView!;
    }

    final displayedMessages = List<AppEvent>.from(messages)
      ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    final eventsById = <String, AppEvent>{
      for (final event in displayedMessages) event.rawEvent.eventId: event,
    };
    final replyTargetsByEventId = <String, AppEvent?>{};
    String? lastReadOutgoingEventId;

    for (final event in displayedMessages) {
      if (event.rawEvent.relationshipType == RelationshipTypes.reply) {
        final replyId = event.rawEvent.relationshipEventId;
        if (replyId != null) {
          replyTargetsByEventId[event.rawEvent.eventId] = eventsById[replyId];
        }
      }

      if (lastReadOutgoingEventId == null && event.isMe) {
        final hasOtherReaders = event.rawEvent.receipts.any(
          (r) => r.user.id != ownUserId,
        );
        if (hasOtherReaders) {
          lastReadOutgoingEventId = event.rawEvent.eventId;
        }
      }
    }

    final resolved = _ResolvedTimelineView(
      displayedMessages: displayedMessages,
      replyTargetsByEventId: replyTargetsByEventId,
      lastReadOutgoingEventId: lastReadOutgoingEventId,
      isWaitingForKey: messages.any((event) => event.isWaitingForRoomKey),
    );

    _cachedTimelineSourceMessages = messages;
    _cachedTimelineOwnUserId = ownUserId;
    _cachedTimelineView = resolved;
    return resolved;
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
                    if (widget.room.bridgePlatform !=
                        BridgePlatform.unknown) ...[
                      const SizedBox(width: 6),
                      BridgeIcon(platform: widget.room.bridgePlatform),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: theme.colorScheme.secondary),
            onPressed: _showRoomSearch,
          ),
          IconButton(
            icon: Icon(Icons.info_outline, color: theme.colorScheme.secondary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RoomDetailsScreen(room: widget.room),
                ),
              );
            },
          ),
        ],
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
                    final auth = Get.find<AuthController>();
                    final ownUserId = auth.client.userID;
                    final timelineView = _resolveTimelineView(
                      messages,
                      ownUserId,
                    );
                    final displayedMessages = timelineView.displayedMessages;

                    return Expanded(
                      child: Column(
                        children: [
                          if (timelineView.isWaitingForKey)
                            _buildRecoveryBanner(theme),
                          Expanded(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollUpdateNotification &&
                                    notification.dragDetails != null) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                }
                                if (notification is ScrollEndNotification ||
                                    notification is OverscrollNotification) {
                                  _maybeLoadMoreHistory(notification.metrics);
                                }
                                return false;
                              },
                              child: ListView.builder(
                                controller: _scrollController,
                                physics: const ClampingScrollPhysics(),
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  18,
                                  12,
                                  20,
                                ),
                                itemCount:
                                    displayedMessages.length +
                                    (_isLoadingHistory ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (_isLoadingHistory &&
                                      index == displayedMessages.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: DotMatrixLoader(
                                            size: 20,
                                            dotSize: 3,
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

                                  final replyTarget =
                                      timelineView.replyTargetsByEventId[event
                                          .rawEvent
                                          .eventId];

                                  final key = _messageKeys.putIfAbsent(
                                    event.rawEvent.eventId,
                                    () => GlobalKey(),
                                  );

                                  final showDateHeader =
                                      index > 0 &&
                                      !_isSameDay(
                                        event.originServerTs,
                                        displayedMessages[index - 1]
                                            .originServerTs,
                                      );

                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (showDateHeader)
                                        _buildDateHeader(
                                          event.originServerTs,
                                          theme,
                                        ),
                                      Container(
                                        key: key,
                                        child: MessageBubble(
                                          event: event,
                                          isMe: event.isMe,
                                          isMetaAi: false,
                                          isFirstInGroup: isFirstInGroup,
                                          isLastInGroup: isLastInGroup,
                                          showReadReceipts:
                                              event.rawEvent.eventId ==
                                              timelineView
                                                  .lastReadOutgoingEventId,
                                          replyToEvent: replyTarget,
                                          onReplyTap: replyTarget != null
                                              ? (id) => _scrollToEvent(
                                                  id,
                                                  displayedMessages,
                                                )
                                              : null,
                                          onAction: _handleMessageAction,
                                        ),
                                      ),
                                    ],
                                  );
                                },
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
          FilledButton.icon(
            onPressed: _openRecoveryTools,
            icon: const Icon(Icons.tune),
            label: const Text('Open recovery tools'),
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
          _buildUnverifiedWarning(),
          if (_shouldShowMentionSuggestions()) ...[
            _buildMentionSuggestions(cs),
            const SizedBox(height: 8),
          ],
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
                if (!_isMessageFieldFocused) ...[
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
                ],
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
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_pendingImages.isNotEmpty)
                                    _buildImagePreviews(cs),
                                  _buildComposerField(cs),
                                ],
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_pendingImages.isNotEmpty)
                                _buildImagePreviews(cs),
                              _buildComposerField(cs),
                            ],
                          ),
                        ),
                ),
                if (_isTyping || _pendingImages.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _buildCircleButton(
                    icon: Icons.send,
                    bg: cs.primary,
                    fg: cs.onPrimary,
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

  Widget _buildComposerField(ColorScheme cs) {
    return TextField(
      controller: _messageController,
      focusNode: _messageFocusNode,
      minLines: 1,
      maxLines: 4,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _sendMessage(),
      contentInsertionConfiguration: ContentInsertionConfiguration(
        onContentInserted: _handleInsertedContent,
        allowedMimeTypes: const [
          'image/gif',
          'image/png',
          'image/jpeg',
          'image/webp',
          'image/jpg',
        ],
      ),
      contextMenuBuilder: _buildComposerContextMenu,
      decoration: InputDecoration(
        hintText: 'Message...',
        hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
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
    );
  }

  Widget _buildComposerContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems = <ContextMenuButtonItem>[];
    for (final item in editableTextState.contextMenuButtonItems) {
      if (item.label == 'Paste') {
        buttonItems.add(
          ContextMenuButtonItem(
            onPressed: () async {
              final hasFiles = (await Pasteboard.files()).isNotEmpty;
              final imageBytes = await Pasteboard.image;
              if (hasFiles || (imageBytes != null && imageBytes.isNotEmpty)) {
                _pasteFromClipboard();
              } else {
                editableTextState.pasteText(SelectionChangedCause.toolbar);
              }
              editableTextState.hideToolbar();
            },
            label: 'Paste',
          ),
        );
      } else {
        buttonItems.add(item);
      }
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  Widget _buildMentionSuggestions(ColorScheme cs) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _isLoadingMentionSuggestions
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: DotMatrixLoader(size: 18, dotSize: 3, color: cs.primary),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _mentionSuggestions.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: cs.outlineVariant),
              itemBuilder: (context, index) {
                final user = _mentionSuggestions[index];
                final name = _mentionDisplayName(user);
                final subtitle = user.id == name ? null : user.id;
                final platform = BridgeDetector.detectFromUserId(user.id);
                final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    child: Text(initial),
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: subtitle == null
                      ? null
                      : Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: platform == BridgePlatform.unknown
                      ? null
                      : BridgeIcon(platform: platform, size: 18),
                  onTap: () => _insertMention(user),
                );
              },
            ),
    );
  }

  bool _shouldShowMentionSuggestions() {
    return _messageFocusNode.hasFocus &&
        (_isLoadingMentionSuggestions || _mentionSuggestions.isNotEmpty) &&
        (_activeMentionStart != null || _activeMentionQuery.isNotEmpty);
  }

  void _handleComposerChanged() {
    final isTyping = _messageController.text.trim().isNotEmpty;
    if (isTyping != _isTyping && mounted) {
      setState(() => _isTyping = isTyping);
    }
    _updateTypingNotification(isTyping);
    _refreshMentionSuggestions();
  }

  void _updateTypingNotification(bool isTyping) {
    if (isTyping) {
      _typingHeartbeatTimer?.cancel();
      _typingHeartbeatTimer = Timer(
        const Duration(seconds: 4),
        () => _setTypingNotification(false),
      );
      unawaited(_setTypingNotification(true));
      return;
    }

    _typingHeartbeatTimer?.cancel();
    unawaited(_setTypingNotification(false));
  }

  Future<void> _setTypingNotification(bool isTyping) async {
    if (_typingNotificationActive == isTyping) {
      return;
    }
    final room = Get.find<AuthController>().client.getRoomById(widget.room.id);
    if (room == null) return;

    _typingNotificationActive = isTyping;
    try {
      await room.setTyping(isTyping, timeout: isTyping ? 5000 : null);
    } catch (_) {
      _typingNotificationActive = false;
    }
  }

  void _clearMentionSuggestions() {
    if (_activeMentionStart == null &&
        _activeMentionQuery.isEmpty &&
        _mentionSuggestions.isEmpty &&
        !_isLoadingMentionSuggestions) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _activeMentionStart = null;
      _activeMentionQuery = '';
      _mentionSuggestions = const [];
      _isLoadingMentionSuggestions = false;
    });
  }

  _MentionQuery? _currentMentionQuery() {
    final value = _messageController.value;
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.extentOffset;
    if (cursor < 0 || cursor > value.text.length) return null;
    final prefix = value.text.substring(0, cursor);
    final match = RegExp(r'(^|[\s(])@([^\s@]*)$').firstMatch(prefix);
    if (match == null) return null;
    final start = match.start + match.group(1)!.length;
    return _MentionQuery(start: start, query: match.group(2) ?? '');
  }

  Future<void> _refreshMentionSuggestions() async {
    if (!_messageFocusNode.hasFocus) {
      _clearMentionSuggestions();
      return;
    }

    final mention = _currentMentionQuery();
    if (mention == null) {
      _clearMentionSuggestions();
      return;
    }

    final queryChanged =
        mention.start != _activeMentionStart ||
        mention.query != _activeMentionQuery;
    if (!queryChanged &&
        (_mentionSuggestions.isNotEmpty || _isLoadingMentionSuggestions)) {
      return;
    }

    if (mounted) {
      setState(() {
        _activeMentionStart = mention.start;
        _activeMentionQuery = mention.query;
        _isLoadingMentionSuggestions = _mentionableUsers.isEmpty;
        if (_mentionableUsers.isEmpty) {
          _mentionSuggestions = const [];
        }
      });
    }

    if (_mentionableUsers.isEmpty) {
      final token = ++_mentionLookupToken;
      final users = await _loadMentionableUsers();
      if (!mounted || token != _mentionLookupToken) return;
      _mentionableUsers = users;
    }

    final suggestions = _filterMentionSuggestions(mention.query);
    if (!mounted) return;
    setState(() {
      if (_activeMentionStart == mention.start &&
          _activeMentionQuery == mention.query) {
        _mentionSuggestions = suggestions;
        _isLoadingMentionSuggestions = false;
      }
    });
  }

  Future<List<User>> _loadMentionableUsers() async {
    final client = Get.find<AuthController>().client;
    final room = client.getRoomById(widget.room.id);
    if (room == null) return const [];

    try {
      final participants = await room.requestParticipants();
      return participants.where((user) {
        if (user.id == client.userID) return false;
        if (!{Membership.invite, Membership.join}.contains(user.membership)) {
          return false;
        }
        return !BridgeDetector.isBridgeBot(
          user.id,
          displayName: user.displayName,
        );
      }).toList()..sort((a, b) {
        final nameCompare = _mentionDisplayName(
          a,
        ).toLowerCase().compareTo(_mentionDisplayName(b).toLowerCase());
        if (nameCompare != 0) return nameCompare;
        return a.id.toLowerCase().compareTo(b.id.toLowerCase());
      });
    } catch (error) {
      debugPrint('Mention participant fetch failed: $error');
      return const [];
    }
  }

  List<User> _filterMentionSuggestions(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    final ranked =
        _mentionableUsers
            .map((user) {
              final displayName = _mentionDisplayName(user).toLowerCase();
              final mxid = user.id.toLowerCase();
              final localpart = user.id.localpart?.toLowerCase() ?? '';
              final startsWith =
                  displayName.startsWith(normalizedQuery) ||
                  localpart.startsWith(normalizedQuery) ||
                  mxid.startsWith(normalizedQuery);
              final contains =
                  normalizedQuery.isEmpty ||
                  displayName.contains(normalizedQuery) ||
                  localpart.contains(normalizedQuery) ||
                  mxid.contains(normalizedQuery);
              return (user: user, startsWith: startsWith, contains: contains);
            })
            .where((entry) => entry.contains)
            .toList()
          ..sort((a, b) {
            if (a.startsWith != b.startsWith) {
              return a.startsWith ? -1 : 1;
            }
            final nameCompare = _mentionDisplayName(a.user)
                .toLowerCase()
                .compareTo(_mentionDisplayName(b.user).toLowerCase());
            if (nameCompare != 0) return nameCompare;
            return a.user.id.toLowerCase().compareTo(b.user.id.toLowerCase());
          });

    return ranked.take(6).map((entry) => entry.user).toList();
  }

  String _mentionDisplayName(User user) {
    final displayName = user.calcDisplayname().trim();
    return displayName.isEmpty ? user.id : displayName;
  }

  void _insertMention(User user) {
    final selection = _messageController.selection;
    final mentionStart = _activeMentionStart;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, _messageController.text.length)
        : _messageController.text.length;
    if (mentionStart == null || mentionStart > cursor) return;

    final replacement = '${user.mention} ';
    final newText = _messageController.text.replaceRange(
      mentionStart,
      cursor,
      replacement,
    );
    final offset = mentionStart + replacement.length;
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
    _messageFocusNode.requestFocus();
    _clearMentionSuggestions();
  }

  Widget _buildUnverifiedWarning() {
    final client = Get.find<AuthController>().client;
    if (isCurrentSessionTrusted(client)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: Colors.orange.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Your device is unverified — others may see a warning on your messages',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.withValues(alpha: 0.7),
                height: 1.3,
              ),
            ),
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
          if (_isMessageFieldFocused) ...[
            const SizedBox(width: 8),
            _buildAttachmentChip(
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              color: const Color(0xFF8BC34A),
              onTap: _takePhoto,
            ),
            const SizedBox(width: 8),
            _buildAttachmentChip(
              icon: Icons.photo_outlined,
              label: 'Gallery',
              color: const Color(0xFF03A9F4),
              onTap: _pickGalleryImage,
            ),
          ],
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
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: fg, size: 22),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        onPressed: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  void _addPendingMedia(
    Iterable<XFile> media, {
    bool closeAttachmentMenu = false,
  }) {
    if (!mounted) return;
    final pendingMedia = media.toList();
    if (pendingMedia.isEmpty) return;
    setState(() {
      _pendingImages.addAll(pendingMedia);
      if (closeAttachmentMenu) {
        _isAttachmentMenuOpen = false;
      }
    });
  }

  Future<bool> _confirmSendToUnverifiedDevices(Room room) async {
    if (!room.encrypted) return true;

    final healthState = await room.calcEncryptionHealthState();
    if (healthState != EncryptionHealthState.unverifiedDevices) {
      return true;
    }

    final participants = await room.requestParticipants();
    if (!mounted) return false;

    final names =
        participants
            .where(
              (user) => {
                Membership.invite,
                Membership.join,
              }.contains(user.membership),
            )
            .where(
              (user) =>
                  room.client.userDeviceKeys[user.id]?.verified !=
                  UserVerifiedStatus.verified,
            )
            .map((user) => user.calcDisplayname().trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    String affectedDevicesLabel;
    if (names.isEmpty) {
      affectedDevicesLabel = 'This room has unverified Matrix devices.';
    } else if (names.length == 1) {
      affectedDevicesLabel =
          'This room has unverified Matrix devices for ${names.first}.';
    } else if (names.length == 2) {
      affectedDevicesLabel =
          'This room has unverified Matrix devices for ${names[0]} and ${names[1]}.';
    } else {
      affectedDevicesLabel =
          'This room has unverified Matrix devices for ${names[0]}, ${names[1]}, and ${names.length - 2} others.';
    }

    final shouldSend =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Send to unverified devices?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(affectedDevicesLabel),
                  const SizedBox(height: 12),
                  const Text(
                    'Sending now will share this room key with those devices so they can decrypt your message.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Send anyway'),
                ),
              ],
            );
          },
        ) ??
        false;

    return shouldSend;
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final images = List<XFile>.from(_pendingImages);
    if (text.isEmpty && images.isEmpty) return;

    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(widget.room.id);
      if (room == null) {
        if (!mounted) return;
        Get.snackbar('Error', 'Room not found');
        return;
      }
      if (!await _confirmSendToUnverifiedDevices(room)) return;

      HapticFeedback.lightImpact();
      _messageController.clear();
      setState(() => _pendingImages.clear());
      final replyTo = _replyingToEvent;
      final editing = _editingEvent;
      setState(() {
        _replyingToEvent = null;
        _editingEvent = null;
      });
      if (editing != null && text.isNotEmpty) {
        await room.sendTextEvent(text, editEventId: editing.rawEvent.eventId);
      } else if (replyTo != null && text.isNotEmpty) {
        await room.sendTextEvent(text, inReplyTo: replyTo.rawEvent);
      } else if (text.isNotEmpty) {
        await room.sendTextEvent(text);
      }
      for (final media in images) {
        if (_isVideoFile(media)) {
          await _sendVideoFile(File(media.path), mimeType: media.mimeType);
        } else {
          await _sendImageFile(File(media.path), mimeType: media.mimeType);
        }
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

  void _handleMessageAction(
    MessageAction action,
    AppEvent event, {
    String? reaction,
  }) {
    switch (action) {
      case MessageAction.reply:
        setState(() => _replyingToEvent = event);
        break;
      case MessageAction.copy:
        HapticFeedback.lightImpact();
        Clipboard.setData(ClipboardData(text: event.body));
        break;
      case MessageAction.forward:
        _showForwardDialog(event);
        break;
      case MessageAction.delete:
        _deleteMessage(event);
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
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
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
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
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
      Get.snackbar(
        '',
        'Message deleted',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
      );
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
                      r.displayname.isNotEmpty
                          ? r.displayname[0].toUpperCase()
                          : '#',
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
      Get.snackbar(
        '',
        'Forwarded',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
      );
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
                child: DotMatrixLoader(
                  size: 14,
                  dotSize: 2.5,
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
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _scheduledMessages.remove(sm));
                    unawaited(_persistScheduledMessages());
                  },
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
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
    await _persistScheduledMessages();

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
    final due = _scheduledMessages
        .where((sm) => sm.sendAt.isBefore(now))
        .toList();

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
      setState(
        () => _scheduledMessages.removeWhere((sm) => sm.sendAt.isBefore(now)),
      );
      await _persistScheduledMessages();
    }
  }

  Future<void> _loadScheduledMessages() async {
    final box = await Hive.openBox(_settingsBoxName);
    final raw = box.get(_scheduledMessageStorageKey);
    if (raw is! List || raw.isEmpty || !mounted) {
      return;
    }

    final sourceMessages = _currentSearchSourceMessages();
    final loaded = raw.whereType<Map>().map((entry) {
      final sendAtRaw = entry['send_at']?.toString();
      final sendAt = sendAtRaw == null ? null : DateTime.tryParse(sendAtRaw);
      if (sendAt == null) {
        return null;
      }
      final replyEventId = entry['reply_to_event_id']?.toString();
      final replyTo = replyEventId == null
          ? null
          : sourceMessages.firstWhereOrNull(
              (message) => message.rawEvent.eventId == replyEventId,
            );
      return _ScheduledMessage(
        text: entry['text']?.toString() ?? '',
        sendAt: sendAt,
        replyTo: replyTo,
      );
    }).whereType<_ScheduledMessage>().toList()
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));

    setState(() {
      _scheduledMessages
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> _persistScheduledMessages() async {
    final box = await Hive.openBox(_settingsBoxName);
    if (_scheduledMessages.isEmpty) {
      await box.delete(_scheduledMessageStorageKey);
      return;
    }

    await box.put(
      _scheduledMessageStorageKey,
      _scheduledMessages
          .map(
            (message) => <String, dynamic>{
              'text': message.text,
              'send_at': message.sendAt.toIso8601String(),
              'reply_to_event_id': message.replyTo?.rawEvent.eventId,
            },
          )
          .toList(),
    );
  }

  String get _scheduledMessageStorageKey => 'scheduled_messages::${widget.room.id}';

  Future<void> _takePhoto() async {
    if (!await requestCameraPermission(context)) return;
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: _pickedImageMaxDimension,
        maxHeight: _pickedImageMaxDimension,
        imageQuality: _pickedImageQuality,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      _addPendingMedia([photo], closeAttachmentMenu: true);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Camera error: $error');
    }
  }

  Future<void> _pickGalleryImage() async {
    if (!await requestPhotosPermission(context)) return;
    try {
      final media = await _imagePicker.pickMultipleMedia(
        maxWidth: _pickedImageMaxDimension,
        maxHeight: _pickedImageMaxDimension,
        imageQuality: _pickedImageQuality,
        requestFullMetadata: false,
      );
      if (media.isEmpty) return;
      _addPendingMedia(media, closeAttachmentMenu: true);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Gallery error: $error');
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      // On desktop, files() preserves original format (GIFs, etc.)
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        for (final path in files) {
          final ext = path.split('.').lastOrNull?.toLowerCase() ?? '';
          String? mime;
          switch (ext) {
            case 'gif':
              mime = 'image/gif';
            case 'png':
              mime = 'image/png';
            case 'jpg':
            case 'jpeg':
              mime = 'image/jpeg';
            case 'webp':
              mime = 'image/webp';
            case 'bmp':
              mime = 'image/bmp';
          }
          final media = XFile(path, mimeType: mime);
          _addPendingMedia([media]);
        }
        if (!mounted) return;
        Get.snackbar('', 'Image pasted');
        return;
      }

      final imageBytes = await Pasteboard.image;
      if (imageBytes == null || imageBytes.isEmpty) {
        if (!mounted) return;
        Get.snackbar('', 'No image in clipboard');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/clipboard_image_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(imageBytes);
      final media = XFile(path, mimeType: 'image/png');
      _addPendingMedia([media]);
      if (!mounted) return;
      Get.snackbar('', 'Image pasted');
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Paste failed: $error');
    }
  }

  Future<void> _handleInsertedContent(KeyboardInsertedContent content) async {
    try {
      final bytes = content.data;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        Get.snackbar('', 'No image data');
        return;
      }
      final mime = content.mimeType;
      final ext = _mimeToExt(mime);
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/keyboard_image_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File(path);
      await file.writeAsBytes(bytes);
      final media = XFile(path, mimeType: mime);
      _addPendingMedia([media]);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Insert failed: $error');
    }
  }

  String _mimeToExt(String mime) {
    switch (mime) {
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/png':
      default:
        return 'png';
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
      final isGif = mimeType?.toLowerCase().contains('gif') ?? false;
      await room.sendFileEvent(
        matrixFile,
        shrinkImageMaxDimension: isGif ? null : 1600,
      );
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Image send failed: $error');
    }
  }

  Future<void> _sendVideoFile(File file, {String? mimeType}) async {
    try {
      if (!await file.exists()) {
        if (!mounted) return;
        Get.snackbar('Error', 'Video file not found');
        return;
      }
      final fileSize = await file.length();
      if (fileSize == 0) {
        if (!mounted) return;
        Get.snackbar('Error', 'Video file is empty');
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
      final metadata = await loadVideoMetadata(file);
      final thumbnail = await createMatrixVideoThumbnail(
        file.path,
        fileName: file.path.split('/').last,
      );
      final matrixFile = MatrixVideoFile(
        bytes: bytes,
        name: file.path.split('/').last,
        mimeType: mimeType,
        width: metadata.width,
        height: metadata.height,
        duration: metadata.durationMs,
      );
      await room.sendFileEvent(matrixFile, thumbnail: thumbnail);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Video send failed: $error');
    }
  }

  Widget _buildImagePreviews(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_pendingImages.length, (index) {
          final file = _pendingImages[index];
          final isVideo = _isVideoFile(file);
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: isVideo
                    ? _VideoPreviewTile(file: file)
                    : Image.file(
                        File(file.path),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        cacheWidth: _previewDecodeSize,
                        cacheHeight: _previewDecodeSize,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_, _, _) => Container(
                          width: 60,
                          height: 60,
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              if (isVideo)
                const Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(index)),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  bool _isVideoFile(XFile file) {
    final mime = file.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('video/')) return true;
    final parts = file.path.toLowerCase().split('.');
    final ext = parts.length > 1 ? parts.last : '';
    return [
      'mp4',
      'mov',
      'avi',
      'mkv',
      'wmv',
      'flv',
      'webm',
      'm4v',
      '3gp',
      '3gpp',
    ].contains(ext);
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
      if (!await _confirmSendToUnverifiedDevices(room)) return;

      final matrixFile = MatrixFile(bytes: bytes, name: file.name);
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
        final path = await _audioRecorder.stop();
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
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        setState(() => _isRecording = true);
      } catch (error) {
        if (!mounted) return;
        Get.snackbar('Error', 'Recording error: $error');
      }
    }
  }

  Future<void> _discardRecording() async {
    try {
      if (_recordedAudioFile != null && await _recordedAudioFile!.exists()) {
        await _recordedAudioFile!.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete recording: $e');
    }
    setState(() => _recordedAudioFile = null);
  }

  Future<void> _sendPreviewAudio(File file) async {
    final client = Get.find<AuthController>().client;
    final room = client.getRoomById(widget.room.id);
    if (room == null) {
      if (!mounted) return;
      Get.snackbar('Error', 'Room not found');
      return;
    }
    if (!await _confirmSendToUnverifiedDevices(room)) return;
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
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  Widget _buildDateHeader(DateTime date, ThemeData theme) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    String text;
    if (_isSameDay(localDate, now)) {
      text = 'Today';
    } else if (_isSameDay(localDate, now.subtract(const Duration(days: 1)))) {
      text = 'Yesterday';
    } else {
      text = _dateHeaderFormat.format(localDate);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
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

  void _openRecoveryTools() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EncryptionSettingsScreen()),
    );
  }

  @override
  void dispose() {
    PushNotificationService().setActiveRoom(null);
    _typingHeartbeatTimer?.cancel();
    unawaited(_setTypingNotification(false));
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _scheduleTimer?.cancel();
    super.dispose();
  }

  List<AppEvent> _currentSearchSourceMessages() {
    final liveRoom = _findLiveRoom();
    final source = liveRoom?.messages ?? widget.room.messages;
    final messages = List<AppEvent>.from(source)
      ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    return messages;
  }

  Future<void> _showRoomSearch() async {
    final allMessages = _currentSearchSourceMessages();
    if (allMessages.isEmpty) {
      Get.snackbar('', 'No messages available to search yet.');
      return;
    }

    final controller = TextEditingController();
    var filtered = allMessages;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search this room',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final query = value.trim().toLowerCase();
                        setModalState(() {
                          filtered = query.isEmpty
                              ? allMessages
                              : allMessages.where((message) {
                                  final body = message.body.toLowerCase();
                                  final sender =
                                      (message.senderName ?? message.senderId)
                                          .toLowerCase();
                                  return body.contains(query) ||
                                      sender.contains(query);
                                }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: MediaQuery.of(ctx).size.height * 0.6,
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matches found'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, index) {
                                final message = filtered[index];
                                final sender =
                                    message.senderName ?? message.senderId;
                                return ListTile(
                                  title: Text(
                                    sender,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    message.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    DateFormat.MMMd().add_jm().format(
                                      message.originServerTs.toLocal(),
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _scrollToEvent(
                                      message.rawEvent.eventId,
                                      _currentSearchSourceMessages(),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }
}

class _VideoPreviewTile extends StatelessWidget {
  const _VideoPreviewTile({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: generateVideoThumbnailBytesFromFile(file.path),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, width: 60, height: 60, fit: BoxFit.cover);
        }

        return Container(
          width: 60,
          height: 60,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.videocam_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 22,
          ),
        );
      },
    );
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
  final _player = AudioPlayer();
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
      await _player.setSource(DeviceFileSource(widget.audioFile.path));
    } catch (e) {
      debugPrint('Audio preview load error: $e');
    }
    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      _player.seek(Duration.zero);
      setState(() => _isPlaying = false);
    });
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.resume();
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
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
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
    '😀',
    '😂',
    '🥰',
    '😍',
    '😎',
    '🤔',
    '😭',
    '😡',
    '👍',
    '👎',
    '👏',
    '🙌',
    '🤝',
    '🙏',
    '💪',
    '❤️',
    '🔥',
    '🎉',
    '✨',
    '💯',
    '😊',
    '😉',
    '🤣',
    '😘',
    '🤗',
    '🤭',
    '😴',
    '😷',
    '🤢',
    '🤬',
    '😱',
    '🤯',
    '🥳',
    '😇',
    '🤠',
    '🥶',
    '🥵',
    '🤡',
    '👻',
    '💀',
    '👋',
    '✋',
    '🤚',
    '🖐️',
    '👌',
    '🤌',
    '🤏',
    '✌️',
    '🤞',
    '🤟',
    '🤘',
    '🤙',
    '👈',
    '👉',
    '👆',
    '👇',
    '☝️',
    '👍',
    '👎',
    '✊',
    '👊',
    '🤛',
    '🤜',
    '👏',
    '🙌',
    '👐',
    '🤲',
    '🤝',
    '🙏',
    '✍️',
    '💅',
    '🤳',
    '💪',
    '🦾',
    '🦿',
    '🦵',
    '🦶',
    '👂',
    '🦻',
    '👃',
    '🧠',
    '🫀',
    '🫁',
    '🦷',
    '🦴',
    '👀',
    '👁️',
    '👅',
    '👄',
    '💋',
    '🩸',
    '🎃',
    '🤖',
    '👽',
    '👾',
    '🤡',
    '💩',
    '👍',
    '👎',
    '👊',
    '✊',
    '🤛',
    '🤜',
    '👏',
    '🙌',
    '👐',
    '🤲',
    '🤝',
    '🙏',
    '✍️',
    '💅',
    '🤳',
    '💪',
    '🦾',
    '🦿',
    '🦵',
    '🦶',
    '👂',
    '🦻',
    '👃',
    '🐶',
    '🐱',
    '🐭',
    '🐹',
    '🐰',
    '🦊',
    '🐻',
    '🐼',
    '🐨',
    '🐯',
    '🦁',
    '🐮',
    '🐷',
    '🐽',
    '🐸',
    '🐵',
    '🙈',
    '🙉',
    '🙊',
    '🐒',
    '🐔',
    '🐧',
    '🐦',
    '🐤',
    '🐣',
    '🐥',
    '🦆',
    '🦅',
    '🦉',
    '🦇',
    '🐺',
    '🐗',
    '🐴',
    '🦄',
    '🐝',
    '🐛',
    '🦋',
    '🐌',
    '🐞',
    '🐜',
    '🦟',
    '🦗',
    '🕷️',
    '🕸️',
    '🦂',
    '🐢',
    '🐍',
    '🦎',
    '🦖',
    '🦕',
    '🐙',
    '🦑',
    '🦐',
    '🦞',
    '🦀',
    '🐡',
    '🐠',
    '🐟',
    '🐬',
    '🐳',
    '🐋',
    '🦈',
    '🐊',
    '🐅',
    '🐆',
    '🦓',
    '🦍',
    '🦧',
    '🐘',
    '🦛',
    '🦏',
    '🐪',
    '🐫',
    '🦒',
    '🦘',
    '🦬',
    '🐃',
    '🐂',
    '🐄',
    '🐖',
    '🐏',
    '🐑',
    '🦙',
    '🐐',
    '🦌',
    '🐕',
    '🐩',
    '🦮',
    '🐕‍🦺',
    '🐈',
    '🐈‍⬛',
    '🐓',
    '🦃',
    '🦚',
    '🦜',
    '🦢',
    '🦩',
    '🕊️',
    '🐇',
    '🦝',
    '🦨',
    '🦡',
    '🦦',
    '🦥',
    '🐁',
    '🐀',
    '🐿️',
    '🦔',
    '🍎',
    '🍐',
    '🍊',
    '🍋',
    '🍌',
    '🍉',
    '🍇',
    '🍓',
    '🫐',
    '🍈',
    '🍒',
    '🍑',
    '🥭',
    '🍍',
    '🥥',
    '🥝',
    '🍅',
    '🍆',
    '🥑',
    '🥦',
    '🥬',
    '🥒',
    '🌶️',
    '🫑',
    '🌽',
    '🥕',
    '🫒',
    '🧄',
    '🧅',
    '🥔',
    '🍠',
    '🥐',
    '🥯',
    '🍞',
    '🥖',
    '🥨',
    '🧀',
    '🥚',
    '🍳',
    '🧈',
    '🥞',
    '🧇',
    '🥓',
    '🥩',
    '🍗',
    '🍖',
    '🌭',
    '🍔',
    '🍟',
    '🍕',
    '🥪',
    '🥙',
    '🧆',
    '🌮',
    '🌯',
    '🫔',
    '🥗',
    '🥘',
    '🫕',
    '🥫',
    '🍝',
    '🍜',
    '🍲',
    '🍛',
    '🍣',
    '🍱',
    '🥟',
    '🦪',
    '🍤',
    '🍙',
    '🍚',
    '🍘',
    '🍥',
    '🥠',
    '🥮',
    '🍢',
    '🍡',
    '🍧',
    '🍨',
    '🍦',
    '🥧',
    '🧁',
    '🍰',
    '🎂',
    '🍮',
    '🍭',
    '🍬',
    '🍫',
    '🍿',
    '🍩',
    '🍪',
    '🌰',
    '🥜',
    '🍯',
    '🥛',
    '🍼',
    '🫖',
    '☕',
    '🍵',
    '🧃',
    '🥤',
    '🧋',
    '🍶',
    '🍺',
    '🍻',
    '🥂',
    '🍷',
    '🥃',
    '🍸',
    '🍹',
    '🧉',
    '🍾',
    '🧊',
    '🥄',
    '🍴',
    '🍽️',
    '🥣',
    '🥡',
    '🥢',
    '🧂',
    '⚽',
    '🏀',
    '🏈',
    '⚾',
    '🥎',
    '🎾',
    '🏐',
    '🏉',
    '🥏',
    '🎱',
    '🪀',
    '🏓',
    '🏸',
    '🏒',
    '🏑',
    '🥍',
    '🏏',
    '🥅',
    '⛳',
    '🪁',
    '🏹',
    '🎣',
    '🤿',
    '🥊',
    '🥋',
    '🎽',
    '🛹',
    '🛼',
    '🛷',
    '⛸️',
    '🥌',
    '🎿',
    '⛷️',
    '🏂',
    '🪂',
    '🏋️',
    '🤼',
    '🤸',
    '⛹️',
    '🤺',
    '🤾',
    '🏌️',
    '🏇',
    '🧘',
    '🏄',
    '🏊',
    '🤽',
    '🚴',
    '🚵',
    '🎖️',
    '🏆',
    '🏅',
    '🥇',
    '🥈',
    '🥉',
    '🎗️',
    '🏵️',
    '🎫',
    '🎟️',
    '🎪',
    '🤹',
    '🎭',
    '🩰',
    '🎨',
    '🎬',
    '🎤',
    '🎧',
    '🎼',
    '🎹',
    '🥁',
    '🎷',
    '🎺',
    '🎸',
    '🪕',
    '🎻',
    '🪗',
    '🎲',
    '♟️',
    '🎯',
    '🎳',
    '🎮',
    '🎰',
    '🧩',
    '🚗',
    '🚕',
    '🚙',
    '🚌',
    '🚎',
    '🏎️',
    '🚓',
    '🚑',
    '🚒',
    '🚐',
    '🛻',
    '🚚',
    '🚛',
    '🚜',
    '🦯',
    '🦽',
    '🦼',
    '🛴',
    '🚲',
    '🛵',
    '🏍️',
    '🛺',
    '🚨',
    '🚔',
    '🚍',
    '🚘',
    '🚖',
    '🚡',
    '🚠',
    '🚟',
    '🚃',
    '🚋',
    '🚞',
    '🚝',
    '🚄',
    '🚅',
    '🚈',
    '🚂',
    '🚆',
    '🚇',
    '🚊',
    '🚉',
    '✈️',
    '🛫',
    '🛬',
    '🛩️',
    '💺',
    '🛶',
    '⛵',
    '🛥️',
    '🚤',
    '🛳️',
    '⛴️',
    '🚢',
    '⚓',
    '🪝',
    '⛽',
    '🚧',
    '🚦',
    '🚥',
    '🚏',
    '🗺️',
    '🗿',
    '🗽',
    '🗼',
    '🏰',
    '🏯',
    '🏟️',
    '🎡',
    '🎢',
    '🎠',
    '⛲',
    '⛱️',
    '🏖️',
    '🏝️',
    '🏜️',
    '🌋',
    '⛰️',
    '🏔️',
    '🗻',
    '🏕️',
    '⛺',
    '🏠',
    '🏡',
    '🏘️',
    '🏚️',
    '🏗️',
    '🏭',
    '🏢',
    '🏬',
    '🏣',
    '🏤',
    '🏥',
    '🏦',
    '🏨',
    '🏪',
    '🏫',
    '🏩',
    '💒',
    '🏛️',
    '⛪',
    '🕌',
    '🕍',
    '🛕',
    '🕋',
    '⛩️',
    '🛤️',
    '🛣️',
    '🗾',
    '🎑',
    '🏞️',
    '🌅',
    '🌄',
    '🌠',
    '🎇',
    '🎆',
    '🌇',
    '🌆',
    '🏙️',
    '🌃',
    '🌉',
    '🌌',
    '🌠',
    '🥶',
    '🥵',
    '🌡️',
    '☀️',
    '🌤️',
    '⛅',
    '🌥️',
    '☁️',
    '🌦️',
    '🌧️',
    '⛈️',
    '🌩️',
    '🌨️',
    '❄️',
    '☃️',
    '⛄',
    '🌬️',
    '💨',
    '💧',
    '☔',
    '☂️',
    '🌊',
    '🌫️',
    '🌪️',
    '🌀',
    '🌈',
    '🌂',
    '🔥',
    '💥',
    '✨',
    '🎊',
    '🎉',
    '🎀',
    '🎁',
    '🎗️',
    '🏷️',
    '🕯️',
    '💡',
    '🔦',
    '🏮',
    '🪔',
    '📜',
    '📃',
    '📄',
    '📑',
    '📊',
    '📈',
    '📉',
    '🗒️',
    '🗓️',
    '📆',
    '📅',
    '📇',
    '🗃️',
    '🗳️',
    '🗄️',
    '📋',
    '📁',
    '📂',
    '🗂️',
    '🗞️',
    '📰',
    '📓',
    '📔',
    '📒',
    '📕',
    '📗',
    '📘',
    '📙',
    '📚',
    '📖',
    '🔖',
    '🧷',
    '🔗',
    '📎',
    '🖇️',
    '📐',
    '📏',
    '🌈',
    '🎨',
    '🧵',
    '🧶',
    '🪡',
    '🧷',
    '🔧',
    '🔨',
    '🪛',
    '⛏️',
    '🪚',
    '🪓',
    '🔩',
    '🦯',
    '🗜️',
    '⚙️',
    '🪝',
    '🧱',
    '🪨',
    '🪵',
    '🛢️',
    '⛽',
    '🧨',
    '🚬',
    '⚰️',
    '🪦',
    '🧸',
    '🪆',
    '🧩',
    '🧮',
    '🪄',
    '💎',
    '💍',
    '👑',
    '💄',
    '💋',
    '💌',
    '📧',
    '📨',
    '📩',
    '📤',
    '📥',
    '📦',
    '🏷️',
    '📪',
    '📫',
    '📬',
    '📭',
    '📮',
    '🗳️',
    '✏️',
    '✒️',
    '🖋️',
    '🖊️',
    '🖌️',
    '🖍️',
    '📝',
    '💼',
    '📁',
    '📂',
    '🗂️',
    '📅',
    '📆',
    '🗒️',
    '🗓️',
    '📇',
    '🗃️',
    '🗄️',
    '📈',
    '📉',
    '📊',
    '📋',
    '📌',
    '📍',
    '📎',
    '🖇️',
    '📏',
    '📐',
    '✂️',
    '🗃️',
    '📒',
    '📓',
    '📔',
    '📕',
    '📖',
    '📗',
    '📘',
    '📙',
    '📚',
    '🔖',
    '🏷️',
    '💰',
    '🪙',
    '💴',
    '💵',
    '💶',
    '💷',
    '💸',
    '💳',
    '🧾',
    '💹',
    '💱',
    '💲',
    '💰',
    '🔮',
    '🪄',
    '🧿',
    '🧸',
    '🪆',
    '🖼️',
    '🧵',
    '🧶',
    '🪡',
    '🎀',
    '🎗️',
    '🎁',
    '🎊',
    '🎉',
    '🎈',
    '🎎',
    '🏆',
    '🥇',
    '🥈',
    '🥉',
    '🏅',
    '🎖️',
    '🥇',
    '🥈',
    '🥉',
    '🏆',
    '🏅',
    '🎗️',
    '🎫',
    '🎟️',
    '🎪',
    '🤹',
    '🎭',
    '🎨',
    '🩰',
    '🎬',
    '🎤',
    '🎧',
    '🎼',
    '🎹',
    '🥁',
    '🎷',
    '🎺',
    '🎸',
    '🪕',
    '🎻',
    '🪗',
    '🎮',
    '🎰',
    '🧩',
    '🎲',
    '♟️',
    '🎯',
    '🎳',
    '🎱',
    '🪀',
    '🏓',
    '🏸',
    '🥊',
    '🥋',
    '🎽',
    '🛹',
    '🛼',
    '🛷',
    '⛸️',
    '🥌',
    '🎿',
    '⛷️',
    '🏂',
    '🪂',
    '🏋️',
    '🤼',
    '🤸',
    '⛹️',
    '🤺',
    '🤾',
    '🏌️',
    '🏇',
    '🧘',
    '🏄',
    '🏊',
    '🤽',
    '🚴',
    '🚵',
    '🛀',
    '🛌',
    '🧑',
    '👶',
    '🧒',
    '👦',
    '👧',
    '🧑',
    '👱',
    '👨',
    '🧔',
    '👩',
    '🧓',
    '👴',
    '👵',
    '🙍',
    '🙎',
    '🙅',
    '🙆',
    '💁',
    '🙋',
    '🧏',
    '🙇',
    '🤦',
    '🤷',
    '💆',
    '💇',
    '🚶',
    '🧍',
    '🧎',
    '🏃',
    '💃',
    '🕺',
    '👯',
    '🧖',
    '🧗',
    '🤺',
    '🏇',
    '⛷️',
    '🏂',
    '🏌️',
    '🏄',
    '🚣',
    '🏊',
    '⛹️',
    '🏋️',
    '🚴',
    '🚵',
    '🤸',
    '🤼',
    '🤽',
    '🧘',
    '🛀',
    '🛌',
    '👭',
    '👫',
    '👬',
    '💏',
    '💑',
    '👪',
    '👨‍👩‍👦',
    '👨‍👩‍👧',
    '👨‍👩‍👧‍👦',
    '👨‍👩‍👦‍👦',
    '👨‍👩‍👧‍👧',
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
                      child: Text(
                        _emojis[i],
                        style: const TextStyle(fontSize: 24),
                      ),
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
