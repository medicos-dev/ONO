import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/room_provider.dart';
import '../services/voice_service.dart';
import '../widgets/app_toast.dart';
import 'home_screen.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _isMicPressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRoomStatus();
    });
  }

  void _checkRoomStatus() {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    if (roomProvider.isPlaying) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GameScreen()),
      );
      return;
    }

    if (roomProvider.room == null || roomProvider.currentPlayer == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
      return;
    }
  }

  Future<void> _handleStartGame() async {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    
    if (roomProvider.room!.players.length < 2) {
      AppToast.show(
        context,
        'Need at least 2 players to start',
        type: AppToastType.error,
      );
      return;
    }

    try {
      await roomProvider.startGame();
      // Wait a bit for the game state to be polled
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted && roomProvider.isPlaying && roomProvider.room?.gameState != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GameScreen()),
        );
      } else if (mounted) {
        // If game state not ready, show error
        AppToast.show(
          context,
          'Game is starting, please wait...',
          type: AppToastType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          e.toString(),
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _handleResignHost() async {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign Host?'),
        content: const Text('A random player will be assigned as the new host.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resign'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await roomProvider.resignHost();
      } catch (e) {
        if (mounted) {
          AppToast.show(
            context,
            e.toString(),
            type: AppToastType.error,
          );
        }
      }
    }
  }

  Future<void> _handleLeaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Room?'),
        content: const Text('Are you sure you want to leave the room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      await VoiceService.leaveRoom();
      await roomProvider.leaveRoom();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, roomProvider, _) {
        // Auto-navigate to game screen when game starts and gameState is ready
        if (roomProvider.isPlaying && roomProvider.room?.gameState != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const GameScreen()),
              );
            }
          });
        }

        if (roomProvider.room == null || roomProvider.currentPlayer == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            );
          });
        }

        final room = roomProvider.room;
        final currentPlayer = roomProvider.currentPlayer;

        if (room == null || currentPlayer == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Room: ${room.code}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                onPressed: _handleLeaveRoom,
                tooltip: 'Leave Room',
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0A0F),
                  Color(0xFF151520),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'Room Code',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              room.code,
                              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                    color: const Color(0xFF00E5FF),
                                    letterSpacing: 4,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: room.players.length,
                      itemBuilder: (context, index) {
                        final player = room.players[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: player.isHost
                                  ? const Color(0xFFFFEA00).withOpacity(0.5)
                                  : Colors.white.withOpacity(0.1),
                              width: player.isHost ? 2 : 1,
                            ),
                            boxShadow: player.isHost
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFFFEA00).withOpacity(0.3),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: player.isHost
                                      ? [
                                          const Color(0xFFFFEA00),
                                          const Color(0xFFFFB300),
                                        ]
                                      : [
                                          Colors.blue.withOpacity(0.6),
                                          Colors.purple.withOpacity(0.6),
                                        ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  player.name.isNotEmpty
                                      ? player.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              player.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: player.isHost
                                ? Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFEA00),
                                          Color(0xFFFFB300),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'HOST',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  )
                                : null,
                            trailing: player.isHost
                                ? const Icon(
                                    Icons.star,
                                    color: Color(0xFFFFEA00),
                                    size: 24,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTapDown: (_) async {
                              setState(() => _isMicPressed = true);
                              await VoiceService.startSpeaking();
                            },
                            onTapUp: (_) async {
                              setState(() => _isMicPressed = false);
                              await VoiceService.stopSpeaking();
                            },
                            onTapCancel: () async {
                              setState(() => _isMicPressed = false);
                              await VoiceService.stopSpeaking();
                            },
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                color: _isMicPressed
                                    ? const Color(0xFFFF1744)
                                    : const Color(0xFF00E5FF),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isMicPressed ? Icons.mic : Icons.mic_none,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (roomProvider.isHost) ...[
                          if (room.players.length >= 2)
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _handleStartGame,
                                child: const Text('START GAME'),
                              ),
                            ),
                          if (room.players.length < 2)
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: null,
                                child: const Text('Need 2+ Players'),
                              ),
                            ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _handleResignHost,
                            child: const Text('RESIGN'),
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
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
