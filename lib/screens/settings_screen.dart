import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5FB), // Off-white/light blue background
      appBar: AppBar(
        leadingWidth: 40,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildProfileHeader(),
            const SizedBox(height: 24),
            _buildSettingsGroup([
              _buildSettingsRow(Icons.dark_mode, 'Dark mode', trailingText: 'System'),
              _buildSettingsRow(Icons.circle_rounded, 'Active status', trailingText: 'On', iconColor: Colors.green),
              _buildSettingsRow(Icons.accessibility_new, 'Accessibility'),
              _buildSettingsRow(Icons.shield, 'Privacy & safety'),
            ]),
            const SizedBox(height: 16),
            _buildSettingsGroup([
              _buildSettingsRow(Icons.face, 'Avatar'),
              _buildSettingsRow(Icons.notifications, 'Notification & sounds', trailingText: 'On'),
              _buildSettingsRow(Icons.shopping_bag, 'Orders'),
              _buildSettingsRow(Icons.payment, 'Payments'),
              _buildSettingsRow(Icons.photo_library, 'Photos & media'),
            ]),
            const SizedBox(height: 16),
            _buildSettingsGroup([
              _buildSettingsRow(Icons.report_problem, 'Report a problem', hideChevron: true),
            ]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Stack(
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: Colors.pinkAccent,
              backgroundImage: AssetImage('assets/images/placeholder_avatar.png'), // Provide a dummy or remove
              child: Icon(Icons.person, size: 48, color: Colors.white), // Fallback
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, size: 20, color: Colors.black87),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Alex Walker',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Leave a note',
          style: TextStyle(
            fontSize: 16,
            color: Colors.blue,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingsRow(
    IconData icon,
    String title, {
    String? trailingText,
    Color iconColor = Colors.black87,
    bool hideChevron = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.black87,
              ),
            ),
          ),
          if (trailingText != null)
            Text(
              trailingText,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          if (!hideChevron) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ]
        ],
      ),
    );
  }
}
