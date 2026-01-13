# ISAR Local Caching Setup

## Overview
This project uses ISAR as a local state mirror for production-grade caching and sync architecture.

## Setup Instructions

### 1. Generate ISAR Models
After adding ISAR models, you must generate the schema files:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This will generate `lib/models/isar_models.g.dart` which contains the schema definitions.

### 2. Architecture Flow

**Data Flow:**
```
Backend (Authoritative)
    ↓
CloudflareService (Network)
    ↓
Validation + Normalization
    ↓
ISAR (Local State Mirror)
    ↓
Providers / State Notifiers
    ↓
Flutter UI
```

**User Actions:**
```
User Action
    ↓
Optimistic Write to ISAR
    ↓
Instant UI Update
    ↓
Send Intent to Backend
    ↓
Backend Validation
    ↓
Confirmed Event from Poll
    ↓
ISAR Reconciliation (Confirm or Rollback)
```

### 3. ISAR Models

- **GameStateSnapshot**: Stores game state with version tracking
- **DiscardPileCard**: Stores discard pile cards with ordering
- **PlayerSnapshot**: Stores player information
- **PlayerHand**: Stores player hands (encrypted/JSON)
- **GameEvent**: Event queue for animations and UI updates
- **SyncMetadata**: Tracks sync state and version

### 4. Key Features

- **Atomic Writes**: All ISAR writes are atomic transactions
- **Version Checking**: Rejects stale state versions
- **Optimistic Updates**: Instant UI feedback before backend confirmation
- **Event-Driven UI**: Animations triggered by events, not network timing
- **Desync Recovery**: Full snapshot fetch on reconnect
- **Rollback Support**: Reverts optimistic updates on backend rejection

### 5. Important Notes

- ISAR is initialized in `main.dart` before app start
- All room data is cleared when leaving a room
- Full sync is triggered when `needsFullSync` flag is set
- Events are marked as applied after successful backend confirmation
- Pending events are cleared on successful sync
