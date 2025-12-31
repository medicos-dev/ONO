// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:ono/logic/deck_generator.dart';

void main() {
  testWidgets('Deck generates exactly 108 cards', (WidgetTester tester) async {
    final deck = DeckGenerator.generateDeck();
    expect(deck.length, 108);
  });
  
  testWidgets('Deck has correct card distribution', (WidgetTester tester) async {
    final deck = DeckGenerator.generateDeck();
    
    // Count number cards (76 total)
    final numberCards = deck.where((c) => c.value.contains(RegExp(r'^[0-9]$'))).toList();
    expect(numberCards.length, 76);
    
    // Count action cards per color (6 per color = 24 total)
    final skipCards = deck.where((c) => c.value == 'Skip').toList();
    final reverseCards = deck.where((c) => c.value == 'Reverse').toList();
    final drawTwoCards = deck.where((c) => c.value == 'DrawTwo').toList();
    expect(skipCards.length, 8);
    expect(reverseCards.length, 8);
    expect(drawTwoCards.length, 8);
    
    // Count wild cards (8 total)
    final wildCards = deck.where((c) => c.value == 'Wild').toList();
    final wildDrawFourCards = deck.where((c) => c.value == 'WildDrawFour').toList();
    expect(wildCards.length, 4);
    expect(wildDrawFourCards.length, 4);
  });
}
