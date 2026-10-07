import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'chat_details_screen.dart';

part 'chat_widgets/chat_bubble_widgets.dart';
part 'chat_widgets/chat_avatar_thumb.dart';
part 'chat_widgets/chat_image_widgets.dart';
part 'chat_widgets/chat_attachment_sheets.dart';
part 'chat_widgets/chat_structured_cards.dart';

enum _ChatMenuAction { details, customize, mute }

enum _AttachmentAction { pictures, documents, location, contact, poll }

enum _DeleteMessageAction { forMe, forEveryone }

enum _PictureSourceAction { gallery, cloud }

enum _CameraCaptureAction { photo, video }

enum _StructuredMessageType { location, contact, poll }

class _StructuredMessageData {
  const _StructuredMessageData({
    required this.type,
    required this.title,
    this.details,
    this.link,
    this.imageUrl,
    this.fields = const <MapEntry<String, String>>[],
    this.options = const <String>[],
    this.allowsMultiple = false,
  });

  final _StructuredMessageType type;
  final String title;
  final String? details;
  final String? link;
  final String? imageUrl;
  final List<MapEntry<String, String>> fields;
  final List<String> options;
  final bool allowsMultiple;
}

class _LinkPreviewData {
  const _LinkPreviewData({
    required this.url,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.siteName,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
}

class _ChatAppearance {
  const _ChatAppearance({
    required this.myBubbleColor,
    required this.otherBubbleColor,
    required this.messageTextColor,
    required this.messageFontFamily,
    this.backgroundImageUrl,
  });

  final Color myBubbleColor;
  final Color otherBubbleColor;
  final Color messageTextColor;
  final String messageFontFamily;
  final String? backgroundImageUrl;

  static const _ChatAppearance defaults = _ChatAppearance(
    myBubbleColor: Color(0xFF2B6DE9),
    otherBubbleColor: Color(0xFF1B2737),
    messageTextColor: Colors.white,
    messageFontFamily: 'Poppins',
  );

  _ChatAppearance copyWith({
    Color? myBubbleColor,
    Color? otherBubbleColor,
    Color? messageTextColor,
    String? messageFontFamily,
    String? backgroundImageUrl,
    bool clearBackground = false,
  }) {
    return _ChatAppearance(
      myBubbleColor: myBubbleColor ?? this.myBubbleColor,
      otherBubbleColor: otherBubbleColor ?? this.otherBubbleColor,
      messageTextColor: messageTextColor ?? this.messageTextColor,
      messageFontFamily: messageFontFamily ?? this.messageFontFamily,
      backgroundImageUrl: clearBackground
          ? null
          : (backgroundImageUrl ?? this.backgroundImageUrl),
    );
  }
}

class _ChatAppearanceStore {
  static final ChatAppearanceStore _store = ChatAppearanceStore();
  static final Map<String, _ChatAppearance> _appearanceByChat =
      <String, _ChatAppearance>{};

  static _ChatAppearance forChat(String key) {
    return _appearanceByChat[key] ?? _ChatAppearance.defaults;
  }

  static Future<void> warmCache() async {
    await _store.warmCache();
  }

  static Future<_ChatAppearance> loadForChat(String key) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return _ChatAppearance.defaults;
    }
    final cached = _appearanceByChat[normalizedKey];
    if (cached != null) {
      return cached;
    }

    final record = await _store.load(normalizedKey);
    if (record == null) {
      return _ChatAppearance.defaults;
    }

    final appearance = _ChatAppearance(
      myBubbleColor: Color(record.myBubbleColorValue),
      otherBubbleColor: Color(record.otherBubbleColorValue),
      messageTextColor: Color(record.messageTextColorValue),
      messageFontFamily: record.messageFontFamily,
      backgroundImageUrl: record.backgroundImageUrl,
    );
    _appearanceByChat[normalizedKey] = appearance;
    return appearance;
  }

  static Future<void> saveForChat(
    String key,
    _ChatAppearance appearance,
  ) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return;
    }
    _appearanceByChat[normalizedKey] = appearance;
    await _store.save(
      ChatAppearanceRecord(
        chatKey: normalizedKey,
        myBubbleColorValue: appearance.myBubbleColor.toARGB32(),
        otherBubbleColorValue: appearance.otherBubbleColor.toARGB32(),
        messageTextColorValue: appearance.messageTextColor.toARGB32(),
        messageFontFamily: appearance.messageFontFamily,
        backgroundImageUrl: appearance.backgroundImageUrl,
      ),
    );
  }

  static void cacheForChat(String key, _ChatAppearance appearance) {
    _appearanceByChat[key] = appearance;
  }
}

class _MutedChatStore {
  static final Set<String> _mutedChatKeys = <String>{};

  static bool isMuted(String key) => _mutedChatKeys.contains(key);

  static bool toggle(String key) {
    if (_mutedChatKeys.remove(key)) {
      return false;
    }
    _mutedChatKeys.add(key);
    return true;
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.title, this.avatarUrl});

  final String title;
  final String? avatarUrl;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static final RegExp _linkPreviewUrlRegExp = RegExp(
    r'(https?:\/\/[^\s<>()]+)',
    caseSensitive: false,
  );

  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  final ScrollController _messagesScrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  // Path of the temp file currently backing _audioPlayer's source, when playing a decrypted
  // (encrypted-attachment) voice message — just_audio needs an actual file/URL, not in-memory
  // bytes, so a decrypted voice message is written to a temp file just_audio can point at.
  // Deleted as soon as a different source is loaded or the screen disposes, so decrypted audio
  // never lingers on disk longer than it's actually playing.
  String? _decryptedAudioTempPath;

  Timer? _typingStopTimer;
  Timer? _presenceRefreshTimer;
  StreamSubscription<PlayerState>? _audioPlayerStateSub;
  StreamSubscription<Duration>? _audioPositionSub;
  StreamSubscription<Duration?>? _audioDurationSub;
  bool _typingActive = false;
  bool _showEmojiPickerPanel = false;
  bool _showScrollToLatestFab = false;
  String? _lastSeenLatestMessageId;
  bool _audioLoading = false;
  String? _playingAudioMessageId;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  final Set<String> _selectedMessageIds = <String>{};
  ChatMessage? _editTargetMessage;
  final Map<String, String> _localMessageReactions = <String, String>{};
  final Set<String> _expandedEventClusterKeys = <String>{};
  final Map<String, _LinkPreviewData> _linkPreviewByUrl =
      <String, _LinkPreviewData>{};
  final Set<String> _linkPreviewRequestsInFlight = <String>{};
  final Set<String> _linkPreviewUnavailableUrls = <String>{};
  final Set<String> _presenceRequestsInFlight = <String>{};
  ChatController? _controllerRef;
  String? _onScreenRoomId;
  ErrorNotifier? _errorNotifierRef;
  late _ChatAppearance _appearance;
  String? _appearancePreferenceKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ChatController>();
    _controllerRef ??= controller;
    if (_errorNotifierRef == null) {
      _errorNotifierRef = context.read<ErrorNotifier>();
      _errorNotifierRef!.addListener(_onErrorNotifierChanged);
    }
    final preferenceKey = _chatPreferenceKey(controller);
    if (_appearancePreferenceKey == preferenceKey) {
      return;
    }

    _appearancePreferenceKey = preferenceKey;
    _appearance = _ChatAppearanceStore.forChat(preferenceKey);
    unawaited(_hydrateChatAppearance(preferenceKey));
  }

  Future<void> _hydrateChatAppearance(String preferenceKey) async {
    try {
      final loaded = await _ChatAppearanceStore.loadForChat(preferenceKey);
      if (!mounted || _appearancePreferenceKey != preferenceKey) {
        return;
      }
      if (_appearance == loaded) {
        return;
      }
      setState(() {
        _appearance = loaded;
      });
    } catch (e, s) {
      debugPrint('Failed to load chat appearance for $preferenceKey: $e\n$s');
    }
  }

  @override
  void initState() {
    super.initState();
    _appearance = _ChatAppearance.defaults;
    unawaited(_warmChatAppearanceCache());
    _presenceRefreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshParticipantPresence(),
    );
    _messagesScrollController.addListener(_handleMessageListScroll);
    _composerFocusNode.addListener(_handleComposerFocusChange);
    _audioPlayerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _audioPosition = Duration.zero;
          _playingAudioMessageId = null;
        });
        unawaited(_audioPlayer.stop());
        return;
      }
      setState(() {});
    });
    _audioPositionSub = _audioPlayer.positionStream.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _audioPosition = position;
      });
    });
    _audioDurationSub = _audioPlayer.durationStream.listen((duration) {
      if (!mounted || duration == null) {
        return;
      }
      setState(() {
        _audioDuration = duration;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = _controllerRef ?? context.read<ChatController>();
      unawaited(_refreshParticipantPresence());
      if (controller.userProfile == null) {
        try {
          await controller.refreshCurrentUserProfile();
        } catch (_) {
          // ErrorNotifier already handles messaging.
        }
      }
    });
  }

  Future<void> _warmChatAppearanceCache() async {
    try {
      await _ChatAppearanceStore.warmCache();
    } catch (e, s) {
      debugPrint('Failed to warm chat appearance cache: $e\n$s');
    }
  }

  String? _extractFirstPreviewUrl(ChatMessage message) {
    if (message.kind != MessageKind.text ||
        message.metadata['isDeleted'] == true) {
      return null;
    }
    if (_parseStructuredMessage(message) != null) {
      return null;
    }
    final match = _linkPreviewUrlRegExp.firstMatch(message.body);
    final rawUrl = match?.group(1)?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }
    return rawUrl.replaceFirst(RegExp(r'[),.;!?]+$'), '');
  }

  void _ensureLinkPreviewsLoaded(Iterable<ChatMessage> messages) {
    final pendingUrls = messages
        .map(_extractFirstPreviewUrl)
        .whereType<String>()
        .where(
          (url) =>
              !_linkPreviewByUrl.containsKey(url) &&
              !_linkPreviewRequestsInFlight.contains(url) &&
              !_linkPreviewUnavailableUrls.contains(url),
        )
        .toSet()
        .toList(growable: false);
    if (pendingUrls.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final url in pendingUrls) {
        if (!mounted ||
            _linkPreviewByUrl.containsKey(url) ||
            _linkPreviewRequestsInFlight.contains(url) ||
            _linkPreviewUnavailableUrls.contains(url)) {
          continue;
        }
        _linkPreviewRequestsInFlight.add(url);
        unawaited(_loadLinkPreview(url));
      }
    });
  }

  Future<void> _loadLinkPreview(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        _linkPreviewUnavailableUrls.add(url);
        return;
      }
      final response = await http.get(
        uri,
        headers: const <String, String>{
          'User-Agent': 'Mozilla/5.0 PlayerChat Link Preview',
          'Accept': 'text/html,application/xhtml+xml',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _linkPreviewUnavailableUrls.add(url);
        return;
      }

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final preview = _parseLinkPreviewDocument(
        response.request?.url ?? uri,
        body,
      );
      if (preview == null || !mounted) {
        _linkPreviewUnavailableUrls.add(url);
        return;
      }

      setState(() {
        _linkPreviewByUrl[url] = preview;
      });
    } catch (_) {
      _linkPreviewUnavailableUrls.add(url);
    } finally {
      _linkPreviewRequestsInFlight.remove(url);
    }
  }

  _LinkPreviewData? _parseLinkPreviewDocument(Uri baseUri, String document) {
    final title = _firstNonEmpty(<String?>[
      _findMetaContent(document, 'property', 'og:title'),
      _findMetaContent(document, 'name', 'twitter:title'),
      _extractTitleTag(document),
    ]);
    final description = _firstNonEmpty(<String?>[
      _findMetaContent(document, 'property', 'og:description'),
      _findMetaContent(document, 'name', 'twitter:description'),
      _findMetaContent(document, 'name', 'description'),
    ]);
    final imageUrl = _resolveLinkPreviewUrl(
      baseUri,
      _firstNonEmpty(<String?>[
        _findMetaContent(document, 'property', 'og:image'),
        _findMetaContent(document, 'property', 'og:image:url'),
        _findMetaContent(document, 'name', 'twitter:image'),
      ]),
    );
    final siteName = _firstNonEmpty(<String?>[
      _findMetaContent(document, 'property', 'og:site_name'),
      _findMetaContent(document, 'name', 'twitter:site'),
      baseUri.host,
    ]);
    if ((title ?? '').isEmpty &&
        (description ?? '').isEmpty &&
        (imageUrl ?? '').isEmpty) {
      return null;
    }

    return _LinkPreviewData(
      url: baseUri.toString(),
      title: title,
      description: description,
      imageUrl: imageUrl,
      siteName: siteName,
    );
  }

  String? _findMetaContent(String document, String attribute, String value) {
    final metaTags = RegExp(r'<meta\b[^>]*>', caseSensitive: false)
        .allMatches(document)
        .map((match) => match.group(0)!)
        .toList(growable: false);
    for (final tag in metaTags) {
      final attributeValue = _extractHtmlAttribute(tag, attribute);
      if (attributeValue?.toLowerCase() != value.toLowerCase()) {
        continue;
      }
      final content = _extractHtmlAttribute(tag, 'content');
      if ((content ?? '').trim().isNotEmpty) {
        return content!.trim();
      }
    }
    return null;
  }

  String? _extractHtmlAttribute(String tag, String name) {
    final match = RegExp(
      '$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    ).firstMatch(tag);
    final value = match?.group(1) ?? match?.group(2) ?? match?.group(3);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return _decodeHtmlEntities(value.trim());
  }

  String? _extractTitleTag(String document) {
    final match = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(document);
    final title = match?.group(1)?.trim();
    if (title == null || title.isEmpty) {
      return null;
    }
    return _decodeHtmlEntities(title);
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  String? _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      if ((candidate ?? '').trim().isNotEmpty) {
        return candidate!.trim();
      }
    }
    return null;
  }

  String? _resolveLinkPreviewUrl(Uri baseUri, String? rawValue) {
    if ((rawValue ?? '').trim().isEmpty) {
      return null;
    }
    final value = rawValue!.trim();
    final resolved = Uri.tryParse(value);
    if (resolved != null && resolved.hasScheme) {
      return resolved.toString();
    }
    return baseUri.resolve(value).toString();
  }

  Future<void> _openExternalLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildLinkPreviewCard({
    required _LinkPreviewData preview,
    required bool mine,
  }) {
    final imageUrl = preview.imageUrl;
    final title = preview.title?.trim();
    final description = preview.description?.trim();
    final siteLabel =
        (preview.siteName ?? Uri.tryParse(preview.url)?.host ?? '')
            .replaceFirst(RegExp(r'^www\.'), '');
    return InkWell(
      onTap: () => unawaited(_openExternalLink(preview.url)),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: mine ? Colors.black.withAlpha(28) : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withAlpha(24)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((imageUrl ?? '').isNotEmpty)
                CachedNetworkImage(
                  imageUrl: imageUrl!,
                  height: 148,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (siteLabel.isNotEmpty)
                      Text(
                        siteLabel.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    if ((title ?? '').isNotEmpty) ...[
                      if (siteLabel.isNotEmpty) const SizedBox(height: 5),
                      Text(
                        title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ],
                    if ((description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkPreviewMessageContent({
    required ChatMessage message,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
    required String previewUrl,
    required _LinkPreviewData? preview,
  }) {
    final trimmedBody = message.body.trim();
    final showBodyText = trimmedBody.isNotEmpty && trimmedBody != previewUrl;
    final showPlaceholder =
        preview == null && _linkPreviewRequestsInFlight.contains(previewUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBodyText)
          Text(
            message.body,
            style: TextStyle(
              fontSize: message.kind == MessageKind.emoji ? 28 : 16,
              fontWeight: FontWeight.w400,
              color: _appearance.messageTextColor,
              fontFamily: _appearance.messageFontFamily,
            ),
          ),
        if (preview != null)
          _buildLinkPreviewCard(preview: preview, mine: mine)
        else if (showPlaceholder)
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(top: showBodyText ? 8 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: mine
                  ? Colors.black.withAlpha(28)
                  : Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Row(
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Loading link preview...',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (showInsideTime || mine)
          Padding(
            padding: EdgeInsets.only(
              top: (preview != null || showPlaceholder) ? 8 : 6,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showInsideTime)
                    Text(
                      _bubbleTimeLabel(context, message.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  if (mine)
                    Padding(
                      padding: EdgeInsets.only(left: showInsideTime ? 4 : 0),
                      child: _SignalReceiptTicks(
                        isSent: _messageHasServerAck(message),
                        showReceivedCircle: _messageShowsReceivedCircle(
                          message,
                        ),
                        isRead: effectiveReadCount > 0,
                        isFailed: _messageIsFailed(message),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _ensurePresenceLoaded(
    ChatController controller,
    Iterable<String> userIds,
  ) {
    final pendingUserIds = userIds
        .where(
          (userId) =>
              userId.isNotEmpty &&
              controller.cachedUserPresence(userId) == null &&
              !_presenceRequestsInFlight.contains(userId),
        )
        .toList(growable: false);
    if (pendingUserIds.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final userId in pendingUserIds) {
        if (!mounted ||
            controller.cachedUserPresence(userId) != null ||
            _presenceRequestsInFlight.contains(userId)) {
          continue;
        }
        _presenceRequestsInFlight.add(userId);
        unawaited(_loadPresence(controller, userId));
      }
    });
  }

  Future<void> _refreshParticipantPresence() async {
    final controller = _controllerRef;
    if (!mounted || controller == null) {
      return;
    }
    final userIds = controller.participants
        .map((participant) => participant.userId)
        .where(
          (userId) => userId.isNotEmpty && userId != controller.matrixUserId,
        )
        .toSet();
    for (final userId in userIds) {
      if (_presenceRequestsInFlight.contains(userId)) {
        continue;
      }
      _presenceRequestsInFlight.add(userId);
      unawaited(_loadPresence(controller, userId, forceRefresh: true));
    }
  }

  Future<void> _loadPresence(
    ChatController controller,
    String userId, {
    bool forceRefresh = false,
  }) async {
    try {
      await controller.getUserPresence(userId, forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Default-offline UI is sufficient if presence lookup fails.
    } finally {
      _presenceRequestsInFlight.remove(userId);
    }
  }

  @override
  void dispose() {
    final onScreenRoomId = _onScreenRoomId;
    if (onScreenRoomId != null)
      _controllerRef?.clearRoomOnScreen(onScreenRoomId);
    _errorNotifierRef?.removeListener(_onErrorNotifierChanged);
    _presenceRefreshTimer?.cancel();
    _typingStopTimer?.cancel();
    _controllerRef?.setTyping(false);
    _audioPlayerStateSub?.cancel();
    _audioPositionSub?.cancel();
    _audioDurationSub?.cancel();
    unawaited(_audioPlayer.dispose());
    _deleteDecryptedAudioTempFile();
    _messagesScrollController.removeListener(_handleMessageListScroll);
    _messagesScrollController.dispose();
    _composerFocusNode.removeListener(_handleComposerFocusChange);
    _composerFocusNode.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _handleMessageListScroll() {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    final shouldShow = _messagesScrollController.offset > 120;
    if (shouldShow != _showScrollToLatestFab && mounted) {
      setState(() {
        _showScrollToLatestFab = shouldShow;
      });
    }
  }

  void _scrollToLatestMessages() {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    _messagesScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToLatestOnNewMessage(String latestId, bool isOwn) {
    final previous = _lastSeenLatestMessageId;
    _lastSeenLatestMessageId = latestId;
    if (previous == null || previous == latestId) {
      return;
    }
    final nearBottom =
        !_messagesScrollController.hasClients ||
        _messagesScrollController.offset <= 200;
    if (!isOwn && !nearBottom) {
      return;
    }
    void snapToLatest() {
      if (!mounted || !_messagesScrollController.hasClients) {
        return;
      }
      _messagesScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => snapToLatest());
    Future<void>.delayed(const Duration(milliseconds: 350), snapToLatest);
  }

  void _handleComposerFocusChange() {
    if (_composerFocusNode.hasFocus && _showEmojiPickerPanel) {
      setState(() {
        _showEmojiPickerPanel = false;
      });
    }
  }

  void _onComposerChanged(ChatController controller, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _stopTyping(controller);
      return;
    }

    if (!_typingActive) {
      _typingActive = true;
      controller.setTyping(true);
    }

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 4), () {
      _stopTyping(controller);
    });
  }

  void _stopTyping(ChatController controller) {
    _typingStopTimer?.cancel();
    if (_typingActive) {
      _typingActive = false;
      controller.setTyping(false);
    }
  }

  String _relativeTime(DateTime time) {
    final localTime = _displayLocalTime(time);
    final diff = DateTime.now().difference(localTime);
    if (diff.inSeconds < 45) {
      return 'Now';
    }
    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
      return '${minutes}m ago';
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours <= 0 ? 1 : diff.inHours;
      return '${hours}hr ago';
    }
    if (diff.inDays < 365) {
      final days = diff.inDays <= 0 ? 1 : diff.inDays;
      return '${days}d ago';
    }
    final years = diff.inDays ~/ 365;
    return '${years}yr ago';
  }

  String _bubbleTimeLabel(BuildContext context, DateTime time) {
    final localTime = _displayLocalTime(time);
    final diff = DateTime.now().difference(localTime);
    if (diff.inSeconds < 45) {
      return 'Now';
    }
    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
      return '${minutes}m ago';
    }

    final localizations = MaterialLocalizations.of(context);
    return localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localTime));
  }

  String _formatClock(
    BuildContext context,
    DateTime time, {
    DateTime? previousTime,
  }) {
    final localTime = _displayLocalTime(time);
    final now = DateTime.now();
    final localizations = MaterialLocalizations.of(context);
    final isToday = _isSameCalendarDate(localTime, now);
    final shouldIncludeDate =
        !isToday &&
        (previousTime == null ||
            !_isSameCalendarDate(localTime, _displayLocalTime(previousTime)));
    if (shouldIncludeDate) {
      final dateLabel = localizations.formatMediumDate(localTime);
      final timeLabel = localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(localTime),
      );
      return '$dateLabel $timeLabel';
    }

    return localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localTime));
  }

  DateTime _displayLocalTime(DateTime time) {
    return DateTime.fromMillisecondsSinceEpoch(
      time.millisecondsSinceEpoch,
      isUtc: true,
    ).toLocal();
  }

  bool _isSameCalendarDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool _shouldShowCenteredTime(DateTime messageTime) {
    final age = DateTime.now().difference(messageTime);
    return age.inHours >= 1;
  }

  bool _isTimelineOnlyMessage(ChatMessage message) {
    return message.metadata['timelineOnly'] == true;
  }

  void _onErrorNotifierChanged() {
    final raw = _errorNotifierRef?.errorMessage?.trim();
    if (raw != null && raw.isNotEmpty) {
      debugPrint('[ChatScreen] Send error: $raw');
    }
    final error = _errorNotifierRef?.visibleErrorMessage?.trim();
    if (error != null && error.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFF4A1616),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  bool _messageHasServerAck(ChatMessage message) {
    final stage = (message.metadata['sendStage'] ?? 'sent').toString();
    return stage != 'local' && stage != 'failed';
  }

  bool _messageIsFailed(ChatMessage message) {
    final stage = (message.metadata['sendStage'] ?? 'sent').toString();
    return stage == 'failed';
  }

  bool _messageShowsReceivedCircle(ChatMessage message) {
    final stage = (message.metadata['sendStage'] ?? '').toString();
    return stage == 'delivered' || stage == 'read';
  }

  String _chatPreferenceKey(ChatController controller) {
    return controller.activeRoomId ?? widget.title;
  }

  bool _startsCenteredTimeCluster(
    ChatMessage message,
    ChatMessage? previousMessage,
  ) {
    if (previousMessage == null) {
      return true;
    }
    if (previousMessage.senderId != message.senderId) {
      return true;
    }
    return false;
  }

  List<_TimelineEventItem> _extractTimelineEvents(List<ChatMessage> messages) {
    final events = <_TimelineEventItem>[];
    for (final message in messages) {
      final timelineEventType = (message.metadata['timelineEventType'] ?? '')
          .toString();
      if (timelineEventType == 'call_started') {
        final isVideoCall = message.metadata['isVideoCall'] == true;
        events.add(
          _TimelineEventItem(
            icon: isVideoCall ? Icons.videocam_outlined : Icons.call_outlined,
            label: message.body,
            time: message.createdAt,
          ),
        );
        continue;
      }
      if (timelineEventType == 'member_profile_updated') {
        events.add(
          _TimelineEventItem(
            icon: Icons.manage_accounts_outlined,
            label: message.body,
            time: message.createdAt,
          ),
        );
        continue;
      }
      if (timelineEventType == 'member_display_name_changed') {
        events.add(
          _TimelineEventItem(
            icon: Icons.badge_outlined,
            label: message.body,
            time: message.createdAt,
          ),
        );
        continue;
      }
      if (timelineEventType == 'member_avatar_changed') {
        events.add(
          _TimelineEventItem(
            icon: Icons.photo_camera_back_outlined,
            label: message.body,
            time: message.createdAt,
          ),
        );
        continue;
      }
      if (timelineEventType == 'member_joined') {
        events.add(
          _TimelineEventItem(
            icon: Icons.person_add_alt_1_outlined,
            label: message.body,
            time: message.createdAt,
          ),
        );
        continue;
      }
      // Edits and shared videos are part of the message itself (edited label / video bubble),
      // not separate timeline events — the web doesn't list them either.
    }
    events.sort((a, b) => a.time.compareTo(b.time));
    return events;
  }

  /// Messages and room events merged into one chronological timeline, like cluborbit-web:
  /// every event sits exactly where it happened between messages. Events that follow each
  /// other with no message in between share one collapsible card; a card never spans a
  /// message (grouping by a time window used to move events past the messages sent meanwhile).
  List<_ChatTimelineEntry> _buildTimelineEntries({
    required List<ChatMessage> visibleMessages,
    required List<_TimelineEventItem> events,
  }) {
    final entries = <_ChatTimelineEntry>[];
    var pendingEvents = <_TimelineEventItem>[];
    void flushEvents() {
      if (pendingEvents.isEmpty) return;
      entries.add(
        _ChatTimelineEntry.eventCluster(
          _TimelineEventCluster(items: pendingEvents),
        ),
      );
      pendingEvents = <_TimelineEventItem>[];
    }

    var eventIndex = 0;
    for (
      var messageIndex = 0;
      messageIndex < visibleMessages.length;
      messageIndex++
    ) {
      final message = visibleMessages[messageIndex];
      while (eventIndex < events.length &&
          !events[eventIndex].time.isAfter(message.createdAt)) {
        pendingEvents.add(events[eventIndex]);
        eventIndex++;
      }
      flushEvents();
      entries.add(_ChatTimelineEntry.message(message, messageIndex));
    }

    while (eventIndex < events.length) {
      pendingEvents.add(events[eventIndex]);
      eventIndex++;
    }
    flushEvents();

    return entries;
  }

  void _toggleEventCluster(_TimelineEventCluster cluster) {
    setState(() {
      if (!_expandedEventClusterKeys.add(cluster.key)) {
        _expandedEventClusterKeys.remove(cluster.key);
      }
    });
  }

  void _showChatSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _appearance.otherBubbleColor,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withAlpha(28)),
          ),
          content: Row(
            children: [
              const Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: Colors.white70,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  String? _mediaUrlFor(ChatMessage message) {
    final value = message.metadata['mediaUrl'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  String? _thumbnailUrlFor(ChatMessage message) {
    final value = message.metadata['thumbnailUrl'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return _mediaUrlFor(message);
  }

  Map<String, dynamic>? _mediaEncryptionFor(ChatMessage message) {
    final value = message.metadata['mediaEncryption'];
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  /// The *thumbnail's own* encryption info (a separate key/iv from the main attachment's — see
  /// MatrixRestService.sendMediaMessage) — null when there's no real encrypted thumbnail, in
  /// which case a caller reusing `_mediaEncryptionFor` for a URL that's actually the full
  /// attachment itself (the `_thumbnailUrlFor` fallback) is still correct.
  Map<String, dynamic>? _thumbnailEncryptionFor(ChatMessage message) {
    final value = message.metadata['thumbnailEncryption'];
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  /// A file extension for a message's audio, from its mimetype (preferred) or its filename —
  /// needed when writing a decrypted voice message to a temp file: just_audio's underlying
  /// platform players (ExoPlayer on Android especially) pick a decoder based on the file
  /// extension, so a generic/missing extension can fail to play even though the bytes are valid.
  String _audioFileExtension(ChatMessage message) {
    final mimeRaw = message.metadata['mimeType'];
    final mime = mimeRaw is String ? mimeRaw.trim().toLowerCase() : '';
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('ogg')) return 'ogg';
    if (mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')) {
      return 'm4a';
    }
    if (mime.contains('mpeg') || mime.contains('mp3')) return 'mp3';
    if (mime.contains('wav')) return 'wav';

    final filenameRaw = message.metadata['filename'];
    final filename = filenameRaw is String
        ? filenameRaw.trim().toLowerCase()
        : '';
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < filename.length - 1) {
      final ext = filename.substring(dotIndex + 1);
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) return ext;
    }
    return 'm4a';
  }

  /// `_mediaUrlFor` bundled with its encryption info (if any) — the shape `_EncryptedImage` and
  /// every other media consumer below needs, since a bare URL alone isn't enough to display an
  /// encrypted attachment.
  // Pictographs plus the joiners/modifiers/flags/keycaps that combine them into one emoji (same
  // rule as MatrixRestService's emoji kind).
  static final RegExp _emojiPattern = RegExp(
    // ignore: valid_regexps
    r'\p{Extended_Pictographic}',
    unicode: true,
  );
  static final RegExp _emojiOnlyPattern = RegExp(
    // ignore: valid_regexps
    r'^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|[\u{1F1E6}-\u{1F1FF}]|[#*0-9]\u{FE0F}?\u{20E3}|\u{200D}|\u{FE0F}|\s)+$',
    unicode: true,
  );

  /// A text message of just 1-3 emoji. Checked from the body rather than trusting `kind` alone,
  /// since a message typed in the composer (and older cached ones) arrive as plain text.
  bool _isEmojiOnlyMessage(ChatMessage message) {
    if (message.kind == MessageKind.emoji) return true;
    if (message.kind != MessageKind.text) return false;
    final body = message.body.trim();
    return body.isNotEmpty &&
        _emojiOnlyPattern.hasMatch(body) &&
        _emojiPattern.allMatches(body).length <= 3;
  }

  _MediaRef? _mediaRefFor(ChatMessage message) {
    return _MediaRef.fromUrl(
      _mediaUrlFor(message),
      _mediaEncryptionFor(message),
    );
  }

  /// Same as `_mediaRefFor`, but preferring the (unencrypted-only) server thumbnail when one
  /// exists, else falling back to the full image — same encryption info either way, since this
  /// app never generates a separate encrypted thumbnail.
  _MediaRef? _thumbnailMediaRefFor(ChatMessage message) {
    // A real thumbnailUrl (video's separately-encrypted preview) needs thumbnailEncryption; when
    // there isn't one, _thumbnailUrlFor falls back to the main attachment's own URL (e.g. an
    // image, which never gets a separate thumbnail), which needs mediaEncryption instead.
    final value = message.metadata['thumbnailUrl'];
    final hasRealThumbnail = value is String && value.trim().isNotEmpty;
    final encryption = hasRealThumbnail
        ? _thumbnailEncryptionFor(message)
        : _mediaEncryptionFor(message);
    return _MediaRef.fromUrl(_thumbnailUrlFor(message), encryption);
  }

  bool _isDocumentAttachment(ChatMessage message) {
    final mediaUrl = _mediaUrlFor(message);
    if (mediaUrl == null) {
      return false;
    }
    if (message.kind == MessageKind.image ||
        message.kind == MessageKind.video) {
      return false;
    }
    final mimeRaw = message.metadata['mimeType'];
    final mime = mimeRaw is String ? mimeRaw.trim().toLowerCase() : '';
    if (mime.startsWith('image/') || mime.startsWith('video/')) {
      return false;
    }
    return true;
  }

  bool _isAudioAttachment(ChatMessage message) {
    final mediaUrl = _mediaUrlFor(message);
    if (mediaUrl == null) {
      return false;
    }
    if (message.kind == MessageKind.image ||
        message.kind == MessageKind.video) {
      return false;
    }

    final mimeRaw = message.metadata['mimeType'];
    final mime = mimeRaw is String ? mimeRaw.trim().toLowerCase() : '';
    if (mime.startsWith('audio/')) {
      return true;
    }

    final filenameRaw = message.metadata['filename'];
    final filename = (filenameRaw is String ? filenameRaw : message.body)
        .trim()
        .toLowerCase();
    return filename.endsWith('.m4a') ||
        filename.endsWith('.mp3') ||
        filename.endsWith('.wav') ||
        filename.endsWith('.aac') ||
        filename.endsWith('.ogg');
  }

  IconData _documentIconForMime(String mime) {
    if (mime.contains('pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description_outlined;
    }
    if (mime.contains('excel') || mime.contains('spreadsheet')) {
      return Icons.table_chart_outlined;
    }
    if (mime.contains('powerpoint') || mime.contains('presentation')) {
      return Icons.slideshow_outlined;
    }
    if (mime.startsWith('text/')) {
      return Icons.article_outlined;
    }
    if (mime.contains('zip') || mime.contains('compressed')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _documentLabel(ChatMessage message) {
    final filenameRaw = message.metadata['filename'];
    final filename = filenameRaw is String ? filenameRaw.trim() : '';
    if (filename.isNotEmpty) {
      return filename;
    }
    final body = message.body.trim();
    if (body.isNotEmpty) {
      return body;
    }
    return 'Document';
  }

  String _formatAudioDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _deleteDecryptedAudioTempFile() {
    final path = _decryptedAudioTempPath;
    _decryptedAudioTempPath = null;
    if (path == null) return;
    unawaited(File(path).delete().catchError((_) => File(path)));
  }

  /// Points `_audioPlayer` at a message's audio — streamed directly from the homeserver for a
  /// legacy unencrypted message, or downloaded+decrypted to a short-lived temp file first for an
  /// encrypted one (just_audio needs an actual file/URL to play from, not in-memory bytes).
  Future<void> _setAudioSourceForMessage(
    ChatMessage message,
    String url,
  ) async {
    final encryption = _mediaEncryptionFor(message);
    if (encryption == null) {
      await _audioPlayer.setUrl(url);
      return;
    }
    final controller = context.read<ChatController>();
    final bytes = await controller.resolveMediaBytes(
      url,
      encryption: encryption,
    );
    final dir = await getTemporaryDirectory();
    final extension = _audioFileExtension(message);
    final path =
        '${dir.path}/co_audio_${DateTime.now().microsecondsSinceEpoch}.$extension';
    await File(path).writeAsBytes(bytes, flush: true);
    _deleteDecryptedAudioTempFile();
    _decryptedAudioTempPath = path;
    await _audioPlayer.setFilePath(path);
  }

  Future<void> _toggleAudioPlayback(ChatMessage message) async {
    final url = _mediaUrlFor(message);
    if (url == null || url.isEmpty) {
      return;
    }

    if (_playingAudioMessageId == message.id) {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (mounted) {
      setState(() {
        _audioLoading = true;
      });
    }

    try {
      await _audioPlayer.stop();
      await _setAudioSourceForMessage(message, url);
      if (!mounted) {
        return;
      }
      setState(() {
        _playingAudioMessageId = message.id;
        _audioPosition = Duration.zero;
        _audioDuration = _audioPlayer.duration ?? Duration.zero;
      });
      await _audioPlayer.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice message.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _audioLoading = false;
        });
      }
    }
  }

  Future<void> _seekAudio(ChatMessage message, double progress) async {
    if (_playingAudioMessageId != message.id ||
        _audioDuration.inMilliseconds <= 0) {
      return;
    }
    final clamped = progress.clamp(0.0, 1.0);
    final targetMs = (_audioDuration.inMilliseconds * clamped).round();
    await _audioPlayer.seek(Duration(milliseconds: targetMs));
  }

  /// The last path segment of `raw`, with anything but safe filename characters replaced — used
  /// to name a decrypted document's temp file. Never trust a message's filename as a path
  /// component directly (it's sender-controlled data): this strips any `/`/`..` it might contain
  /// rather than letting it influence where the temp file actually gets written.
  String _sanitizedTempFilename(String raw) {
    final base = raw.split(RegExp(r'[\\/]')).last.trim();
    final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  Future<void> _openDocumentExternally(ChatMessage message) async {
    final url = _mediaUrlFor(message);
    if (url == null) {
      return;
    }

    final encryption = _mediaEncryptionFor(message);
    Uri? uri;
    if (encryption != null) {
      // Encrypted document: decrypt to a temp file first — an external viewer app can't be handed
      // a URL pointing at ciphertext, and needs an actual local file. Named after the real
      // filename (sanitized) so the OS's file-type association (by extension) still works.
      try {
        final controller = context.read<ChatController>();
        final bytes = await controller.resolveMediaBytes(
          url,
          encryption: encryption,
        );
        final dir = await getTemporaryDirectory();
        final filename = _sanitizedTempFilename(_documentLabel(message));
        final path =
            '${dir.path}/co_doc_${DateTime.now().microsecondsSinceEpoch}_$filename';
        await File(path).writeAsBytes(bytes, flush: true);
        uri = Uri.file(path);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not decrypt the document.')),
          );
        }
        return;
      }
    } else {
      uri = Uri.tryParse(url);
    }
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open document link.')),
        );
      }
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app available to open this file.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the document.')),
        );
      }
    }
  }

  bool _isPlayableVideo(ChatMessage message) {
    if (_mediaUrlFor(message) == null) return false;
    if (message.kind == MessageKind.video) return true;
    final mime = message.metadata['mimeType'];
    return mime is String && mime.trim().toLowerCase().startsWith('video/');
  }

  Widget _buildVideoMessageContent({
    required BuildContext context,
    required ChatMessage message,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
  }) {
    final media = _mediaRefFor(message)!;
    // Only a real server thumbnail can be drawn as an image; the fallback in _thumbnailUrlFor is
    // the video file itself, which can't be decoded as a picture.
    final thumbRaw = message.metadata['thumbnailUrl'];
    final thumb =
        thumbRaw is String &&
            thumbRaw.trim().isNotEmpty &&
            thumbRaw.trim() != media.url
        ? _MediaRef.fromUrl(thumbRaw, _thumbnailEncryptionFor(message))
        : null;
    final caption = (message.metadata['caption'] as String?)?.trim() ?? '';
    void open() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              _VideoPlayerScreen(media: media, title: message.senderName),
        ),
      );
    }

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: open,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 240,
                height: 160,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null)
                      _EncryptedImage(media: thumb, fit: BoxFit.cover)
                    else
                      Container(color: Colors.black87),
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                caption,
                style: TextStyle(
                  color: _appearance.messageTextColor,
                  fontSize: 14,
                  fontFamily: _appearance.messageFontFamily,
                ),
              ),
            ),
          if (showInsideTime || mine)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showInsideTime)
                      Text(
                        _bubbleTimeLabel(context, message.createdAt),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    if (mine)
                      Padding(
                        padding: EdgeInsets.only(left: showInsideTime ? 4 : 0),
                        child: _SignalReceiptTicks(
                          isSent: _messageHasServerAck(message),
                          showReceivedCircle: _messageShowsReceivedCircle(
                            message,
                          ),
                          isRead: effectiveReadCount > 0,
                          isFailed: _messageIsFailed(message),
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

  LatLng? _locationOf(ChatMessage message) {
    final raw = message.metadata['geoUri'];
    if (raw is! String) return null;
    final match = RegExp(
      r'geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
    ).firstMatch(raw);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Widget _buildLocationMessageContent({
    required ChatMessage message,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
  }) {
    final point = _locationOf(message)!;
    final descriptionRaw = message.metadata['locationDescription'];
    final description = descriptionRaw is String ? descriptionRaw.trim() : '';
    final mapsUri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}&zoom=15',
    );
    Future<void> open() async {
      // A geo: URI makes Android open the user's preferred maps app (or its chooser); fall back to
      // the browser when nothing handles it or on other platforms.
      final label = description.isNotEmpty
          ? '(${Uri.encodeComponent(description)})'
          : '';
      final geoUri = Uri.parse(
        'geo:${point.latitude},${point.longitude}?q=${point.latitude},${point.longitude}$label',
      );
      var launched = false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          launched = await launchUrl(
            geoUri,
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {}
      }
      if (!launched) {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      }
    }

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                width: 240,
                height: 140,
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.playerchat',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.redAccent,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on,
                  size: 14,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    description.isNotEmpty ? description : 'Shared location',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 2, 7, 3),
            child: Row(
              children: [
                GestureDetector(
                  onTap: open,
                  child: const Text(
                    'Open in Maps',
                    style: TextStyle(
                      color: Color(0xFF60A5FA),
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Spacer(),
                if (showInsideTime)
                  Text(
                    _bubbleTimeLabel(context, message.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                if (mine)
                  Padding(
                    padding: EdgeInsets.only(left: showInsideTime ? 4 : 0),
                    child: _SignalReceiptTicks(
                      isSent: _messageHasServerAck(message),
                      showReceivedCircle: _messageShowsReceivedCircle(message),
                      isRead: effectiveReadCount > 0,
                      isFailed: _messageIsFailed(message),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentMessageContent({
    required ChatMessage message,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
  }) {
    final mimeRaw = message.metadata['mimeType'];
    final mime = mimeRaw is String ? mimeRaw.trim().toLowerCase() : '';
    final label = _documentLabel(message);
    final subtitle = mime.isEmpty ? 'Document' : mime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openDocumentExternally(message),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(26)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    _documentIconForMime(mime),
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new, color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
        if (showInsideTime || mine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showInsideTime)
                    Text(
                      _bubbleTimeLabel(context, message.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  if (mine)
                    Padding(
                      padding: EdgeInsets.only(left: showInsideTime ? 4 : 0),
                      child: _SignalReceiptTicks(
                        isSent: _messageHasServerAck(message),
                        showReceivedCircle: _messageShowsReceivedCircle(
                          message,
                        ),
                        isRead: effectiveReadCount > 0,
                        isFailed: _messageIsFailed(message),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioMessageContent({
    required ChatMessage message,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
  }) {
    final filenameRaw = message.metadata['filename'];
    final label = filenameRaw is String && filenameRaw.trim().isNotEmpty
        ? filenameRaw.trim()
        : 'Voice message';
    final isCurrent = _playingAudioMessageId == message.id;
    final isPlaying = isCurrent && _audioPlayer.playing;
    final duration = isCurrent ? _audioDuration : Duration.zero;
    final position = isCurrent ? _audioPosition : Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final trailingIcon = _audioLoading && isCurrent
        ? null
        : isPlaying
        ? Icons.pause
        : Icons.play_arrow_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _toggleAudioPlayback(message),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(26)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Voice message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: progress,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatAudioDuration(position)} / ${_formatAudioDuration(duration)}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_audioLoading && isCurrent)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  )
                else
                  Icon(trailingIcon, color: Colors.white70, size: 18),
              ],
            ),
          ),
        ),
        if (isCurrent && duration.inMilliseconds > 0)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white70,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: progress,
              onChanged: (value) {
                unawaited(_seekAudio(message, value));
              },
            ),
          ),
        if (showInsideTime || mine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showInsideTime)
                    Text(
                      _bubbleTimeLabel(context, message.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  if (mine)
                    Padding(
                      padding: EdgeInsets.only(left: showInsideTime ? 4 : 0),
                      child: _SignalReceiptTicks(
                        isSent: _messageHasServerAck(message),
                        showReceivedCircle: _messageShowsReceivedCircle(
                          message,
                        ),
                        isRead: effectiveReadCount > 0,
                        isFailed: _messageIsFailed(message),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  _StructuredMessageData? _parseStructuredMessage(ChatMessage message) {
    if (message.kind != MessageKind.text) {
      return null;
    }

    final normalized = message.body.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return null;
    }

    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return null;
    }

    switch (lines.first.toLowerCase()) {
      case '[location]':
        final title = lines.length > 1 ? lines[1] : 'Shared location';
        String? details;
        String? link;
        String? imageUrl;
        for (final line in lines.skip(2)) {
          if (line.toLowerCase().startsWith('image:')) {
            final value = line.substring('image:'.length).trim();
            if (value.isNotEmpty) {
              imageUrl ??= value;
            }
          } else if (line.toLowerCase().startsWith('map:')) {
            final value = line.substring('map:'.length).trim();
            if (value.isNotEmpty) {
              link ??= value;
            }
          } else if (Uri.tryParse(line)?.isAbsolute ?? false) {
            link ??= line;
          } else {
            details = details == null ? line : '$details\n$line';
          }
        }
        return _StructuredMessageData(
          type: _StructuredMessageType.location,
          title: title,
          details: details,
          link: link,
          imageUrl: imageUrl,
        );
      case '[contact]':
        final fields = <MapEntry<String, String>>[];
        for (final line in lines.skip(1)) {
          final separator = line.indexOf(':');
          if (separator <= 0 || separator >= line.length - 1) {
            continue;
          }
          fields.add(
            MapEntry(
              line.substring(0, separator).trim(),
              line.substring(separator + 1).trim(),
            ),
          );
        }
        if (fields.isEmpty) {
          return null;
        }
        final name = fields
            .firstWhere(
              (entry) => entry.key.toLowerCase() == 'name',
              orElse: () => fields.first,
            )
            .value;
        return _StructuredMessageData(
          type: _StructuredMessageType.contact,
          title: name,
          fields: fields,
        );
      case '[poll]':
        final question = lines.length > 1 ? lines[1] : 'Poll';
        var allowsMultiple = false;
        final options = lines
            .skip(2)
            .where((line) {
              final lower = line.toLowerCase();
              if (lower == 'mode: multi' || lower == 'mode: multiple') {
                allowsMultiple = true;
                return false;
              }
              if (lower == 'mode: single') {
                allowsMultiple = false;
                return false;
              }
              return true;
            })
            .where((line) => line.startsWith('- '))
            .map((line) => line.substring(2).trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
        if (options.isEmpty) {
          return null;
        }
        return _StructuredMessageData(
          type: _StructuredMessageType.poll,
          title: question,
          options: options,
          allowsMultiple: allowsMultiple,
        );
      default:
        return null;
    }
  }

  String _structuredPreviewText(String rawBody, {required MessageKind kind}) {
    final normalized = rawBody.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return kind == MessageKind.video
          ? 'Video'
          : kind == MessageKind.image
          ? 'Image'
          : 'Original message';
    }

    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return 'Original message';
    }

    switch (lines.first.toLowerCase()) {
      case '[poll]':
        return lines.length > 1 && lines[1].isNotEmpty ? lines[1] : 'Poll';
      case '[location]':
        return lines.length > 1 && lines[1].isNotEmpty
            ? lines[1]
            : 'Shared location';
      case '[contact]':
        for (final line in lines.skip(1)) {
          final separator = line.indexOf(':');
          if (separator <= 0 || separator >= line.length - 1) {
            continue;
          }
          final key = line.substring(0, separator).trim().toLowerCase();
          final value = line.substring(separator + 1).trim();
          if (key == 'name' && value.isNotEmpty) {
            return value;
          }
        }
        return 'Contact';
      default:
        return normalized;
    }
  }

  IconData _structuredMessageIcon(_StructuredMessageType type) {
    switch (type) {
      case _StructuredMessageType.location:
        return Icons.location_on_outlined;
      case _StructuredMessageType.contact:
        return Icons.person_outline;
      case _StructuredMessageType.poll:
        return Icons.poll_outlined;
    }
  }

  String _structuredMessageLabel(_StructuredMessageType type) {
    switch (type) {
      case _StructuredMessageType.location:
        return 'Location pin';
      case _StructuredMessageType.contact:
        return 'Contact';
      case _StructuredMessageType.poll:
        return 'Poll';
    }
  }

  Widget _buildStructuredMessageContent({
    required _StructuredMessageData data,
    required ChatMessage message,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
    required ChatController controller,
  }) {
    final accent = mine
        ? Colors.white.withAlpha(220)
        : PlayerUiSignalTheme.primaryDarkColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withAlpha(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      _structuredMessageIcon(data.type),
                      color: accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _structuredMessageLabel(data.type),
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (data.type == _StructuredMessageType.contact)
                _StructuredContactCard(data: data)
              else if (data.type == _StructuredMessageType.location)
                _StructuredLocationCard(data: data, accent: accent)
              else
                _StructuredPollCard(
                  data: data,
                  accent: accent,
                  message: message,
                  currentUserId: controller.matrixUserId,
                  onVote: (optionIndex) => controller.voteOnPoll(
                    message,
                    optionIndex,
                    allowsMultiple: data.allowsMultiple,
                  ),
                ),
            ],
          ),
        ),
        if (showInsideTime || mine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showInsideTime)
                    Text(
                      _bubbleTimeLabel(context, message.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  if (mine)
                    Padding(
                      padding: EdgeInsets.only(left: showInsideTime ? 4 : 0),
                      child: _SignalReceiptTicks(
                        isSent: _messageHasServerAck(message),
                        showReceivedCircle: _messageShowsReceivedCircle(
                          message,
                        ),
                        isRead: effectiveReadCount > 0,
                        isFailed: _messageIsFailed(message),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// A gallery message (org.cluborbit.gallery) as one entry per image - the shape the image
  /// collage bubble takes - or null for any other message.
  List<ChatMessage>? _galleryMessagesFor(ChatMessage message) {
    final raw = message.metadata['galleryImages'];
    if (raw is! List || raw.isEmpty) return null;
    final images = <ChatMessage>[];
    for (var i = 0; i < raw.length; i++) {
      final img = raw[i];
      if (img is! Map) continue;
      images.add(
        message.copyWith(
          id: i == 0 ? message.id : '${message.id}#$i',
          metadata: <String, dynamic>{
            ...message.metadata,
            'mediaUrl': img['mediaUrl'],
            'mediaEncryption': img['mediaEncryption'],
            'thumbnailUrl': img['thumbnailUrl'],
            'thumbnailEncryption': img['thumbnailEncryption'],
            'mimeType': img['mimeType'],
            'filename': img['filename'],
            'caption': i == 0 ? message.metadata['caption'] : '',
          },
        ),
      );
    }
    return images.isEmpty ? null : images;
  }

  bool get _isSelectionMode => _selectedMessageIds.isNotEmpty;

  String? get _singleSelectedMessageId =>
      _selectedMessageIds.length == 1 ? _selectedMessageIds.first : null;

  bool _isMessageSelected(ChatMessage message) {
    return _selectedMessageIds.contains(message.id);
  }

  void _clearSelectedMessages() {
    if (_selectedMessageIds.isEmpty) {
      return;
    }
    setState(() => _selectedMessageIds.clear());
  }

  void _startEditingMessage(ChatMessage message) {
    setState(() {
      _editTargetMessage = message;
      _selectedMessageIds.clear();
    });
    _composerController.text = message.body;
    _composerController.selection = TextSelection.collapsed(
      offset: message.body.length,
    );
    _composerFocusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editTargetMessage = null;
    });
    _composerController.clear();
    _composerFocusNode.unfocus();
  }

  void _toggleMessageSelection(
    ChatMessage message, {
    bool forceSelect = false,
  }) {
    setState(() {
      final isSelected = _selectedMessageIds.contains(message.id);
      if (forceSelect || !isSelected) {
        _selectedMessageIds.add(message.id);
      } else {
        _selectedMessageIds.remove(message.id);
      }
    });
  }

  List<ChatMessage> _selectedMessagesFrom(List<ChatMessage> allMessages) {
    final selected = allMessages
        .where((message) => _selectedMessageIds.contains(message.id))
        .toList(growable: false);
    selected.sort((left, right) {
      final createdAtComparison = left.createdAt.compareTo(right.createdAt);
      if (createdAtComparison != 0) {
        return createdAtComparison;
      }
      return left.id.compareTo(right.id);
    });
    return selected;
  }

  List<ChatMessage> _selectedForwardBatchFrom(List<ChatMessage> allMessages) {
    final seenIds = <String>{};
    final batch = <ChatMessage>[];
    for (final selected in _selectedMessagesFrom(allMessages)) {
      // Exactly what was selected: separately sent images are separate messages now (only a
      // gallery message is one collage), so neighbouring images are no longer pulled in.
      if (seenIds.add(selected.id)) {
        batch.add(selected);
      }
    }
    batch.sort((left, right) {
      final createdAtComparison = left.createdAt.compareTo(right.createdAt);
      if (createdAtComparison != 0) {
        return createdAtComparison;
      }
      return left.id.compareTo(right.id);
    });
    return batch;
  }

  Future<_DeleteMessageAction?> _showDeleteActionSheet({
    required bool canDeleteForEveryone,
  }) {
    return showModalBottomSheet<_DeleteMessageAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: PlayerUiSignalTheme.secondaryColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.person_outline,
                    color: PlayerUiSignalTheme.primaryDarkColor,
                  ),
                  title: const Text('Delete for me'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_DeleteMessageAction.forMe),
                ),
                if (canDeleteForEveryone)
                  ListTile(
                    leading: const Icon(
                      Icons.group_remove_outlined,
                      color: PlayerUiSignalTheme.primaryDarkColor,
                    ),
                    title: const Text('Delete for everyone'),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_DeleteMessageAction.forEveryone),
                  ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDeleteSelection(ChatController controller) async {
    final selectedMessages = _selectedMessagesFrom(controller.messages);
    if (selectedMessages.isEmpty) {
      return;
    }

    final canDeleteForEveryone = selectedMessages.every(
      (message) => message.senderId == controller.matrixUserId,
    );
    final deleteAction = await _showDeleteActionSheet(
      canDeleteForEveryone: canDeleteForEveryone,
    );
    if (deleteAction == null) {
      return;
    }

    final selectedIds = selectedMessages
        .map((message) => message.id)
        .toList(growable: false);
    _clearSelectedMessages();

    if (deleteAction == _DeleteMessageAction.forEveryone) {
      await controller.deleteMessages(selectedIds);
      return;
    }
    await controller.deleteMessagesForMe(selectedIds);
  }

  Widget _buildSelectionIndicator(bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? PlayerUiSignalTheme.primaryDarkColor
            : Colors.transparent,
        border: Border.all(
          color: selected
              ? PlayerUiSignalTheme.primaryDarkColor
              : Colors.white.withAlpha(120),
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }

  Widget _buildSelectableMessageRow({
    required ChatMessage message,
    required bool mine,
    required Widget child,
  }) {
    final selectionMode = _isSelectionMode;
    final isSelected = _isMessageSelected(message);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _toggleMessageSelection(message, forceSelect: true),
      onTap: selectionMode ? () => _toggleMessageSelection(message) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: EdgeInsets.only(
          left: selectionMode && !mine ? 38 : 0,
          right: selectionMode && mine ? 38 : 0,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black.withAlpha(36) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            AbsorbPointer(absorbing: selectionMode, child: child),
            if (selectionMode)
              Positioned(
                left: mine ? null : 8,
                right: mine ? 8 : null,
                top: 0,
                bottom: 0,
                child: Center(child: _buildSelectionIndicator(isSelected)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardedIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.forward, size: 12, color: Colors.white70),
          SizedBox(width: 4),
          Text(
            'Forwarded',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandalonePollMessage({
    required BuildContext context,
    required _StructuredMessageData data,
    required ChatMessage message,
    required String senderName,
    required String? senderAvatarUrl,
    required bool isOtherOnline,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
    required ChatController controller,
  }) {
    final accent = mine
        ? Colors.white.withAlpha(220)
        : PlayerUiSignalTheme.primaryDarkColor;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(34)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _AvatarThumb(
                    imageUrl: senderAvatarUrl,
                    initials: senderName.isEmpty
                        ? '?'
                        : senderName[0].toUpperCase(),
                    size: 30,
                    backgroundColor: PlayerUiSignalTheme.mobileSearchColor,
                    showPresence: !mine,
                    isOnline: isOtherOnline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7D9EC0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (showInsideTime)
                    Text(
                      _bubbleTimeLabel(context, message.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  if (mine)
                    Padding(
                      padding: EdgeInsets.only(left: showInsideTime ? 6 : 0),
                      child: _SignalReceiptTicks(
                        isSent: _messageHasServerAck(message),
                        showReceivedCircle: _messageShowsReceivedCircle(
                          message,
                        ),
                        isRead: effectiveReadCount > 0,
                        isFailed: _messageIsFailed(message),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                border: Border(
                  top: BorderSide(color: Colors.white.withAlpha(24)),
                  bottom: BorderSide(color: Colors.white.withAlpha(24)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(26),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.poll_outlined, size: 14, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          _structuredMessageLabel(_StructuredMessageType.poll),
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: _StructuredPollCard(
                data: data,
                accent: accent,
                message: message,
                currentUserId: controller.matrixUserId,
                onVote: (optionIndex) => controller.voteOnPoll(
                  message,
                  optionIndex,
                  allowsMultiple: data.allowsMultiple,
                ),
                showTitle: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChatCustomization() async {
    final updated = await Navigator.of(context).push<_ChatAppearance>(
      MaterialPageRoute(
        builder: (_) => _ChatCustomizationScreen(initial: _appearance),
      ),
    );
    if (updated == null || !mounted) return;
    final controller = _controllerRef ?? context.read<ChatController>();
    final preferenceKey = _chatPreferenceKey(controller);
    setState(() {
      _appearance = updated;
    });
    _ChatAppearanceStore.cacheForChat(preferenceKey, updated);
    unawaited(_persistChatAppearance(preferenceKey, updated));
  }

  Future<void> _persistChatAppearance(
    String preferenceKey,
    _ChatAppearance appearance,
  ) async {
    try {
      await _ChatAppearanceStore.saveForChat(preferenceKey, appearance);
    } catch (e, s) {
      debugPrint(
        'Failed to persist chat appearance for $preferenceKey: $e\n$s',
      );
    }
  }

  Future<void> _openCallSession({required bool isVideo}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            _CallSessionScreen(chatTitle: widget.title, isVideo: isVideo),
      ),
    );
  }

  bool _isHeartReaction(String emoji) {
    return emoji == '\u{2764}\u{FE0F}' || emoji == '\u{2764}';
  }

  Widget _buildReplyPreviewInBubble(ChatMessage message) {
    final replyKindRaw = message.metadata['replyToKind'];
    final replyKind = replyKindRaw is String ? replyKindRaw : '';
    final isMediaReply =
        replyKind == MessageKind.image.name ||
        replyKind == MessageKind.video.name;
    final replyThumbRaw = message.metadata['replyToThumbnailUrl'];
    final replyMediaRaw = message.metadata['replyToMediaUrl'];
    final hasRealReplyThumbnail =
        replyThumbRaw is String && replyThumbRaw.trim().isNotEmpty;
    // A real thumbnailUrl (video) needs its own thumbnailEncryption; falling back to the full
    // attachment's URL (e.g. an image, which never gets a separate thumbnail) needs
    // mediaEncryption instead — same distinction as _thumbnailMediaRefFor above.
    final replyEncryptionRaw = hasRealReplyThumbnail
        ? message.metadata['replyToThumbnailEncryption']
        : message.metadata['replyToMediaEncryption'];
    final replyEncryption = replyEncryptionRaw is Map
        ? replyEncryptionRaw.cast<String, dynamic>()
        : null;
    final replyThumb = _MediaRef.fromUrl(
      hasRealReplyThumbnail
          ? replyThumbRaw.trim()
          : (replyMediaRaw is String ? replyMediaRaw.trim() : null),
      replyEncryption,
    );
    final replyForwarded = message.metadata['replyToIsForwarded'] == true;
    final replyBody = _structuredPreviewText(
      (message.replyToBody ?? '').trim(),
      kind: replyKind == MessageKind.video.name
          ? MessageKind.video
          : replyKind == MessageKind.image.name
          ? MessageKind.image
          : MessageKind.text,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(45),
        borderRadius: BorderRadius.circular(9),
        border: const Border(
          left: BorderSide(
            color: PlayerUiSignalTheme.primaryDarkColor,
            width: 2.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyToSenderName ?? 'Reply',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (replyForwarded)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forward, size: 10, color: Colors.white60),
                  SizedBox(width: 3),
                  Text(
                    'Forwarded',
                    style: TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          if (isMediaReply)
            Row(
              children: [
                if (replyThumb != null)
                  Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 8),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      color: Colors.black26,
                    ),
                    child: _EncryptedImage(
                      media: replyThumb,
                      fit: BoxFit.cover,
                      errorWidget: (context, error) => const Icon(
                        Icons.broken_image,
                        color: Colors.white60,
                        size: 16,
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.photo_outlined,
                      color: Colors.white60,
                      size: 16,
                    ),
                  ),
                Expanded(
                  child: Text(
                    replyBody.isEmpty
                        ? (replyKind == MessageKind.video.name
                              ? 'Video'
                              : 'Image')
                        : replyBody,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            )
          else
            Text(
              replyBody.isEmpty ? 'Original message' : replyBody,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  void _openImageViewer(
    BuildContext context,
    List<_MediaRef> images,
    int initialIndex,
  ) {
    if (images.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ImageSlideshowScreen(images: images, initialIndex: initialIndex),
      ),
    );
  }

  Widget _buildImageGroupBubble({
    required BuildContext context,
    required ChatMessage message,
    required List<ChatMessage> imageGroup,
    required bool mine,
    required bool showInsideTime,
    required int effectiveReadCount,
  }) {
    final fullImages = imageGroup
        .map(_mediaRefFor)
        .whereType<_MediaRef>()
        .toList(growable: false);
    final thumbImages = imageGroup
        .map(_thumbnailMediaRefFor)
        .whereType<_MediaRef>()
        .toList(growable: false);
    final caption = imageGroup
        .map((m) => (m.metadata['caption'] as String?) ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final stamp = (showInsideTime || mine)
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showInsideTime)
                  Text(
                    _bubbleTimeLabel(context, message.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                if (mine)
                  Padding(
                    padding: EdgeInsets.only(left: showInsideTime ? 4 : 0),
                    child: _SignalReceiptTicks(
                      isSent: _messageHasServerAck(message),
                      showReceivedCircle: _messageShowsReceivedCircle(message),
                      isRead: effectiveReadCount > 0,
                      isFailed: _messageIsFailed(message),
                    ),
                  ),
              ],
            ),
          )
        : null;

    // Only a captioned image gets a chat bubble (bubbles are for text); an uncaptioned one sits
    // straight on the chat background, so a transparent image shows through to it. The time and
    // ticks sit on a small dark pill over the image's corner so they stay readable on any picture.
    final hasCaption = caption.isNotEmpty;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.74,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: hasCaption ? const EdgeInsets.all(3) : EdgeInsets.zero,
        decoration: hasCaption
            ? BoxDecoration(
                color: mine
                    ? _appearance.myBubbleColor
                    : _appearance.otherBubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 5),
                  bottomRight: Radius.circular(mine ? 5 : 18),
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: mine && !hasCaption
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (message.metadata['isForwarded'] == true)
              _buildForwardedIndicator(),
            Stack(
              children: [
                _ImageCollageGrid(
                  images: thumbImages,
                  onOpenAt: (index) {
                    _openImageViewer(context, fullImages, index);
                  },
                ),
                if (stamp != null)
                  Positioned(right: 6, bottom: 6, child: stamp),
              ],
            ),
            if (hasCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 5, 7, 4),
                child: Text(
                  caption,
                  style: TextStyle(
                    color: _appearance.messageTextColor,
                    fontSize: 14,
                    fontFamily: _appearance.messageFontFamily,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, controller, _) {
        // Tell the controller which chat is on screen, so pushes for it skip the notification.
        final activeRoomId = controller.activeRoomId;
        if (activeRoomId != null && activeRoomId != _onScreenRoomId) {
          final previous = _onScreenRoomId;
          if (previous != null) controller.clearRoomOnScreen(previous);
          _onScreenRoomId = activeRoomId;
          controller.setRoomOnScreen(activeRoomId);
        }
        final isChatMuted = _MutedChatStore.isMuted(
          _chatPreferenceKey(controller),
        );
        final messages = controller.messages;
        final visibleMessages = messages
            .where(
              (message) =>
                  !_isTimelineOnlyMessage(message) &&
                  message.metadata['isDeleted'] != true,
            )
            .toList(growable: false);
        if (visibleMessages.isNotEmpty) {
          final latest = visibleMessages.last;
          _scrollToLatestOnNewMessage(
            latest.id,
            latest.senderId == controller.matrixUserId,
          );
        }
        final replyTo = controller.replyToMessage;
        final typingUsers = controller.typingUsers;
        final participantsById = <String, ChatParticipant>{
          for (final participant in controller.participants)
            participant.userId: participant,
        };
        _ensurePresenceLoaded(
          controller,
          controller.participants
              .map((participant) => participant.userId)
              .where((userId) => userId != controller.matrixUserId),
        );
        final effectiveOwnReadCounts = <String, int>{};
        var strongestOwnReadCount = 0;
        for (final candidate in visibleMessages.reversed) {
          if (candidate.senderId != controller.matrixUserId) {
            continue;
          }
          if (candidate.readCount > strongestOwnReadCount) {
            strongestOwnReadCount = candidate.readCount;
          }
          effectiveOwnReadCounts[candidate.id] = strongestOwnReadCount;
        }
        final events = _extractTimelineEvents(messages);
        _ensureLinkPreviewsLoaded(visibleMessages);
        final timelineEntries = _buildTimelineEntries(
          visibleMessages: visibleMessages,
          events: events,
        );
        final composerFocused = _composerFocusNode.hasFocus;
        final scrollFabBottom =
            (_showEmojiPickerPanel ? 386.0 : 66.0) +
            (_editTargetMessage != null || replyTo != null ? 72.0 : 0.0);

        return PopScope<void>(
          canPop:
              !_showEmojiPickerPanel &&
              !_isSelectionMode &&
              _editTargetMessage == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              if (_editTargetMessage != null) {
                _cancelEditing();
              } else if (_isSelectionMode) {
                _clearSelectedMessages();
              } else if (_showEmojiPickerPanel) {
                setState(() {
                  _showEmojiPickerPanel = false;
                });
              }
            }
          },
          child: Scaffold(
            backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
            appBar: _isSelectionMode
                ? AppBar(
                    backgroundColor: PlayerUiSignalTheme.secondaryColor,
                    // Dark app bar: white status-bar icons (the theme default gave black ones).
                    systemOverlayStyle: SystemUiOverlayStyle.light,
                    automaticallyImplyLeading: false,
                    leadingWidth: 48,
                    leading: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: PlayerUiSignalTheme.primaryDarkColor,
                      ),
                      tooltip: 'Deselect',
                      onPressed: _clearSelectedMessages,
                    ),
                    title: Text(
                      '${_selectedMessageIds.length} selected',
                      style: TextStyle(
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    actions: [
                      if (_selectedMessageIds.length == 1)
                        IconButton(
                          icon: const Icon(
                            Icons.reply,
                            color: PlayerUiSignalTheme.primaryDarkColor,
                          ),
                          tooltip: 'Reply',
                          onPressed: () {
                            final selectedMessages = _selectedMessagesFrom(
                              controller.messages,
                            );
                            if (selectedMessages.length != 1) {
                              return;
                            }
                            controller.setReplyTarget(selectedMessages.first);
                            _clearSelectedMessages();
                            _composerFocusNode.requestFocus();
                          },
                        ),
                      Builder(
                        builder: (context) {
                          if (_selectedMessageIds.length != 1) {
                            return const SizedBox.shrink();
                          }
                          final selectedMessages = _selectedMessagesFrom(
                            controller.messages,
                          );
                          if (selectedMessages.length != 1) {
                            return const SizedBox.shrink();
                          }
                          final msg = selectedMessages.first;
                          final canEdit =
                              msg.senderId == controller.matrixUserId &&
                              msg.kind == MessageKind.text &&
                              msg.metadata['isDeleted'] != true &&
                              msg.metadata['timelineOnly'] != true;
                          if (!canEdit) return const SizedBox.shrink();
                          return IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: PlayerUiSignalTheme.primaryDarkColor,
                            ),
                            tooltip: 'Edit',
                            onPressed: () => _startEditingMessage(msg),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: PlayerUiSignalTheme.primaryDarkColor,
                        ),
                        tooltip: 'Delete',
                        onPressed: () => _handleDeleteSelection(controller),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.forward,
                          color: PlayerUiSignalTheme.primaryDarkColor,
                        ),
                        tooltip: 'Forward',
                        onPressed: () async {
                          final batch = _selectedForwardBatchFrom(
                            controller.messages,
                          );
                          _clearSelectedMessages();
                          final target = await _pickForwardTarget(
                            context,
                            controller,
                          );
                          if (target != null) {
                            for (final message in batch) {
                              await controller.forwardMessage(
                                source: message,
                                targetRoomId: target.id,
                              );
                            }
                            await controller.openRoom(
                              target.id,
                              roomTitle: target.title,
                            );
                            if (!context.mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  title: target.title,
                                  avatarUrl: target.avatarUrl,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  )
                : AppBar(
                    backgroundColor: PlayerUiSignalTheme.secondaryColor,
                    systemOverlayStyle: SystemUiOverlayStyle.light,
                    automaticallyImplyLeading: false,
                    leading: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Back',
                      icon: SvgPicture.asset(
                        'assets/icon/ic_back.svg',
                        package: 'clubcommon',
                        width: 22,
                        height: 22,
                      ),
                    ),
                    titleSpacing: 16,
                    title: Row(
                      children: [
                        if ((controller.activeRoomAvatarUrl ??
                                    widget.avatarUrl) !=
                                null ||
                            widget.title.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _AvatarThumb(
                              imageUrl:
                                  controller.activeRoomAvatarUrl ??
                                  widget.avatarUrl,
                              initials: widget.title.isEmpty
                                  ? '?'
                                  : widget.title[0].toUpperCase(),
                              size: 32,
                              backgroundColor:
                                  PlayerUiSignalTheme.mobileSearchColor,
                              useGroupPlaceholder:
                                  controller.activeRoomType == ChatType.group,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PlayerUiSignalTheme.primaryDarkColor,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      if (!kReleaseMode) ...[
                        IconButton(
                          icon: const Icon(
                            Icons.call_outlined,
                            color: PlayerUiSignalTheme.primaryDarkColor,
                          ),
                          tooltip: 'Voice call',
                          onPressed: () =>
                              unawaited(_openCallSession(isVideo: false)),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.videocam_outlined,
                            color: PlayerUiSignalTheme.primaryDarkColor,
                          ),
                          tooltip: 'Video call',
                          onPressed: () =>
                              unawaited(_openCallSession(isVideo: true)),
                        ),
                      ],
                      PopupMenuButton<_ChatMenuAction>(
                        tooltip: 'Chat options',
                        position: PopupMenuPosition.under,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        color: PlayerUiSignalTheme.secondaryColor,
                        icon: const Icon(
                          Icons.more_vert,
                          color: PlayerUiSignalTheme.primaryDarkColor,
                        ),
                        onSelected: (_ChatMenuAction action) {
                          switch (action) {
                            case _ChatMenuAction.details:
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ChatDetailsScreen(),
                                ),
                              );
                            case _ChatMenuAction.customize:
                              _openChatCustomization();
                            case _ChatMenuAction.mute:
                              final muted = _MutedChatStore.toggle(
                                _chatPreferenceKey(controller),
                              );
                              _showChatSnackBar(
                                context,
                                muted ? 'Chat muted' : 'Chat unmuted',
                              );
                              setState(() {});
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem<_ChatMenuAction>(
                            value: _ChatMenuAction.details,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: PlayerUiSignalTheme.primaryDarkColor,
                                ),
                                SizedBox(width: 8),
                                Text('Chat details'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<_ChatMenuAction>(
                            value: _ChatMenuAction.customize,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.palette_outlined,
                                  size: 18,
                                  color: PlayerUiSignalTheme.primaryDarkColor,
                                ),
                                SizedBox(width: 8),
                                Text('Customize chat'),
                              ],
                            ),
                          ),
                          PopupMenuItem<_ChatMenuAction>(
                            value: _ChatMenuAction.mute,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isChatMuted
                                      ? Icons.notifications_active_outlined
                                      : Icons.notifications_off_outlined,
                                  size: 18,
                                  color: PlayerUiSignalTheme.primaryDarkColor,
                                ),
                                const SizedBox(width: 8),
                                Text(isChatMuted ? 'Unmute chat' : 'Mute chat'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            body: Container(
              decoration: BoxDecoration(
                color: PlayerUiSignalTheme.mobileBackgroundColor,
                image: _appearance.backgroundImageUrl == null
                    ? null
                    : DecorationImage(
                        image: NetworkImage(_appearance.backgroundImageUrl!),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Colors.black.withAlpha(130),
                          BlendMode.darken,
                        ),
                      ),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            fontFamily: _appearance.messageFontFamily,
                          ),
                          child: ListView.builder(
                            controller: _messagesScrollController,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            itemCount: timelineEntries.length,
                            itemBuilder: (context, index) {
                              final timelineIndex =
                                  timelineEntries.length - index - 1;
                              final entry = timelineEntries[timelineIndex];
                              if (entry.eventCluster != null) {
                                final cluster = entry.eventCluster!;
                                final isExpanded = _expandedEventClusterKeys
                                    .contains(cluster.key);
                                return _TimelineEventClusterCard(
                                  cluster: cluster,
                                  showAllEvents: isExpanded,
                                  onToggle: cluster.items.length > 1
                                      ? () => _toggleEventCluster(cluster)
                                      : null,
                                  relativeTime: _relativeTime,
                                );
                              }

                              final message = entry.message!;
                              final messageIndex = entry.messageIndex!;
                              final mine =
                                  message.senderId == controller.matrixUserId;
                              final effectiveReadCount =
                                  effectiveOwnReadCounts[message.id] ??
                                  message.readCount;
                              final participant =
                                  participantsById[message.senderId];
                              final senderName =
                                  participant?.displayName ??
                                  message.senderName;
                              final senderAvatarUrl = participant?.avatarUrl;
                              final senderPresence = controller
                                  .cachedUserPresence(message.senderId);
                              final isOtherOnline =
                                  !mine &&
                                  (typingUsers.any(
                                        (typing) =>
                                            typing.userId == message.senderId,
                                      ) ||
                                      senderPresence?.isOnline == true);
                              final centeredTimeEligible =
                                  _shouldShowCenteredTime(message.createdAt);

                              final olderMessage = messageIndex > 0
                                  ? visibleMessages[messageIndex - 1]
                                  : null;
                              final newerMessage =
                                  messageIndex < visibleMessages.length - 1
                                  ? visibleMessages[messageIndex + 1]
                                  : null;

                              final closeToOlderSameSender =
                                  olderMessage != null &&
                                  olderMessage.senderId == message.senderId &&
                                  message.createdAt
                                          .difference(olderMessage.createdAt)
                                          .inMinutes <
                                      1;
                              final closeToNewerSameSender =
                                  newerMessage != null &&
                                  newerMessage.senderId == message.senderId &&
                                  newerMessage.createdAt
                                          .difference(message.createdAt)
                                          .inMinutes <
                                      1;
                              final senderChangedFromPrevious =
                                  olderMessage == null ||
                                  olderMessage.senderId != message.senderId;
                              final previewUrl = _extractFirstPreviewUrl(
                                message,
                              );
                              final linkPreview = previewUrl == null
                                  ? null
                                  : _linkPreviewByUrl[previewUrl];
                              final showCenteredTime =
                                  centeredTimeEligible &&
                                  _startsCenteredTimeCluster(
                                    message,
                                    olderMessage,
                                  );

                              var showSenderHeader =
                                  !mine && senderChangedFromPrevious;
                              final showInsideTime = mine
                                  ? !closeToOlderSameSender
                                  : !closeToNewerSameSender;

                              if (message.kind == MessageKind.image &&
                                  _mediaUrlFor(message) != null) {
                                // Only a gallery (multi-image) message shows as one collage -
                                // it carries all its images itself. Images sent as separate
                                // messages each get their own bubble, even when sent back to
                                // back, rather than being merged into a collage.
                                final gallery = _galleryMessagesFor(message);
                                final imageGroup =
                                    gallery ?? <ChatMessage>[message];
                                final previousVisibleMessage = messageIndex > 0
                                    ? visibleMessages[messageIndex - 1]
                                    : null;
                                final showGroupedCenteredTime =
                                    centeredTimeEligible &&
                                    _startsCenteredTimeCluster(
                                      message,
                                      previousVisibleMessage,
                                    );
                                showSenderHeader =
                                    !mine &&
                                    (previousVisibleMessage == null ||
                                        previousVisibleMessage.senderId !=
                                            message.senderId);

                                final bubble = _buildImageGroupBubble(
                                  context: context,
                                  message: message,
                                  imageGroup: imageGroup,
                                  mine: mine,
                                  showInsideTime: showInsideTime,
                                  effectiveReadCount: effectiveReadCount,
                                );
                                final bubbleWithReaction =
                                    _buildBubbleWithReactionOverlay(
                                      message: message,
                                      bubble: bubble,
                                      controller: controller,
                                    );

                                final row = mine
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Flexible(child: bubbleWithReaction),
                                        ],
                                      )
                                    : Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (showSenderHeader)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 12,
                                              ),
                                              child: _AvatarThumb(
                                                imageUrl: senderAvatarUrl,
                                                initials: senderName.isEmpty
                                                    ? '?'
                                                    : senderName[0]
                                                          .toUpperCase(),
                                                size: 32,
                                                backgroundColor:
                                                    PlayerUiSignalTheme
                                                        .mobileSearchColor,
                                                showPresence: true,
                                                isOnline: isOtherOnline,
                                              ),
                                            )
                                          else
                                            const SizedBox(width: 32),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: showSenderHeader
                                                ? Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 2,
                                                            ),
                                                        child: Text(
                                                          senderName,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                  0xFF7D9EC0,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                      bubbleWithReaction,
                                                    ],
                                                  )
                                                : bubbleWithReaction,
                                          ),
                                        ],
                                      );

                                return Dismissible(
                                  key: ValueKey(
                                    '${message.id}_${message.createdAt.millisecondsSinceEpoch}',
                                  ),
                                  direction: _isSelectionMode
                                      ? DismissDirection.none
                                      : DismissDirection.horizontal,
                                  confirmDismiss: (_) async {
                                    controller.setReplyTarget(message);
                                    _composerFocusNode.requestFocus();
                                    return false;
                                  },
                                  background: _ReplySwipeBackground(
                                    alignment: mine,
                                  ),
                                  secondaryBackground: _ReplySwipeBackground(
                                    alignment: !mine,
                                  ),
                                  child: Column(
                                    children: [
                                      if (showGroupedCenteredTime)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            _formatClock(
                                              context,
                                              message.createdAt,
                                              previousTime:
                                                  previousVisibleMessage
                                                      ?.createdAt,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white54,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      _buildSelectableMessageRow(
                                        message: message,
                                        mine: mine,
                                        child: row,
                                      ),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: ScaleTransition(
                                              scale: Tween<double>(
                                                begin: 0.94,
                                                end: 1,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child:
                                            _singleSelectedMessageId ==
                                                message.id
                                            ? KeyedSubtree(
                                                key: ValueKey(
                                                  'hover_${message.id}',
                                                ),
                                                child:
                                                    _buildInlineReactionHover(
                                                      controller: controller,
                                                      message: message,
                                                      mine: mine,
                                                    ),
                                              )
                                            : const SizedBox.shrink(
                                                key: ValueKey('hover_none'),
                                              ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final structuredMessage = _parseStructuredMessage(
                                message,
                              );
                              final isStandalonePoll =
                                  structuredMessage?.type ==
                                  _StructuredMessageType.poll;
                              if (isStandalonePoll) {
                                final pollContent = _buildStandalonePollMessage(
                                  context: context,
                                  data: structuredMessage!,
                                  message: message,
                                  senderName: senderName,
                                  senderAvatarUrl: senderAvatarUrl,
                                  isOtherOnline: isOtherOnline,
                                  mine: mine,
                                  showInsideTime: showInsideTime,
                                  effectiveReadCount: effectiveReadCount,
                                  controller: controller,
                                );
                                final pollWithReaction =
                                    _buildBubbleWithReactionOverlay(
                                      message: message,
                                      bubble: pollContent,
                                      controller: controller,
                                    );

                                return Dismissible(
                                  key: ValueKey(
                                    '${message.id}_${message.createdAt.millisecondsSinceEpoch}',
                                  ),
                                  direction: _isSelectionMode
                                      ? DismissDirection.none
                                      : DismissDirection.horizontal,
                                  confirmDismiss: (_) async {
                                    controller.setReplyTarget(message);
                                    _composerFocusNode.requestFocus();
                                    return false;
                                  },
                                  background: _ReplySwipeBackground(
                                    alignment: mine,
                                  ),
                                  secondaryBackground: _ReplySwipeBackground(
                                    alignment: !mine,
                                  ),
                                  child: Column(
                                    children: [
                                      if (showCenteredTime)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            _formatClock(
                                              context,
                                              message.createdAt,
                                              previousTime:
                                                  olderMessage?.createdAt,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white54,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      _buildSelectableMessageRow(
                                        message: message,
                                        mine: mine,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Flexible(child: pollWithReaction),
                                          ],
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: ScaleTransition(
                                              scale: Tween<double>(
                                                begin: 0.94,
                                                end: 1,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child:
                                            _singleSelectedMessageId ==
                                                message.id
                                            ? KeyedSubtree(
                                                key: ValueKey(
                                                  'hover_${message.id}',
                                                ),
                                                child:
                                                    _buildInlineReactionHover(
                                                      controller: controller,
                                                      message: message,
                                                      mine: mine,
                                                    ),
                                              )
                                            : const SizedBox.shrink(
                                                key: ValueKey('hover_none'),
                                              ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              // Only messages with text get a bubble: an emoji-only message or
                              // an uncaptioned video sits straight on the chat background (a
                              // reply keeps its bubble, since the quoted text is part of it).
                              final bubbleless =
                                  message.replyToEventId == null &&
                                  structuredMessage == null &&
                                  previewUrl == null &&
                                  (_isEmojiOnlyMessage(message) ||
                                      (_isPlayableVideo(message) &&
                                          ((message.metadata['caption']
                                                          as String?)
                                                      ?.trim() ??
                                                  '')
                                              .isEmpty));
                              final bubble = ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.74,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  padding: bubbleless
                                      ? const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        )
                                      : _locationOf(message) != null
                                      ? const EdgeInsets.all(3)
                                      : const EdgeInsets.symmetric(
                                          vertical: 7,
                                          horizontal: 10,
                                        ),
                                  decoration: bubbleless
                                      ? null
                                      : BoxDecoration(
                                          color: mine
                                              ? _appearance.myBubbleColor
                                              : _appearance.otherBubbleColor,
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(18),
                                            topRight: const Radius.circular(18),
                                            bottomLeft: Radius.circular(
                                              mine ? 18 : 5,
                                            ),
                                            bottomRight: Radius.circular(
                                              mine ? 5 : 18,
                                            ),
                                          ),
                                        ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (message.replyToEventId != null)
                                        _buildReplyPreviewInBubble(message),
                                      if (message.metadata['isForwarded'] ==
                                          true)
                                        _buildForwardedIndicator(),
                                      if (structuredMessage != null)
                                        _buildStructuredMessageContent(
                                          data: structuredMessage,
                                          message: message,
                                          mine: mine,
                                          showInsideTime: showInsideTime,
                                          effectiveReadCount:
                                              effectiveReadCount,
                                          controller: controller,
                                        )
                                      else if (_isAudioAttachment(message))
                                        _buildAudioMessageContent(
                                          message: message,
                                          mine: mine,
                                          showInsideTime: showInsideTime,
                                          effectiveReadCount:
                                              effectiveReadCount,
                                        )
                                      else if (_isPlayableVideo(message))
                                        _buildVideoMessageContent(
                                          context: context,
                                          message: message,
                                          mine: mine,
                                          showInsideTime: showInsideTime,
                                          effectiveReadCount:
                                              effectiveReadCount,
                                        )
                                      else if (_locationOf(message) != null)
                                        _buildLocationMessageContent(
                                          message: message,
                                          mine: mine,
                                          showInsideTime: showInsideTime,
                                          effectiveReadCount:
                                              effectiveReadCount,
                                        )
                                      else if (_isDocumentAttachment(message))
                                        _buildDocumentMessageContent(
                                          message: message,
                                          mine: mine,
                                          showInsideTime: showInsideTime,
                                          effectiveReadCount:
                                              effectiveReadCount,
                                        )
                                      else if (previewUrl != null)
                                        _buildLinkPreviewMessageContent(
                                          message: message,
                                          mine: mine,
                                          showInsideTime: showInsideTime,
                                          effectiveReadCount:
                                              effectiveReadCount,
                                          previewUrl: previewUrl,
                                          preview: linkPreview,
                                        )
                                      else
                                        RichText(
                                          text: TextSpan(
                                            style: TextStyle(
                                              fontSize:
                                                  _isEmojiOnlyMessage(message)
                                                  ? 28
                                                  : 16,
                                              fontWeight: FontWeight.w400,
                                              color:
                                                  _appearance.messageTextColor,
                                              fontFamily:
                                                  _appearance.messageFontFamily,
                                            ),
                                            children: [
                                              TextSpan(text: message.body),
                                              if (showInsideTime || mine)
                                                const TextSpan(text: '  '),
                                              if (showInsideTime)
                                                WidgetSpan(
                                                  alignment:
                                                      PlaceholderAlignment
                                                          .baseline,
                                                  baseline:
                                                      TextBaseline.alphabetic,
                                                  child: Text(
                                                    _bubbleTimeLabel(
                                                      context,
                                                      message.createdAt,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                ),
                                              if (mine)
                                                WidgetSpan(
                                                  alignment:
                                                      PlaceholderAlignment
                                                          .middle,
                                                  child: Padding(
                                                    padding: EdgeInsets.only(
                                                      left: showInsideTime
                                                          ? 4
                                                          : 0,
                                                    ),
                                                    child: _SignalReceiptTicks(
                                                      isSent:
                                                          _messageHasServerAck(
                                                            message,
                                                          ),
                                                      showReceivedCircle:
                                                          _messageShowsReceivedCircle(
                                                            message,
                                                          ),
                                                      isRead:
                                                          effectiveReadCount >
                                                          0,
                                                      isFailed:
                                                          _messageIsFailed(
                                                            message,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          softWrap: true,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                              final bubbleWithReaction =
                                  _buildBubbleWithReactionOverlay(
                                    message: message,
                                    bubble: bubble,
                                    controller: controller,
                                  );

                              final row = mine
                                  ? Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Flexible(child: bubbleWithReaction),
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (showSenderHeader)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: _AvatarThumb(
                                              imageUrl: senderAvatarUrl,
                                              initials: senderName.isEmpty
                                                  ? '?'
                                                  : senderName[0].toUpperCase(),
                                              size: 32,
                                              backgroundColor:
                                                  PlayerUiSignalTheme
                                                      .mobileSearchColor,
                                              showPresence: true,
                                              isOnline: isOtherOnline,
                                            ),
                                          )
                                        else
                                          const SizedBox(width: 32),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: showSenderHeader
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 2,
                                                          ),
                                                      child: Text(
                                                        senderName,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Color(
                                                            0xFF7D9EC0,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    bubbleWithReaction,
                                                  ],
                                                )
                                              : bubbleWithReaction,
                                        ),
                                      ],
                                    );

                              return Dismissible(
                                key: ValueKey(
                                  '${message.id}_${message.createdAt.millisecondsSinceEpoch}',
                                ),
                                direction: _isSelectionMode
                                    ? DismissDirection.none
                                    : DismissDirection.horizontal,
                                confirmDismiss: (_) async {
                                  controller.setReplyTarget(message);
                                  _composerFocusNode.requestFocus();
                                  return false;
                                },
                                background: _ReplySwipeBackground(
                                  alignment: mine,
                                ),
                                secondaryBackground: _ReplySwipeBackground(
                                  alignment: !mine,
                                ),
                                child: Column(
                                  children: [
                                    if (showCenteredTime)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          _formatClock(
                                            context,
                                            message.createdAt,
                                            previousTime:
                                                olderMessage?.createdAt,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    _buildSelectableMessageRow(
                                      message: message,
                                      mine: mine,
                                      child: row,
                                    ),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (child, animation) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                              begin: 0.94,
                                              end: 1,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child:
                                          _singleSelectedMessageId == message.id
                                          ? KeyedSubtree(
                                              key: ValueKey(
                                                'hover_${message.id}',
                                              ),
                                              child: _buildInlineReactionHover(
                                                controller: controller,
                                                message: message,
                                                mine: mine,
                                              ),
                                            )
                                          : const SizedBox.shrink(
                                              key: ValueKey('hover_none'),
                                            ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: typingUsers.isNotEmpty
                            ? _TypingBubble(
                                title:
                                    '${typingUsers.first.displayName.split(' ').first} is typing',
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (_editTargetMessage != null)
                        Container(
                          margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _appearance.otherBubbleColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: PlayerUiSignalTheme.primaryDarkColor
                                  .withAlpha(120),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: PlayerUiSignalTheme.primaryDarkColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Edit message',
                                      style: TextStyle(
                                        color: PlayerUiSignalTheme
                                            .primaryDarkColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _editTargetMessage!.body,
                                      maxLines: 2,
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
                                onPressed: _cancelEditing,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (replyTo != null)
                        Container(
                          margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _appearance.otherBubbleColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withAlpha(40),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (replyTo.kind == MessageKind.image &&
                                  _thumbnailMediaRefFor(replyTo) != null)
                                Container(
                                  width: 46,
                                  height: 46,
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.black26,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _EncryptedImage(
                                    media: _thumbnailMediaRefFor(replyTo)!,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, error) => const Icon(
                                      Icons.broken_image,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Replying to ${replyTo.senderName}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      _structuredPreviewText(
                                        replyTo.body,
                                        kind: replyTo.kind,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: controller.clearReplyTarget,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Composer — same look as cluborbit-web's ChatWindow: separate rounded-square
                      // attach/emoji buttons, a boxed text field, and mic ↔ send on the right (send
                      // takes the user's bubble colour once there's text).
                      SafeArea(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // The + button steps aside while typing so the text
                              // field gets the room (same as the web composer).
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _composerController,
                                builder: (context, value, _) {
                                  final typing = value.text.isNotEmpty;
                                  return AnimatedSize(
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeOut,
                                    child: typing
                                        ? const SizedBox.shrink()
                                        : Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: _ComposerIconButton(
                                              icon: Icons.add_rounded,
                                              onPressed: () =>
                                                  _openAttachmentSheet(
                                                    controller,
                                                  ),
                                            ),
                                          ),
                                  );
                                },
                              ),
                              _ComposerIconButton(
                                icon: Icons.emoji_emotions_outlined,
                                active: _showEmojiPickerPanel,
                                onPressed: () {
                                  FocusScope.of(context).unfocus();
                                  setState(() {
                                    _showEmojiPickerPanel =
                                        !_showEmojiPickerPanel;
                                  });
                                },
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: _ComposerIconButton.size,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: composerFocused
                                          ? const Color(
                                              0xFF38BDF8,
                                            ).withValues(alpha: 0.5)
                                          : Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _composerController,
                                          focusNode: _composerFocusNode,
                                          minLines: 1,
                                          maxLines: 5,
                                          textAlignVertical:
                                              TextAlignVertical.center,
                                          keyboardType: TextInputType.multiline,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          cursorColor: const Color(0xFF38BDF8),
                                          style: TextStyle(
                                            fontFamily:
                                                _appearance.messageFontFamily,
                                            fontSize: 14,
                                            height: 1.35,
                                            color: const Color(0xFFF1F5F9),
                                          ),
                                          decoration: InputDecoration(
                                            hintText: _editTargetMessage != null
                                                ? 'Edit message...'
                                                : 'Message...',
                                            isDense: true,
                                            filled: false,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 9,
                                                ),
                                            hintStyle: TextStyle(
                                              fontFamily:
                                                  _appearance.messageFontFamily,
                                              fontSize: 14,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                          onChanged: (value) {
                                            _onComposerChanged(
                                              controller,
                                              value,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Right-hand slot, outside the text box: the mic while empty,
                              // send once there's text (a check when editing), in the user's
                              // bubble colour.
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _composerController,
                                builder: (context, value, _) {
                                  final editing = _editTargetMessage != null;
                                  if (value.text.isEmpty && !editing) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _ComposerIconButton(
                                          icon: Icons.photo_camera_outlined,
                                          onPressed: () =>
                                              _openCameraCapture(controller),
                                        ),
                                        const SizedBox(width: 6),
                                        _ComposerIconButton(
                                          icon: Icons.mic_rounded,
                                          onPressed: () =>
                                              _openVoiceRecorderDialog(
                                                controller,
                                              ),
                                        ),
                                      ],
                                    );
                                  }
                                  return _ComposerIconButton(
                                    icon: editing
                                        ? Icons.check_rounded
                                        : Icons.send_rounded,
                                    fillColor: _appearance.myBubbleColor,
                                    iconColor: Colors.white,
                                    onPressed: value.text.trim().isEmpty
                                        ? null
                                        : () async {
                                            final text =
                                                _composerController.text;
                                            final editTarget =
                                                _editTargetMessage;
                                            _composerController.clear();
                                            _stopTyping(controller);
                                            if (editTarget != null) {
                                              setState(() {
                                                _editTargetMessage = null;
                                              });
                                              await controller.editMessage(
                                                eventId: editTarget.id,
                                                updatedText: text,
                                              );
                                            } else {
                                              await controller.sendText(text);
                                            }
                                          },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: _showEmojiPickerPanel
                            ? SizedBox(
                                height: 320,
                                child: EmojiPicker(
                                  textEditingController: _composerController,
                                  onEmojiSelected: (category, emoji) {
                                    _onComposerChanged(
                                      controller,
                                      _composerController.text,
                                    );
                                  },
                                  onBackspacePressed: () {
                                    _onComposerChanged(
                                      controller,
                                      _composerController.text,
                                    );
                                  },
                                  config: const Config(),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    right: 12,
                    bottom: scrollFabBottom,
                    child: AnimatedScale(
                      scale: _showScrollToLatestFab ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      child: IgnorePointer(
                        ignoring: !_showScrollToLatestFab,
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: FloatingActionButton(
                            mini: true,
                            heroTag: 'scrollToLatestFab',
                            elevation: 2,
                            backgroundColor:
                                PlayerUiSignalTheme.primaryDarkColor,
                            foregroundColor: PlayerUiSignalTheme.secondaryColor,
                            onPressed: _scrollToLatestMessages,
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 18,
                            ),
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
      },
    );
  }

  Widget _buildInlineReactionHover({
    required ChatController controller,
    required ChatMessage message,
    required bool mine,
  }) {
    const emojis = [
      '\u{1F44D}',
      '\u{2764}\u{FE0F}',
      '\u{1F602}',
      '\u{1F62E}',
      '\u{1F622}',
      '\u{1F64F}',
    ];
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.fromLTRB(mine ? 56 : 36, 4, mine ? 36 : 56, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        decoration: BoxDecoration(
          color: PlayerUiSignalTheme.secondaryColor.withAlpha(230),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(26)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...emojis.map(
                (emoji) => InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    _setLocalReaction(message.id, emoji);
                    _clearSelectedMessages();
                    await controller.sendReaction(message.id, emoji);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: _isHeartReaction(emoji)
                        ? const Icon(
                            Icons.favorite,
                            color: Colors.redAccent,
                            size: 24,
                          )
                        : Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _openMoreReactionsSheet(
                  context,
                  controller: controller,
                  message: message,
                ),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, size: 20, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleWithReactionOverlay({
    required ChatMessage message,
    required Widget bubble,
    required ChatController controller,
  }) {
    // Merge server-side reactions with any local optimistic reaction.
    final reactionEventsRaw = message.metadata['reactionEvents'];
    final serverEvents = reactionEventsRaw is List
        ? reactionEventsRaw
              .whereType<Map<String, dynamic>>()
              .where(
                (e) =>
                    !(e['key'] ?? '').toString().startsWith('poll:') &&
                    (e['key'] ?? '').toString().isNotEmpty,
              )
              .toList()
        : <Map<String, dynamic>>[];

    final localReaction = _localMessageReactions[message.id];
    final localUserId = controller.matrixUserId;
    final hasLocalInServer =
        localUserId.isNotEmpty &&
        serverEvents.any((e) => e['senderId'] == localUserId);
    final allEvents = [
      ...serverEvents,
      if (localReaction != null &&
          localReaction.isNotEmpty &&
          !hasLocalInServer)
        <String, dynamic>{'senderId': localUserId, 'key': localReaction},
    ];

    if (allEvents.isEmpty) {
      return bubble;
    }

    // Build emoji summary: distinct emojis with counts.
    final emojiCounts = <String, int>{};
    for (final e in allEvents) {
      final key = (e['key'] ?? '').toString();
      if (key.isNotEmpty) emojiCounts[key] = (emojiCounts[key] ?? 0) + 1;
    }
    final totalCount = allEvents.length;

    // Find the current user's own reaction event (if any) so it can be removed.
    final myReactionEvent = localUserId.isNotEmpty
        ? allEvents.firstWhere(
            (e) => e['senderId'] == localUserId,
            orElse: () => <String, dynamic>{},
          )
        : <String, dynamic>{};
    final myReactionEventId = (myReactionEvent['eventId'] ?? '').toString();
    final iHaveReacted = myReactionEvent.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          Positioned(
            left: 10,
            bottom: -6,
            child: GestureDetector(
              onTap: () => _showReactionDetailSheet(
                context,
                message,
                controller,
                allEvents,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: PlayerUiSignalTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: PlayerUiSignalTheme.primaryDarkColor.withAlpha(130),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...emojiCounts.entries.take(3).map((entry) {
                      final emoji = entry.key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 1),
                        child: _isHeartReaction(emoji)
                            ? const Icon(
                                Icons.favorite,
                                color: Colors.redAccent,
                                size: 11,
                              )
                            : Text(emoji, style: const TextStyle(fontSize: 11)),
                      );
                    }),
                    if (totalCount > 1)
                      Text(
                        ' $totalCount',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReactionDetailSheet(
    BuildContext context,
    ChatMessage message,
    ChatController controller,
    List<Map<String, dynamic>> allEvents,
  ) async {
    final participantsById = <String, ChatParticipant>{
      for (final p in controller.participants) p.userId: p,
    };
    // Group by emoji.
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final e in allEvents) {
      final key = (e['key'] ?? '').toString();
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(e);
    }
    if (grouped.isEmpty) return;
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.30,
        minChildSize: 0.20,
        maxChildSize: 0.75,
        expand: false,
        snap: true,
        snapSizes: const [0.30, 0.75],
        builder: (sheetContext, scrollController) => _ReactionDetailSheet(
          grouped: grouped,
          participantsById: participantsById,
          myUserId: controller.matrixUserId,
          isHeartReaction: _isHeartReaction,
          scrollController: scrollController,
          onRemoveReaction: (reactionEventId) {
            setState(() => _localMessageReactions.remove(message.id));
            controller.removeReaction(reactionEventId);
          },
        ),
      ),
    );
  }

  void _setLocalReaction(String messageId, String emoji) {
    setState(() {
      _localMessageReactions[messageId] = emoji;
    });
  }

  Future<void> _openMoreReactionsSheet(
    BuildContext context, {
    required ChatController controller,
    required ChatMessage message,
  }) async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            height: 320,
            decoration: const BoxDecoration(
              color: PlayerUiSignalTheme.secondaryColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: EmojiPicker(
              textEditingController: TextEditingController(),
              onEmojiSelected: (category, emoji) async {
                Navigator.of(sheetContext).pop();
                _setLocalReaction(message.id, emoji.emoji);
                _clearSelectedMessages();
                await controller.sendReaction(message.id, emoji.emoji);
              },
              config: const Config(),
            ),
          ),
        );
      },
    );
  }

  /// Preview + caption step before sending photos, or a camera video when [videoPath] is set.
  /// Returns the caption, or null if cancelled.
  Future<String?> _showImageBatchComposerSheet(
    BuildContext context, {
    List<PickedImageMedia> images = const [],
    String? videoPath,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ImageBatchComposerSheet(
        images: images,
        videoPath: videoPath,
        initialCaption: _composerController.text.trim(),
        sendColor: _appearance.myBubbleColor,
        fontFamily: _appearance.messageFontFamily,
      ),
    );
  }

  Future<void> _openAttachmentSheet(ChatController controller) async {
    FocusScope.of(context).unfocus();
    final action = await showModalBottomSheet<_AttachmentAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AttachmentActionSheet(
        onSelect: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _AttachmentAction.pictures:
        await _handlePictureAttachment(controller);
        break;
      case _AttachmentAction.documents:
        await _handleDocumentAttachment(controller);
        break;
      case _AttachmentAction.location:
        await _handleStructuredAttachment(
          controller,
          composer: () => _showLocationComposerSheet(context),
        );
        break;
      case _AttachmentAction.contact:
        await _handleStructuredAttachment(
          controller,
          composer: () => _showContactComposerSheet(context),
        );
        break;
      case _AttachmentAction.poll:
        await _handleStructuredAttachment(
          controller,
          composer: () => _showPollComposerSheet(context),
        );
        break;
    }
  }

  Future<void> _handlePictureAttachment(ChatController controller) async {
    final source = await showModalBottomSheet<_PictureSourceAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PictureSourceSheet(
        onSelect: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (!mounted || source == null) {
      return;
    }

    final selected = source == _PictureSourceAction.gallery
        ? await controller.pickImagesForBatch()
        : await controller.pickImagesForBatchFromFiles();
    if (selected.isEmpty || !mounted) {
      return;
    }

    final caption = await _showImageBatchComposerSheet(
      context,
      images: selected,
    );
    if (caption == null || !mounted) {
      return;
    }

    final sent = await controller.sendPickedImages(
      images: selected,
      caption: caption,
    );
    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send images. Please try again.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    _composerController.clear();
    _stopTyping(controller);
  }

  Future<void> _handleDocumentAttachment(ChatController controller) async {
    final sent = await controller.pickAndSendDocument();
    if (sent && mounted) {
      _composerController.clear();
      _stopTyping(controller);
    }
  }

  /// The composer's camera button: take a photo or record a video and send it to the room.
  Future<void> _openCameraCapture(ChatController controller) async {
    FocusScope.of(context).unfocus();
    final action = await showModalBottomSheet<_CameraCaptureAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CameraCaptureSheet(
        onSelect: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (!mounted || action == null) return;

    final picker = ImagePicker();
    try {
      if (action == _CameraCaptureAction.photo) {
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 84,
          maxWidth: 1920,
          maxHeight: 1920,
        );
        if (photo == null || !mounted) return;
        final images = [
          PickedImageMedia(
            bytes: await photo.readAsBytes(),
            filename: photo.name.isNotEmpty ? photo.name : 'photo.jpg',
          ),
        ];
        if (!mounted) return;
        // Same preview + caption step as photos picked from the gallery.
        final caption = await _showImageBatchComposerSheet(
          context,
          images: images,
        );
        if (caption == null || !mounted) return;
        final sent = await controller.sendPickedImages(
          images: images,
          caption: caption,
        );
        if (!mounted) return;
        if (!sent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send photo. Please try again.')),
          );
          return;
        }
      } else {
        final video = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 2),
        );
        if (video == null || !mounted) return;
        // Same preview + caption step as photos.
        final caption = await _showImageBatchComposerSheet(
          context,
          videoPath: video.path,
        );
        if (caption == null || !mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Sending video...'),
            duration: Duration(seconds: 3),
          ),
        );
        final sent = await controller.sendCapturedVideo(
          path: video.path,
          caption: caption.trim().isEmpty ? null : caption.trim(),
        );
        if (!mounted) return;
        if (!sent) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Could not send video. Please try again.')),
          );
          return;
        }
      }
      _composerController.clear();
      _stopTyping(controller);
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'camera_access_denied'
                ? 'Camera access is turned off for ClubOrbit. Allow it in your phone settings.'
                : 'Could not open the camera.',
          ),
        ),
      );
    }
  }

  Future<void> _openVoiceRecorderDialog(ChatController controller) async {
    final result = await showDialog<_VoiceRecordingPayload>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _VoiceRecorderDialog(),
    );
    if (!mounted || result == null) {
      return;
    }

    try {
      final bytes = await File(result.path).readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recorded audio is empty.')),
          );
        }
        return;
      }

      final sent = await controller.sendMedia(
        bytes: bytes,
        filename: result.filename,
        kind: MessageKind.text,
      );
      if (sent && mounted) {
        _composerController.clear();
        _stopTyping(controller);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send voice recording.')),
        );
      }
    }
  }

  Future<void> _handleStructuredAttachment(
    ChatController controller, {
    required Future<String?> Function() composer,
  }) async {
    final message = await composer();
    if (message == null || message.trim().isEmpty || !mounted) {
      return;
    }

    _composerController.clear();
    _stopTyping(controller);
    try {
      await controller.sendText(message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<String?> _showLocationComposerSheet(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _LocationAttachmentSheet(),
    );
  }

  Future<String?> _showContactComposerSheet(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _ContactAttachmentSheet(),
    );
  }

  Future<String?> _showPollComposerSheet(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _PollAttachmentSheet(),
    );
  }

  Future<ChatThread?> _pickForwardTarget(
    BuildContext context,
    ChatController controller,
  ) async {
    if (controller.threads.isEmpty) {
      await controller.loadThreads();
    }
    if (!context.mounted) {
      return null;
    }

    return Navigator.of(context).push<ChatThread>(
      MaterialPageRoute(
        builder: (_) => _ForwardChatPickerScreen(
          threads: controller.threads,
          activeRoomId: controller.activeRoomId,
        ),
      ),
    );
  }

  // Emoji picker is rendered inline at the bottom of the screen so chat and
  // composer stay visible above it while selecting emojis.
}

/// A cluborbit-web style composer button: a small rounded square with a faint fill and border
/// (or a solid fill, for send), matching ChatWindow.jsx's 32px buttons at a touch-friendly size.
class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.onPressed,
    this.fillColor,
    this.iconColor,
    this.active = false,
  });

  static const double size = 38;

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? fillColor;
  final Color? iconColor;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final solid = fillColor != null;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: solid
            ? fillColor
            : Colors.white.withValues(alpha: active ? 0.12 : 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: solid
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: 20,
              color: iconColor ?? const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceRecordingPayload {
  const _VoiceRecordingPayload({required this.path, required this.filename});

  final String path;
  final String filename;
}

class _VoiceRecorderDialog extends StatefulWidget {
  const _VoiceRecorderDialog();

  @override
  State<_VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<_VoiceRecorderDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _waveTimer;
  DateTime? _startedAt;
  bool _isRecording = false;
  bool _busy = false;
  List<double> _bars = List<double>.filled(20, 0.18);

  String get _elapsedLabel {
    if (_startedAt == null) {
      return '00:00';
    }
    final elapsed = DateTime.now().difference(_startedAt!);
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    if (_isRecording) {
      unawaited(_recorder.stop());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_busy || _isRecording) {
      return;
    }
    setState(() => _busy = true);
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required.')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${tempDir.path}/voice_$stamp.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
        ),
        path: path,
      );

      _startedAt = DateTime.now();
      _waveTimer?.cancel();
      _waveTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || !_isRecording) {
          return;
        }
        final elapsedMs = DateTime.now().difference(_startedAt!).inMilliseconds;
        final phase = elapsedMs / 180.0;
        setState(() {
          _bars = List<double>.generate(
            20,
            (i) => 0.16 + (sin(phase + (i * 0.52)).abs() * 0.84),
          );
        });
      });

      if (mounted) {
        setState(() => _isRecording = true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (_isRecording) {
      await _recorder.stop();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _stopAndSend() async {
    if (_busy || !_isRecording) {
      return;
    }
    setState(() => _busy = true);
    try {
      final path = await _recorder.stop();
      _waveTimer?.cancel();
      if (mounted) {
        setState(() => _isRecording = false);
      }
      if ((path ?? '').trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No recording captured.')),
          );
        }
        return;
      }
      if (mounted) {
        Navigator.of(context).pop(
          _VoiceRecordingPayload(
            path: path!.trim(),
            filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF162739),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Voice recording',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _cancelRecording,
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(24),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(24)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _bars
                  .map(
                    (value) => Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          height: 8 + (value * 34),
                          width: 4,
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.redAccent
                                : Colors.white38,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _elapsedLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _cancelRecording,
          child: const Text('Cancel'),
        ),
        if (!_isRecording)
          FilledButton.icon(
            onPressed: _busy ? null : _startRecording,
            icon: const Icon(Icons.mic),
            label: const Text('Start'),
          )
        else
          FilledButton.icon(
            onPressed: _busy ? null : _stopAndSend,
            icon: const Icon(Icons.stop),
            label: const Text('Stop & Send'),
          ),
      ],
    );
  }
}

class _ForwardChatPickerScreen extends StatefulWidget {
  const _ForwardChatPickerScreen({
    required this.threads,
    required this.activeRoomId,
  });

  final List<ChatThread> threads;
  final String? activeRoomId;

  @override
  State<_ForwardChatPickerScreen> createState() =>
      _ForwardChatPickerScreenState();
}

class _ForwardChatPickerScreenState extends State<_ForwardChatPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedRoomId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatThread> get _filteredThreads {
    final normalized = _query.trim().toLowerCase();
    final candidates = widget.threads
        .where((thread) => thread.id != widget.activeRoomId)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return candidates;
    }
    return candidates
        .where(
          (thread) =>
              thread.title.toLowerCase().contains(normalized) ||
              (thread.lastMessage ?? '').toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  String _initialsFromTitle(String title) {
    final parts = title
        .trim()
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return '?';
    }
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final threads = _filteredThreads;
    return Scaffold(
      backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
      appBar: AppBar(
        backgroundColor: PlayerUiSignalTheme.secondaryColor,
        titleSpacing: 20,
        title: const Text(
          'Forward message',
          style: TextStyle(color: PlayerUiSignalTheme.primaryDarkColor),
        ),
        iconTheme: const IconThemeData(
          color: PlayerUiSignalTheme.primaryDarkColor,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
              cursorColor: Colors.white,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search chats',
                hintStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: PlayerUiSignalTheme.secondaryColor.withAlpha(180),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: threads.isEmpty
                ? const Center(
                    child: Text(
                      'No chats found',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : ListView.builder(
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      final selected = _selectedRoomId == thread.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedRoomId = thread.id;
                          });
                        },
                        leading: _AvatarThumb(
                          imageUrl: thread.avatarUrl,
                          initials: _initialsFromTitle(thread.title),
                          size: 34,
                          backgroundColor:
                              PlayerUiSignalTheme.mobileSearchColor,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                thread.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            if (thread.unreadCount > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: PlayerUiSignalTheme.primaryDarkColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  thread.unreadCount > 99
                                      ? '99+'
                                      : thread.unreadCount.toString(),
                                  style: const TextStyle(
                                    color: PlayerUiSignalTheme.secondaryColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: (thread.lastMessage ?? '').isEmpty
                            ? null
                            : Text(
                                thread.lastMessage!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                        trailing: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? PlayerUiSignalTheme.primaryDarkColor
                              : Colors.white70,
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedRoomId == null
                      ? null
                      : () => Navigator.of(context).pop(
                          widget.threads.firstWhere(
                            (thread) => thread.id == _selectedRoomId,
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                    foregroundColor: PlayerUiSignalTheme.secondaryColor,
                  ),
                  child: const Text('Forward'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallSessionScreen extends StatefulWidget {
  const _CallSessionScreen({required this.chatTitle, required this.isVideo});

  final String chatTitle;
  final bool isVideo;

  @override
  State<_CallSessionScreen> createState() => _CallSessionScreenState();
}

class _CallSessionScreenState extends State<_CallSessionScreen> {
  ChatController? _controller;
  StreamSubscription<ChatCallSnapshot>? _callSub;
  StreamSubscription<void>? _callMediaSub;
  ChatCallSnapshot _snapshot = const ChatCallSnapshot.idle();
  DateTime? _connectedAt;
  Timer? _ticker;
  bool _bootstrapped = false;
  bool _poppingAfterEnd = false;
  String? _startError;

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
    if (_bootstrapped) return;
    _bootstrapped = true;
    _controller = context.read<ChatController>();
    _snapshot = _controller!.callSnapshot;
    _callSub = _controller!.callUpdates.listen(_onCallSnapshot);
    _callMediaSub = _controller!.callMediaUpdates.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    unawaited(_startCall());
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _callMediaSub?.cancel();
    _ticker?.cancel();
    if (_snapshot.hasLiveCall) {
      unawaited(_controller?.hangupCall());
    }
    _controller?.resetCallState();
    super.dispose();
  }

  String get _elapsed {
    final connectedAt = _connectedAt;
    if (connectedAt == null) {
      return '00:00';
    }
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
        return _snapshot.isIncoming ? 'Incoming call' : 'Ringing...';
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

  Future<void> _startCall() async {
    try {
      await _controller!.startCall(isVideo: widget.isVideo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _startError = e.toString();
      });
    }
  }

  void _onCallSnapshot(ChatCallSnapshot snapshot) {
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      if (snapshot.phase == ChatCallPhase.connected && _connectedAt == null) {
        _connectedAt = DateTime.now();
      }
    });

    if ((snapshot.phase == ChatCallPhase.ended ||
            snapshot.phase == ChatCallPhase.error) &&
        !_poppingAfterEnd) {
      _poppingAfterEnd = true;
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
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
                          _snapshot.remoteDisplayName ?? widget.chatTitle,
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
                          child: const Icon(
                            Icons.call,
                            size: 42,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.chatTitle,
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
                        if (_startError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _startError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        if ((_snapshot.remoteUserId ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _snapshot.remoteUserId!,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
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
          if (_startError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _startError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
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

class _ChatCustomizationScreen extends StatefulWidget {
  const _ChatCustomizationScreen({required this.initial});

  final _ChatAppearance initial;

  @override
  State<_ChatCustomizationScreen> createState() =>
      _ChatCustomizationScreenState();
}

class _ChatCustomizationScreenState extends State<_ChatCustomizationScreen> {
  static const List<Color> _palette = <Color>[
    Color(0xFF2B6DE9),
    Color(0xFF1B2737),
    Color(0xFF0F9D58),
    Color(0xFFD14836),
    Color(0xFF7B1FA2),
    Color(0xFF0097A7),
    Color(0xFF5D4037),
    Colors.black,
    Colors.white,
    Color(0xFFFF0000),
    Color(0xFFFF5A00),
    Color(0xFFFFB000),
    Color(0xFFFFE600),
    Color(0xFF7ED321),
    Color(0xFF00C853),
    Color(0xFF00B8D4),
    Color(0xFF2979FF),
    Color(0xFF651FFF),
    Color(0xFFD500F9),
  ];

  static const List<String> _fonts = <String>[
    'Poppins',
    'Roboto',
    'sans-serif',
    'monospace',
    'serif',
  ];

  static const List<String> _backgrounds = <String>[
    'https://singlecolorimage.com/get/0f172a/1200x2000',
    'https://singlecolorimage.com/get/f8fafc/1200x2000',
    'https://singlecolorimage.com/get/3f4f46/1200x2000',
    'https://singlecolorimage.com/get/1f2937/1200x2000',
    'https://singlecolorimage.com/get/f5efe6/1200x2000',
    'https://images.unsplash.com/photo-1517816428104-797678c7cf0c?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1465101046530-73398c7f28ca?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1523712999610-f77fbcfc3843?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1470770903676-69b98201ea1c?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1418065460487-3e41a6c84dc5?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1473116763249-2faaef81ccda?auto=format&fit=crop&w=1200&q=80',
  ];

  late _ChatAppearance _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  Widget _buildColorSwatch({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2.2 : 1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
      appBar: AppBar(
        backgroundColor: PlayerUiSignalTheme.secondaryColor,
        title: const Text(
          'Customize chat',
          style: TextStyle(color: PlayerUiSignalTheme.primaryDarkColor),
        ),
        iconTheme: const IconThemeData(
          color: PlayerUiSignalTheme.primaryDarkColor,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_draft),
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
            'My bubble color',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            children: _palette
                .map(
                  (color) => _buildColorSwatch(
                    color: color,
                    selected:
                        _draft.myBubbleColor.toARGB32() == color.toARGB32(),
                    onTap: () => setState(
                      () => _draft = _draft.copyWith(myBubbleColor: color),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          const Text(
            'Other user bubble color',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            children: _palette
                .map(
                  (color) => _buildColorSwatch(
                    color: color,
                    selected:
                        _draft.otherBubbleColor.toARGB32() == color.toARGB32(),
                    onTap: () => setState(
                      () => _draft = _draft.copyWith(otherBubbleColor: color),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          const Text(
            'Message font',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _fonts
                .map(
                  (font) => ChoiceChip(
                    selected: _draft.messageFontFamily == font,
                    label: Text(font),
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(messageFontFamily: font),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          const Text(
            'Message font color',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            children: _palette
                .map(
                  (color) => _buildColorSwatch(
                    color: color,
                    selected:
                        _draft.messageTextColor.toARGB32() == color.toARGB32(),
                    onTap: () => setState(
                      () => _draft = _draft.copyWith(messageTextColor: color),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          const Text(
            'Chat background (online)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              GestureDetector(
                onTap: () => setState(
                  () => _draft = _draft.copyWith(clearBackground: true),
                ),
                child: Container(
                  width: 90,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _draft.backgroundImageUrl == null
                          ? Colors.white
                          : Colors.white24,
                    ),
                  ),
                  child: const Text(
                    'None',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              ..._backgrounds.map(
                (url) => GestureDetector(
                  onTap: () => setState(
                    () => _draft = _draft.copyWith(backgroundImageUrl: url),
                  ),
                  child: Container(
                    width: 90,
                    height: 64,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _draft.backgroundImageUrl == url
                            ? Colors.white
                            : Colors.white24,
                        width: _draft.backgroundImageUrl == url ? 2 : 1,
                      ),
                    ),
                    child: Image.network(url, fit: BoxFit.cover),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction detail bottom sheet
// ---------------------------------------------------------------------------

class _ReactionDetailSheet extends StatefulWidget {
  const _ReactionDetailSheet({
    required this.grouped,
    required this.participantsById,
    required this.myUserId,
    required this.isHeartReaction,
    required this.scrollController,
    required this.onRemoveReaction,
  });

  /// emoji → list of reaction event maps (each has 'senderId', 'key', 'eventId').
  final Map<String, List<Map<String, dynamic>>> grouped;
  final Map<String, ChatParticipant> participantsById;
  final String myUserId;
  final bool Function(String emoji) isHeartReaction;
  final ScrollController scrollController;

  /// Called with the reaction's eventId when the user removes their own reaction.
  final void Function(String reactionEventId) onRemoveReaction;

  @override
  State<_ReactionDetailSheet> createState() => _ReactionDetailSheetState();
}

class _ReactionDetailSheetState extends State<_ReactionDetailSheet>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _tabs; // 'All' + each distinct emoji
  // Mutable local copy so reactions can be removed in-place.
  late Map<String, List<Map<String, dynamic>>> _grouped;

  @override
  void initState() {
    super.initState();
    _grouped = {
      for (final e in widget.grouped.entries)
        e.key: List<Map<String, dynamic>>.from(e.value),
    };
    _tabs = ['All', ..._grouped.keys];
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  void _rebuildTabs() {
    final prevIndex = _tabController.index;
    final newTabs = ['All', ..._grouped.keys];
    final newIndex = prevIndex.clamp(0, (newTabs.length - 1).clamp(0, 999));
    final old = _tabController;
    _tabs = newTabs;
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: newIndex,
    );
    // Dispose old controller after creating the new one so vsync remains valid.
    old.dispose();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _eventsForTab(String tab) {
    if (tab == 'All') {
      return _grouped.values.expand((list) => list).toList();
    }
    return _grouped[tab] ?? [];
  }

  Widget _buildTabLabel(String tab) {
    if (tab == 'All') {
      final total = _grouped.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      return Text('All  $total', style: const TextStyle(fontSize: 13));
    }
    final count = _grouped[tab]?.length ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.isHeartReaction(tab)
            ? const Icon(Icons.favorite, color: Colors.redAccent, size: 18)
            : Text(tab, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 4),
        Text('$count', style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildRow(Map<String, dynamic> event) {
    final senderId = (event['senderId'] ?? '').toString();
    final participant = widget.participantsById[senderId];
    final displayName =
        participant?.displayName ??
        (senderId.isNotEmpty
            ? senderId.split(':').first.replaceFirst('@', '')
            : 'Unknown');
    final avatarUrl = participant?.avatarUrl;
    final emoji = (event['key'] ?? '').toString();
    final isMe = senderId == widget.myUserId;
    final reactionEventId = (event['eventId'] ?? '').toString();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: isMe && reactionEventId.isNotEmpty
          ? () {
              // Remove in-place from the sheet's local state.
              setState(() {
                for (final list in _grouped.values) {
                  list.removeWhere(
                    (e) => (e['eventId'] ?? '') == reactionEventId,
                  );
                }
                _grouped.removeWhere((_, list) => list.isEmpty);
                _rebuildTabs();
              });
              widget.onRemoveReaction(reactionEventId);
            }
          : null,
      trailing: isMe && reactionEventId.isNotEmpty
          ? const Icon(Icons.close, size: 16, color: Colors.white38)
          : null,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          _AvatarThumb(
            imageUrl: avatarUrl,
            initials: displayName.isNotEmpty
                ? displayName[0].toUpperCase()
                : '?',
            size: 40,
            backgroundColor: PlayerUiSignalTheme.mobileSearchColor,
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: PlayerUiSignalTheme.secondaryColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: PlayerUiSignalTheme.mobileBackgroundColor,
                  width: 1,
                ),
              ),
              child: widget.isHeartReaction(emoji)
                  ? const Icon(
                      Icons.favorite,
                      color: Colors.redAccent,
                      size: 13,
                    )
                  : Text(emoji, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
      title: Text(
        isMe ? '$displayName (You)' : displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PlayerUiSignalTheme.secondaryColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(60),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          // Tab bar
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: PlayerUiSignalTheme.primaryDarkColor,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            dividerColor: Colors.white.withAlpha(20),
            tabs: _tabs.map((tab) => Tab(child: _buildTabLabel(tab))).toList(),
          ),
          // Tab content — fills remaining height and scrolls
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((tab) {
                final events = _eventsForTab(tab);
                return ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  itemCount: events.length,
                  itemBuilder: (context, index) => _buildRow(events[index]),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
