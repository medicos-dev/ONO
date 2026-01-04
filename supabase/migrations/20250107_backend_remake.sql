-- =====================================================
-- Backend Remake: Enhanced Database Functions
-- This migration adds RPC functions for atomic operations
-- =====================================================

-- 1. Function to add a player to a room (atomic operation)
-- This ensures both room_players and game_state are updated together
CREATE OR REPLACE FUNCTION add_player_to_room(
  p_room_code TEXT,
  p_player_id TEXT,
  p_player_name TEXT,
  p_host_id TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_room_id UUID;
  v_game_state JSONB;
  v_players JSONB;
  v_new_player JSONB;
  v_updated_state JSONB;
BEGIN
  -- Get room ID and current game state
  SELECT id, game_state INTO v_room_id, v_game_state
  FROM uno_rooms
  WHERE room_code = p_room_code;
  
  IF v_room_id IS NULL THEN
    RAISE EXCEPTION 'Room not found';
  END IF;
  
  -- Check if player already exists in room_players
  IF EXISTS (
    SELECT 1 FROM room_players 
    WHERE room_id = v_room_id AND player_id = p_player_id
  ) THEN
    -- Player already exists, return current state
    RETURN v_game_state;
  END IF;
  
  -- Insert player into room_players table
  INSERT INTO room_players (room_id, player_id, player_name, is_ready, cards)
  VALUES (v_room_id, p_player_id, p_player_name, false, '[]'::jsonb)
  ON CONFLICT (room_id, player_id) DO NOTHING;
  
  -- Update game_state JSONB to include new player
  -- Extract players array from game_state
  v_players := COALESCE(v_game_state->'p', v_game_state->'players', '[]'::jsonb);
  
  -- Create new player object (compact format)
  v_new_player := jsonb_build_object(
    'i', p_player_id,
    'n', p_player_name,
    'h', '[]'::jsonb,
    'r', false
  );
  
  -- Add player to players array if not already present
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_players) AS elem
    WHERE elem->>'i' = p_player_id OR elem->>'id' = p_player_id
  ) THEN
    v_players := v_players || jsonb_build_array(v_new_player);
  END IF;
  
  -- Update game_state with new players array
  v_updated_state := v_game_state || jsonb_build_object('p', v_players);
  
  -- Also update hands map if it exists
  IF v_updated_state ? 'hands' THEN
    v_updated_state := v_updated_state || jsonb_build_object(
      'hands', COALESCE(v_updated_state->'hands', '{}'::jsonb) || jsonb_build_object(p_player_id, '[]'::jsonb)
    );
  END IF;
  
  -- Update hostId if not set
  IF v_updated_state->>'hostId' IS NULL OR v_updated_state->>'hostId' = '' THEN
    v_updated_state := v_updated_state || jsonb_build_object('hostId', p_host_id);
  END IF;
  
  -- Update the room with new game_state
  UPDATE uno_rooms
  SET game_state = v_updated_state
  WHERE room_code = p_room_code;
  
  RETURN v_updated_state;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Function to sync players from room_players to game_state
-- This ensures game_state always has the latest players from room_players
CREATE OR REPLACE FUNCTION sync_players_to_game_state(p_room_code TEXT)
RETURNS JSONB AS $$
DECLARE
  v_room_id UUID;
  v_game_state JSONB;
  v_players_array JSONB := '[]'::jsonb;
  v_player_record RECORD;
BEGIN
  -- Get room ID
  SELECT id INTO v_room_id
  FROM uno_rooms
  WHERE room_code = p_room_code;
  
  IF v_room_id IS NULL THEN
    RAISE EXCEPTION 'Room not found';
  END IF;
  
  -- Get current game_state
  SELECT game_state INTO v_game_state
  FROM uno_rooms
  WHERE room_code = p_room_code;
  
  -- Build players array from room_players table (source of truth)
  FOR v_player_record IN
    SELECT player_id, player_name, is_ready, cards
    FROM room_players
    WHERE room_id = v_room_id
    ORDER BY created_at NULLS LAST, id
  LOOP
    -- Get existing hand from game_state if available, otherwise use cards from room_players
    DECLARE
      v_existing_hand JSONB;
    BEGIN
      -- Try to get hand from game_state hands map
      IF v_game_state ? 'hands' AND v_game_state->'hands' ? v_player_record.player_id THEN
        v_existing_hand := v_game_state->'hands'->v_player_record.player_id;
      -- Try to get hand from players array
      ELSIF v_game_state ? 'p' THEN
        SELECT elem->'h' INTO v_existing_hand
        FROM jsonb_array_elements(v_game_state->'p') AS elem
        WHERE elem->>'i' = v_player_record.player_id OR elem->>'id' = v_player_record.player_id
        LIMIT 1;
      END IF;
      
      -- Use existing hand if found, otherwise use cards from room_players
      IF v_existing_hand IS NULL THEN
        v_existing_hand := COALESCE(v_player_record.cards, '[]'::jsonb);
      END IF;
      
      -- Add player to array (compact format)
      v_players_array := v_players_array || jsonb_build_object(
        'i', v_player_record.player_id,
        'n', v_player_record.player_name,
        'h', v_existing_hand,
        'r', COALESCE(v_player_record.is_ready, false)
      );
    END;
  END LOOP;
  
  -- Update game_state with synced players
  v_game_state := COALESCE(v_game_state, '{}'::jsonb) || jsonb_build_object('p', v_players_array);
  
  -- Update the room
  UPDATE uno_rooms
  SET game_state = v_game_state
  WHERE room_code = p_room_code;
  
  RETURN v_game_state;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Function to update game state atomically
CREATE OR REPLACE FUNCTION update_game_state(
  p_room_code TEXT,
  p_game_state JSONB,
  p_status TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_update_data JSONB := jsonb_build_object('game_state', p_game_state);
BEGIN
  -- Add status if provided
  IF p_status IS NOT NULL THEN
    v_update_data := v_update_data || jsonb_build_object('status', p_status);
  END IF;
  
  -- Update the room
  UPDATE uno_rooms
  SET 
    game_state = p_game_state,
    status = COALESCE(p_status, status)
  WHERE room_code = p_room_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Grant execute permissions
GRANT EXECUTE ON FUNCTION add_player_to_room TO anon;
GRANT EXECUTE ON FUNCTION sync_players_to_game_state TO anon;
GRANT EXECUTE ON FUNCTION update_game_state TO anon;

