import '../models/uno_card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import 'deck_generator.dart';

/// Core game logic for UNO validation and effects
class GameLogic {
  /// Check if a card can be played on the current discard pile
  static bool isValidMove(UnoCard card, UnoCard? topDiscard, UnoColor? activeColor) {
    // Wild cards can always be played
    if (card.isWild) return true;
    
    // If no discard pile (shouldn't happen), allow any card
    if (topDiscard == null) return true;
    
    // Get the effective color (wild color choice or top card color)
    final effectiveColor = activeColor ?? topDiscard.color;
    
    // Match by color
    if (card.color == effectiveColor) return true;
    
    // Match by value/type (number matches number, skip matches skip, etc.)
    if (card.value == topDiscard.value) return true;
    
    return false;
  }

  /// Check if a player has any valid move
  static bool hasValidMove(List<UnoCard> hand, UnoCard? topDiscard, UnoColor? activeColor) {
    return hand.any((card) => isValidMove(card, topDiscard, activeColor));
  }

  /// Calculate the next player index based on direction
  static int getNextPlayerIndex(int currentIndex, int playerCount, bool isClockwise, {int skip = 1}) {
    if (playerCount <= 0) return 0;
    
    if (isClockwise) {
      return (currentIndex + skip) % playerCount;
    } else {
      return (currentIndex - skip + playerCount * skip) % playerCount;
    }
  }

  /// Apply the effect of a played card and return the new game state
  static GameState applyCardEffect({
    required GameState state,
    required UnoCard card,
    required String playerId,
    UnoColor? chosenColor, // For wild cards
  }) {
    // Remove card from player's hand
    final playerIndex = state.getPlayerIndex(playerId);
    if (playerIndex == -1) return state;
    
    final player = state.players[playerIndex];
    final updatedPlayer = player.removeCard(card.id);
    
    // Add card to discard pile
    List<UnoCard> newDiscardPile = [...state.discardPile, card];
    
    // Update players list
    List<Player> updatedPlayers = List.from(state.players);
    updatedPlayers[playerIndex] = updatedPlayer;
    
    // Check for winner
    if (updatedPlayer.hasWon) {
      return state.copyWith(
        players: updatedPlayers,
        discardPile: newDiscardPile,
        phase: GamePhase.finished,
        winnerId: playerId,
        winnerName: player.name,
        activeColor: null,
        clearActiveColor: true,
      );
    }
    
    // Calculate new state based on card type
    GameState newState = state.copyWith(
      players: updatedPlayers,
      discardPile: newDiscardPile,
    );
    
    switch (card.type) {
      case UnoCardType.number:
        // Just move to next player
        newState = newState.copyWith(
          currentPlayerIndex: getNextPlayerIndex(
            newState.currentPlayerIndex,
            newState.players.length,
            newState.isClockwise,
          ),
          activeColor: null,
          clearActiveColor: true,
        );
        break;
        
      case UnoCardType.skip:
        // Skip the next player (move 2 positions)
        newState = newState.copyWith(
          currentPlayerIndex: getNextPlayerIndex(
            newState.currentPlayerIndex,
            newState.players.length,
            newState.isClockwise,
            skip: 2,
          ),
          activeColor: null,
          clearActiveColor: true,
        );
        break;
        
      case UnoCardType.reverse:
        // Toggle direction
        bool newDirection = !newState.isClockwise;
        
        // In 2-player game, reverse acts like skip
        if (newState.players.length == 2) {
          newState = newState.copyWith(
            isClockwise: newDirection,
            currentPlayerIndex: getNextPlayerIndex(
              newState.currentPlayerIndex,
              newState.players.length,
              newDirection,
              skip: 2,
            ),
            activeColor: null,
            clearActiveColor: true,
          );
        } else {
          newState = newState.copyWith(
            isClockwise: newDirection,
            currentPlayerIndex: getNextPlayerIndex(
              newState.currentPlayerIndex,
              newState.players.length,
              newDirection,
            ),
            activeColor: null,
            clearActiveColor: true,
          );
        }
        break;
        
      case UnoCardType.drawTwo:
        // Next player draws 2 and loses turn
        int nextPlayer = getNextPlayerIndex(
          newState.currentPlayerIndex,
          newState.players.length,
          newState.isClockwise,
        );
        newState = _drawCards(newState, nextPlayer, 2);
        // Skip the player who drew
        newState = newState.copyWith(
          currentPlayerIndex: getNextPlayerIndex(
            nextPlayer,
            newState.players.length,
            newState.isClockwise,
          ),
          activeColor: null,
          clearActiveColor: true,
        );
        break;
        
      case UnoCardType.wild:
        // Set the chosen color
        newState = newState.copyWith(
          activeColor: chosenColor,
          currentPlayerIndex: getNextPlayerIndex(
            newState.currentPlayerIndex,
            newState.players.length,
            newState.isClockwise,
          ),
        );
        break;
        
      case UnoCardType.wildDrawFour:
        // Set color, next player draws 4, loses turn
        int nextPlayer = getNextPlayerIndex(
          newState.currentPlayerIndex,
          newState.players.length,
          newState.isClockwise,
        );
        newState = _drawCards(newState, nextPlayer, 4);
        newState = newState.copyWith(
          activeColor: chosenColor,
          currentPlayerIndex: getNextPlayerIndex(
            nextPlayer,
            newState.players.length,
            newState.isClockwise,
          ),
        );
        break;
    }
    
    return newState;
  }

  /// Draw cards from draw pile to a player's hand
  static GameState _drawCards(GameState state, int playerIndex, int count) {
    if (playerIndex >= state.players.length || playerIndex < 0) return state;
    
    List<UnoCard> newDrawPile = List.from(state.drawPile);
    List<Player> newPlayers = List.from(state.players);
    Player player = newPlayers[playerIndex];
    
    List<UnoCard> drawnCards = [];
    
    for (int i = 0; i < count; i++) {
      if (newDrawPile.isEmpty) {
        // Reshuffle discard pile into draw pile (keep top card)
        if (state.discardPile.length > 1) {
          // Top card stays on discard pile
          newDrawPile = DeckGenerator.shuffle(
            state.discardPile.sublist(0, state.discardPile.length - 1),
          );
          // Note: We update discard pile in the return
        } else {
          break; // No more cards available
        }
      }
      
      if (newDrawPile.isNotEmpty) {
        drawnCards.add(newDrawPile.removeAt(0));
      }
    }
    
    newPlayers[playerIndex] = player.addCards(drawnCards);
    
    return state.copyWith(
      drawPile: newDrawPile,
      players: newPlayers,
    );
  }

  /// Handle a player drawing a card (returns the new state and drawn card)
  static ({GameState state, UnoCard? drawnCard}) drawCard(GameState state, String playerId) {
    final playerIndex = state.getPlayerIndex(playerId);
    if (playerIndex == -1) return (state: state, drawnCard: null);
    
    List<UnoCard> newDrawPile = List.from(state.drawPile);
    List<UnoCard> newDiscardPile = List.from(state.discardPile);
    
    // If draw pile is empty, reshuffle discard pile
    if (newDrawPile.isEmpty && newDiscardPile.length > 1) {
      final topCard = newDiscardPile.removeLast();
      newDrawPile = DeckGenerator.shuffle(newDiscardPile);
      newDiscardPile = [topCard];
    }
    
    if (newDrawPile.isEmpty) {
      return (state: state, drawnCard: null);
    }
    
    final drawnCard = newDrawPile.removeAt(0);
    List<Player> newPlayers = List.from(state.players);
    newPlayers[playerIndex] = newPlayers[playerIndex].addCard(drawnCard);
    
    return (
      state: state.copyWith(
        drawPile: newDrawPile,
        discardPile: newDiscardPile,
        players: newPlayers,
      ),
      drawnCard: drawnCard,
    );
  }

  /// Pass the turn to the next player (used after drawing when card is not playable)
  static GameState passTurn(GameState state) {
    return state.copyWith(
      currentPlayerIndex: getNextPlayerIndex(
        state.currentPlayerIndex,
        state.players.length,
        state.isClockwise,
      ),
    );
  }

  /// Initialize a new game (deal 7 cards to each player)
  static GameState initializeGame(GameState lobbyState) {
    List<UnoCard> deck = DeckGenerator.generateShuffledDeck();
    List<Player> players = [];
    
    // Deal 7 cards to each player
    for (final player in lobbyState.players) {
      final hand = deck.take(7).toList();
      deck = deck.skip(7).toList();
      players.add(player.copyWith(hand: hand));
    }
    
    // Find first non-wild card for initial discard
    int firstNonWildIndex = deck.indexWhere((card) => !card.isWild);
    if (firstNonWildIndex == -1) firstNonWildIndex = 0;
    
    final initialDiscard = deck.removeAt(firstNonWildIndex);
    
    return lobbyState.copyWith(
      drawPile: deck,
      discardPile: [initialDiscard],
      players: players,
      currentPlayerIndex: 0,
      isClockwise: true,
      phase: GamePhase.playing,
      activeColor: null,
      clearActiveColor: true,
    );
  }
}
