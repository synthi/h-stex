-- storage.lua
-- persistent state for h-stex (notes, hold, loop, octave)
-- v1.0

local Storage = {}

local function state_path()
   return norns.state.data .. "host_state.data"
end

-- Save current state to disk
-- @param playing      table of active notes (each: {note, x, y, ...})
-- @param hold         boolean (poly_hold state)
-- @param loop         boolean (poly_loop state)
-- @param oct          number (current octave)
-- @param oct_state_1  number (0-2, left oct button cycle)
-- @param oct_state_3  number (0-2, right oct button cycle)
function Storage.save(playing, hold, loop, oct, oct_state_1, oct_state_3)
   local data = {
      notes        = {},
      hold         = hold,
      loop         = loop,
      oct          = oct,
      oct_state_1  = oct_state_1,
      oct_state_3  = oct_state_3,
   }
   for _, n in ipairs(playing) do
      table.insert(data.notes, {note = n.note, x = n.x, y = n.y})
   end
   tab.save(data, state_path())
end

-- Load saved state from disk
-- @return table with .notes, .hold, .loop, .oct or nil
function Storage.load()
   local ok, data = pcall(tab.load, state_path())
   if ok and data then
      return data
   end
   return nil
end

return Storage