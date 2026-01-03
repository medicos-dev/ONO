-- 1. Enable Realtime for your tables
-- This ensures that 'stream()' in Flutter actually receives updates
alter publication supabase_realtime add table uno_rooms;
alter publication supabase_realtime add table room_players;

-- 2. Temporarily disable RLS (Row Level Security)
-- This ensures that permissions aren't silently blocking the Host from seeing Joiners
alter table uno_rooms disable row level security;
alter table room_players disable row level security;
