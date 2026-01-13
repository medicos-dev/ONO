enum CardColor {
  red,
  blue,
  green,
  yellow,
  wild;

  String get displayName {
    switch (this) {
      case CardColor.red:
        return 'Red';
      case CardColor.blue:
        return 'Blue';
      case CardColor.green:
        return 'Green';
      case CardColor.yellow:
        return 'Yellow';
      case CardColor.wild:
        return 'Wild';
    }
  }
}

enum CardType {
  number,
  skip,
  reverse,
  drawTwo,
  wild,
  wildDrawFour;

  String get displayName {
    switch (this) {
      case CardType.number:
        return 'Number';
      case CardType.skip:
        return 'Skip';
      case CardType.reverse:
        return 'Reverse';
      case CardType.drawTwo:
        return 'Draw Two';
      case CardType.wild:
        return 'Wild';
      case CardType.wildDrawFour:
        return 'Wild Draw Four';
    }
  }
}

class UnoCard {
  final CardColor color;
  final CardType type;
  final int? number;

  UnoCard({
    required this.color,
    required this.type,
    this.number,
  });

  bool get isWild => color == CardColor.wild;
  bool get isAction => type != CardType.number;
  bool get isNumber => type == CardType.number;

  bool canPlayOn(UnoCard topCard, CardColor activeColor) {
    if (isWild) {
      if (type == CardType.wildDrawFour) {
        return true;
      }
      return true;
    }

    if (color == activeColor) {
      return true;
    }

    if (topCard.isWild) {
      return color == activeColor;
    }

    if (type == topCard.type) {
      return true;
    }

    if (isNumber && topCard.isNumber && number == topCard.number) {
      return true;
    }

    return false;
  }

  Map<String, dynamic> toJson() {
    return {
      'color': color.name,
      'type': type.name,
      'number': number,
    };
  }

  factory UnoCard.fromJson(Map<String, dynamic> json) {
    return UnoCard(
      color: CardColor.values.firstWhere(
        (e) => e.name == json['color'],
        orElse: () => CardColor.wild,
      ),
      type: CardType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CardType.number,
      ),
      number: json['number'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnoCard &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          type == other.type &&
          number == other.number;

  @override
  int get hashCode => color.hashCode ^ type.hashCode ^ (number ?? 0).hashCode;

  @override
  String toString() {
    if (isWild) {
      return type == CardType.wildDrawFour ? 'Wild +4' : 'Wild';
    }
    if (type == CardType.skip) {
      return '$color Skip';
    }
    if (type == CardType.reverse) {
      return '$color Reverse';
    }
    if (type == CardType.drawTwo) {
      return '$color +2';
    }
    return '$color $number';
  }

  static List<UnoCard> createStandardDeck() {
    final deck = <UnoCard>[];

    for (final color in [CardColor.red, CardColor.blue, CardColor.green, CardColor.yellow]) {
      deck.add(UnoCard(color: color, type: CardType.number, number: 0));

      for (int i = 1; i <= 9; i++) {
        deck.add(UnoCard(color: color, type: CardType.number, number: i));
        deck.add(UnoCard(color: color, type: CardType.number, number: i));
      }

      deck.add(UnoCard(color: color, type: CardType.skip));
      deck.add(UnoCard(color: color, type: CardType.skip));
      deck.add(UnoCard(color: color, type: CardType.reverse));
      deck.add(UnoCard(color: color, type: CardType.reverse));
      deck.add(UnoCard(color: color, type: CardType.drawTwo));
      deck.add(UnoCard(color: color, type: CardType.drawTwo));
    }

    for (int i = 0; i < 4; i++) {
      deck.add(UnoCard(color: CardColor.wild, type: CardType.wild));
      deck.add(UnoCard(color: CardColor.wild, type: CardType.wildDrawFour));
    }

    return deck;
  }
}
