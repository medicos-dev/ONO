import { UnoCard, CardColor, CardType, GameState } from './types';

export function createStandardDeck(): UnoCard[] {
  const deck: UnoCard[] = [];

  const colors = [CardColor.red, CardColor.blue, CardColor.green, CardColor.yellow];

  for (const color of colors) {
    deck.push({ color, type: CardType.number, number: 0, isWild: false, isAction: false });

    for (let i = 1; i <= 9; i++) {
      deck.push({ color, type: CardType.number, number: i, isWild: false, isAction: false });
      deck.push({ color, type: CardType.number, number: i, isWild: false, isAction: false });
    }

    deck.push({ color, type: CardType.skip, isWild: false, isAction: true });
    deck.push({ color, type: CardType.skip, isWild: false, isAction: true });
    deck.push({ color, type: CardType.reverse, isWild: false, isAction: true });
    deck.push({ color, type: CardType.reverse, isWild: false, isAction: true });
    deck.push({ color, type: CardType.drawTwo, isWild: false, isAction: true });
    deck.push({ color, type: CardType.drawTwo, isWild: false, isAction: true });
  }

  for (let i = 0; i < 4; i++) {
    deck.push({ color: CardColor.wild, type: CardType.wild, isWild: true, isAction: true });
    deck.push({ color: CardColor.wild, type: CardType.wildDrawFour, isWild: true, isAction: true });
  }

  return deck;
}

export function shuffleDeck(deck: UnoCard[]): UnoCard[] {
  const shuffled = [...deck];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

export function dealCards(deck: UnoCard[], playerCount: number): UnoCard[][] {
  const hands: UnoCard[][] = [];
  const cardsPerPlayer = 7;

  for (let i = 0; i < playerCount; i++) {
    hands.push([]);
  }

  for (let i = 0; i < cardsPerPlayer; i++) {
    for (let j = 0; j < playerCount; j++) {
      if (deck.length > 0) {
        hands[j].push(deck.shift()!);
      }
    }
  }

  return hands;
}

export function canPlayCard(
  card: UnoCard,
  topCard: UnoCard,
  activeColor: CardColor,
  pendingDrawCount: number,
  playerHand?: UnoCard[]
): boolean {
  if (card.isWild) {
    if (card.type === CardType.wildDrawFour) {
      if (playerHand && playerHand.length > 0) {
        const hasMatchingColor = playerHand.some((c) => 
          !c.isWild && c.color === activeColor
        );
        if (hasMatchingColor) {
          return false;
        }
      }
      if (pendingDrawCount > 0 && pendingDrawCount < 8) {
        return false;
      }
      if (pendingDrawCount >= 8) {
        return true;
      }
      return true;
    }
    return true;
  }

  if (card.color === activeColor) {
    return true;
  }

  if (topCard.isWild) {
    return card.color === activeColor;
  }

  if (card.type === topCard.type) {
    return true;
  }

  if (card.type === CardType.number && topCard.type === CardType.number && card.number === topCard.number) {
    return true;
  }

  if (pendingDrawCount > 0) {
    if (pendingDrawCount % 2 === 0 && card.type === CardType.drawTwo && card.color === activeColor) {
      return true;
    }
    if (pendingDrawCount >= 8 && card.type === CardType.wildDrawFour) {
      return true;
    }
  }

  return false;
}

export function processCardPlay(
  gameState: GameState,
  card: UnoCard,
  chosenColor: CardColor | undefined,
  playerId: string,
  playerIds: string[]
): GameState {
  let newActiveColor = gameState.activeColor;
  let newDirection = gameState.direction;
  let newPendingDrawCount = gameState.pendingDrawCount;
  let newCurrentTurnPlayerId = playerId;
  const newDiscardPile = [...gameState.discardPile, card];

  if (card.isWild) {
    if (chosenColor) {
      newActiveColor = chosenColor;
    } else {
      newActiveColor = CardColor.red;
    }
  } else {
    newActiveColor = card.color;
  }

  if (card.type === CardType.skip) {
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
    newCurrentTurnPlayerId = getNextPlayer(newCurrentTurnPlayerId, playerIds, newDirection);
  } else if (card.type === CardType.reverse) {
    newDirection *= -1;
    if (playerIds.length === 2) {
      newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
    }
  } else if (card.type === CardType.drawTwo) {
    if (newPendingDrawCount > 0 && newPendingDrawCount % 2 === 0) {
      newPendingDrawCount += 2;
    } else {
      newPendingDrawCount = 2;
    }
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
  } else if (card.type === CardType.wildDrawFour) {
    if (newPendingDrawCount >= 8) {
      newPendingDrawCount += 4;
    } else {
      newPendingDrawCount = 4;
    }
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
  } else {
    newCurrentTurnPlayerId = getNextPlayer(playerId, playerIds, newDirection);
  }

  if (card.type !== CardType.drawTwo && card.type !== CardType.wildDrawFour) {
    newPendingDrawCount = 0;
  }

  const animationId = `${playerId}|${JSON.stringify(card)}|${Date.now()}`;

  return {
    ...gameState,
    discardPile: newDiscardPile,
    activeColor: newActiveColor,
    direction: newDirection,
    pendingDrawCount: newPendingDrawCount,
    currentTurnPlayerId: newCurrentTurnPlayerId,
    lastPlayedCardJson: JSON.stringify(card),
    pendingWildColorChoice: card.isWild && chosenColor ? chosenColor : null,
    lastPlayedCardAnimationId: animationId,
    stateVersion: gameState.stateVersion + 1,
    lastActivity: new Date().toISOString(),
  };
}

export function getNextPlayer(currentPlayerId: string, playerIds: string[], direction: number, playersWithSeats?: Array<{ id: string; seatNumber?: number }>): string {
  if (playersWithSeats && playersWithSeats.length > 0) {
    const currentPlayer = playersWithSeats.find(p => p.id === currentPlayerId);
    if (!currentPlayer) {
      return playerIds[0];
    }

    const sortedPlayers = [...playersWithSeats].sort((a, b) => {
      const seatA = a.seatNumber ?? 999;
      const seatB = b.seatNumber ?? 999;
      return seatA - seatB;
    });

    const currentIndex = sortedPlayers.findIndex(p => p.id === currentPlayerId);
    if (currentIndex === -1) {
      return sortedPlayers[0].id;
    }

    let nextIndex = currentIndex + direction;
    if (nextIndex < 0) {
      nextIndex = sortedPlayers.length - 1;
    } else if (nextIndex >= sortedPlayers.length) {
      nextIndex = 0;
    }

    return sortedPlayers[nextIndex].id;
  }

  const currentIndex = playerIds.indexOf(currentPlayerId);
  if (currentIndex === -1) {
    return playerIds[0];
  }

  let nextIndex = currentIndex + direction;
  if (nextIndex < 0) {
    nextIndex = playerIds.length - 1;
  } else if (nextIndex >= playerIds.length) {
    nextIndex = 0;
  }

  return playerIds[nextIndex];
}

export async function checkUnoCall(
  gameState: GameState,
  playerId: string,
  handSize: number,
  env: any,
  roomCode: string
): Promise<void> {
  const playerIds = Object.keys(gameState.unoCalled);
  
  for (const pid of playerIds) {
    if (pid !== playerId && gameState.unoCalled[pid] === true) {
      const lastCardPlayTime = new Date(gameState.lastActivity).getTime();
      const now = new Date().getTime();
      
      if (now - lastCardPlayTime > 2000) {
        continue;
      }

      const playerResult = await env.DB.prepare('SELECT * FROM players WHERE id = ? AND room_code = ?')
        .bind(pid, roomCode)
        .first();
      const player = playerResult as { hand_json: string } | null;

      if (player) {
        const hand = JSON.parse(player.hand_json) as UnoCard[];
        if (hand.length !== 1 && gameState.unoCalled[pid]) {
          const penalty = hand.concat(gameState.drawPile.splice(0, 2));
          await env.DB.prepare('UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?')
            .bind(JSON.stringify(penalty), penalty.length, pid)
            .run();
          
          gameState.unoCalled[pid] = false;
          gameState.drawPile = gameState.drawPile;
        }
      }
    }
  }

  if (handSize === 1 && !gameState.unoCalled[playerId]) {
    setTimeout(async () => {
      const playerResult = await env.DB.prepare('SELECT * FROM players WHERE id = ? AND room_code = ?')
        .bind(playerId, roomCode)
        .first();
      const player = playerResult as { hand_json: string } | null;

      if (player) {
        const hand = JSON.parse(player.hand_json) as UnoCard[];
        if (hand.length === 1 && !gameState.unoCalled[playerId]) {
          const penalty = hand.concat(gameState.drawPile.splice(0, 2));
          env.DB.prepare('UPDATE players SET hand_json = ?, card_count = ? WHERE id = ?')
            .bind(JSON.stringify(penalty), penalty.length, playerId)
            .run();
        }
      }
    }, 2000);
  }
}
