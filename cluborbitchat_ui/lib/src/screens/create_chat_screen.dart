import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/playerchat_router.dart';

const Color _groupAvatarBackgroundColor = Color(0xFFE7EAED);
const Color _groupAvatarForegroundColor = Color(0xFFADB4BA);
const String _clubOrbitRoomsDeepLink = 'cluborbit://rooms';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final TextEditingController _dmUserController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _membersController = TextEditingController();
  final FocusNode _membersFocusNode = FocusNode();
  late ChatController _chatController;
  ChatParticipant? _selectedDmUser;
  String? _pendingSearchRetry;
  String? _pendingGroupSearchRetry;
  bool _lastMatrixConnecting = false;
  bool _creatingDirectMessage = false;
  bool _creatingGroup = false;
  Uint8List? _groupAvatarBytes;
  String? _groupAvatarFilename;
  bool _dmSearchLoading = false;
  int _dmSearchRequestId = 0;
  List<ChatParticipant> _dmSuggestions = const <ChatParticipant>[];
  bool _groupMemberSearchLoading = false;
  int _groupMemberSearchRequestId = 0;
  List<ChatParticipant> _groupMemberSuggestions = const <ChatParticipant>[];
  List<ChatParticipant> _selectedGroupMembers = const <ChatParticipant>[];
  Timer? _dmSearchDebounceTimer;
  Timer? _groupMembersDebounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatController = context.read<ChatController>();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _chatController.clearSearchState(notify: false);
    _dmSearchDebounceTimer?.cancel();
    _groupMembersDebounceTimer?.cancel();
    _dmUserController.dispose();
    _groupNameController.dispose();
    _membersController.dispose();
    _membersFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final hasSearchText = _dmUserController.text.trim().isNotEmpty;
    final hasGroupSearchText = _membersController.text.trim().isNotEmpty;
    final matrixConnecting = controller.matrixConnecting;
    final anyCreateInProgress = _creatingDirectMessage || _creatingGroup;

    if (_lastMatrixConnecting && !matrixConnecting) {
      final pendingQuery = _pendingSearchRetry;
      final currentQuery = _dmUserController.text.trim();
      if (pendingQuery != null &&
          pendingQuery.isNotEmpty &&
          pendingQuery == currentQuery) {
        _pendingSearchRetry = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _runDirectMessageSearch(currentQuery);
        });
      }

      final pendingGroupQuery = _pendingGroupSearchRetry;
      final currentGroupQuery = _membersController.text.trim();
      if (pendingGroupQuery != null &&
          pendingGroupQuery.isNotEmpty &&
          pendingGroupQuery == currentGroupQuery) {
        _pendingGroupSearchRetry = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _runGroupMemberSearch(currentGroupQuery);
        });
      }
    }
    _lastMatrixConnecting = matrixConnecting;

    return Scaffold(
      appBar: AppBar(
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
        title: const Text('New chat'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Create direct message', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            _buildDirectMessageSearchField(),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Search by display name',
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
              ),
            ),
            if (hasSearchText) ...[
              const SizedBox(height: 12),
              if (matrixConnecting)
                const ListTile(
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Syncing chats to search users...'),
                )
              else if (_dmSearchLoading)
                const ListTile(
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Searching users...'),
                )
              else if (_dmSuggestions.isEmpty)
                const ListTile(title: Text('No user matches'))
              else
                ..._dmSuggestions.map(
                  (user) => ListTile(
                    tileColor: PlayerUiSignalTheme.mobileSearchColor.withAlpha(
                      90,
                    ),
                    selected: _selectedDmUser?.userId == user.userId,
                    leading: CircleAvatar(
                      backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                      backgroundImage:
                          (user.avatarUrl != null &&
                              user.avatarUrl!.trim().isNotEmpty)
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child:
                          (user.avatarUrl == null ||
                              user.avatarUrl!.trim().isEmpty)
                          ? Text(
                              user.displayName.isEmpty
                                  ? '?'
                                  : user.displayName[0].toUpperCase(),
                              style: const TextStyle(
                                color: PlayerUiSignalTheme.secondaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    title: Text(user.displayName),
                    onTap: anyCreateInProgress
                        ? null
                        : () => unawaited(_selectDirectMessageUser(user)),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            const Divider(height: 32),
            const Text('Create group', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            _buildClubOrbitPromoTile(),
            const SizedBox(height: 14),
            Center(child: _buildGroupAvatarPicker()),
            const SizedBox(height: 12),
            CommonWidgets.commonTextFieldForLoginSignUP(
              context: context,
              controller: _groupNameController,
              hintText: 'Group name',
              labelText: 'Group Name',
            ),
            const SizedBox(height: 8),
            _buildGroupMembersField(),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Search by display name and add members to the group',
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
              ),
            ),
            if (hasGroupSearchText) ...[
              const SizedBox(height: 12),
              if (matrixConnecting)
                const ListTile(
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Syncing chats to search users...'),
                )
              else if (_groupMemberSearchLoading)
                const ListTile(
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Searching users...'),
                )
              else if (_groupMemberSuggestions.isEmpty)
                const ListTile(title: Text('No user matches'))
              else
                ..._groupMemberSuggestions.map(_buildGroupMemberSuggestionTile),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: anyCreateInProgress ? null : _handleCreateGroup,
              child: _creatingGroup
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create group'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDirectMessageUser(ChatParticipant user) async {
    if (_creatingDirectMessage || _creatingGroup) {
      return;
    }
    setState(() => _selectedDmUser = user);
    _dmUserController.text = user.displayName;
    _pendingSearchRetry = null;

    final confirmed = await _showDirectMessageSheet(user);
    if (confirmed != true || !mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    setState(() => _creatingDirectMessage = true);
    try {
      await _chatController.createDm(user.userId, roomTitle: user.displayName);
      if (!mounted) return;
      navigator.pop();
      router.pushNamed(
        PlayerChatRoutes.chat,
        extra: PlayerChatChatRouteData(
          title: user.displayName,
          avatarUrl: user.avatarUrl,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not create direct message: $e');
    } finally {
      if (mounted) {
        setState(() => _creatingDirectMessage = false);
      }
    }
  }

  void _handleDirectMessageInputChanged(String value) {
    final trimmed = value.trim();
    _dmSearchDebounceTimer?.cancel();

    if (trimmed.isEmpty) {
      setState(() {
        _selectedDmUser = null;
        _pendingSearchRetry = null;
        _dmSearchLoading = false;
        _dmSuggestions = const <ChatParticipant>[];
      });
      return;
    }

    setState(() {
      _selectedDmUser = null;
      _pendingSearchRetry = _chatController.matrixConnecting ? trimmed : null;
      _dmSearchLoading = true;
    });

    _dmSearchDebounceTimer = Timer(const Duration(milliseconds: 220), () {
      _runDirectMessageSearch(trimmed);
    });
  }

  Future<void> _runDirectMessageSearch(String query) async {
    final trimmed = query.trim();
    final requestId = ++_dmSearchRequestId;
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _dmSearchLoading = false;
        _dmSuggestions = const <ChatParticipant>[];
      });
      return;
    }

    try {
      final results = await _chatController.searchUsers(trimmed);
      if (!mounted ||
          requestId != _dmSearchRequestId ||
          _dmUserController.text.trim() != trimmed) {
        return;
      }

      setState(() {
        _pendingSearchRetry = null;
        _dmSearchLoading = false;
        _dmSuggestions = results;
      });
    } catch (_) {
      if (!mounted || requestId != _dmSearchRequestId) {
        return;
      }
      setState(() {
        _dmSearchLoading = false;
        _dmSuggestions = const <ChatParticipant>[];
      });
    }
  }

  Widget _buildGroupMembersField() {
    return _buildSearchFieldShell(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ..._selectedGroupMembers.map(_buildGroupMemberChip),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 180,
              maxWidth: MediaQuery.of(context).size.width - 108,
            ),
            child: TextField(
              controller: _membersController,
              focusNode: _membersFocusNode,
              onChanged: _handleGroupMemberInputChanged,
              cursorColor: Colors.white,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: 'Search users',
                hintStyle: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectMessageSearchField() {
    return _buildSearchFieldShell(
      child: TextField(
        controller: _dmUserController,
        onChanged: _handleDirectMessageInputChanged,
        cursorColor: Colors.white,
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: 'Search users',
          hintStyle: TextStyle(
            color: Colors.white70,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchFieldShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 2),
        color: Colors.transparent,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.search, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildClubOrbitPromoTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _creatingGroup || _creatingDirectMessage
            ? null
            : () => unawaited(_openClubOrbitRooms()),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF102744), Color(0xFF203F63)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF9CC0B), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF9CC0B).withAlpha(28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withAlpha(44)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Image.asset(
                      'assets/images/logo-icon.png',
                      package: 'cluborbit_matrix',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.travel_explore_rounded,
                          color: Color(0xFF102744),
                          size: 28,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Join a club in Club Orbit',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Open the main app to explore club rooms, clubs, and communities.',
                        style: TextStyle(
                          color: Color(0xFFD8E2EF),
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9CC0B),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: Color(0xFF0C1D36),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Open',
                        style: TextStyle(
                          color: Color(0xFF0C1D36),
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
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
    );
  }

  Widget _buildGroupMemberChip(ChatParticipant user) {
    final initials = user.displayName.isEmpty
        ? '?'
        : user.displayName[0].toUpperCase();

    return InputChip(
      avatar: CircleAvatar(
        backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
        backgroundImage:
            user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty
            ? NetworkImage(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null || user.avatarUrl!.trim().isEmpty
            ? Text(
                initials,
                style: const TextStyle(
                  color: PlayerUiSignalTheme.secondaryColor,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
      label: Text(user.displayName),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: PlayerUiSignalTheme.mobileSearchColor.withAlpha(110),
      side: const BorderSide(color: PlayerUiSignalTheme.primaryDarkColor),
      deleteIconColor: Colors.white70,
      onDeleted: () {
        setState(() {
          _selectedGroupMembers = _selectedGroupMembers
              .where((member) => member.userId != user.userId)
              .toList(growable: false);
          _groupMemberSuggestions = _groupMemberSuggestions
              .where((member) => member.userId != user.userId)
              .toList(growable: false);
        });
        _handleGroupMemberInputChanged(_membersController.text);
      },
    );
  }

  Widget _buildGroupMemberSuggestionTile(ChatParticipant user) {
    return ListTile(
      tileColor: PlayerUiSignalTheme.mobileSearchColor.withAlpha(90),
      leading: CircleAvatar(
        backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
        backgroundImage:
            (user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty)
            ? NetworkImage(user.avatarUrl!)
            : null,
        child: (user.avatarUrl == null || user.avatarUrl!.trim().isEmpty)
            ? Text(
                user.displayName.isEmpty
                    ? '?'
                    : user.displayName[0].toUpperCase(),
                style: const TextStyle(
                  color: PlayerUiSignalTheme.secondaryColor,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
      title: Text(user.displayName),
      onTap: _creatingGroup || _creatingDirectMessage
          ? null
          : () => _addGroupMember(user),
    );
  }

  Future<void> _handleCreateGroup() async {
    final name = _groupNameController.text.trim();
    final members = _selectedGroupMembers
        .map((member) => member.userId)
        .toList(growable: false);

    if (name.isEmpty) {
      _showMessage('Enter a group name first.');
      return;
    }
    if (members.isEmpty) {
      _showMessage('Add at least one group member.');
      return;
    }

    setState(() => _creatingGroup = true);
    try {
      await _chatController.createGroup(
        name: name,
        members: members,
        avatarBytes: _groupAvatarBytes,
        avatarFilename: _groupAvatarFilename,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not create group: $e');
    } finally {
      if (mounted) {
        setState(() => _creatingGroup = false);
      }
    }
  }

  Future<void> _openClubOrbitRooms() async {
    final launched = await launchUrl(
      Uri.parse(_clubOrbitRoomsDeepLink),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      _showMessage('Could not open Club Orbit.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildGroupAvatarPicker() {
    final hasAvatar =
        _groupAvatarBytes != null && _groupAvatarBytes!.isNotEmpty;

    return Column(
      children: [
        GestureDetector(
          onTap: _creatingGroup || _creatingDirectMessage
              ? null
              : () => unawaited(_pickGroupAvatar()),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: _groupAvatarBackgroundColor,
                  backgroundImage: hasAvatar
                      ? MemoryImage(_groupAvatarBytes!)
                      : null,
                  child: hasAvatar
                      ? null
                      : const Icon(
                          Icons.groups_rounded,
                          size: 34,
                          color: _groupAvatarForegroundColor,
                        ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                  child: Icon(
                    hasAvatar ? Icons.edit : Icons.add,
                    size: 16,
                    color: PlayerUiSignalTheme.secondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _creatingGroup || _creatingDirectMessage
              ? null
              : () => unawaited(_pickGroupAvatar()),
          child: Text(hasAvatar ? 'Change group avatar' : 'Add group avatar'),
        ),
      ],
    );
  }

  Future<void> _pickGroupAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 92,
    );
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _groupAvatarBytes = bytes;
      _groupAvatarFilename = file.name.isEmpty ? 'group-avatar.jpg' : file.name;
    });
  }

  void _handleGroupMemberInputChanged(String value) {
    final trimmed = value.trim();
    _groupMembersDebounceTimer?.cancel();

    if (trimmed.isEmpty) {
      setState(() {
        _pendingGroupSearchRetry = null;
        _groupMemberSearchLoading = false;
        _groupMemberSuggestions = const <ChatParticipant>[];
      });
      return;
    }

    setState(() {
      _pendingGroupSearchRetry = _chatController.matrixConnecting
          ? trimmed
          : null;
      _groupMemberSearchLoading = true;
    });

    _groupMembersDebounceTimer = Timer(const Duration(milliseconds: 220), () {
      _runGroupMemberSearch(trimmed);
    });
  }

  Future<void> _runGroupMemberSearch(String query) async {
    final trimmed = query.trim();
    final requestId = ++_groupMemberSearchRequestId;
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _groupMemberSearchLoading = false;
        _groupMemberSuggestions = const <ChatParticipant>[];
      });
      return;
    }

    try {
      final results = await _chatController.searchUsers(trimmed);
      if (!mounted ||
          requestId != _groupMemberSearchRequestId ||
          _membersController.text.trim() != trimmed) {
        return;
      }

      final selectedIds = _selectedGroupMembers
          .map((member) => member.userId)
          .toSet();

      setState(() {
        _groupMemberSearchLoading = false;
        _groupMemberSuggestions = results
            .where((member) => !selectedIds.contains(member.userId))
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted || requestId != _groupMemberSearchRequestId) {
        return;
      }
      setState(() {
        _groupMemberSearchLoading = false;
        _groupMemberSuggestions = const <ChatParticipant>[];
      });
    }
  }

  void _addGroupMember(ChatParticipant user) {
    if (_selectedGroupMembers.any((member) => member.userId == user.userId)) {
      return;
    }

    setState(() {
      _selectedGroupMembers = <ChatParticipant>[..._selectedGroupMembers, user];
      _pendingGroupSearchRetry = null;
      _groupMemberSearchLoading = false;
      _groupMemberSuggestions = const <ChatParticipant>[];
      _membersController.clear();
    });

    _membersFocusNode.requestFocus();
  }

  Future<bool?> _showDirectMessageSheet(ChatParticipant user) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<ChatUserPresence>(
          future: _chatController.getUserPresence(user.userId),
          builder: (context, snapshot) {
            final presence = snapshot.data;
            final isOnline = presence?.isOnline ?? false;
            final statusText = _presenceLabel(presence);
            final activityText = _lastActivityLabel(presence);

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUserAvatar(user, size: 84, isOnline: isOnline),
                    const SizedBox(height: 16),
                    Text(
                      user.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? const Color(0xFF44CC77)
                                : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (activityText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        activityText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                          foregroundColor: PlayerUiSignalTheme.secondaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _creatingDirectMessage || _creatingGroup
                            ? null
                            : () => Navigator.of(sheetContext).pop(true),
                        child: _creatingDirectMessage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Direct message'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserAvatar(
    ChatParticipant user, {
    required double size,
    required bool isOnline,
  }) {
    final initials = user.displayName.trim().isEmpty
        ? '?'
        : user.displayName.trim()[0].toUpperCase();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: size / 2,
          backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
          backgroundImage:
              user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty
              ? NetworkImage(user.avatarUrl!)
              : null,
          child: user.avatarUrl == null || user.avatarUrl!.trim().isEmpty
              ? Text(
                  initials,
                  style: TextStyle(
                    color: PlayerUiSignalTheme.secondaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.34,
                  ),
                )
              : null,
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: Container(
            width: size * 0.24,
            height: size * 0.24,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF44CC77) : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: PlayerUiSignalTheme.mobileBackgroundColor,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _presenceLabel(ChatUserPresence? presence) {
    if (presence == null) {
      return 'Checking presence...';
    }
    if (presence.isOnline) {
      return 'Online';
    }
    if (presence.presence == 'unavailable') {
      return 'Away';
    }
    return 'Offline';
  }

  String? _lastActivityLabel(ChatUserPresence? presence) {
    final lastActiveAt = presence?.lastActiveAt;
    if (lastActiveAt == null) {
      return null;
    }

    final difference = DateTime.now().difference(lastActiveAt);
    if (difference.inSeconds < 60) {
      return 'Active just now';
    }
    if (difference.inMinutes < 60) {
      return 'Last active ${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return 'Last active ${difference.inHours} hr ago';
    }
    if (difference.inDays < 7) {
      return 'Last active ${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    }
    return 'Last active on ${lastActiveAt.year}-${lastActiveAt.month.toString().padLeft(2, '0')}-${lastActiveAt.day.toString().padLeft(2, '0')}';
  }
}
