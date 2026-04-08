import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/room_model.dart';

class MessageBubble extends StatelessWidget {
  final AppEvent event;
  final bool isMe;

  const MessageBubble({super.key, required this.event, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(event.originServerTs);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.body,
              style: TextStyle(color: isMe ? Colors.white : Colors.black),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 12,
                color: isMe ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}