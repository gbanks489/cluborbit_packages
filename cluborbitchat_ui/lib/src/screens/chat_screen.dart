import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_details_screen.dart';

part 'chat_widgets/chat_bubble_widgets.dart';
part 'chat_widgets/chat_avatar_thumb.dart';
part 'chat_widgets/chat_image_widgets.dart';
part 'chat_widgets/chat_attachment_sheets.dart';
part 'chat_widgets/chat_structured_cards.dart';

enum _ChatMenuAction { details, customize, mute }

enum _AttachmentAction { pictures, documents, location, contact, poll }

enum _PictureSourceAction { gallery, cloud }

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

  Timer? _typingStopTimer;
  StreamSubscription<PlayerState>? _audioPlayerStateSub;
  StreamSubscription<Duration>? _audioPositionSub;
  StreamSubscription<Duration?>? _audioDurationSub;
  bool _typingActive = false;
  bool _showEmojiPickerPanel = false;
  bool _showScrollToLatestFab = false;
  bool _audioLoading = false;
  String? _playingAudioMessageId;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  ChatMessage? _selectedMessage;
  final Map<String, String> _localMessageReactions = <String, String>{};
  final Set<String> _expandedEventClusterKeys = <String>{};
  final Map<String, _LinkPreviewData> _linkPreviewByUrl =
      <String, _LinkPreviewData>{};
  final Set<String> _linkPreviewRequestsInFlight = <String>{};
  final Set<String> _linkPreviewUnavailableUrls = <String>{};
  final Set<String> _presenceRequestsInFlight = <String>{};
  ChatController? _controllerRef;
  late _ChatAppearance _appearance;
  String? _appearancePreferenceKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ChatController>();
    _controllerRef ??= controller;
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

  Future<void> _loadPresence(ChatController controller, String userId) async {
    try {
      await controller.getUserPresence(userId);
    } catch (_) {
      // Default-offline UI is sufficient if presence lookup fails.
    } finally {
      _presenceRequestsInFlight.remove(userId);
    }
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _controllerRef?.setTyping(false);
    _audioPlayerStateSub?.cancel();
    _audioPositionSub?.cancel();
    _audioDurationSub?.cancel();
    unawaited(_audioPlayer.dispose());
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

  bool _messageHasServerAck(ChatMessage message) {
    final stage = (message.metadata['sendStage'] ?? 'sent').toString();
    return stage != 'local' && stage != 'failed';
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
      if (message.metadata['isForwarded'] == true) {
        continue;
      }
      if (message.isEdited) {
        events.add(
          _TimelineEventItem(
            icon: Icons.edit_outlined,
            label: 'Message edited',
            time: message.createdAt,
          ),
        );
      }
      if (message.kind == MessageKind.video) {
        events.add(
          _TimelineEventItem(
            icon: Icons.videocam_outlined,
            label: 'Video shared',
            time: message.createdAt,
          ),
        );
      }
      if (message.kind == MessageKind.emoji) {
        events.add(
          _TimelineEventItem(
            icon: Icons.tag_faces_outlined,
            label: 'Reaction sent',
            time: message.createdAt,
          ),
        );
      }
    }
    events.sort((a, b) => a.time.compareTo(b.time));
    return events;
  }

  static const Duration _timelineEventClusterWindow = Duration(minutes: 5);

  List<_TimelineEventCluster> _clusterTimelineEvents(
    List<_TimelineEventItem> events,
  ) {
    if (events.isEmpty) {
      return const <_TimelineEventCluster>[];
    }

    final clusters = <_TimelineEventCluster>[];
    var currentItems = <_TimelineEventItem>[events.first];

    for (final event in events.skip(1)) {
      final previous = currentItems.last;
      if (event.time.difference(previous.time) <= _timelineEventClusterWindow) {
        currentItems.add(event);
        continue;
      }
      clusters.add(_TimelineEventCluster(items: currentItems));
      currentItems = <_TimelineEventItem>[event];
    }

    clusters.add(_TimelineEventCluster(items: currentItems));
    return clusters;
  }

  List<_ChatTimelineEntry> _buildTimelineEntries({
    required List<ChatMessage> visibleMessages,
    required List<_TimelineEventCluster> eventClusters,
  }) {
    final entries = <_ChatTimelineEntry>[];
    var clusterIndex = 0;

    for (
      var messageIndex = 0;
      messageIndex < visibleMessages.length;
      messageIndex++
    ) {
      final message = visibleMessages[messageIndex];
      while (clusterIndex < eventClusters.length &&
          !eventClusters[clusterIndex].latestEvent.time.isAfter(
            message.createdAt,
          )) {
        entries.add(
          _ChatTimelineEntry.eventCluster(eventClusters[clusterIndex]),
        );
        clusterIndex++;
      }
      entries.add(_ChatTimelineEntry.message(message, messageIndex));
    }

    while (clusterIndex < eventClusters.length) {
      entries.add(_ChatTimelineEntry.eventCluster(eventClusters[clusterIndex]));
      clusterIndex++;
    }

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
      await _audioPlayer.setUrl(url);
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

  Future<void> _openDocumentExternally(ChatMessage message) async {
    final url = _mediaUrlFor(message);
    if (url == null) {
      return;
    }
    final uri = Uri.tryParse(url);
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
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  bool _isImageClusterPair(ChatMessage a, ChatMessage b) {
    if (a.kind != MessageKind.image || b.kind != MessageKind.image) {
      return false;
    }
    if (a.senderId != b.senderId) {
      return false;
    }
    if (_mediaUrlFor(a) == null || _mediaUrlFor(b) == null) {
      return false;
    }
    final diffSeconds = a.createdAt.difference(b.createdAt).inSeconds.abs();
    return diffSeconds <= 45;
  }

  List<ChatMessage> _collectForwardBatch(
    ChatMessage selected,
    List<ChatMessage> allMessages,
  ) {
    if (selected.kind != MessageKind.image) {
      return <ChatMessage>[selected];
    }

    final index = allMessages.indexWhere((m) => m.id == selected.id);
    if (index < 0) {
      return <ChatMessage>[selected];
    }

    var start = index;
    while (start > 0 &&
        _isImageClusterPair(allMessages[start - 1], allMessages[start])) {
      start--;
    }

    var end = index;
    while (end < allMessages.length - 1 &&
        _isImageClusterPair(allMessages[end], allMessages[end + 1])) {
      end++;
    }

    return allMessages.sublist(start, end + 1);
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

    return GestureDetector(
      onLongPress: () => setState(() => _selectedMessage = message),
      child: ConstrainedBox(
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
                            _structuredMessageLabel(
                              _StructuredMessageType.poll,
                            ),
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
    final replyThumb =
        replyThumbRaw is String && replyThumbRaw.trim().isNotEmpty
        ? replyThumbRaw.trim()
        : null;
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
                    child: CachedNetworkImage(
                      imageUrl: replyThumb,
                      fit: BoxFit.cover,
                      errorWidget: (context, error, stackTrace) => const Icon(
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
    List<String> imageUrls,
    int initialIndex,
  ) {
    if (imageUrls.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ImageSlideshowScreen(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
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
    final fullUrls = imageGroup
        .map(_mediaUrlFor)
        .whereType<String>()
        .toList(growable: false);
    final thumbUrls = imageGroup
        .map((m) => _thumbnailUrlFor(m) ?? _mediaUrlFor(m))
        .whereType<String>()
        .toList(growable: false);
    final caption = imageGroup
        .map((m) => (m.metadata['caption'] as String?) ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    return GestureDetector(
      onLongPress: () => setState(() => _selectedMessage = message),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          decoration: BoxDecoration(
            color: mine
                ? _appearance.myBubbleColor
                : _appearance.otherBubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 5),
              bottomRight: Radius.circular(mine ? 5 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.metadata['isForwarded'] == true)
                _buildForwardedIndicator(),
              _ImageCollageGrid(
                imageUrls: thumbUrls,
                onOpenAt: (index) {
                  _openImageViewer(context, fullUrls, index);
                },
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
                  padding: EdgeInsets.only(top: caption.isNotEmpty ? 4 : 8),
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
                            padding: EdgeInsets.only(
                              left: showInsideTime ? 4 : 0,
                            ),
                            child: _SignalReceiptTicks(
                              isSent: _messageHasServerAck(message),
                              showReceivedCircle: _messageShowsReceivedCircle(
                                message,
                              ),
                              isRead: effectiveReadCount > 0,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, controller, _) {
        final isChatMuted = _MutedChatStore.isMuted(
          _chatPreferenceKey(controller),
        );
        final messages = controller.messages;
        final visibleMessages = messages
            .where((message) => !_isTimelineOnlyMessage(message))
            .toList(growable: false);
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
        final eventClusters = _clusterTimelineEvents(events);
        final timelineEntries = _buildTimelineEntries(
          visibleMessages: visibleMessages,
          eventClusters: eventClusters,
        );
        final scrollFabBottom =
            (_showEmojiPickerPanel ? 386.0 : 66.0) +
            (replyTo != null ? 72.0 : 0.0);

        return PopScope<void>(
          canPop: !_showEmojiPickerPanel && _selectedMessage == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              if (_selectedMessage != null) {
                setState(() {
                  _selectedMessage = null;
                });
              } else if (_showEmojiPickerPanel) {
                setState(() {
                  _showEmojiPickerPanel = false;
                });
              }
            }
          },
          child: Scaffold(
            backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
            appBar: _selectedMessage != null
                ? AppBar(
                    backgroundColor: PlayerUiSignalTheme.secondaryColor,
                    automaticallyImplyLeading: false,
                    leadingWidth: 48,
                    leading: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: PlayerUiSignalTheme.primaryDarkColor,
                      ),
                      tooltip: 'Deselect',
                      onPressed: () => setState(() => _selectedMessage = null),
                    ),
                    title: const Text(
                      '1 selected',
                      style: TextStyle(
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(
                          Icons.reply,
                          color: PlayerUiSignalTheme.primaryDarkColor,
                        ),
                        tooltip: 'Reply',
                        onPressed: () {
                          controller.setReplyTarget(_selectedMessage!);
                          setState(() => _selectedMessage = null);
                          _composerFocusNode.requestFocus();
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: PlayerUiSignalTheme.primaryDarkColor,
                        ),
                        tooltip: 'Delete',
                        onPressed: () async {
                          final msg = _selectedMessage!;
                          setState(() => _selectedMessage = null);
                          await controller.deleteMessage(msg.id);
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.forward,
                          color: PlayerUiSignalTheme.primaryDarkColor,
                        ),
                        tooltip: 'Forward',
                        onPressed: () async {
                          final msg = _selectedMessage!;
                          final batch = _collectForwardBatch(
                            msg,
                            controller.messages,
                          );
                          setState(() => _selectedMessage = null);
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
                    titleSpacing: 8,
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
                                participant?.displayName ?? message.senderName;
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
                            final previewUrl = _extractFirstPreviewUrl(message);
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
                              final groupedWithNewer =
                                  newerMessage != null &&
                                  _isImageClusterPair(message, newerMessage);
                              if (groupedWithNewer) {
                                return const SizedBox.shrink();
                              }

                              final imageGroup = <ChatMessage>[message];
                              var cursor = messageIndex - 1;
                              while (cursor >= 0) {
                                final candidate = visibleMessages[cursor];
                                final anchor = imageGroup.last;
                                if (_isImageClusterPair(candidate, anchor)) {
                                  imageGroup.add(candidate);
                                  cursor--;
                                  continue;
                                }
                                break;
                              }

                              final previousVisibleMessage = cursor >= 0
                                  ? visibleMessages[cursor]
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
                                direction: DismissDirection.horizontal,
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
                                            previousTime: previousVisibleMessage
                                                ?.createdAt,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    row,
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
                                      child: _selectedMessage?.id == message.id
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
                                  );

                              return Dismissible(
                                key: ValueKey(
                                  '${message.id}_${message.createdAt.millisecondsSinceEpoch}',
                                ),
                                direction: DismissDirection.horizontal,
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
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(child: pollWithReaction),
                                      ],
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
                                      child: _selectedMessage?.id == message.id
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
                            }
                            final bubble = GestureDetector(
                              onLongPress: () =>
                                  setState(() => _selectedMessage = message),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.74,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
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
                                      else if (message.metadata['isDeleted'] ==
                                          true)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(
                                              Icons.block,
                                              size: 14,
                                              color: Colors.white38,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Message deleted',
                                              style: TextStyle(
                                                color: Colors.white38,
                                                fontStyle: FontStyle.italic,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        )
                                      else if (_isAudioAttachment(message))
                                        _buildAudioMessageContent(
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
                                                  message.kind ==
                                                      MessageKind.emoji
                                                  ? 28
                                                  : 16,
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
                              ),
                            );
                            final bubbleWithReaction =
                                _buildBubbleWithReactionOverlay(
                                  message: message,
                                  bubble: bubble,
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
                                            backgroundColor: PlayerUiSignalTheme
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
                              direction: DismissDirection.horizontal,
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
                                          previousTime: olderMessage?.createdAt,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white54,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  row,
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
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
                                    child: _selectedMessage?.id == message.id
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
                      if (replyTo != null)
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
                                  _thumbnailUrlFor(replyTo) != null)
                                Container(
                                  width: 46,
                                  height: 46,
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.black26,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: CachedNetworkImage(
                                    imageUrl: _thumbnailUrlFor(replyTo)!,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, error, stackTrace) =>
                                        const Icon(
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
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 38),
                            decoration: BoxDecoration(
                              color: PlayerUiSignalTheme.secondaryColor
                                  .withAlpha(190),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: PlayerUiSignalTheme.primaryDarkColor
                                    .withAlpha(170),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 38,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      FocusScope.of(context).unfocus();
                                      setState(() {
                                        _showEmojiPickerPanel =
                                            !_showEmojiPickerPanel;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.emoji_emotions_outlined,
                                      size: 20,
                                      color:
                                          PlayerUiSignalTheme.primaryDarkColor,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 38,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _openAttachmentSheet(controller),
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 20,
                                      color:
                                          PlayerUiSignalTheme.primaryDarkColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child:
                                      CommonWidgets.commonTextFieldForLoginSignUP(
                                        context: context,
                                        controller: _composerController,
                                        focusNode: _composerFocusNode,
                                        minLines: 1,
                                        maxLines: 1,
                                        maxHeight: 36,
                                        hintText: 'Type message',
                                        filled: false,
                                        wantBorder: false,
                                        style: TextStyle(
                                          fontFamily:
                                              _appearance.messageFontFamily,
                                          fontSize: 14,
                                          color: _appearance.messageTextColor,
                                        ),
                                        hintStyle: TextStyle(
                                          fontFamily:
                                              _appearance.messageFontFamily,
                                          fontSize: 12,
                                          color: _appearance.messageTextColor
                                              .withAlpha(170),
                                        ),
                                        onChanged: (value) {
                                          _onComposerChanged(controller, value);
                                        },
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                      ),
                                ),
                                SizedBox(
                                  width: 38,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _openVoiceRecorderDialog(controller),
                                    icon: const Icon(
                                      Icons.mic_none_rounded,
                                      size: 20,
                                      color:
                                          PlayerUiSignalTheme.primaryDarkColor,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 38,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () async {
                                      final text = _composerController.text;
                                      _composerController.clear();
                                      _stopTyping(controller);
                                      await controller.sendText(text);
                                    },
                                    icon: const Icon(
                                      Icons.send,
                                      size: 20,
                                      color:
                                          PlayerUiSignalTheme.primaryDarkColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                    setState(() => _selectedMessage = null);
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
  }) {
    final reaction = _localMessageReactions[message.id];
    if (reaction == null || reaction.isEmpty) {
      return bubble;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          Positioned(
            left: 10,
            bottom: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: PlayerUiSignalTheme.secondaryColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: PlayerUiSignalTheme.primaryDarkColor.withAlpha(130),
                ),
              ),
              child: _isHeartReaction(reaction)
                  ? const Icon(
                      Icons.favorite,
                      color: Colors.redAccent,
                      size: 16,
                    )
                  : Text(reaction, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
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
                setState(() => _selectedMessage = null);
                await controller.sendReaction(message.id, emoji.emoji);
              },
              config: const Config(),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _showImageBatchComposerSheet(
    BuildContext context, {
    required List<PickedImageMedia> images,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ImageBatchComposerSheet(
        images: images,
        initialCaption: _composerController.text.trim(),
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
    if (sent && mounted) {
      _composerController.clear();
      _stopTyping(controller);
    }
  }

  Future<void> _handleDocumentAttachment(ChatController controller) async {
    final sent = await controller.pickAndSendDocument();
    if (sent && mounted) {
      _composerController.clear();
      _stopTyping(controller);
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
    await controller.sendText(message);
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
