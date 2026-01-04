-- =====================================================
-- Revert discard_pile column - use game_state JSONB instead
-- =====================================================

-- Drop the discard_pile column
ALTER TABLE uno_rooms
DROP COLUMN IF EXISTS discard_pile;

-- Drop the index
DROP INDEX IF EXISTS idx_uno_rooms_discard_pile;

-- Restore the original update_game_state function (3 parameters)
DROP FUNCTION IF EXISTS update_game_state(TEXT, JSONB, TEXT, JSONB);

CREATE OR REPLACE FUNCTION update_game_state(
  p_room_code TEXT,
  p_game_state JSONB,
  p_status TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  -- Update the room
  UPDATE uno_rooms
  SET 
    game_state = p_game_state,
    status = COALESCE(p_status, status)
  WHERE room_code = p_room_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION update_game_state(TEXT, JSONB, TEXT) TO anon;

