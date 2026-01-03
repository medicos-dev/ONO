import '../models/uno_card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import 'deck_generator.dart';

/// Core game logic for UNO validation and effects
class GameLogic {
  /// Check if a card can be played on the current discard pile
  static bool isValidMove(
    UnoCard card,
    UnoCard? topDiscard,
    UnoColor? activeColor,
  ) {
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
  static bool hasValidMove(
    List<UnoCard> hand,
    UnoCard? topDiscard,
    UnoColor? activeColor,
  ) {
    return hand.any((card) => isValidMove(card, topDiscard, activeColor));
  }

  /// Calculate the next player index based on direction
  static int getNextPlayerIndex(
    int currentIndex,
    int playerCount,
    bool isClockwise, {
    int skip = 1,
  }) {
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
      // Add to winners list if not already there
      List<String> newWinners = List.from(state.winners);
      if (!newWinners.contains(player.name)) {
        newWinners.add(player.name);
      }

      // Check if game is over (only 1 active player left)
      int activePlayersCount =
          updatedPlayers.where((p) => p.hand.isNotEmpty).length;
      bool isGameOver = activePlayersCount <= 1;

      if (isGameOver) {
        // Add the last remaining player to winners list (last place)
        final lastPlayer = updatedPlayers.firstWhere(
          (p) => p.hand.isNotEmpty,
          orElse: () => updatedPlayers.first,
        );
        if (!newWinners.contains(lastPlayer.name)) {
          newWinners.add(lastPlayer.name);
        }

        return state.copyWith(
          players: updatedPlayers,
          discardPile: newDiscardPile,
          phase: GamePhase.finished,
          winnerId: playerId, // Last person to go out
          winnerName: player.name,
          winners: newWinners,
          activeColor: null,
          clearActiveColor: true,
          lastPlayedCard: card,
        );
      } else {
        // Game continues - removing the winner from rotation?
        // For simplicity, we keep them in the list but GameLogic needs to know to skip them?
        // Or we assume the winner leaves the lobby?
        // Better: Mark as won, but let them "pass" automatically?
        // Actually, usuall UNO rules: winner leaves.
        // Let's remove the player from the list?
        // "Do NOT delete any game data mid-game"
        // So we keep them. But we need to ensure getNextPlayerIndex skips them.

        // Let's just create the newState and let the switch case run?
        // No, if they won, they don't play anymore.
        // We need to pass turn to next ACTIVE player.

        GameState midState = state.copyWith(
          players: updatedPlayers,
          discardPile: newDiscardPile,
          winners: newWinners,
          lastPlayedCard: card,
        );

        // Determine effects (like +2) but apply to next ACTIVE player?
        // If I won with a +2, the next person still draws.
        // So we run the switch case, but ensure the resulting currentPlayerIndex is valid (has cards).

        GameState finalState = _applyCardTypeEffect(
          midState,
          card,
          chosenColor,
        );

        // Ensure current player is active
        return _ensureActivePlayer(finalState);
      }
    }

    // Calculate new state based on card type
    GameState newState = state.copyWith(
      players: updatedPlayers,
      discardPile: newDiscardPile,
      lastPlayedCard: card,
    );

    return _applyCardTypeEffect(newState, card, chosenColor);
  }

  static GameState _applyCardTypeEffect(
    GameState state,
    UnoCard card,
    UnoColor? chosenColor,
  ) {
    GameState newState = state;

    switch (card.type) {
      case UnoCardType.number:
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
        bool newDirection = !newState.isClockwise;
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
        newState = newState.copyWith(
          currentPlayerIndex: getNextPlayerIndex(
            newState.currentPlayerIndex,
            newState.players.length,
            newState.isClockwise,
          ),
          activeColor: null,
          clearActiveColor: true,
          pendingDraws: 2,
        );
        break;

      case UnoCardType.wild:
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
        newState = newState.copyWith(
          activeColor: chosenColor,
          currentPlayerIndex: getNextPlayerIndex(
            newState.currentPlayerIndex,
            newState.players.length,
            newState.isClockwise,
          ),
          pendingDraws: 4,
        );
        break;
    }
    return newState;
  }

  /// Ensure the current player has cards. If not, skip to next.
  static GameState _ensureActivePlayer(GameState state) {
    if (state.phase == GamePhase.finished) return state;

    int attempts = 0;
    int index = state.currentPlayerIndex;

    while (state.players[index].hand.isEmpty &&
        attempts < state.players.length) {
      index = getNextPlayerIndex(
        index,
        state.players.length,
        state.isClockwise,
      );
      attempts++;
    }

    return state.copyWith(currentPlayerIndex: index);
  }

  /// Handle a player drawing a card (returns the new state and drawn card)
  static ({GameState state, UnoCard? drawnCard}) drawCard(
    GameState state,
    String playerId,
  ) {
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

    /* 
    // OLD LOGIC: Find first non-wild card for initial discard
    int firstNonWildIndex = deck.indexWhere((card) => !card.isWild);
    if (firstNonWildIndex == -1) firstNonWildIndex = 0;
    
    final initialDiscard = deck.removeAt(firstNonWildIndex);
    */

    // NEW LOGIC: Start with empty discard pile (Host must play first)
    // Note: Host validation must allow any card if pile is empty

    return lobbyState.copyWith(
      drawPile: deck,
      discardPile: [], // Empty pile
      players: players,
      currentPlayerIndex: 0,
      isClockwise: true,
      phase: GamePhase.playing,
      activeColor: null,
      clearActiveColor: true,
    );
  }
}
