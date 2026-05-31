import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:provider/provider.dart';

import 'playerchat_router.dart';

@pragma('vm:entry-point')
Future<void> playerChatFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  await PushNotificationService.handleBackgroundRemoteMessage(message);
}

class PlayerChatApp extends StatelessWidget {
  const PlayerChatApp({
    super.key,
    required this.config,
    this.firebaseOptions,
    this.title = 'Player Chat',
    this.envFile,
    this.loadEnvironment = true,
  });

  final PlayerChatConfig config;
  final FirebaseOptions? firebaseOptions;
  final String title;
  final String? envFile;
  final bool loadEnvironment;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ensureFirebaseInitialized(),
      builder: (context, snapshot) {
        final router = createPlayerChatRouter();
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            theme: PlayerUiSignalTheme.darkTheme(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            theme: PlayerUiSignalTheme.darkTheme(),
            home: Scaffold(
              body: Center(
                child: Text('Initialization error: ${snapshot.error}'),
              ),
            ),
          );
        }

        return MultiProvider(
          providers: [
            Provider<PlayerChatConfig>.value(value: config),
            ChangeNotifierProvider<ErrorNotifier>.value(value: ErrorNotifier()),
            ProxyProvider<ErrorNotifier, AuthService>(
              update: (_, errorNotifier, previous) {
                final service =
                    previous ?? AuthService(errorNotifier: errorNotifier);
                service.errorNotifier = errorNotifier;
                return service;
              },
            ),
            Provider<ConnectivityService>(
              create: (_) => ConnectivityService(_matrixHomeserver),
            ),
            Provider<MatrixRestService>(
              create: (_) => MatrixRestService(
                homeserver: _matrixHomeserver,
                clientName: config.matrixClientName,
                databaseName: config.matrixDatabaseName,
                databaseBuilder: config.matrixDatabaseBuilder,
                transportFactory: config.matrixTransportFactory,
              ),
              dispose: (_, service) => service.dispose(),
            ),
            ProxyProvider2<AuthService, PlayerChatConfig, UserProfileService>(
              update: (ctx, authService, config, prev) {
                return UserProfileService(
                  config: config,
                  authService: authService,
                );
              },
            ),
            ChangeNotifierProvider<ChatController>(
              create: (ctx) => ChatController(
                authService: ctx.read<AuthService>(),
                matrixService: ctx.read<MatrixRestService>(),
                connectivityService: ctx.read<ConnectivityService>(),
                errorNotifier: ctx.read<ErrorNotifier>(),
                userProfileService: ctx.read<UserProfileService>(),
              ),
            ),
            Provider<PushNotificationService>(
              create: (ctx) => PushNotificationService(
                matrixService: ctx.read<MatrixRestService>(),
                gatewayHost: _pushGatewayHost,
                gatewayUseHttps: _pushGatewayUseHttps,
                appId: _pushAppId,
                appDisplayName: config.pushAppDisplayName,
                deviceDisplayName: config.matrixClientName,
                legacyAppIds: _legacyPushAppIds,
              ),
              dispose: (_, service) => service.dispose(),
            ),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: title,
            theme: PlayerUiSignalTheme.darkTheme(),
            routerConfig: router,
            builder: (context, child) {
              return _GlobalMatrixBootstrapLayer(
                child: _GlobalIncomingCallLayer(
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String get _matrixHomeserver => ClubEnvironment.matrixHost(
    read: dotenv.maybeGet,
    fallback: config.matrixHomeserver,
  );

  String get _pushGatewayHost {
    final envValue = dotenv.maybeGet('PUSH_NOTIFICATIONS_GATEWAY')?.trim();
    if (envValue != null && envValue.isNotEmpty) {
      return envValue;
    }
    return config.pushGateway;
  }

  bool get _pushGatewayUseHttps {
    final envValue = dotenv.maybeGet('PUSH_NOTIFICATIONS_GATEWAY_USE_HTTPS');
    if (envValue == null || envValue.trim().isEmpty) {
      return config.pushGatewayUseHttps;
    }
    final normalized = envValue.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  String get _pushAppId {
    final explicitPushAppId = dotenv.maybeGet('PUSH_APP_ID')?.trim();
    if (explicitPushAppId != null && explicitPushAppId.isNotEmpty) {
      return explicitPushAppId;
    }

    final baseAppId = dotenv.maybeGet('APP_ID')?.trim();
    if (baseAppId != null && baseAppId.isNotEmpty) {
      return '$baseAppId.data_message';
    }

    return config.pushAppId;
  }

  List<String> get _legacyPushAppIds {
    final legacy = <String>{};

    final explicitLegacy = dotenv.maybeGet('LEGACY_PUSH_APP_IDS')?.trim();
    if (explicitLegacy != null && explicitLegacy.isNotEmpty) {
      legacy.addAll(
        explicitLegacy
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }

    final baseAppId = dotenv.maybeGet('APP_ID')?.trim();
    if (baseAppId != null && baseAppId.isNotEmpty) {
      legacy.add('$baseAppId.data_message');
      if (baseAppId.contains('.messenger.')) {
        legacy.add(
          '${baseAppId.replaceFirst('.messenger.', '.')}.data_message',
        );
      }
    }

    if (_pushAppId.contains('.messenger.')) {
      legacy.add(_pushAppId.replaceFirst('.messenger.', '.'));
    }

    legacy.remove(_pushAppId);
    return legacy.toList(growable: false);
  }

  Future<void> _ensureFirebaseInitialized() async {
    if (loadEnvironment && !dotenv.isInitialized) {
      final selectedEnv =
          envFile ??
          const String.fromEnvironment('ENV_FILE', defaultValue: '.dev.env');
      try {
        await dotenv.load(fileName: selectedEnv);
      } catch (_) {
        // Keep startup resilient for host apps that load dotenv before calling PlayerChatApp.
      }
    }

    if (Firebase.apps.isNotEmpty) {
      FirebaseMessaging.onBackgroundMessage(
        playerChatFirebaseMessagingBackgroundHandler,
      );
      return;
    }

    if (firebaseOptions != null) {
      await Firebase.initializeApp(options: firebaseOptions!);
      FirebaseMessaging.onBackgroundMessage(
        playerChatFirebaseMessagingBackgroundHandler,
      );
      return;
    }

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
      playerChatFirebaseMessagingBackgroundHandler,
    );
  }
}

class _GlobalMatrixBootstrapLayer extends StatefulWidget {
  const _GlobalMatrixBootstrapLayer({required this.child});

  final Widget child;

  @override
  State<_GlobalMatrixBootstrapLayer> createState() =>
      _GlobalMatrixBootstrapLayerState();
}

class _GlobalMatrixBootstrapLayerState
    extends State<_GlobalMatrixBootstrapLayer> {
  ChatController? _controller;
  PushNotificationService? _pushNotifications;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pushNotifications ??= context.read<PushNotificationService>();
    final nextController = context.read<ChatController>();
    if (!identical(_controller, nextController)) {
      _controller?.removeListener(_ensureMatrixSync);
      _controller = nextController;
      _controller?.addListener(_ensureMatrixSync);
      _pushNotifications?.bindMessageSyncHandler(_handleIncomingPushMessage);
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureMatrixSync());
    }
  }

  @override
  void dispose() {
    _pushNotifications?.bindMessageSyncHandler(null);
    _controller?.removeListener(_ensureMatrixSync);
    super.dispose();
  }

  Future<void> _handleIncomingPushMessage(RemoteMessage message) async {
    final controller = _controller;
    if (!mounted || controller == null || !controller.hasFirebaseSession) {
      return;
    }

    final roomId = (message.data['room_id'] ?? '').toString().trim();
    final eventId = (message.data['event_id'] ?? '').toString().trim();
    debugPrint(
      '[FCM][sync-request] roomId=$roomId eventId=$eventId activeRoom=${controller.activeRoomId ?? ''}',
    );
    await controller.refreshFromPush(roomId: roomId);
  }

  void _ensureMatrixSync() {
    final controller = _controller;
    if (!mounted || controller == null) {
      return;
    }
    unawaited(_pushNotifications?.syncForCurrentSession() ?? Future.value());
    if (!controller.hasFirebaseSession) {
      return;
    }
    if (controller.matrixUserId.isNotEmpty || controller.matrixConnecting) {
      return;
    }
    unawaited(controller.connectMatrixUsingProfileInBackground());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _GlobalIncomingCallLayer extends StatefulWidget {
  const _GlobalIncomingCallLayer({required this.child});

  final Widget child;

  @override
  State<_GlobalIncomingCallLayer> createState() =>
      _GlobalIncomingCallLayerState();
}

class _GlobalIncomingCallLayerState extends State<_GlobalIncomingCallLayer> {
  ChatController? _controller;
  StreamSubscription<ChatCallSnapshot>? _callSub;
  ChatCallSnapshot? _incomingCall;
  bool _callScreenOpen = false;
  bool _incomingScreenOpen = false;
  Timer? _incomingFeedbackTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      _controller = context.read<ChatController>();
      _controller!.addListener(_onControllerChanged);
      _callSub = _controller!.callUpdates.listen(_onCallSnapshot);
    }
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _incomingFeedbackTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncIncomingFeedback();
    setState(() {});
  }

  void _onCallSnapshot(ChatCallSnapshot snapshot) {
    if (!mounted) return;

    final isIncomingRinging =
        snapshot.isIncoming && snapshot.phase == ChatCallPhase.ringing;
    final shouldClear =
        snapshot.phase == ChatCallPhase.ended ||
        snapshot.phase == ChatCallPhase.error ||
        snapshot.phase == ChatCallPhase.idle;

    if (isIncomingRinging) {
      setState(() {
        _incomingCall = snapshot;
      });
      _syncIncomingFeedback();
      final settings = _controller!.incomingCallUxSettings;
      if (settings.autoOpenFullScreen &&
          !_incomingScreenOpen &&
          !_callScreenOpen) {
        unawaited(_openIncomingRoute(snapshot));
      }
      return;
    }

    if (shouldClear) {
      setState(() {
        _incomingCall = null;
        _incomingScreenOpen = false;
        _callScreenOpen = false;
      });
      _syncIncomingFeedback();
    }
  }

  void _syncIncomingFeedback() {
    final hasIncoming = _incomingCall != null;
    final settings = _controller!.incomingCallUxSettings;
    final shouldRunFeedback =
        hasIncoming && (settings.ringtoneEnabled || settings.vibrationEnabled);

    if (!shouldRunFeedback) {
      _incomingFeedbackTimer?.cancel();
      _incomingFeedbackTimer = null;
      return;
    }

    _incomingFeedbackTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      final liveIncoming = _incomingCall;
      if (liveIncoming == null) return;
      final liveSettings = _controller?.incomingCallUxSettings;
      if (liveSettings == null) return;
      if (liveSettings.ringtoneEnabled) {
        SystemSound.play(SystemSoundType.alert);
      }
      if (liveSettings.vibrationEnabled) {
        HapticFeedback.vibrate();
      }
    });
  }

  Future<void> _openIncomingRoute(ChatCallSnapshot snapshot) async {
    if (!mounted || _incomingScreenOpen || _callScreenOpen) return;
    final nav = Navigator.of(context, rootNavigator: true);
    setState(() {
      _incomingScreenOpen = true;
    });

    await nav.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _GlobalIncomingCallScreen(
          initialSnapshot: snapshot,
          onAnswer: _answerIncoming,
          onReject: _rejectIncoming,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _incomingScreenOpen = false;
    });
  }

  Future<void> _answerIncoming() async {
    final call = _incomingCall;
    if (call == null || _callScreenOpen) return;
    try {
      await _controller!.answerCall();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not answer call: $e')));
      return;
    }
    if (!mounted) return;

    final nav = Navigator.of(context, rootNavigator: true);
    if (_incomingScreenOpen && nav.canPop()) {
      nav.pop();
    }
    setState(() {
      _incomingCall = null;
      _incomingScreenOpen = false;
      _callScreenOpen = true;
    });
    _syncIncomingFeedback();

    await nav.push<void>(
      MaterialPageRoute(
        builder: (_) => _GlobalCallSessionScreen(
          title: (call.remoteDisplayName ?? '').trim().isEmpty
              ? 'Incoming call'
              : call.remoteDisplayName!,
          avatarUrl: call.remoteAvatarUrl,
          isVideo: call.isVideo,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _callScreenOpen = false;
    });
  }

  Future<void> _rejectIncoming() async {
    final wasIncomingScreenOpen = _incomingScreenOpen;
    await _controller!.rejectCall();
    if (!mounted) return;
    setState(() {
      _incomingCall = null;
      _incomingScreenOpen = false;
    });
    _syncIncomingFeedback();
    final nav = Navigator.of(context, rootNavigator: true);
    if (wasIncomingScreenOpen && nav.canPop()) {
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _incomingCall;
    final settings = _controller?.incomingCallUxSettings;
    return Stack(
      children: [
        widget.child,
        if (incoming != null && !_callScreenOpen)
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    final shouldOpen = settings?.autoOpenFullScreen ?? true;
                    if (shouldOpen) {
                      unawaited(_openIncomingRoute(incoming));
                    }
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF12233A).withAlpha(244),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.white12,
                            backgroundImage:
                                (incoming.remoteAvatarUrl ?? '').trim().isEmpty
                                ? null
                                : NetworkImage(incoming.remoteAvatarUrl!),
                            child:
                                (incoming.remoteAvatarUrl ?? '').trim().isEmpty
                                ? Icon(
                                    incoming.isVideo
                                        ? Icons.videocam
                                        : Icons.call,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  incoming.isVideo
                                      ? 'Incoming video call'
                                      : 'Incoming voice call',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  (incoming.remoteDisplayName ?? '')
                                          .trim()
                                          .isEmpty
                                      ? ((incoming.remoteUserId ?? '')
                                                .trim()
                                                .isEmpty
                                            ? 'Unknown caller'
                                            : incoming.remoteUserId!)
                                      : incoming.remoteDisplayName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Reject',
                            onPressed: _rejectIncoming,
                            icon: const Icon(
                              Icons.call_end,
                              color: Colors.redAccent,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Answer',
                            onPressed: _answerIncoming,
                            icon: const Icon(
                              Icons.call,
                              color: Colors.lightGreenAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GlobalCallSessionScreen extends StatefulWidget {
  const _GlobalCallSessionScreen({
    required this.title,
    required this.isVideo,
    this.avatarUrl,
  });

  final String title;
  final bool isVideo;
  final String? avatarUrl;

  @override
  State<_GlobalCallSessionScreen> createState() =>
      _GlobalCallSessionScreenState();
}

class _GlobalCallSessionScreenState extends State<_GlobalCallSessionScreen> {
  ChatController? _controller;
  StreamSubscription<ChatCallSnapshot>? _callSub;
  StreamSubscription<void>? _callMediaSub;
  ChatCallSnapshot _snapshot = const ChatCallSnapshot.idle();
  DateTime? _connectedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= context.read<ChatController>();
    _snapshot = _controller!.callSnapshot;
    _callSub ??= _controller!.callUpdates.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        if (snapshot.phase == ChatCallPhase.connected && _connectedAt == null) {
          _connectedAt = DateTime.now();
        }
      });
      if (snapshot.phase == ChatCallPhase.ended ||
          snapshot.phase == ChatCallPhase.error ||
          snapshot.phase == ChatCallPhase.idle) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });
    _callMediaSub ??= _controller!.callMediaUpdates.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _callMediaSub?.cancel();
    _ticker?.cancel();
    if (_snapshot.hasLiveCall) {
      unawaited(_controller?.hangupCall());
    }
    super.dispose();
  }

  String get _elapsed {
    final connectedAt = _connectedAt;
    if (connectedAt == null) return '00:00';
    final seconds = DateTime.now().difference(connectedAt).inSeconds;
    final minutesPart = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (seconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  String get _stateLabel {
    switch (_snapshot.phase) {
      case ChatCallPhase.idle:
        return 'Starting call...';
      case ChatCallPhase.ringing:
        return 'Ringing...';
      case ChatCallPhase.connecting:
        return 'Connecting...';
      case ChatCallPhase.connected:
        return 'Connected';
      case ChatCallPhase.ending:
        return 'Ending call...';
      case ChatCallPhase.ended:
        return 'Call ended';
      case ChatCallPhase.error:
        return _snapshot.error ?? 'Call failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final micMuted = _snapshot.microphoneMuted;
    final speakerOn = _snapshot.speakerOn;
    final videoMuted = _snapshot.videoMuted;
    final localRenderer = _controller?.localCallVideoRenderer;
    final remoteRenderer = _controller?.remoteCallVideoRenderer;

    Widget buildVideoArea() {
      final hasRemote = remoteRenderer?.srcObject != null;
      final hasLocal = localRenderer?.srcObject != null;
      return Stack(
        children: [
          Positioned.fill(
            child: hasRemote
                ? RTCVideoView(
                    remoteRenderer!,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(
                    color: const Color(0xFF0E2036),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person,
                          size: 54,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _snapshot.remoteDisplayName ?? widget.title,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            width: 120,
            height: 170,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: Colors.black87,
                child: hasLocal
                    ? RTCVideoView(
                        localRenderer!,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : const Center(
                        child: Icon(Icons.videocam_off, color: Colors.white70),
                      ),
              ),
            ),
          ),
          if (videoMuted)
            const Positioned(
              left: 16,
              top: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Camera off', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B1524),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1524),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.isVideo ? 'Video call' : 'Voice call',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.isVideo
                ? buildVideoArea()
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: Colors.white12,
                          backgroundImage:
                              (widget.avatarUrl ?? '').trim().isEmpty
                              ? null
                              : NetworkImage(widget.avatarUrl!),
                          child: (widget.avatarUrl ?? '').trim().isEmpty
                              ? const Icon(
                                  Icons.call,
                                  size: 42,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _snapshot.phase == ChatCallPhase.connected
                              ? _elapsed
                              : _stateLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (widget.isVideo)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _snapshot.phase == ChatCallPhase.connected
                    ? _elapsed
                    : _stateLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: micMuted
                        ? Colors.redAccent
                        : Colors.white12,
                    child: IconButton(
                      onPressed: () {
                        unawaited(
                          _controller!.setCallMicrophoneMuted(!micMuted),
                        );
                      },
                      icon: Icon(
                        micMuted ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.redAccent,
                    child: IconButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        await _controller!.hangupCall();
                        if (mounted && nav.canPop()) {
                          nav.pop();
                        }
                      },
                      icon: const Icon(Icons.call_end, color: Colors.white),
                    ),
                  ),
                  CircleAvatar(
                    radius: 27,
                    backgroundColor:
                        (widget.isVideo && videoMuted) ||
                            (!widget.isVideo && speakerOn)
                        ? const Color(0xFF1F3E73)
                        : Colors.white12,
                    child: IconButton(
                      onPressed: () {
                        if (widget.isVideo) {
                          unawaited(
                            _controller!.setCallVideoMuted(!videoMuted),
                          );
                        } else {
                          unawaited(_controller!.setCallSpeakerOn(!speakerOn));
                        }
                      },
                      icon: Icon(
                        widget.isVideo
                            ? (videoMuted ? Icons.videocam_off : Icons.videocam)
                            : (speakerOn ? Icons.volume_up : Icons.volume_mute),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalIncomingCallScreen extends StatefulWidget {
  const _GlobalIncomingCallScreen({
    required this.initialSnapshot,
    required this.onAnswer,
    required this.onReject,
  });

  final ChatCallSnapshot initialSnapshot;
  final Future<void> Function() onAnswer;
  final Future<void> Function() onReject;

  @override
  State<_GlobalIncomingCallScreen> createState() =>
      _GlobalIncomingCallScreenState();
}

class _GlobalIncomingCallScreenState extends State<_GlobalIncomingCallScreen>
    with SingleTickerProviderStateMixin {
  ChatController? _controller;
  StreamSubscription<ChatCallSnapshot>? _callSub;
  late final AnimationController _pulseController;
  late ChatCallSnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= context.read<ChatController>();
    _callSub ??= _controller!.callUpdates.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
      });
      if (snapshot.phase == ChatCallPhase.ended ||
          snapshot.phase == ChatCallPhase.error ||
          snapshot.phase == ChatCallPhase.idle) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String get _callerLabel {
    final display = (_snapshot.remoteDisplayName ?? '').trim();
    if (display.isNotEmpty) return display;
    final id = (_snapshot.remoteUserId ?? '').trim();
    if (id.isNotEmpty) return id;
    return 'Unknown caller';
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = (_snapshot.remoteAvatarUrl ?? '').trim();
    return Scaffold(
      backgroundColor: const Color(0xFF08111D),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              _snapshot.isVideo ? 'Incoming video call' : 'Incoming voice call',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.95, end: 1.05).animate(
                        CurvedAnimation(
                          parent: _pulseController,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 62,
                          backgroundColor: Colors.white12,
                          backgroundImage: avatarUrl.isEmpty
                              ? null
                              : NetworkImage(avatarUrl),
                          child: avatarUrl.isEmpty
                              ? Icon(
                                  _snapshot.isVideo
                                      ? Icons.videocam
                                      : Icons.person,
                                  size: 52,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _callerLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ringing...',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CircleAvatar(
                    radius: 33,
                    backgroundColor: Colors.redAccent,
                    child: IconButton(
                      tooltip: 'Reject',
                      icon: const Icon(Icons.call_end, color: Colors.white),
                      onPressed: widget.onReject,
                    ),
                  ),
                  CircleAvatar(
                    radius: 33,
                    backgroundColor: Colors.lightGreen,
                    child: IconButton(
                      tooltip: 'Answer',
                      icon: const Icon(Icons.call, color: Colors.white),
                      onPressed: widget.onAnswer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
