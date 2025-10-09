import 'dart:async';
import 'package:flutter/material.dart';

class CustomNotification {
  static OverlayEntry? _overlayEntry;
  static Timer? _timer;

  static void show({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onTap,
  }) {
    // Remove any existing notification
    hide();

    _overlayEntry = OverlayEntry(
      builder: (context) => _NotificationWidget(
        title: title,
        message: message,
        onTap: onTap,
        onDismiss: hide,
      ),
    );

    // Insert the notification into the overlay
    Overlay.of(context).insert(_overlayEntry!);

    // Set a timer to automatically dismiss the notification after 5 seconds
    _timer = Timer(const Duration(seconds: 5), hide);
  }

  static void hide() {
    _timer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _NotificationWidget extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationWidget({
    Key? key,
    required this.title,
    required this.message,
    required this.onTap,
    required this.onDismiss,
  }) : super(key: key);

  @override
  _NotificationWidgetState createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<_NotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  double _dragStartY = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    // If dragging upwards
    if (details.globalPosition.dy < _dragStartY) {
      final double delta = (_dragStartY - details.globalPosition.dy) / 100;
      _controller.value = 1.0 - delta.clamp(0.0, 1.0);
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    // If dragged more than halfway up or with enough velocity, dismiss
    if (_controller.value < 0.5 || details.primaryVelocity! < -500) {
      _controller.reverse().then((_) => widget.onDismiss());
    } else {
      // Otherwise, snap back to full view
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8.0,
      left: 8.0,
      right: 8.0,
      child: SlideTransition(
        position: _offsetAnimation,
        child: GestureDetector(
          onTap: () {
            widget.onDismiss();
            widget.onTap();
          },
          onVerticalDragStart: _handleDragStart,
          onVerticalDragUpdate: _handleDragUpdate,
          onVerticalDragEnd: _handleDragEnd,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8.0),
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  const Icon(Icons.message_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.message,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}