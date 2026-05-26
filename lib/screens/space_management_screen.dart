import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/room_controller.dart';
import '../widgets/dot_matrix_loader.dart';

class SpaceManagementScreen extends StatefulWidget {
  const SpaceManagementScreen({super.key});

  @override
  State<SpaceManagementScreen> createState() => _SpaceManagementScreenState();
}

class _SpaceManagementScreenState extends State<SpaceManagementScreen> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Spaces'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _isSaving ? null : _createSpace,
          ),
        ],
      ),
      body: GetBuilder<RoomController>(
        builder: (roomController) {
          final spaces = roomController.spaces;
          if (spaces.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 40,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No spaces yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create spaces to group related chats together.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _createSpace,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: DotMatrixLoader(
                                size: 18,
                                dotSize: 3,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: const Text('Create space'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: spaces.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final space = spaces[index];
              final name = space['name'] ?? 'Space';
              final roomId = space['id']!;
              return Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    child: Icon(Icons.hub, color: cs.onSecondaryContainer),
                  ),
                  title: Text(name),
                  subtitle: Text(roomId),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _renameSpace(roomId, name);
                          break;
                        case 'delete':
                          _deleteSpace(roomId, name);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Get.find<RoomController>().spaces.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _createSpace,
              icon: const Icon(Icons.add),
              label: const Text('New space'),
            )
          : null,
    );
  }

  Future<void> _createSpace() async {
    final name = await _promptForName(
      title: 'Create space',
      confirmLabel: 'Create',
    );
    if (name == null) return;

    setState(() => _isSaving = true);
    try {
      final client = Get.find<AuthController>().client;
      await client.createSpace(name: name, waitForSync: true);
      await Get.find<RoomController>().refreshRooms();
      if (!mounted) return;
      Get.snackbar('', 'Space created');
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Could not create space: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _renameSpace(String roomId, String currentName) async {
    final nextName = await _promptForName(
      title: 'Rename space',
      initialValue: currentName,
      confirmLabel: 'Save',
    );
    if (nextName == null || nextName == currentName) return;

    setState(() => _isSaving = true);
    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw Exception('Space not found');
      }
      await room.setName(nextName);
      await Get.find<RoomController>().refreshRooms();
      if (!mounted) return;
      Get.snackbar('', 'Space renamed');
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Could not rename space: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteSpace(String roomId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete space'),
        content: Text(
          'This will leave and forget "$name" on this device. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final client = Get.find<AuthController>().client;
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw Exception('Space not found');
      }
      await room.leave();
      await room.forget();
      await Get.find<RoomController>().refreshRooms(rebuildTimelines: true);
      if (!mounted) return;
      Get.snackbar('', 'Space deleted');
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('Error', 'Could not delete space: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<String?> _promptForName({
    required String title,
    String initialValue = '',
    required String confirmLabel,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Space name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) {
      return null;
    }
    return result.trim();
  }
}
