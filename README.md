🎴 ONO - Multiplayer UNO Card Game
Project Overview
This is a real-time multiplayer UNO card game built with Flutter and Supabase. It uses a Host-Authority architecture where one player (the Host) controls the game state and synchronizes it with all other players (Clients).

📁 Project Structure
lib/
├── main.dart              # App entry point, Supabase init
├── models/                # Data models
│   ├── uno_card.dart      # Card type, color, value definitions
│   ├── player.dart        # Player model (id, name, hand, isHost)
│   └── game_state.dart    # Complete game state (deck, discard, players, turn)
├── logic/                 # Pure game rules
│   ├── deck_generator.dart # Generates shuffled 108-card deck
│   └── game_logic.dart    # Card validation, effects (+2, skip, reverse)
├── providers/             # State management
│   └── game_provider.dart # Central game controller (ChangeNotifier)
├── services/              # Backend communication
│   ├── message_types.dart # Message type constants
│   └── supabase_uno_service.dart # Supabase Realtime sync
├── screens/               # UI screens
│   ├── splash_screen.dart # Loading/landing screen
│   ├── lobby_screen.dart  # Room creation/joining
│   └── game_screen.dart   # Main gameplay UI
└── widgets/               # Reusable UI components
    ├── uno_card_widget.dart # Card display widget
    ├── horseshoe_history.dart # Discard pile history fan
    ├── podium_screen.dart # Winner podium
    └── wild_celebration.dart # Wild card animation
🔄 Game Flow
Phase 1: Lobby
┌─────────────────┐     ┌─────────────────┐
│  Player 1       │     │  Player 2       │
│  (CREATE ROOM)  │     │  (JOIN ROOM)    │
│  becomes HOST   │     │  becomes CLIENT │
└────────┬────────┘     └────────┬────────┘
         │                       │
         │  Room Code: "ABC123"  │
         │◄──────────────────────┤ Joins via code
         │                       │
         ▼                       ▼
   ┌──────────────────────────────────┐
   │         LOBBY SCREEN             │
   │  Waiting for players...          │
   │  [Start Game] (Host only)        │
   └──────────────────────────────────┘
Phase 2: Game Start (Host)
Host clicks "Start Game"
GameLogic.initializeGame() runs:
Generates 108-card shuffled deck
Deals 7 cards to each player
Sets phase to playing
Host pushes state to Supabase DB atomically
Broadcasts to all clients via Realtime
Phase 3: Gameplay Loop
┌─────────────────────────────────────────┐
│              HOST DEVICE                │
│  ┌─────────────────────────────────┐   │
│  │     GAME STATE (Source of Truth) │   │
│  │  - drawPile: [cards...]         │   │
│  │  - discardPile: [cards...]      │   │
│  │  - players: [{hand: [...]}]     │   │
│  │  - currentPlayerIndex: 0        │   │
│  └─────────────────────────────────┘   │
│              │                          │
│              │ _broadcastGameState()    │
│              ▼                          │
│     ┌──────────────────┐               │
│     │ Supabase DB      │               │
│     │ (game_state col) │               │
│     └────────┬─────────┘               │
└──────────────┼──────────────────────────┘
               │
   ┌───────────┴───────────┐
   ▼                       ▼
┌───────────┐       ┌───────────┐
│ CLIENT 1  │       │ CLIENT 2  │
│ Receives  │       │ Receives  │
│ state via │       │ state via │
│ Realtime  │       │ Realtime  │
└───────────┘       └───────────┘
🔧 Backend (Supabase)
Database Schema
Table: uno_rooms

Column	Type	Description
id	UUID	Primary key
room_code	TEXT	6-char join code
host_id	TEXT	Host's player ID
status	TEXT	lobby, playing, finished
game_state	JSONB	Full game state (deck, hands, etc.)
Table: room_players

Column	Type	Description
room_id	UUID	FK to uno_rooms
player_id	TEXT	Unique player ID
player_name	TEXT	Display name
cards	JSONB	Player's hand
📡 Key Backend Functions (
supabase_uno_service.dart
)
Function	Role	Description
connect()
Both	Join/create room, start subscriptions
_createRoom()
Host	Insert new room in DB
_joinRoom()
Client	Upsert self into room_players
startRemoteGame()
Host	Atomically set status=playing + game_state
updateRemoteGameState()
Host	Push updated state to DB
send()
Both	Ephemeral broadcast (moves, UNO calls)
deleteRoom()
Host	Cleanup after game ends
🎮 Key Provider Functions (
game_provider.dart
)
Host Functions
Function	Description
createRoom()
Initialize room, connect as host
startGame()
Deal cards, start playing phase
_handleMoveAttempt()
Validate & apply client moves
_broadcastGameState()
Sync state to all clients
_kickPlayer()
Remove player, redistribute cards
Client Functions
Function	Description
joinRoom()
Connect, send JOIN_REQUEST
_handleGameState()
Parse incoming state, update UI
playCard()
Send MOVE_ATTEMPT to host
drawCard()
Request card from host
Shared Functions
Function	Description
callUno()
Broadcast UNO call
resign()
Leave game, return cards to deck
🃏 Game Logic (
game_logic.dart
)
Function	Description
initializeGame()
Shuffle deck, deal 7 cards each
isValidMove()
Check if card can be played (color/value match)
applyCardEffect()
Handle +2, +4, Skip, Reverse effects
drawCard()
Move card from deck to player hand
passTurn()
Advance to next player
📨 Message Types
Type	Direction	Purpose
GAME_STATE	Host→All	Full state sync (persistent)
MOVE_ATTEMPT	Client→Host	Request to play card
DRAW_REQUEST	Client→Host	Request to draw
UNO_CALL	Any→All	Broadcast "UNO!"
PREPARE_GAME	Host→All	Pre-start handshake
GO_LIVE	Host→All	Game officially started
🛡️ Recent Fixes Applied
Host Initialization - Added _gameStarted flag to validate game state before sync
Lobby Reversion - 
_broadcastGameState()
 forces phase: playing after game starts
Room Deletion - Only Host can delete rooms (clients ignore empty room data)
Horseshoe History - Cards display in polar-coordinate arc with rotation
This architecture ensures low-latency gameplay with Supabase Realtime while maintaining consistency through Host-authority game logic! 🎮