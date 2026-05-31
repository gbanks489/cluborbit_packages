import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:provider/provider.dart';

import '../app/playerchat_router.dart';
import '../widgets/playerui_search_bar.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final Map<String, String> _dmCounterpartUserIdByRoom = <String, String>{};
  final Set<String> _dmParticipantRequestsInFlight = <String>{};
  final Set<String> _presenceRequestsInFlight = <String>{};
  Timer? _presenceRefreshTimer;
  String _presenceRefreshKey = '';

  @override
  void initState() {
    super.initState();
    _presenceRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) {
        return;
      }
      _refreshVisibleDmPresence(context.read<ChatController>());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(ChatAppearanceStore().warmCache());
      final controller = context.read<ChatController>();
      _refreshVisibleDmPresence(controller);
      if (controller.userProfile == null) {
        try {
          await controller.refreshCurrentUserProfile();
        } catch (_) {
          // Error notifier already receives the exception. Keep chat list usable.
        }
      }
    });
  }

  @override
  void dispose() {
    _presenceRefreshTimer?.cancel();
    super.dispose();
  }

  void _refreshVisibleDmPresence(ChatController controller) {
    for (final thread in controller.threads) {
      if (thread.type != ChatType.dm || thread.isInvited) {
        continue;
      }
      final cachedCounterpart = controller.cachedDirectMessageCounterpart(
        thread.id,
      );
      final userId =
          cachedCounterpart?.userId ?? _dmCounterpartUserIdByRoom[thread.id];
      if (cachedCounterpart != null && userId != null && userId.isNotEmpty) {
        _dmCounterpartUserIdByRoom[thread.id] = userId;
        _ensurePresenceLoaded(controller, userId);
        continue;
      }
      _ensureDmCounterpartLoaded(controller, thread.id);
    }
  }

  void _ensureDmCounterpartLoaded(ChatController controller, String roomId) {
    if (_dmParticipantRequestsInFlight.contains(roomId)) {
      return;
    }
    _dmParticipantRequestsInFlight.add(roomId);
    unawaited(() async {
      try {
        final participants = await controller.getRoomParticipants(roomId);
        final counterpart = participants.where((participant) {
          return participant.userId != controller.matrixUserId &&
              participant.membership != 'leave';
        }).firstOrNull;
        if (!mounted || counterpart == null) {
          return;
        }
        if (_dmCounterpartUserIdByRoom[roomId] != counterpart.userId) {
          setState(() {
            _dmCounterpartUserIdByRoom[roomId] = counterpart.userId;
          });
        } else {
          _dmCounterpartUserIdByRoom[roomId] = counterpart.userId;
        }
        _ensurePresenceLoaded(controller, counterpart.userId);
      } catch (_) {
        // Presence is best-effort in the chat list.
      } finally {
        _dmParticipantRequestsInFlight.remove(roomId);
      }
    }());
  }

  void _ensurePresenceLoaded(ChatController controller, String userId) {
    if (userId.isEmpty || _presenceRequestsInFlight.contains(userId)) {
      return;
    }
    if (controller.cachedUserPresence(userId) != null) {
      return;
    }
    _presenceRequestsInFlight.add(userId);
    unawaited(() async {
      try {
        await controller.getUserPresence(userId);
        if (mounted) {
          setState(() {});
        }
      } catch (_) {
        // Presence refresh is best-effort.
      } finally {
        _presenceRequestsInFlight.remove(userId);
      }
    }());
  }

  void _schedulePresenceRefreshIfNeeded(ChatController controller) {
    final dmThreadIds =
        controller.threads
            .where((thread) => thread.type == ChatType.dm && !thread.isInvited)
            .map((thread) => thread.id)
            .toList(growable: false)
          ..sort();
    final nextKey = dmThreadIds.join('|');
    if (nextKey.isEmpty || nextKey == _presenceRefreshKey) {
      return;
    }
    _presenceRefreshKey = nextKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshVisibleDmPresence(controller);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, controller, _) {
        _schedulePresenceRefreshIfNeeded(controller);
        final error = context.watch<ErrorNotifier>().errorMessage?.trim();
        return Scaffold(
          backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
          appBar: AppBar(
            backgroundColor: PlayerUiSignalTheme.secondaryColor,
            title: const Text(
              'Chats',
              style: TextStyle(color: PlayerUiSignalTheme.primaryDarkColor),
            ),
            actions: [
              Builder(
                builder: (context) {
                  final profile = controller.userProfile;
                  final avatarUrl = profile?.profilePic?.thumbnailURL;
                  final initialsSource =
                      profile?.displayName ?? profile?.firstName ?? 'U';
                  final initials = initialsSource.trim().isEmpty
                      ? 'U'
                      : initialsSource.trim()[0].toUpperCase();

                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: PopupMenuButton<String>(
                      tooltip: 'Account menu',
                      position: PopupMenuPosition.under,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      color: PlayerUiSignalTheme.secondaryColor,
                      onSelected: (value) async {
                        if (value == 'profile') {
                          context.pushNamed(PlayerChatRoutes.profile);
                          return;
                        }
                        if (value == 'call_settings') {
                          context.pushNamed(PlayerChatRoutes.callSettings);
                          return;
                        }
                        if (value == 'logout') {
                          await controller.logout();
                          if (!context.mounted) return;
                          context.goNamed(PlayerChatRoutes.login);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                          value: 'profile',
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 18,
                                color: PlayerUiSignalTheme.primaryDarkColor,
                              ),
                              SizedBox(width: 8),
                              Text('Profile'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'call_settings',
                          child: Row(
                            children: [
                              Icon(
                                Icons.call,
                                size: 18,
                                color: PlayerUiSignalTheme.primaryDarkColor,
                              ),
                              SizedBox(width: 8),
                              Text('Call settings'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(
                                Icons.logout,
                                size: 18,
                                color: PlayerUiSignalTheme.primaryDarkColor,
                              ),
                              SizedBox(width: 8),
                              Text('Logout'),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: PlayerUiSignalTheme.primaryDarkColor,
                            width: 3,
                          ),
                        ),
                        child: _AvatarThumb(
                          imageUrl: avatarUrl,
                          initials: initials,
                          size: 32,
                          backgroundColor: PlayerUiSignalTheme.secondaryColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
            foregroundColor: PlayerUiSignalTheme.secondaryColor,
            onPressed: () {
              context.pushNamed(PlayerChatRoutes.createChat);
            },
            child: const Icon(Icons.edit_square),
          ),
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (error != null && error.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A1616),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFF8A80).withAlpha(150),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.error_outline,
                                color: Color(0xFFFFB4AB),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                error,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFFFDAD6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: context.read<ErrorNotifier>().clear,
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close,
                                  color: Color(0xFFFFDAD6),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    PlayerUiSearchBar(
                      onChanged: controller.updateSearchQuery,
                      title: 'users and chats',
                      accentColor: PlayerUiSignalTheme.primaryDarkColor,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: controller.loadThreads,
                        child: _buildResultsList(context, controller),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.matrixConnecting)
                Positioned.fill(
                  child: _ChatListSyncOverlay(
                    progressPercent: controller.matrixSyncPercent,
                    status: controller.matrixSyncStatus,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResultsList(BuildContext context, ChatController controller) {
    final showUsers = controller.query.trim().isNotEmpty;
    final threads = controller.threads;
    final users = controller.searchedUsers;

    if (!showUsers) {
      return ListView.separated(
        itemCount: threads.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _buildThreadTile(context, controller, threads[index]),
      );
    }

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Chats',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: PlayerUiSignalTheme.primaryDarkColor,
            ),
          ),
        ),
        if (threads.isEmpty)
          const ListTile(title: Text('No chat matches'))
        else
          ...threads.map((t) => _buildThreadTile(context, controller, t)),
        const Divider(height: 24),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Users',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: PlayerUiSignalTheme.primaryDarkColor,
            ),
          ),
        ),
        if (users.isEmpty)
          const ListTile(title: Text('No user matches'))
        else
          ...users.map(
            (u) => ListTile(
              leading: _AvatarThumb(
                imageUrl: u.avatarUrl,
                initials: u.displayName.isEmpty
                    ? '?'
                    : u.displayName[0].toUpperCase(),
                size: 40,
                backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
              ),
              title: Text(u.displayName),
              subtitle: Text(u.userId),
              onTap: () async {
                await controller.createDm(u.userId, roomTitle: u.displayName);
                if (!context.mounted) return;
                context.pushNamed(
                  PlayerChatRoutes.chat,
                  extra: PlayerChatChatRouteData(
                    title: u.displayName,
                    avatarUrl: u.avatarUrl,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildThreadTile(
    BuildContext context,
    ChatController controller,
    ChatThread thread,
  ) {
    final avatarUrl = thread.avatarUrl;
    final isInvited = thread.isInvited;
    final lastMessage = thread.lastMessage?.trim() ?? '';
    final subtitleText = lastMessage.isEmpty ? 'No messages' : lastMessage;
    final counterpartUserId = thread.type == ChatType.dm
        ? (controller.cachedDirectMessageCounterpart(thread.id)?.userId ??
              _dmCounterpartUserIdByRoom[thread.id])
        : null;
    final isOnline =
        counterpartUserId != null &&
        (controller.cachedUserPresence(counterpartUserId)?.isOnline ?? false);

    return ListTile(
      tileColor: PlayerUiSignalTheme.mobileSearchColor.withAlpha(90),
      leading: _AvatarThumb(
        imageUrl: avatarUrl,
        initials: thread.title.isEmpty ? '?' : thread.title[0].toUpperCase(),
        size: 40,
        backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
        useGroupPlaceholder: thread.type == ChatType.group,
        showPresence: thread.type == ChatType.dm && !isInvited,
        isOnline: isOnline,
      ),
      title: Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTimeAgo(thread.updatedAt),
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isInvited)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.mail_outline,
                    size: 16,
                    color: Colors.orange,
                  ),
                ),
              if (thread.unreadCount > 0)
                CircleAvatar(
                  radius: 10,
                  backgroundColor: PlayerUiSignalTheme.primaryColor,
                  child: Text(
                    thread.unreadCount.toString(),
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
      onTap: () async {
        if (isInvited) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              return const AlertDialog(
                content: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 16),
                    Expanded(child: Text('Joining room...')),
                  ],
                ),
              );
            },
          );
          try {
            final joined = await controller.joinRoomIfInvited(thread.id);
            if (!context.mounted) return;
            Navigator.of(context, rootNavigator: true).pop();
            if (!joined) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not join this invited room yet.'),
                ),
              );
              return;
            }
            await controller.loadThreads();
          } catch (_) {
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            rethrow;
          }
        }

        controller.openRoomInBackground(thread.id, roomTitle: thread.title);
        if (!context.mounted) return;
        context.pushNamed(
          PlayerChatRoutes.chat,
          extra: PlayerChatChatRouteData(
            title: thread.title,
            avatarUrl: thread.avatarUrl,
          ),
        );
      },
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return dateTime.toString().split(' ')[0];
    }
  }
}

class _ChatListSyncOverlay extends StatelessWidget {
  const _ChatListSyncOverlay({
    required this.progressPercent,
    required this.status,
  });

  final int progressPercent;
  final String status;

  @override
  Widget build(BuildContext context) {
    final progressValue = (progressPercent / 100).clamp(0, 1).toDouble();
    return AbsorbPointer(
      child: ColoredBox(
        color: PlayerUiSignalTheme.mobileBackgroundColor.withAlpha(232),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              IgnorePointer(
                child: Opacity(
                  opacity: 0.98,
                  child: const PlayerUiSearchBar(title: 'users and chats'),
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withAlpha(22)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Syncing chats',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            '$progressPercent%',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: PlayerUiSignalTheme.primaryDarkColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progressValue,
                          minHeight: 8,
                          backgroundColor: Colors.white.withAlpha(18),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            PlayerUiSignalTheme.primaryDarkColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: math.max(6, (progressPercent / 18).ceil()),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, index) => _ShimmerFrame(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(24),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 130 + (index % 3) * 28,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(24),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(16),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: 150 + (index % 2) * 56,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerFrame extends StatefulWidget {
  const _ShimmerFrame({required this.child});

  final Widget child;

  @override
  State<_ShimmerFrame> createState() => _ShimmerFrameState();
}

class _ShimmerFrameState extends State<_ShimmerFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final sweep = Tween<double>(
          begin: -1.4,
          end: 2.0,
        ).evaluate(_controller);
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1 + sweep, -0.3),
              end: Alignment(sweep, 0.3),
              colors: [
                Colors.white.withAlpha(0),
                Colors.white.withAlpha(24),
                Colors.white.withAlpha(72),
                Colors.white.withAlpha(24),
                Colors.white.withAlpha(0),
              ],
              stops: const [0, 0.35, 0.5, 0.65, 1],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }
}

class _AvatarThumb extends StatefulWidget {
  const _AvatarThumb({
    required this.imageUrl,
    required this.initials,
    required this.size,
    required this.backgroundColor,
    this.useGroupPlaceholder = false,
    this.showPresence = false,
    this.isOnline = false,
  });

  final String? imageUrl;
  final String initials;
  final double size;
  final Color backgroundColor;
  final bool useGroupPlaceholder;
  final bool showPresence;
  final bool isOnline;

  @override
  State<_AvatarThumb> createState() => _AvatarThumbState();
}

class _AvatarThumbState extends State<_AvatarThumb> {
  static const Color _groupAvatarBackgroundColor = Color(0xFFE7EAED);
  static const Color _groupAvatarForegroundColor = Color(0xFFADB4BA);

  String? _activeUrl;
  bool _attemptedDownloadFallback = false;

  Widget _defaultAvatarImage() {
    if (widget.useGroupPlaceholder) {
      return CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: _groupAvatarBackgroundColor,
        child: Icon(
          Icons.groups_rounded,
          size: widget.size * 0.54,
          color: _groupAvatarForegroundColor,
        ),
      );
    }
    return ClipOval(
      child: Image.asset(
        'assets/images/blank_profile_pic.png',
        package: 'clubcommon',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.imageUrl;
  }

  @override
  void didUpdateWidget(covariant _AvatarThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _activeUrl = widget.imageUrl;
      _attemptedDownloadFallback = false;
    }
  }

  String? _downloadFallbackUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    if (!url.contains('/_matrix/media/v3/thumbnail/')) {
      return null;
    }

    var fallback = url.replaceFirst(
      '/_matrix/media/v3/thumbnail/',
      '/_matrix/media/v3/download/',
    );
    final queryIndex = fallback.indexOf('?');
    if (queryIndex >= 0) {
      fallback = fallback.substring(0, queryIndex);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final url = _activeUrl;
    final presenceDot = widget.showPresence
        ? Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: widget.size * 0.28,
              height: widget.size * 0.28,
              decoration: BoxDecoration(
                color: widget.isOnline ? const Color(0xFF44CC77) : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: PlayerUiSignalTheme.mobileBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          )
        : null;

    Widget avatarCore;
    if (url != null && url.isNotEmpty) {
      avatarCore = CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: widget.backgroundColor,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            memCacheWidth: (widget.size * 3).round(),
            memCacheHeight: (widget.size * 3).round(),
            maxWidthDiskCache: (widget.size * 4).round(),
            maxHeightDiskCache: (widget.size * 4).round(),
            filterQuality: FilterQuality.low,
            placeholder: (context, _) => _defaultAvatarImage(),
            errorWidget: (context, error, stackTrace) {
              if (!_attemptedDownloadFallback) {
                final fallback = _downloadFallbackUrl(url);
                if (fallback != null && fallback.isNotEmpty) {
                  _attemptedDownloadFallback = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _activeUrl = fallback;
                    });
                  });
                  return _defaultAvatarImage();
                }
              }
              return _defaultAvatarImage();
            },
          ),
        ),
      );
    } else {
      avatarCore = CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: widget.backgroundColor,
        child: Text(
          widget.initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: math.max(14, widget.size * 0.4),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatarCore,
        ...?presenceDot == null ? null : <Widget>[presenceDot],
      ],
    );
  }
}
