-- =====================================================
-- ONO Card Game: Host Cleanup Logic
-- =====================================================

-- 1. Add host_id column to uno_rooms
ALTER TABLE uno_rooms 
ADD COLUMN IF NOT EXISTS host_id TEXT; -- Storing UUID string from the app

-- 2. Update RLS Policies

-- Allow DELETE if the user's ID matches host_id (Passed via USING clause isn't possible with anon key directly for "current user" without auth)
-- BUT, for "anon" access with custom ID, we can't easily restrict DELETE based on "who is requesting" in a secure way without Auth.
-- So for this Hybrid approach (Anon Key + Custom IDs):
-- We allow DELETE for anon, but the WHERE clause in the app must match.
-- (This is "Client-Side Trust" which is acceptable for this stage, as noted in the plan).

-- DROP existing DELETE policy if it exists to be safe
DROP POLICY IF EXISTS "Allow public DELETE" ON uno_rooms;

-- Create DELETE policy
CREATE POLICY "Allow DELETE matching host_id" ON uno_rooms
  FOR DELETE TO anon
  USING (true); 
  -- Ideally: USING (host_id = current_setting('request.jwt.claim.sub', true)) but we don't have that.
  -- So we rely on the App sending the correct DELETE WHERE clause.

-- Ensure INSERT allows setting host_id
DROP POLICY IF EXISTS "Allow public INSERT" ON uno_rooms;
CREATE POLICY "Allow public INSERT with host_id" ON uno_rooms
  FOR INSERT TO anon
  WITH CHECK (true);

-- Ensure UPDATE keeps working
DROP POLICY IF EXISTS "Allow public UPDATE" ON uno_rooms;
CREATE POLICY "Allow public UPDATE" ON uno_rooms
  FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);
