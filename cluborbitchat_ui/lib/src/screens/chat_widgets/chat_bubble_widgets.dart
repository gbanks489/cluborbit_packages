part of '../chat_screen.dart';

// ---------------------------------------------------------------------------
// _TimelineEventItem – plain data class for activity strip entries
// ---------------------------------------------------------------------------

class _TimelineEventItem {
  const _TimelineEventItem({
    required this.icon,
    required this.label,
    required this.time,
  });

  final IconData icon;
  final String label;
  final DateTime time;
}

class _TimelineEventCluster {
  const _TimelineEventCluster({required this.items});

  final List<_TimelineEventItem> items;

  _TimelineEventItem get latestEvent => items.last;

  String get key {
    return '${latestEvent.time.millisecondsSinceEpoch}:${latestEvent.label}:${items.length}';
  }
}

class _ChatTimelineEntry {
  const _ChatTimelineEntry.message(this.message, this.messageIndex)
    : eventCluster = null;

  const _ChatTimelineEntry.eventCluster(this.eventCluster)
    : message = null,
      messageIndex = null;

  final ChatMessage? message;
  final int? messageIndex;
  final _TimelineEventCluster? eventCluster;
}

// ---------------------------------------------------------------------------
// _TimelineEventClusterCard – collapsible event cluster shown inline in chat
// ---------------------------------------------------------------------------

class _TimelineEventClusterCard extends StatelessWidget {
  const _TimelineEventClusterCard({
    required this.cluster,
    required this.showAllEvents,
    required this.relativeTime,
    this.onToggle,
  });

  final _TimelineEventCluster cluster;
  final bool showAllEvents;
  final VoidCallback? onToggle;
  final String Function(DateTime) relativeTime;

  @override
  Widget build(BuildContext context) {
    final latestEvent = cluster.latestEvent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(latestEvent.icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  latestEvent.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                relativeTime(latestEvent.time),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          if (cluster.items.length > 1) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onToggle,
              child: Text(
                showAllEvents ? 'Hide events' : 'More events',
                style: const TextStyle(
                  color: Color(0xFF9BC7FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (showAllEvents && cluster.items.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: cluster.items.reversed
                    .skip(1)
                    .map(
                      (event) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(event.icon, size: 14, color: Colors.white54),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                event.label,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              relativeTime(event.time),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ReplySwipeBackground – swipe-to-reply indicator shown behind the bubble
// ---------------------------------------------------------------------------

class _ReplySwipeBackground extends StatelessWidget {
  const _ReplySwipeBackground({required this.alignment});

  final bool alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      alignment: alignment ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Icon(
        Icons.reply,
        color: PlayerUiSignalTheme.primaryDarkColor,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SignalReceiptTicks – double-circle read receipt indicator
// ---------------------------------------------------------------------------

class _SignalReceiptTicks extends StatelessWidget {
  const _SignalReceiptTicks({
    required this.isSent,
    required this.showReceivedCircle,
    required this.isRead,
  });

  final bool isSent;
  final bool showReceivedCircle;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    Widget circle({required bool active, required bool shouldBeFilled}) {
      final fill = shouldBeFilled
          ? const Color(0xFFB6D8FF)
          : Colors.transparent;
      final borderColor = shouldBeFilled ? Colors.white70 : Colors.white38;
      final checkColor = shouldBeFilled
          ? const Color(0xFF0E2E5C)
          : Colors.white70;

      return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: borderColor, width: 1),
        ),
        child: active ? Icon(Icons.check, size: 6, color: checkColor) : null,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle(active: isSent, shouldBeFilled: isSent || isRead),
        if (showReceivedCircle)
          Transform.translate(
            offset: const Offset(-2, 0),
            child: circle(active: isRead, shouldBeFilled: isRead),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _TypingBubble – animated "… is typing" indicator
// ---------------------------------------------------------------------------

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 24,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A273A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              const _AnimatedTypingDots(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedTypingDots extends StatefulWidget {
  const _AnimatedTypingDots();

  @override
  State<_AnimatedTypingDots> createState() => _AnimatedTypingDotsState();
}

class _AnimatedTypingDotsState extends State<_AnimatedTypingDots> {
  Timer? _timer;
  int _activeDot = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (!mounted) return;
      setState(() {
        _activeDot = (_activeDot + 1) % 3;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(3, (index) {
        final bool active = index == _activeDot;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: active ? 6 : 5,
          height: active ? 6 : 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withAlpha(active ? 230 : 120),
          ),
        );
      }),
    );
  }
}
