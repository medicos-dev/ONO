-- 1. Enable Realtime for your tables (idempotent - safe to run multiple times)
-- This ensures that 'stream()' in Flutter actually receives updates
DO $$
BEGIN
  -- Add uno_rooms if not already in publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'uno_rooms'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE uno_rooms;
  END IF;
  
  -- Add room_players if not already in publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'room_players'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE room_players;
  END IF;
END $$;

-- 2. Temporarily disable RLS (Row Level Security)
-- This ensures that permissions aren't silently blocking the Host from seeing Joiners
-- Note: These are idempotent - disabling an already disabled RLS is safe
ALTER TABLE uno_rooms DISABLE ROW LEVEL SECURITY;
ALTER TABLE room_players DISABLE ROW LEVEL SECURITY;
