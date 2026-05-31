part of '../chat_screen.dart';

// ---------------------------------------------------------------------------
// _StructuredLocationCard – renders a location pin message card
// ---------------------------------------------------------------------------

class _StructuredLocationCard extends StatelessWidget {
  const _StructuredLocationCard({required this.data, required this.accent});

  final _StructuredMessageData data;
  final Color accent;

  LatLng? _extractCoordinates() {
    final link = data.link;
    if (link != null && link.isNotEmpty) {
      final uri = Uri.tryParse(link);
      if (uri != null) {
        final mlat = double.tryParse(uri.queryParameters['mlat'] ?? '');
        final mlon = double.tryParse(uri.queryParameters['mlon'] ?? '');
        if (mlat != null && mlon != null) {
          return LatLng(mlat, mlon);
        }

        final lat = double.tryParse(uri.queryParameters['lat'] ?? '');
        final lon = double.tryParse(uri.queryParameters['lon'] ?? '');
        if (lat != null && lon != null) {
          return LatLng(lat, lon);
        }
      }
    }

    final text = '${data.title}\n${data.details ?? ''}\n${data.link ?? ''}';
    final latMatch = RegExp(
      r'lat\s*[:=]\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);
    final lngMatch = RegExp(
      r'(?:lng|lon|longitude)\s*[:=]\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);
    final lat = latMatch == null ? null : double.tryParse(latMatch.group(1)!);
    final lng = lngMatch == null ? null : double.tryParse(lngMatch.group(1)!);
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return null;
  }

  String? _mapImageUrl(LatLng? coordinates) {
    if ((data.imageUrl ?? '').isNotEmpty) {
      return data.imageUrl;
    }
    if (coordinates == null) {
      return null;
    }
    final lat = coordinates.latitude.toStringAsFixed(6);
    final lng = coordinates.longitude.toStringAsFixed(6);
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=15&size=600x300&markers=$lat,$lng,red-pushpin';
  }

  Widget _buildMapPreview({
    required LatLng coordinates,
    required double height,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: coordinates,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.playerchat',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: coordinates,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.redAccent,
                    size: 36,
                  ),
                ),
              ],
            ),
          ],
        ),
        // subtle vignette for readability of overlaid content
        Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withAlpha(20), Colors.black.withAlpha(40)],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openExternalMap() async {
    final coordinates = _extractCoordinates();
    if (coordinates != null) {
      final lat = coordinates.latitude.toStringAsFixed(6);
      final lng = coordinates.longitude.toStringAsFixed(6);
      final geo = Uri.parse(
        'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(data.title)})',
      );
      if (await canLaunchUrl(geo)) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
        return;
      }

      final gmaps = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      if (await canLaunchUrl(gmaps)) {
        await launchUrl(gmaps, mode: LaunchMode.externalApplication);
        return;
      }
    }

    final link = data.link;
    if ((link ?? '').isNotEmpty) {
      final uri = Uri.tryParse(link!);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinates = _extractCoordinates();
    final mapImageUrl = _mapImageUrl(coordinates);
    const mapHeight = 130.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (coordinates != null || (mapImageUrl ?? '').isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
            child: SizedBox(
              height: mapHeight,
              width: double.infinity,
              child: coordinates != null
                  ? _buildMapPreview(
                      coordinates: coordinates,
                      height: mapHeight,
                    )
                  : CachedNetworkImage(
                      imageUrl: mapImageUrl!,
                      fit: BoxFit.cover,
                      height: mapHeight,
                      width: double.infinity,
                      errorWidget: (context, error, stackTrace) => Container(
                        height: mapHeight,
                        alignment: Alignment.center,
                        color: Colors.black26,
                        child: const Icon(
                          Icons.map_outlined,
                          color: Colors.white70,
                        ),
                      ),
                    ),
            ),
          ),
        Text(
          data.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        if ((data.details ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              data.details!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        if ((data.link ?? '').isNotEmpty)
          GestureDetector(
            onTap: _openExternalMap,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withAlpha(24),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.open_in_new, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Open in Maps',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _StructuredContactCard – renders a contact card message
// ---------------------------------------------------------------------------

class _StructuredContactCard extends StatelessWidget {
  const _StructuredContactCard({required this.data});

  final _StructuredMessageData data;

  IconData _iconForField(String key) {
    switch (key.toLowerCase()) {
      case 'phone':
        return Icons.call_outlined;
      case 'email':
        return Icons.mail_outline;
      default:
        return Icons.badge_outlined;
    }
  }

  Future<void> _openExternalSaveContact(BuildContext context) async {
    final fullName = data.fields
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'name',
          orElse: () => const MapEntry('', ''),
        )
        .value
        .trim();
    final displayName = fullName.isNotEmpty ? fullName : data.title;

    final phones = data.fields
        .where((entry) => entry.key.toLowerCase() == 'phone')
        .map((entry) => entry.value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final emails = data.fields
        .where((entry) => entry.key.toLowerCase() == 'email')
        .map((entry) => entry.value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final prefilled = Contact(
      displayName: displayName,
      name: Name(first: displayName),
      phones: phones.map((phone) => Phone(phone)).toList(growable: false),
      emails: emails.map((email) => Email(email)).toList(growable: false),
    );

    try {
      await FlutterContacts.openExternalInsert(prefilled);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open external contacts app.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarBase64 = data.fields
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'avatarbase64',
          orElse: () => const MapEntry('', ''),
        )
        .value
        .trim();
    final visibleFields = data.fields
        .where((entry) {
          final key = entry.key.toLowerCase();
          return key != 'avatarbase64' && key != 'contactid';
        })
        .toList(growable: false);

    MemoryImage? avatarImage;
    if (avatarBase64.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(avatarBase64));
      } catch (_) {
        avatarImage = null;
      }
    }

    final initials = data.title.isEmpty
        ? '?'
        : data.title
              .split(' ')
              .where((part) => part.trim().isNotEmpty)
              .take(2)
              .map((part) => part.trim()[0].toUpperCase())
              .join();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withAlpha(16),
              backgroundImage: avatarImage,
              child: avatarImage == null
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GestureDetector(
            onTap: () => _openExternalSaveContact(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1_outlined, color: Colors.white70),
                  SizedBox(width: 6),
                  Text('Save contact', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...visibleFields
            .where((entry) => entry.value.trim().isNotEmpty)
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GestureDetector(
                  onTap: () async {
                    final key = entry.key.toLowerCase();
                    Uri? uri;
                    if (key == 'phone') {
                      uri = Uri(scheme: 'tel', path: entry.value);
                    } else if (key == 'email') {
                      uri = Uri(scheme: 'mailto', path: entry.value);
                    }
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _iconForField(entry.key),
                        size: 15,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _StructuredPollCard – renders a poll options card
// ---------------------------------------------------------------------------

class _StructuredPollCard extends StatelessWidget {
  const _StructuredPollCard({
    required this.data,
    required this.accent,
    required this.message,
    required this.currentUserId,
    required this.onVote,
    this.showTitle = true,
  });

  final _StructuredMessageData data;
  final Color accent;
  final ChatMessage message;
  final String? currentUserId;
  final Future<void> Function(int optionIndex) onVote;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final pollVotes =
        (message.metadata['pollVotes'] as List?) ?? const <dynamic>[];
    final voteCounts = <int, int>{};
    final selectedOptionIndexes = <int>{};

    for (final rawVote in pollVotes.whereType<Map>()) {
      final optionIndex = rawVote['optionIndex'];
      if (optionIndex is! int) {
        continue;
      }
      voteCounts[optionIndex] = (voteCounts[optionIndex] ?? 0) + 1;
      if ((rawVote['senderId'] ?? '').toString() == currentUserId) {
        selectedOptionIndexes.add(optionIndex);
      }
    }

    final totalVotes = voteCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            data.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
        ],
        ...data.options.asMap().entries.map((entry) {
          final optionIndex = entry.key;
          final optionVotes = voteCounts[optionIndex] ?? 0;
          final isSelected = selectedOptionIndexes.contains(optionIndex);

          return Container(
            width: double.infinity,
            margin: EdgeInsets.only(
              bottom: entry.key == data.options.length - 1 ? 0 : 8,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onVote(optionIndex),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withAlpha(22)
                        : Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? accent.withAlpha(180)
                          : accent.withAlpha(38),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accent.withAlpha(56)
                              : accent.withAlpha(24),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$optionVotes',
                        style: TextStyle(
                          color: isSelected ? accent : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  totalVotes == 1 ? '1 vote' : '$totalVotes votes',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              Text(
                data.allowsMultiple ? 'Multi-select' : 'Single-select',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
