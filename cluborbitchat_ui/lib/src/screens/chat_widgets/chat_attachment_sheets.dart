part of '../chat_screen.dart';

// ---------------------------------------------------------------------------
// _AttachmentActionSheet – main attachment menu (5 options)
// ---------------------------------------------------------------------------

class _AttachmentActionSheet extends StatelessWidget {
  const _AttachmentActionSheet({required this.onSelect});

  final ValueChanged<_AttachmentAction> onSelect;

  @override
  Widget build(BuildContext context) {
    return _AttachmentSheetFrame(
      title: 'Share something',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentOptionTile(
            icon: Icons.photo_library_outlined,
            title: 'Pictures',
            subtitle: 'Send photos from local gallery or files/cloud picker',
            onTap: () => onSelect(_AttachmentAction.pictures),
          ),
          _AttachmentOptionTile(
            icon: Icons.insert_drive_file_outlined,
            title: 'Documents',
            subtitle: 'Pick any file from your device or cloud storage',
            onTap: () => onSelect(_AttachmentAction.documents),
          ),
          _AttachmentOptionTile(
            icon: Icons.location_on_outlined,
            title: 'Location pin',
            subtitle: 'Pick a spot on the map and send it',
            onTap: () => onSelect(_AttachmentAction.location),
          ),
          _AttachmentOptionTile(
            icon: Icons.person_outline,
            title: 'Contact',
            subtitle: 'Open contacts and share a card',
            onTap: () => onSelect(_AttachmentAction.contact),
          ),
          _AttachmentOptionTile(
            icon: Icons.poll_outlined,
            title: 'Poll',
            subtitle: 'Compose a quick poll as a chat message',
            onTap: () => onSelect(_AttachmentAction.poll),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PictureSourceSheet – gallery vs cloud for image picking
// ---------------------------------------------------------------------------

class _PictureSourceSheet extends StatelessWidget {
  const _PictureSourceSheet({required this.onSelect});

  final ValueChanged<_PictureSourceAction> onSelect;

  @override
  Widget build(BuildContext context) {
    return _AttachmentSheetFrame(
      title: 'Choose pictures from',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentOptionTile(
            icon: Icons.collections_outlined,
            title: 'Gallery',
            subtitle: 'Local phone gallery only (multi-select)',
            onTap: () => onSelect(_PictureSourceAction.gallery),
          ),
          _AttachmentOptionTile(
            icon: Icons.cloud_outlined,
            title: 'Files and cloud apps',
            subtitle:
                'Provider picker (Google Photos, iCloud, Drive, and files)',
            onTap: () => onSelect(_PictureSourceAction.cloud),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AttachmentSheetFrame – shared rounded bottom-sheet container
// ---------------------------------------------------------------------------

class _AttachmentSheetFrame extends StatelessWidget {
  const _AttachmentSheetFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: PlayerUiSignalTheme.secondaryColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AttachmentOptionTile – single row in an attachment sheet
// ---------------------------------------------------------------------------

class _AttachmentOptionTile extends StatelessWidget {
  const _AttachmentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: PlayerUiSignalTheme.primaryDarkColor),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// _AttachmentInput – styled text field used in compose sheets
// ---------------------------------------------------------------------------

class _AttachmentInput extends StatelessWidget {
  const _AttachmentInput({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Poppins',
          fontSize: 14,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: PlayerUiSignalTheme.mobileBackgroundColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: PlayerUiSignalTheme.primaryDarkColor.withAlpha(120),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: PlayerUiSignalTheme.primaryDarkColor.withAlpha(120),
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: PlayerUiSignalTheme.primaryDarkColor),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AttachmentFormActionRow – Cancel / Send button row
// ---------------------------------------------------------------------------

class _AttachmentFormActionRow extends StatelessWidget {
  const _AttachmentFormActionRow({required this.onSend});

  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: onSend,
          style: FilledButton.styleFrom(
            backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
            foregroundColor: PlayerUiSignalTheme.secondaryColor,
          ),
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Send'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _LocationAttachmentSheet – integrated flutter_map location picker
// ---------------------------------------------------------------------------

class _LocationAttachmentSheet extends StatefulWidget {
  const _LocationAttachmentSheet();

  @override
  State<_LocationAttachmentSheet> createState() =>
      _LocationAttachmentSheetState();
}

class _LocationAttachmentSheetState extends State<_LocationAttachmentSheet> {
  final TextEditingController _titleController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng? _pickedLocation;

  @override
  void dispose() {
    _titleController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _submit() {
    final loc = _pickedLocation;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map to pick a location first.')),
      );
      return;
    }

    final title = _titleController.text.trim();
    final lat = loc.latitude.toStringAsFixed(6);
    final lng = loc.longitude.toStringAsFixed(6);
    final link = 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng&zoom=15';
    final mapImage =
        'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=15&size=600x300&markers=$lat,$lng,red-pushpin';

    final lines = <String>['[Location]'];
    lines.add(title.isNotEmpty ? title : 'Shared location');
    lines.add('Map: $link');
    lines.add('Image: $mapImage');

    Navigator.of(context).pop(lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: PlayerUiSignalTheme.secondaryColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pick a location',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Optional place name
            _AttachmentInput(
              controller: _titleController,
              label: 'Place name (optional)',
              hint: 'Coffee shop, venue, park...',
            ),
            // Map
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 280,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(51.5074, -0.1278),
                    initialZoom: 12,
                    onTap: (tapPosition, point) {
                      setState(() => _pickedLocation = point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.playerchat',
                    ),
                    if (_pickedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pickedLocation!,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (_pickedLocation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Selected: ${_pickedLocation!.latitude.toStringAsFixed(5)}, '
                  '${_pickedLocation!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            _AttachmentFormActionRow(onSend: _submit),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ContactAttachmentSheet – native contacts picker
// ---------------------------------------------------------------------------

class _ContactAttachmentSheet extends StatefulWidget {
  const _ContactAttachmentSheet();

  @override
  State<_ContactAttachmentSheet> createState() =>
      _ContactAttachmentSheetState();
}

class _ContactAttachmentSheetState extends State<_ContactAttachmentSheet> {
  bool _loading = false;
  String? _errorMessage;

  Future<void> _pickContact() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorMessage = 'Contacts permission was denied.';
          });
        }
        return;
      }

      final contact = await FlutterContacts.openExternalPick();
      if (!mounted) return;

      if (contact == null) {
        setState(() => _loading = false);
        return;
      }

      // Fetch full contact details
      final full = await FlutterContacts.getContact(
        contact.id,
        withProperties: true,
        withThumbnail: true,
        withPhoto: true,
      );
      if (!mounted) return;

      final name = full?.displayName ?? contact.displayName;
      final phones = (full?.phones ?? contact.phones)
          .map((p) => p.number)
          .where((n) => n.isNotEmpty)
          .toList();
      final emails = (full?.emails ?? contact.emails)
          .map((e) => e.address)
          .where((a) => a.isNotEmpty)
          .toList();

      final lines = <String>['[Contact]'];
      lines.add('ContactId: ${full?.id ?? contact.id}');
      if (name.isNotEmpty) lines.add('Name: $name');
      for (final phone in phones) {
        lines.add('Phone: $phone');
      }
      for (final email in emails) {
        lines.add('Email: $email');
      }

      final avatarBytes =
          full?.thumbnail ?? full?.photo ?? contact.thumbnail ?? contact.photo;
      if (avatarBytes != null && avatarBytes.isNotEmpty) {
        lines.add('AvatarBase64: ${base64Encode(avatarBytes)}');
      }

      Navigator.of(context).pop(lines.join('\n'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Could not open contacts: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AttachmentSheetFrame(
      title: 'Contact',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _pickContact,
              style: FilledButton.styleFrom(
                backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                foregroundColor: PlayerUiSignalTheme.secondaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.contacts_outlined),
              label: Text(
                _loading ? 'Opening contacts…' : 'Choose from contacts',
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PollAttachmentSheet – poll with dynamic option list (2–10 options)
// ---------------------------------------------------------------------------

class _PollAttachmentSheet extends StatefulWidget {
  const _PollAttachmentSheet();

  @override
  State<_PollAttachmentSheet> createState() => _PollAttachmentSheetState();
}

class _PollAttachmentSheetState extends State<_PollAttachmentSheet> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowsMultiple = false;

  static const int _maxOptions = 10;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= _maxOptions) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  void _submit() {
    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (question.isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a question and at least 2 options.'),
        ),
      );
      return;
    }

    final lines = <String>[
      '[Poll]',
      question,
      _allowsMultiple ? 'mode: multi' : 'mode: single',
    ];
    for (final option in options) {
      lines.add('- $option');
    }
    Navigator.of(context).pop(lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return _AttachmentSheetFrame(
      title: 'Poll',
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AttachmentInput(
              controller: _questionController,
              label: 'Question',
              hint: 'What time works best?',
              maxLines: 2,
            ),
            SwitchListTile.adaptive(
              value: _allowsMultiple,
              activeThumbColor: PlayerUiSignalTheme.primaryDarkColor,
              activeTrackColor: PlayerUiSignalTheme.primaryDarkColor.withAlpha(
                120,
              ),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Allow multiple selections',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _allowsMultiple
                    ? 'Users can vote for more than one option'
                    : 'Users can vote for only one option',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _allowsMultiple = value;
                });
              },
            ),
            ...List.generate(_optionControllers.length, (index) {
              return Row(
                children: [
                  Expanded(
                    child: _AttachmentInput(
                      controller: _optionControllers[index],
                      label: 'Option ${index + 1}',
                      hint: index == 0
                          ? '6:00 PM'
                          : index == 1
                          ? '7:00 PM'
                          : 'Add option',
                    ),
                  ),
                  if (_optionControllers.length > 2)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 12),
                      child: GestureDetector(
                        onTap: () => _removeOption(index),
                        child: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.white54,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              );
            }),
            if (_optionControllers.length < _maxOptions)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(
                    Icons.add_circle_outline,
                    size: 18,
                    color: PlayerUiSignalTheme.primaryDarkColor,
                  ),
                  label: const Text(
                    'Add option',
                    style: TextStyle(
                      color: PlayerUiSignalTheme.primaryDarkColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            _AttachmentFormActionRow(onSend: _submit),
          ],
        ),
      ),
    );
  }
}
