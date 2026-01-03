-- =====================================================
-- ONO Card Game: Supabase Database Setup
-- Migration for uno_rooms table with Realtime & RLS
-- =====================================================

-- 1. Create the uno_rooms table
CREATE TABLE IF NOT EXISTS uno_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code TEXT UNIQUE NOT NULL,
  game_state JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create index for faster room_code lookups
CREATE INDEX IF NOT EXISTS idx_uno_rooms_room_code ON uno_rooms(room_code);

-- 3. Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE uno_rooms;

-- 4. Enable Row Level Security (RLS)
ALTER TABLE uno_rooms ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS Policies for public 'anon' access
-- Allow SELECT (read game state)
CREATE POLICY "Allow public SELECT" ON uno_rooms
  FOR SELECT TO anon
  USING (true);

-- Allow INSERT (create new rooms)
CREATE POLICY "Allow public INSERT" ON uno_rooms
  FOR INSERT TO anon
  WITH CHECK (true);

-- Allow UPDATE (update game state)
CREATE POLICY "Allow public UPDATE" ON uno_rooms
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);

-- Allow DELETE (cleanup after game ends)
CREATE POLICY "Allow public DELETE" ON uno_rooms
  FOR DELETE TO anon
  USING (true);

-- 6. Auto-update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_uno_rooms_updated_at
  BEFORE UPDATE ON uno_rooms
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- Done! Your uno_rooms table is ready for real-time sync.
-- =====================================================
