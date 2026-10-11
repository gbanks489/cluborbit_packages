import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:flutter/foundation.dart';

/// What a group chat belongs to: a place's, group's or event's chat, or a plain group chat
/// someone started (linked to none of them).
enum ChatRoomCategory { place, group, event, groupChat }

/// Supplied by the host app, which knows its places, groups and events: tells the chat list which
/// one a chat belongs to, for its filter chips. Provide it above the chat list
/// (`ChangeNotifierProvider<ChatRoomCategoryResolver>`); without one the list shows no filters.
abstract class ChatRoomCategoryResolver extends ChangeNotifier {
  /// The chat's category, or null while it isn't known yet. When it isn't, start finding out
  /// and call notifyListeners once it is. Not called for direct messages.
  ChatRoomCategory? categoryFor(ChatThread thread);
}
