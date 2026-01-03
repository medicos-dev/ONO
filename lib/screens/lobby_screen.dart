import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/game_state.dart';
import '../widgets/app_toast.dart';

/// Lobby screen for creating/joining rooms
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _nameController = TextEditingController();
  final _roomController = TextEditingController();
  bool _isCreatingRoom = false; // Specific loading state for Create
  bool _isJoiningRoom = false; // Specific loading state for Join

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _createRoom() async {
    if (_nameController.text.trim().isEmpty ||
        _roomController.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Please enter your name and room code',
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _isCreatingRoom = true);

    final provider = context.read<GameProvider>();
    final success = await provider.createRoom(
      _nameController.text.trim(),
      _roomController.text.trim().toUpperCase(),
    );

    if (mounted) setState(() => _isCreatingRoom = false);

    if (success && mounted) {
      AppToast.show(
        context,
        'Room created! Waiting for players...',
        type: AppToastType.success,
      );
      Navigator.of(context).pushReplacementNamed('/waiting');
    } else if (mounted) {
      AppToast.show(context, 'Failed to create room', type: AppToastType.error);
    }
  }

  void _joinRoom() async {
    if (_nameController.text.trim().isEmpty ||
        _roomController.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Please enter your name and room code',
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _isJoiningRoom = true);

    final provider = context.read<GameProvider>();
    final success = await provider.joinRoom(
      _nameController.text.trim(),
      _roomController.text.trim().toUpperCase(),
    );

    if (mounted) setState(() => _isJoiningRoom = false);

    if (success && mounted) {
      AppToast.show(context, 'Joining room...', type: AppToastType.success);
      Navigator.of(context).pushReplacementNamed('/waiting');
    } else if (mounted) {
      AppToast.show(context, 'Failed to join room', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          bottom: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                // Logo
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE94560).withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: Image.asset(
                        'assets/ONO APP LOGO.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFFE94560),
                            child: const Center(
                              child: Text(
                                'ONO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Title
                const Text(
                  'ONO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 8,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Multiplayer Card Game',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 60),

                // Name input
                _buildTextField(
                  controller: _nameController,
                  label: 'Your Name',
                  icon: Icons.person_outline,
                ),

                const SizedBox(height: 20),

                // Room code input
                _buildTextField(
                  controller: _roomController,
                  label: 'Room Code',
                  icon: Icons.meeting_room_outlined,
                  textCapitalization: TextCapitalization.characters,
                ),

                const SizedBox(height: 40),

                // Create room button
                _buildButton(
                  onPressed:
                      (_isCreatingRoom || _isJoiningRoom) ? null : _createRoom,
                  label: 'Create Room',
                  isPrimary: true,
                  isLoading: _isCreatingRoom,
                ),

                const SizedBox(height: 16),

                // Join room button
                _buildButton(
                  onPressed:
                      (_isCreatingRoom || _isJoiningRoom) ? null : _joinRoom,
                  label: 'Join Room',
                  isPrimary: false,
                  isLoading: _isJoiningRoom,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30), // Much more rounded
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10), // Glass effect
        child: Container(
          height: 64, // Explicit height to prevent clipping ambiguity
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: TextField(
            controller: controller,
            textCapitalization: textCapitalization,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            cursorColor: const Color(0xFFE94560), // Match explicit theme color
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              prefixIcon: Icon(icon, color: const Color(0xFFE94560)),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12, // Reduced from 20 to prevent hint clipping
              ),
              isDense: true, // Helps compact the layout
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required VoidCallback? onPressed,
    required String label,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20), // More rounded
        gradient:
            isPrimary
                ? const LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFFFF6B6B)],
                )
                : null,
        border:
            isPrimary
                ? null
                : Border.all(color: const Color(0xFFE94560), width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child:
                isLoading
                    ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth:
                                3, // Slightly thicker for better visibility
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isPrimary
                                  ? Colors.white
                                  : const Color(0xFFE94560),
                            ),
                          ),
                        ),
                      ],
                    )
                    : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            isPrimary ? Colors.white : const Color(0xFFE94560),
                        letterSpacing: 1,
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}

/// Waiting room screen (after creating/joining, before game starts)
class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  bool _hasNavigated = false; // Prevent double navigation

  @override
  Widget build(BuildContext context) {
    // Use Selector to only watch gamePhase changes
    return Selector<GameProvider, GamePhase?>(
      selector: (_, provider) => provider.gameState?.phase,
      builder: (context, phase, child) {
        // Navigate to game when phase becomes 'playing'
        if (phase == GamePhase.playing && !_hasNavigated) {
          _hasNavigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              AppToast.show(
                context,
                'Game started!',
                type: AppToastType.success,
              );
              Navigator.of(context).pushReplacementNamed('/game');
            }
          });
        }

        // Logic for "Host Closed Room" Kick (Lobby Only)
        // If provider has specific kickoff error, we navigate back.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final provider = context.read<GameProvider>();

          if (!_hasNavigated && provider.error == 'Host closed the room') {
            // Kicked!
            _hasNavigated = true;
            if (mounted) {
              AppToast.show(
                context,
                'Host closed the room',
                type: AppToastType.error,
              );
              Navigator.of(context).pushReplacementNamed('/lobby');

              // Clear the error so we don't loop or show it again unnecessarily
              provider.clearError();
            }
          }
        });

        // Use Consumer for the rest of the UI
        return Consumer<GameProvider>(
          builder: (context, provider, _) {
            final gameState = provider.gameState;

            // Debug Print for UI Visibility Checking
            debugPrint(
              "UI DEBUG: I am host: ${provider.isHost}, Players: ${gameState?.players.length ?? 0}",
            );

            // Greedy Navigation: Show loading overlay when PREPARE_GAME received
            if (provider.isPreparingGame && !_hasNavigated) {
              // ... (keep existing loading logic) ...

              return Scaffold(
                // ... (keep existing scaffold content for loading) ...
                body: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1A1A2E),
                        Color(0xFF16213E),
                        Color(0xFF0F3460),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFE94560),
                          ),
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Loading Game...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Sync progress checklist
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              _SyncChecklistItem(
                                label: 'Receiving Players...',
                                isComplete: provider.hasReceivedPlayers,
                              ),
                              const SizedBox(height: 8),
                              _SyncChecklistItem(
                                label: 'Downloading Deck...',
                                isComplete: provider.hasReceivedDeck,
                              ),
                              const SizedBox(height: 8),
                              _SyncChecklistItem(
                                label: 'Fetching Your Cards...',
                                isComplete: provider.hasReceivedHand,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } else {
              // Reset timer if not preparing
            }

            return PopScope(
              canPop: false, // Handle pop manually
              onPopInvokedWithResult: (bool didPop, dynamic result) async {
                if (didPop) return;

                // FIX: Do not leave immediately on system back (prevent accidental disconnects)
                // Show confirmation dialog
                final shouldLeave = await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Leave Room?'),
                        content: const Text(
                          'Are you sure you want to leave the room?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Leave'),
                          ),
                        ],
                      ),
                );

                if (shouldLeave == true) {
                  // Host cleanup logic
                  if (provider.isHost) {
                    debugPrint('Host exiting lobby - cleaning up room...');
                    await provider.cleanupRoom();
                  } else {
                    provider.leaveRoom();
                  }

                  if (context.mounted) {
                    Navigator.of(context).pushReplacementNamed('/lobby');
                  }
                }
              },
              child: Scaffold(
                body: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1A1A2E),
                        Color(0xFF16213E),
                        Color(0xFF0F3460),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          Row(
                            children: [
                              IconButton(
                                onPressed: () async {
                                  // Trigger PopScope logic (shows confirmation dialog)
                                  await Navigator.of(context).maybePop();
                                },
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                              ),

                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Room Code',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      gameState?.roomCode ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (provider.isHost)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE94560),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'HOST',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 40),

                          // Players list
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Players (${gameState?.players.length ?? 0})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: gameState?.players.length ?? 0,
                                    itemBuilder: (context, index) {
                                      final player = gameState!.players[index];
                                      final isMe =
                                          player.id == provider.myPlayerId;

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          color:
                                              isMe
                                                  ? const Color(
                                                    0xFFE94560,
                                                  ).withValues(alpha: 0.3)
                                                  : Colors.white.withValues(
                                                    alpha: 0.1,
                                                  ),
                                          border: Border.all(
                                            color:
                                                isMe
                                                    ? const Color(0xFFE94560)
                                                    : Colors.white.withValues(
                                                      alpha: 0.2,
                                                    ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  isMe
                                                      ? const Color(0xFFE94560)
                                                      : Colors.white.withValues(
                                                        alpha: 0.2,
                                                      ),
                                              child: Text(
                                                player.name.isNotEmpty
                                                    ? player.name[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    player.name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (isMe)
                                                    Text(
                                                      'You',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.6,
                                                            ),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (player.isHost)
                                              const Icon(
                                                Icons.star,
                                                color: Color(0xFFFDD835),
                                                size: 20,
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Start game button (host only)
                          if (provider.isHost) ...[
                            const SizedBox(height: 20),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient:
                                    (gameState?.players.length ?? 0) >= 2
                                        ? const LinearGradient(
                                          colors: [
                                            Color(0xFFE94560),
                                            Color(0xFFFF6B6B),
                                          ],
                                        )
                                        : null,
                                color:
                                    (gameState?.players.length ?? 0) >= 2
                                        ? null
                                        : Colors.grey.withValues(alpha: 0.3),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap:
                                      (gameState?.players.length ?? 0) >= 2
                                          ? () {
                                            provider.startGame();
                                            AppToast.show(
                                              context,
                                              'Starting game...',
                                              type: AppToastType.success,
                                            );
                                          }
                                          : null,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    child: Text(
                                      (gameState?.players.length ?? 0) >= 2
                                          ? 'Start Game'
                                          : 'Waiting for players...',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white.withValues(
                                          alpha:
                                              (gameState?.players.length ??
                                                          0) >=
                                                      2
                                                  ? 1.0
                                                  : 0.5,
                                        ),
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Waiting for host to start...',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Error display
                          if (provider.error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: const Color(
                                  0xFFE94560,
                                ).withValues(alpha: 0.3),
                              ),
                              child: Text(
                                provider.error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ); // Closing PopScope
          },
        ); // Closing Consumer
      }, // Closing Selector builder
    ); // Closing Selector
  } // Closing build
} // Closing class

/// Checklist item for sync progress display
class _SyncChecklistItem extends StatelessWidget {
  final String label;
  final bool isComplete;

  const _SyncChecklistItem({required this.label, required this.isComplete});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isComplete)
          const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20)
        else
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
            ),
          ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: isComplete ? const Color(0xFF4CAF50) : Colors.white70,
            fontSize: 14,
            fontWeight: isComplete ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
