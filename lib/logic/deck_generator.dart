import 'dart:math';
import '../models/uno_card.dart';

/// Generates the standard 108-card UNO deck
class DeckGenerator {
  static final _random = Random();

  /// Generate a complete UNO deck (108 cards)
  static List<UnoCard> generateDeck() {
    final List<UnoCard> deck = [];
    
    final colors = [UnoColor.red, UnoColor.blue, UnoColor.green, UnoColor.yellow];
    
    for (final color in colors) {
      // One '0' card per color (4 total)
      deck.add(UnoCard(
        color: color,
        value: '0',
        type: UnoCardType.number,
      ));
      
      // Two of each '1-9' per color (72 total)
      for (int num = 1; num <= 9; num++) {
        for (int i = 0; i < 2; i++) {
          deck.add(UnoCard(
            color: color,
            value: num.toString(),
            type: UnoCardType.number,
          ));
        }
      }
      
      // Two Skip cards per color (8 total)
      for (int i = 0; i < 2; i++) {
        deck.add(UnoCard(
          color: color,
          value: 'Skip',
          type: UnoCardType.skip,
        ));
      }
      
      // Two Reverse cards per color (8 total)
      for (int i = 0; i < 2; i++) {
        deck.add(UnoCard(
          color: color,
          value: 'Reverse',
          type: UnoCardType.reverse,
        ));
      }
      
      // Two Draw Two cards per color (8 total)
      for (int i = 0; i < 2; i++) {
        deck.add(UnoCard(
          color: color,
          value: 'DrawTwo',
          type: UnoCardType.drawTwo,
        ));
      }
    }
    
    // Four Wild cards
    for (int i = 0; i < 4; i++) {
      deck.add(UnoCard(
        color: UnoColor.black,
        value: 'Wild',
        type: UnoCardType.wild,
      ));
    }
    
    // Four Wild Draw Four cards
    for (int i = 0; i < 4; i++) {
      deck.add(UnoCard(
        color: UnoColor.black,
        value: 'WildDrawFour',
        type: UnoCardType.wildDrawFour,
      ));
    }
    
    // Total: 4 + 72 + 8 + 8 + 8 + 4 + 4 = 108 cards
    return deck;
  }

  /// Shuffle the deck using Fisher-Yates algorithm
  static List<UnoCard> shuffle(List<UnoCard> deck) {
    final shuffled = List<UnoCard>.from(deck);
    for (int i = shuffled.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = temp;
    }
    return shuffled;
  }

  /// Generate and shuffle a new deck
  static List<UnoCard> generateShuffledDeck() {
    return shuffle(generateDeck());
  }
}
