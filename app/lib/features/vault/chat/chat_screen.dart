import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:peek_shield_core/peek_shield_core.dart';

import '../../../core/theme/app_theme.dart';
import 'message_bubble.dart';

// ── Hive model ────────────────────────────────────────────────────────────────

/// A single chat message persisted in the Hive vault.
///
/// The Hive box is opened with an AES-256 key derived from FlutterSecureStorage
/// so messages are encrypted at rest on the device.
@HiveType(typeId: 1)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String text;

  @HiveField(1)
  final String senderName;

  @HiveField(2)
  final bool isMe;

  @HiveField(3)
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.senderName,
    required this.isMe,
    required this.timestamp,
  });
}

/// Generated type adapter for [ChatMessage].
///
/// Run `dart run build_runner build` to regenerate from annotations.
/// Provided manually here to keep the file self-contained without a build step.
class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 1;

  @override
  ChatMessage read(BinaryReader reader) {
    return ChatMessage(
      text: reader.readString(),
      senderName: reader.readString(),
      isMe: reader.readBool(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer.writeString(obj.text);
    writer.writeString(obj.senderName);
    writer.writeBool(obj.isMe);
    writer.writeInt(obj.timestamp.millisecondsSinceEpoch);
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

/// Provides the encrypted list of [ChatMessage] objects backed by Hive.
///
/// Call `ref.read(chatMessagesProvider.notifier).init()` once before reading
/// state. `ChatScreen.initState` handles this automatically.
final chatMessagesProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>(
  (ref) => ChatNotifier(),
);

/// Manages the Hive-backed, encrypted chat message list.
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  static const _boxName = 'peek_messages';
  static const _storageKey = 'peek_shield_chat_key';

  Box<ChatMessage>? _box;

  ChatNotifier() : super(const []);

  /// Opens (or creates) the encrypted Hive box and loads persisted messages.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops once the box
  /// is already open.
  Future<void> init() async {
    if (_box != null && _box!.isOpen) {
      // Box already open — just refresh state from it.
      state = _box!.values.toList();
      return;
    }

    // Register adapter once (idempotent guard).
    if (!Hive.isAdapterRegistered(ChatMessageAdapter().typeId)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }

    // Derive or create the AES encryption key from secure storage.
    const storage = FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );

    String? keyString = await storage.read(key: _storageKey);
    if (keyString == null) {
      final freshKey = Hive.generateSecureKey();
      keyString = freshKey.join(',');
      await storage.write(key: _storageKey, value: keyString);
    }

    final encryptionKey =
        keyString.split(',').map(int.parse).toList(growable: false);
    final cipher = HiveAesCipher(encryptionKey);

    _box = await Hive.openBox<ChatMessage>(
      _boxName,
      encryptionCipher: cipher,
    );

    state = _box!.values.toList();
  }

  /// Appends [message] to the Hive box and updates state.
  Future<void> addMessage(ChatMessage message) async {
    await _box?.add(message);
    state = _box?.values.toList() ?? [...state, message];
  }
}

// ── Chat screen ───────────────────────────────────────────────────────────────

/// Protected private chat vault screen.
///
/// All message content is rendered inside a [ProtectedWidget] so the
/// peek-detection layer can blur or obscure it when an unauthorized viewer
/// is detected. The underlying Hive box is AES-256 encrypted at rest.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _initialized = false;

  // ── Demo seed data ──────────────────────────────────────────────────────────

  static final _demoMessages = [
    ChatMessage(
      text: "Hey! Did you get a chance to look at those documents I sent?",
      senderName: "Alex",
      isMe: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 47)),
    ),
    ChatMessage(
      text: "Yes, just finished reviewing them. Looks solid.",
      senderName: "Me",
      isMe: true,
      timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
    ),
    ChatMessage(
      text: "Great! The seed phrase backup is in the usual place 🔒",
      senderName: "Alex",
      isMe: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 44)),
    ),
    ChatMessage(
      text: "Got it. I'll transfer the funds once the confirmation lands.",
      senderName: "Me",
      isMe: true,
      timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
    ChatMessage(
      text: "Perfect. Keep this between us — this conversation stays private.",
      senderName: "Alex",
      isMe: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
  ];

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Defer init until after the first frame so Riverpod is fully wired.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMessages());
  }

  Future<void> _initMessages() async {
    final notifier = ref.read(chatMessagesProvider.notifier);
    await notifier.init();

    // Seed demo messages when the vault is empty (first launch).
    final messages = ref.read(chatMessagesProvider);
    if (messages.isEmpty) {
      for (final msg in _demoMessages) {
        await notifier.addMessage(msg);
      }
    }

    if (mounted) setState(() => _initialized = true);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _showDemoSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Demo mode — messages are read-only'),
        backgroundColor: AppTheme.bgCardElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Private Chat',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Protected by PeekShield',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.accentBlue,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppTheme.borderSubtle),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ProtectedWidget(
              localOverride: false,
              child: Column(
                children: [
                  // ── Protection banner ─────────────────────────────────────
                  _ProtectionBanner(),

                  // ── Message list ──────────────────────────────────────────
                  Expanded(
                    child: _initialized
                        ? ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: MessageBubble(
                                    message: messages[index]),
                              );
                            },
                          )
                        : const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.accentBlue,
                              strokeWidth: 2,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // ── Input bar (demo) ──────────────────────────────────────────────
          _DemoInputBar(onSendTap: _showDemoSnackbar),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showDemoSnackbar,
        backgroundColor: AppTheme.accentBlue,
        foregroundColor: AppTheme.textPrimary,
        elevation: 4,
        tooltip: 'Send (demo)',
        child: const Icon(Icons.send_rounded, size: 22),
      ),
    );
  }
}

// ── Protection banner ─────────────────────────────────────────────────────────

class _ProtectionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.accentBlue.withOpacity(0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 14,
            color: AppTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This conversation is protected',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.accentBlue,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Demo input bar ────────────────────────────────────────────────────────────

class _DemoInputBar extends StatelessWidget {
  final VoidCallback onSendTap;

  const _DemoInputBar({required this.onSendTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(
          top: BorderSide(color: AppTheme.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onSendTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppTheme.borderSubtle, width: 0.5),
                ),
                child: Text(
                  'Message…',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Spacer so the FAB doesn't overlap the send area.
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}
