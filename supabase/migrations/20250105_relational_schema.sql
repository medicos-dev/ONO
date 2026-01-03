-- 1. Reset (Clear old tables to prevent conflicts)
DROP TABLE IF EXISTS public.room_players;
DROP TABLE IF EXISTS public.uno_rooms;

-- 2. Create the Rooms Table (The Container)
CREATE TABLE public.uno_rooms (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    room_code TEXT UNIQUE NOT NULL,
    host_id TEXT NOT NULL, -- Storing Local UUID
    status TEXT DEFAULT 'lobby', -- 'lobby', 'playing', 'finished'
    game_state JSONB DEFAULT '{}', -- Stores deck, pile, current_color, turn info
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Create the Players Table (The Roster)
-- This fixes the concurrency bug. Joining is just a simple INSERT.
CREATE TABLE public.room_players (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    room_id UUID REFERENCES public.uno_rooms(id) ON DELETE CASCADE,
    player_id TEXT NOT NULL,
    player_name TEXT,
    is_ready BOOLEAN DEFAULT false,
    cards JSONB DEFAULT '[]', -- The player's hand
    UNIQUE(room_id, player_id) -- Prevent duplicate joins
);

-- 4. Open Security Gates (For Local UUID Dev Mode)
ALTER TABLE public.uno_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_players ENABLE ROW LEVEL SECURITY;

-- Note: In production, you might want stricter policies, but for this 'local uuid' architecture,
-- we rely on the room_code knowledge as the "key".
CREATE POLICY "Allow All Rooms" ON public.uno_rooms FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow All Players" ON public.room_players FOR ALL USING (true) WITH CHECK (true);

-- 5. Enable Realtime
-- Important: We need 'replica identity full' usually if we want detailed old/new records,
-- but for now default is okay. Adding to publication is key.
ALTER PUBLICATION supabase_realtime ADD TABLE public.uno_rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE public.room_players;
