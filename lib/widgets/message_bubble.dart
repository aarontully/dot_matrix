import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final AppEvent event;
  final bool isMe;
  final bool isMetaAi;

  const MessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    this.isMetaAi = false,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the styling based on the messenger design
    Color bgColor;
    Color textColor;
    Gradient? gradient;

    if (isMe) {
      if (isMetaAi) {
        gradient = const LinearGradient(
          colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
        );
        bgColor = Colors.blue; 
      } else {
        bgColor = AppTheme.primaryBlue;
      }
      textColor = Colors.white;
    } else {
      bgColor = AppTheme.messageGray;
      textColor = Colors.black;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0), // Spacing between messages
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            const Padding(
              padding: EdgeInsets.only(right: 8.0, bottom: 4.0),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, size: 16, color: Colors.white),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: gradient == null ? bgColor : null,
                gradient: gradient,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4), // Simple logic for tails
                  bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
              ),
              child: Text(
                event.body,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          if (isMe)
            const Padding(
              padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
              child: CircleAvatar(
                radius: 8,
                backgroundColor: Colors.transparent,
                // Usually an indicator status goes here
              ),
            ),
        ],
      ),
    );
  }
}