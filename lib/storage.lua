-- storage.lua
-- persistent state for h-stex (notes, hold, loop, octave, envelope params)
-- v1.3 — per-PSET storage with cycle_len for reproducible loop timing

local Storage = {}

local function state_path()
   return norns.state.data .. "host_state.data"
end

local function pset_path(number)
   return _path.data .. "host/" .. string.format("%02d", number) .. "_state.data"
end

-- Save current state to disk (cleanup / global fallback)
-- @param playing      table of active notes (each: {note, x, y, timestamp, ...})
-- @param hold         boolean (poly_hold state)
-- @param loop         boolean (poly_loop state)
-- @param oct          number (current octave 0..4)
-- @param cycle_len    number (pre-calculated envelope cycle length for loop)
function Storage.save(playing, hold, loop, oct, cycle_len)
   local data = {
      notes = {},
      hold  = hold,
      loop  = loop,
      oct   = oct,
      cycle_len = cycle_len or 0.02,
   }
   for _, n in ipairs(playing) do
      table.insert(data.notes, {note = n.note, x = n.x, y = n.y, timestamp = n.timestamp})
   end
   tab.save(data, state_path())
end

-- Load saved state from disk
-- @return table with .notes, .hold, .loop, .oct, .cycle_len or nil
function Storage.load()
   local ok, data = pcall(tab.load, state_path())
   if ok and data then
      return data
   end
   return nil
end

-- Save state for a specific PSET number
-- @param number       PSET number (1-based)
-- @param playing      table of active notes
-- @param hold         boolean
-- @param loop         boolean
-- @param oct          number (0..4)
-- @param cycle_len    number (pre-calculated envelope cycle length for loop)
function Storage.save_pset(number, playing, hold, loop, oct, cycle_len, sequencers)
   if not number then return end
   if not util.file_exists(_path.data .. "host") then
      util.make_dir(_path.data .. "host")
   end
   local data = {
      notes = {},
      hold  = hold,
      loop  = loop,
      oct   = oct,
      cycle_len = cycle_len or 0.02,
      sequencers = {},
   }
   for _, n in ipairs(playing) do
      table.insert(data.notes, {note = n.note, x = n.x, y = n.y, timestamp = n.timestamp})
   end
   if sequencers then
      for i = 1, 4 do
         local s = sequencers[i]
         data.sequencers[i] = {
            data = s.data,
            state = s.state,
            duration = s.duration,
         }
      end
   end
   tab.save(data, pset_path(number))
end

-- Load state for a specific PSET number
-- @param number PSET number (1-based)
-- @return table or nil
function Storage.load_pset(number)
   if not number then return nil end
   local path = pset_path(number)
   if util.file_exists(path) then
      local ok, data = pcall(tab.load, path)
      if ok and data then
         if data.sequencers then
            for i = 1, 4 do
               local s = data.sequencers[i]
               if s and s.data and #s.data > 0 then
                  s.state = 3  -- stopped with data
                  s.duration = s.duration or 0
               else
                  data.sequencers[i] = {data = {}, state = 0, duration = 0}
               end
            end
         end
         return data
      end
   end
   return nil
end

return Storage