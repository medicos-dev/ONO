-- Add players_data column to store lightweight player info for joining
-- This allows clients to "write" their presence without overwriting the full game_state
ALTER TABLE uno_rooms 
ADD COLUMN players_data JSONB DEFAULT '[]'::jsonb;

-- Policy: Allow anyone to update players_data (logic handled by app)
-- Note: Existing policies allowing UPDATE on uno_rooms should cover this if they are USING (true)

-- RPC to safetly append player to the list
create or replace function join_room(p_room_code text, p_player jsonb)
returns void as $$
begin
  update uno_rooms
  set players_data = case 
      when players_data is null then '[]'::jsonb || p_player
      else players_data || p_player
  end
  where room_code = p_room_code;
end;
$$ language plpgsql security definer;

