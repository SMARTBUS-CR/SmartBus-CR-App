import 'dart:async';

import 'package:flutter/material.dart';

/// Notice shown while a request is in progress, but only once it takes longer
/// than [delay].
///
/// Render's free tier puts the Gateway and the Auth service to sleep after a
/// while, so the first request can take up to a minute. Without a hint the user
/// thinks the app froze and retries (which also hits the login throttle).
///
/// Usage: `if (isLoading) const SlowRequestHint()` — the timer starts when the
/// widget is inserted and is cancelled when it is removed.
class SlowRequestHint extends StatefulWidget {
  const SlowRequestHint({
    super.key,
    this.delay = const Duration(seconds: 8),
    this.message = 'Preparando todo… Puede tardar un momento.',
  });

  final Duration delay;
  final String message;

  @override
  State<SlowRequestHint> createState() => _SlowRequestHintState();
}

class _SlowRequestHintState extends State<SlowRequestHint> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(Icons.hourglass_top, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
