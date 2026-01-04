-- =====================================================
-- Add discard_pile column to uno_rooms table
-- This allows for separate tracking of discard pile updates
-- =====================================================

-- Add discard_pile column as JSONB (stores array of cards)
ALTER TABLE uno_rooms
ADD COLUMN IF NOT EXISTS discard_pile JSONB DEFAULT '[]'::jsonb;

-- Create index for faster queries (optional, but helpful)
CREATE INDEX IF NOT EXISTS idx_uno_rooms_discard_pile 
ON uno_rooms USING gin (discard_pile);

-- Drop the old update_game_state function first (if it exists)
DROP FUNCTION IF EXISTS update_game_state(TEXT, JSONB, TEXT);

-- Update the update_game_state function to also handle discard_pile
CREATE OR REPLACE FUNCTION update_game_state(
  p_room_code TEXT,
  p_game_state JSONB,
  p_status TEXT DEFAULT NULL,
  p_discard_pile JSONB DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_update_data JSONB := jsonb_build_object('game_state', p_game_state);
BEGIN
  -- Add discard_pile if provided
  IF p_discard_pile IS NOT NULL THEN
    v_update_data := v_update_data || jsonb_build_object('discard_pile', p_discard_pile);
  END IF;
  
  -- Add status if provided
  IF p_status IS NOT NULL THEN
    v_update_data := v_update_data || jsonb_build_object('status', p_status);
  END IF;
  
  -- Update the room
  UPDATE uno_rooms
  SET 
    game_state = p_game_state,
    discard_pile = COALESCE(p_discard_pile, discard_pile),
    status = COALESCE(p_status, status)
  WHERE room_code = p_room_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission (specify full signature to avoid ambiguity)
GRANT EXECUTE ON FUNCTION update_game_state(TEXT, JSONB, TEXT, JSONB) TO anon;

