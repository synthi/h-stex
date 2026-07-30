-- lib/lfos.lua
-- 4 free-running LFOs with ramp-tri-saw shape morphing
-- Publishes contributions to ModBus at 120Hz
-- v1.0 for h-stex

local LFOs = {}

LFOs.data = {}          -- 4 LFOs
LFOs.patch_mode = nil   -- lfo_id activo en patch (nil si no hay)
LFOs.patch_target = nil -- param_id seleccionado para editar depth
LFOs.clock_ids = {}     -- clock coroutine IDs

-- Wave shape: 0=ramp, 0.5=triangle, 1=saw (continuous crossfade)
local function calc_wave(phase_norm, shape)
   -- phase_norm: 0..1
   local ramp = phase_norm * 2 - 1                    -- -1→1
   local tri  = 2 * math.abs(2 * phase_norm - 1) - 1  -- -1→1→-1
   local saw  = (1 - phase_norm) * 2 - 1               -- 1→-1
   if shape <= 0.5 then
      local t = shape / 0.5
      return ramp * (1 - t) + tri * t
   else
      local t = (shape - 0.5) / 0.5
      return tri * (1 - t) + saw * t
   end
end

function LFOs.init()
   LFOs.data = {}
   LFOs.patch_mode = nil
   LFOs.patch_target = nil
   local default_freqs = {0.05, 0.12, 0.25, 0.42}
   for i = 1, 4 do
      LFOs.data[i] = {
         freq = default_freqs[i],
         shape = 0.5,    -- 0=ramp, 0.5=tri, 1=saw
         phase = math.random() * 2 * math.pi,
         value = 0.0,
         assignments = {},  -- {param_id, depth}
         history = {},
         history_head = 1,
      }
      for j = 1, 128 do LFOs.data[i].history[j] = 0 end
      LFOs.clock_ids[i] = clock.run(function() LFOs._run(i) end)
   end
end

function LFOs.cleanup()
   for i = 1, 4 do
      if LFOs.clock_ids[i] then
         clock.cancel(LFOs.clock_ids[i])
         LFOs.clock_ids[i] = nil
      end
      if ModBus then ModBus.clear_source("lfo" .. i) end
   end
   LFOs.data = {}
   LFOs.patch_mode = nil
   LFOs.patch_target = nil
end

-- LFO coroutine: runs at 120Hz
function LFOs._run(id)
   local lfo = LFOs.data[id]
   if not lfo then return end
   while true do
      LFOs._tick(id)
      clock.sleep(1/120)
   end
end

function LFOs._tick(id)
   local lfo = LFOs.data[id]
   if not lfo then return end

   -- Advance phase
   lfo.phase = lfo.phase + (2 * math.pi * lfo.freq / 120)
   if lfo.phase > 2 * math.pi then lfo.phase = lfo.phase - 2 * math.pi end

   local phase_norm = lfo.phase / (2 * math.pi)
   lfo.value = calc_wave(phase_norm, lfo.shape)

   -- Push to history ALWAYS (for scope)
   lfo.history_head = (lfo.history_head % 128) + 1
   lfo.history[lfo.history_head] = lfo.value

   -- Publish contributions to ModBus
   for _, a in ipairs(lfo.assignments) do
      local param_id, depth = a[1], a[2]
      local p = params:lookup_param(param_id)
      if p then
         local range = p.controlspec.maxval - p.controlspec.minval
         local contrib = ((lfo.value + 1) / 2) * depth * range
         ModBus.set_contrib("lfo" .. id, param_id, contrib)
      end
   end
end

-- Connect LFO to param, or select if already connected
function LFOs.connect_or_select(lfo_id, param_id)
   if not LFOs.data[lfo_id] then return end
   for _, a in ipairs(LFOs.data[lfo_id].assignments) do
      if a[1] == param_id then
         LFOs.patch_target = param_id
         return
      end
   end
   table.insert(LFOs.data[lfo_id].assignments, {param_id, 0.25})
   LFOs.patch_target = param_id
end

-- Remove assignment
function LFOs.remove_assignment(lfo_id, param_id)
   if not LFOs.data[lfo_id] then return end
   for idx, a in ipairs(LFOs.data[lfo_id].assignments) do
      if a[1] == param_id then
         table.remove(LFOs.data[lfo_id].assignments, idx)
         ModBus.clear_contrib("lfo" .. lfo_id, param_id)
         if LFOs.patch_target == param_id then LFOs.patch_target = nil end
         return
      end
   end
end

-- Remove current patch_target (used with SHIFT in patch mode)
function LFOs.remove_current_target()
   if not LFOs.patch_mode or not LFOs.patch_target then return end
   LFOs.remove_assignment(LFOs.patch_mode, LFOs.patch_target)
end

-- Clear all assignments for an LFO
function LFOs.clear_assignments(lfo_id)
   if not LFOs.data[lfo_id] then return end
   for _, a in ipairs(LFOs.data[lfo_id].assignments) do
      ModBus.clear_contrib("lfo" .. lfo_id, a[1])
   end
   LFOs.data[lfo_id].assignments = {}
   LFOs.patch_target = nil
end

function LFOs.clear_all()
   for i = 1, 4 do
      if LFOs.data[i] then
         for _, a in ipairs(LFOs.data[i].assignments) do
            ModBus.clear_contrib("lfo" .. i, a[1])
         end
         LFOs.data[i].assignments = {}
      end
   end
   LFOs.patch_target = nil
end

-- Adjust depth of current patch_target
function LFOs.adjust_depth(delta)
   local id = LFOs.patch_mode
   local param_id = LFOs.patch_target
   if not id or not param_id or not LFOs.data[id] then return end
   for _, a in ipairs(LFOs.data[id].assignments) do
      if a[1] == param_id then
         a[2] = util.clamp(a[2] + delta / 100, -1, 1)
         break
      end
   end
end

-- Flip polarity of current patch_target
function LFOs.flip_polarity()
   local id = LFOs.patch_mode
   local param_id = LFOs.patch_target
   if not id or not param_id or not LFOs.data[id] then return end
   for _, a in ipairs(LFOs.data[id].assignments) do
      if a[1] == param_id then
         a[2] = -a[2]
         break
      end
   end
end

-- Cycle to next assignment target
function LFOs.next_target()
   local id = LFOs.patch_mode
   if not id or not LFOs.data[id] then return end
   local lfo = LFOs.data[id]
   if #lfo.assignments == 0 then return end
   local current_idx = nil
   for idx, a in ipairs(lfo.assignments) do
      if a[1] == LFOs.patch_target then current_idx = idx; break end
   end
   if not current_idx then
      LFOs.patch_target = lfo.assignments[1][1]
   else
      local next_idx = current_idx + 1
      if next_idx > #lfo.assignments then next_idx = 1 end
      LFOs.patch_target = lfo.assignments[next_idx][1]
   end
end

-- Adjust frequency of current patch_mode LFO
function LFOs.adjust_freq(delta)
   local id = LFOs.patch_mode
   if not id or not LFOs.data[id] then return end
   local lfo = LFOs.data[id]
   lfo.freq = util.clamp(lfo.freq + delta * 0.01, 0.01, 12)
end

-- Adjust shape of current patch_mode LFO
function LFOs.adjust_shape(delta)
   local id = LFOs.patch_mode
   if not id or not LFOs.data[id] then return end
   local lfo = LFOs.data[id]
   lfo.shape = util.clamp(lfo.shape + delta * 0.05, 0, 1)
end

-- Get depth of current patch_target
function LFOs.get_current_depth()
   local id = LFOs.patch_mode
   local param_id = LFOs.patch_target
   if not id or not param_id or not LFOs.data[id] then return 0 end
   for _, a in ipairs(LFOs.data[id].assignments) do
      if a[1] == param_id then return a[2] end
   end
   return 0
end

-- Get target index info
function LFOs.get_target_info()
   local id = LFOs.patch_mode
   if not id or not LFOs.data[id] then return 0, 0 end
   local lfo = LFOs.data[id]
   local total = #lfo.assignments
   if total == 0 then return 0, 0 end
   local current_idx = 1
   for idx, a in ipairs(lfo.assignments) do
      if a[1] == LFOs.patch_target then current_idx = idx; break end
   end
   return current_idx, total
end

-- Serialize for PSET
function LFOs.get_state()
   local state = {}
   for i = 1, 4 do
      if LFOs.data[i] then
         local lfo = LFOs.data[i]
         local assignments = {}
         for _, a in ipairs(lfo.assignments) do
            table.insert(assignments, {a[1], a[2]})
         end
         state[i] = {
            freq = lfo.freq,
            shape = lfo.shape,
            assignments = assignments,
         }
      end
   end
   return state
end

-- Restore from PSET
function LFOs.set_state(state)
   if not state then return end
   for i = 1, 4 do
      if state[i] and LFOs.data[i] then
         local s = state[i]
         LFOs.data[i].freq = s.freq or 0.25
         LFOs.data[i].shape = s.shape or 0.5
         LFOs.data[i].assignments = {}
         if s.assignments then
            for _, a in ipairs(s.assignments) do
               table.insert(LFOs.data[i].assignments, {a[1], a[2]})
            end
         end
      end
   end
   LFOs.patch_target = nil
end

return LFOs