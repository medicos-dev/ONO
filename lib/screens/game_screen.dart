import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/uno_card.dart';
import '../widgets/uno_card_widget.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/app_toast.dart';

/// Main game screen
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _animationShown = false;
  
  // Multi-card selection & Animation state
  final Set<String> _selectedCardIds = {};
  bool _isSelectionMode = false;
  String? _selectedCardValue;
  
  // Animation Keys
  final Map<String, GlobalKey> _cardKeys = {};
  final GlobalKey _discardPileKey = GlobalKey();
  
  /// Fly cards from hand to center
  void _flyCardsToCenter(List<String> cardIds, List<UnoCard> cards) {
    if (cards.isEmpty) return;
    
    final overlay = Overlay.of(context);
    final discardBox = _discardPileKey.currentContext?.findRenderObject() as RenderBox?;
    if (discardBox == null) return;
    final discardPos = discardBox.localToGlobal(Offset.zero);
    
    // Create flight entries
    for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final key = _cardKeys[card.id];
        final box = key?.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) continue;
        
        final startPos = box.localToGlobal(Offset.zero);
        
        OverlayEntry? entry;
        entry = OverlayEntry(
          builder: (context) {
             return TweenAnimationBuilder<Offset>(
               tween: Tween(begin: startPos, end: discardPos + Offset(i * 20.0, 0)),
               duration: const Duration(milliseconds: 600),
               curve: Curves.easeOutBack,
               onEnd: () {
                 entry?.remove();
               },
               builder: (context, offset, child) {
                 return Positioned(
                   left: offset.dx,
                   top: offset.dy,
                   child: child!,
                 );
               },
               child: UnoCardWidget(card: card, size: UnoCardSize.medium, isPlayable: false),
             );
          },
        );
        
        // Stagger the launch
        Future.delayed(Duration(milliseconds: i * 100), () {
          overlay.insert(entry!);
          HapticFeedback.mediumImpact(); // Haptic pulse per card launch
        });
    }
  }
  
  /// Check if a card can be selected (must match value of first selected card)
  bool _canSelectCard(UnoCard card, GameProvider provider) {
    // Block Wild cards from multi-selection
    if (card.isWild) return false;
    
    // If no cards selected yet, any non-wild card can start selection
    if (_selectedCardIds.isEmpty) return true;
    
    // Must match the value of already selected cards
    return card.value == _selectedCardValue;
  }
  
  void _toggleCardSelection(String cardId, UnoCard card, GameProvider provider) {
    // Don't allow Wild cards in multi-selection
    if (card.isWild) return;
    
    setState(() {
      if (_selectedCardIds.contains(cardId)) {
        // Deselecting
        _selectedCardIds.remove(cardId);
        if (_selectedCardIds.isEmpty) {
          _isSelectionMode = false;
          _selectedCardValue = null;
        }
      } else {
        // Selecting - check if value matches
        if (_selectedCardIds.isEmpty || card.value == _selectedCardValue) {
          _selectedCardIds.add(cardId);
          _selectedCardValue = card.value;
          _isSelectionMode = true;
        }
      }
    });
  }
  
  void _clearSelection() {
    setState(() {
      _selectedCardIds.clear();
      _isSelectionMode = false;
      _selectedCardValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, provider, child) {
        // Handle winner being kicked (they won and need to leave)
        if (provider.wasKickedAsWinner) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.leaveRoom();
            Navigator.of(context).pushReplacementNamed('/lobby');
          });
        }
        
        // Show winner animation
        if (provider.showWinnerAnimation && !_animationShown) {
          _animationShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showWinnerAnimationDialog(context, provider);
          });
        }
        
        if (!provider.showWinnerAnimation) {
          _animationShown = false;
        }
        
        return Scaffold(
          body: SafeArea(
            bottom: true,
            child: Stack(
            children: [
              // Main game UI
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0F3460),
                      Color(0xFF1A1A2E),
                      Color(0xFF16213E),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildTopBar(context, provider),
                      _buildOpponentsSection(provider),
                      Expanded(
                        child: _buildGameArea(context, provider),
                      ),
                      _buildMyHand(context, provider),
                    ],
                  ),
                ),
              ),
              
              // UNO Call Animation Overlay
              if (provider.showUnoCallAnimation)
                _buildUnoCallAnimation(provider),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildUnoCallAnimation(GameProvider provider) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Container(
          color: Colors.black.withValues(alpha: 0.6 * value),
          child: Center(
            child: Transform.scale(
              scale: value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Player name who called UNO
                  Text(
                    provider.unoCallerName ?? '',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: value),
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // UNO text with zoom animation
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFE53935), // Red
                          Color(0xFFFF9800), // Orange  
                          Color(0xFFFDD835), // Yellow
                          Color(0xFF43A047), // Green
                          Color(0xFF1E88E5), // Blue
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE94560).withValues(alpha: 0.8),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Text(
                      'UNO!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(3, 3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '🎉 One card left! 🎉',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: value),
                      fontSize: 18,
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

  Widget _buildTopBar(BuildContext context, GameProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Resign button
          IconButton(
            onPressed: () => _showResignConfirmation(context, provider),
            icon: const Icon(Icons.flag_outlined, color: Colors.white),
            tooltip: 'Resign',
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              provider.gameState?.roomCode ?? '',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          if (provider.isMyTurn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFFFF6B6B)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE94560).withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Text(
                'YOUR TURN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          const Spacer(),
          // Leave button
          IconButton(
            onPressed: () => _showLeaveConfirmation(context, provider),
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
            tooltip: 'Leave Game',
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentsSection(GameProvider provider) {
    final opponents = provider.opponents;
    final currentPlayerId = provider.gameState?.currentPlayer?.id;
    
    if (opponents.isEmpty) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: Text(
          'Waiting for other players...',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }
    
    return Container(
      height: 75,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: opponents.length,
        itemBuilder: (context, index) {
          final player = opponents[index];
          final isCurrentTurn = player.id == currentPlayerId;
          final hasUno = player.hasUno;
          
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: isCurrentTurn
                  ? const LinearGradient(
                      colors: [Color(0xFFE94560), Color(0xFFFF6B6B)],
                    )
                  : null,
              color: isCurrentTurn ? null : Colors.white.withValues(alpha: 0.1),
              border: Border.all(
                color: isCurrentTurn
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: isCurrentTurn
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE94560).withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (hasUno) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDD835),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'UNO!',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.style,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${player.hand.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGameArea(BuildContext context, GameProvider provider) {
    final gameState = provider.gameState;
    final topCard = gameState?.topDiscard;
    final activeColor = gameState?.effectiveColor;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Direction indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  gameState?.isClockwise == true
                      ? Icons.rotate_right
                      : Icons.rotate_left,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  gameState?.isClockwise == true ? 'Clockwise' : 'Counter-Clockwise',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Cards in center
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Draw pile
              GestureDetector(
                onTap: () {
                  if (provider.isMyTurn && !provider.hasDrawnCard) {
                    provider.drawCard();
                    AppToast.show(context, 'Card drawn!', type: AppToastType.info);
                  }
                },
                child: Container(
                  width: 85,
                  height: 125,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1A1A2E),
                        Color(0xFF0F3460),
                      ],
                    ),
                    border: Border.all(
                      color: provider.isMyTurn && !provider.hasDrawnCard
                          ? const Color(0xFFE94560)
                          : Colors.white24,
                      width: provider.isMyTurn && !provider.hasDrawnCard ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: provider.isMyTurn && !provider.hasDrawnCard
                            ? const Color(0xFFE94560).withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'ONO',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${gameState?.drawPile.length ?? 0}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                        if (provider.isMyTurn && !provider.hasDrawnCard) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE94560),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'DRAW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 24),
              
              // Discard pile
              // Discard pile (Multi-Stack or Single)
              if (gameState?.activeMultiThrowStack != null && 
                  gameState!.activeMultiThrowStack!.isNotEmpty)
                SizedBox(
                  key: _discardPileKey, 
                  width: 140 + (gameState.activeMultiThrowStack!.length - 1) * 20.0,
                  height: 200, // Approximate large card height
                  child: Stack(
                     alignment: Alignment.centerLeft,
                     children: List.generate(gameState.activeMultiThrowStack!.length, (index) {
                        final card = gameState.activeMultiThrowStack![index];
                        return Positioned(
                          left: index * 20.0,
                          child: UnoCardWidget(
                            card: card,
                            isPlayable: false,
                            activeColor: index == gameState.activeMultiThrowStack!.length - 1 
                                ? activeColor 
                                : null, // Only last card shows active color glow if wild
                            size: UnoCardSize.large,
                          ),
                        );
                     }),
                  ),
                )
              else if (topCard != null)
                UnoCardWidget(
                  card: topCard,
                  isPlayable: false,
                  activeColor: activeColor,
                  size: UnoCardSize.large,
                ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Active color indicator (for wild cards)
          if (activeColor != null && topCard?.isWild == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: Color(activeColor.colorValue).withValues(alpha: 0.25),
                border: Border.all(
                  color: Color(activeColor.colorValue),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Color(activeColor.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    activeColor.name.toUpperCase(),
                    style: TextStyle(
                      color: Color(activeColor.colorValue),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          
          // Pass turn button (after drawing)
          if (provider.isMyTurn && provider.hasDrawnCard)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: ElevatedButton.icon(
                onPressed: () {
                  provider.passTurn();
                  AppToast.show(context, 'Turn passed', type: AppToastType.info);
                },
                icon: const Icon(Icons.skip_next, size: 20),
                label: const Text(
                  'Pass Turn',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyHand(BuildContext context, GameProvider provider) {
    final myPlayer = provider.myPlayer;
    if (myPlayer == null) return const SizedBox.shrink();
    
    final hasUno = myPlayer.hasUno;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        bottom: bottomPadding + 12, // Safe area + padding
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.5),
          ],
        ),
      ),
      child: Column(
        children: [
          // UNO indicator
          if (hasUno)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFDD835), Color(0xFFFFB300)],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFDD835).withValues(alpha: 0.6),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🎉', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'UNO!',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('🎉', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
          
          // UNO Button and Throw Selected Button row
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Throw Selected Button (visible when > 1 cards selected)
                if (_selectedCardIds.length > 1)
                  GestureDetector(
                    onTap: () {
                      // Trigger Animation
                      final selectedCards = myPlayer.hand.where((c) => _selectedCardIds.contains(c.id)).toList();
                      _flyCardsToCenter(_selectedCardIds.toList(), selectedCards);
                      
                      // Send THROW_MULTIPLE
                      provider.throwMultipleCards(_selectedCardIds.toList());
                      _clearSelection();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFA4CD01), Color(0xFF7CB342)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFA4CD01).withValues(alpha: 0.6),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            'Throw ${_selectedCardIds.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // UNO Button
                GestureDetector(
                  onTap: provider.canCallUno ? () {
                    provider.callUno();
                  } : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: provider.canCallUno
                          ? const LinearGradient(
                              colors: [Color(0xFFE53935), Color(0xFFFF9800), Color(0xFFFDD835)],
                            )
                          : null,
                      color: provider.canCallUno ? null : Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: provider.canCallUno
                          ? [
                              BoxShadow(
                                color: const Color(0xFFE53935).withValues(alpha: 0.6),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      'UNO!',
                      style: TextStyle(
                        color: provider.canCallUno ? Colors.white : Colors.white38,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                
                // Clear selection button (visible when in selection mode)
                if (_isSelectionMode)
                  GestureDetector(
                    onTap: _clearSelection,
                    child: Container(
                      margin: const EdgeInsets.only(left: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          
          // Cards - increased height for better visibility
          SizedBox(
            height: 150, // Increased from 120 for better card lift visibility
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: myPlayer.hand.length,
              itemBuilder: (context, index) {
                final card = myPlayer.hand[index];
                final isPlayable = provider.isMyTurn && provider.canPlayCard(card);
                final isSelected = _selectedCardIds.contains(card.id);
                // Create key for this card if needed
                if (!_cardKeys.containsKey(card.id)) {
                   _cardKeys[card.id] = GlobalKey();
                }

                return GestureDetector(
                  onLongPress: () {
                    // Conditional Multi-Selection Logic
                    if (card.isWild) return; 

                    // 1. Check if playable
                    if (!isPlayable) {
                         AppToast.show(context, 'First card must be playable', type: AppToastType.error);
                         return;
                    }

                    // 2. Count matches in hand
                    final matchCount = myPlayer.hand.where((c) => c.value == card.value && !c.isWild).length;
                    
                    // 3. Allow only if > 1 match
                    if (matchCount > 1) {
                      _toggleCardSelection(card.id, card, provider);
                    } else {
                       AppToast.show(context, 'Single play only (need matching cards)', type: AppToastType.info);
                    }
                  },
                  onTap: () {
                    if (_isSelectionMode) {
                      // Toggle selection (only if value matches)
                      if (_canSelectCard(card, provider)) {
                        _toggleCardSelection(card.id, card, provider);
                      } else {
                        AppToast.show(context, 'Cards must have the same value', type: AppToastType.info);
                      }
                    } else if (isPlayable) {
                      _playCard(context, provider, card);
                    } else if (provider.isMyTurn) {
                      AppToast.show(context, 'Cannot play this card', type: AppToastType.error);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Center(
                      child: UnoCardWidget(
                        key: _cardKeys[card.id],
                        card: card,
                        isPlayable: isPlayable,
                        isSelected: isSelected,
                        size: UnoCardSize.medium,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Card count
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${myPlayer.hand.length} cards in hand',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _playCard(BuildContext context, GameProvider provider, UnoCard card) {
    if (card.isWild) {
      // Show color picker for wild cards
      showDialog(
        context: context,
        builder: (context) => ColorPickerDialog(
          onColorSelected: (color) {
            provider.playCard(card, chosenColor: color);
            AppToast.show(context, 'Card played!', type: AppToastType.success);
          },
        ),
      );
    } else {
      provider.playCard(card);
      AppToast.show(context, 'Card played!', type: AppToastType.success);
    }
  }

  void _showResignConfirmation(BuildContext context, GameProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.flag, color: Color(0xFFE94560)),
            SizedBox(width: 12),
            Text('Resign Game?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Are you sure you want to resign? You will be removed from this game.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              provider.resign();
              Navigator.of(context).pushReplacementNamed('/lobby');
              AppToast.show(context, 'You resigned from the game', type: AppToastType.info);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
            ),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
  }

  void _showLeaveConfirmation(BuildContext context, GameProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave Game?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to leave? You can rejoin with the same room code.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              provider.leaveRoom();
              Navigator.of(context).pushReplacementNamed('/lobby');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showWinnerAnimationDialog(BuildContext context, GameProvider provider) {
    final isWinner = provider.isWinnerAnimationForMe;
    final winnerName = provider.winnerAnimationName ?? 'Unknown';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WinnerAnimationDialog(
        winnerName: winnerName,
        isWinner: isWinner,
        onAnimationComplete: () {
          Navigator.of(dialogContext).pop();
          
          if (provider.isHost) {
            // Host kicks the winner and continues game
            provider.kickWinnerAndContinue();
          } else {
            provider.dismissWinnerAnimation();
          }
          
          // If I was the winner, I get kicked
          if (isWinner) {
            AppToast.show(context, 'Congratulations! You won! 🎉', type: AppToastType.success);
          }
        },
      ),
    );
  }
}

/// Animated winner dialog
class WinnerAnimationDialog extends StatefulWidget {
  final String winnerName;
  final bool isWinner;
  final VoidCallback onAnimationComplete;

  const WinnerAnimationDialog({
    super.key,
    required this.winnerName,
    required this.isWinner,
    required this.onAnimationComplete,
  });

  @override
  State<WinnerAnimationDialog> createState() => _WinnerAnimationDialogState();
}

class _WinnerAnimationDialogState extends State<WinnerAnimationDialog>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _rotateController;
  late AnimationController _confettiController;
  
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    
    _rotateAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rotateController, curve: Curves.easeInOut),
    );
    
    _startAnimation();
  }

  void _startAnimation() async {
    _scaleController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _rotateController.forward();
    _confettiController.forward();
    
    // Auto-close after animation
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      widget.onAnimationComplete();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _rotateController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A1A2E),
                    Color(0xFF16213E),
                    Color(0xFF0F3460),
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: const Color(0xFFFDD835),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFDD835).withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Trophy with rotation
                  AnimatedBuilder(
                    animation: _rotateController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotateAnimation.value * 0.1,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glow effect
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFFDD835).withValues(alpha: 0.4),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.emoji_events,
                              size: 100,
                              color: Color(0xFFFDD835),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Winner text
                  Text(
                    widget.isWinner ? '🎉 YOU WON! 🎉' : '🎊 WINNER! 🎊',
                    style: const TextStyle(
                      color: Color(0xFFFDD835),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Text(
                    widget.winnerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    widget.isWinner 
                        ? 'Congratulations! You\'ll be leaving the room.'
                        : 'The winner will leave, game continues!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Confetti animation indicator
                  AnimatedBuilder(
                    animation: _confettiController,
                    builder: (context, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                -20 * _confettiController.value * (1 + index * 0.2),
                              ),
                              child: Opacity(
                                opacity: 1 - _confettiController.value,
                                child: Text(
                                  ['🎊', '✨', '🎉', '⭐', '🎈'][index],
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
