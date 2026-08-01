-- lib/lfos.lua
-- 4 LFOs with ramp-tri-saw shape morphing + LFNoise, free-running or clock-synced
-- Writes directly via params:set() (base_values + offset pattern)
-- v2.1 for h-stex

local LFOs = {}

LFOs.data = {}          -- 4 LFOs
LFOs.patch_mode = nil   -- lfo_id activo en patch (nil si no hay)
LFOs.patch_cursor = 1   -- item seleccionado en menu (1=shape, 2=noise, 3+=assignments)
LFOs.clock_ids = {}     -- clock coroutine IDs

-- Sync divisions: 18 values from 4/1 to 1/64 with dotted (.) and triplets (T)
LFOs.sync_divisions = {
   "4/1", "2/1", "1/1", "1/2.", "1/2", "1/2T",
   "1/4.", "1/4", "1/4T", "1/8.", "1/8", "1/8T",
   "1/16.", "1/16", "1/16T", "1/32", "1/32T", "1/64"
}
-- Beats per cycle for each division (4/1=16 beats ... 1/64=0.0625 beats)
LFOs.sync_beats = {
   16, 8, 4, 3, 2, 4/3,
   1.5, 1, 2/3, 0.75, 0.5, 1/3,
   0.375, 0.25, 1/6, 0.125, 1/12, 0.0625
}

-- Wave shape: 0=ramp, 0.5=triangle, 1=saw (continuous crossfade)
local function calc_wave(phase_norm, shape)
   local ramp = phase_norm * 2 - 1
   local tri  = 2 * math.abs(2 * phase_norm - 1) - 1
   local saw  = (1 - phase_norm) * 2 - 1
   if shape <= 0.5 then
      local t = shape / 0.5
      return ramp * (1 - t) + tri * t
   else
      local t = (shape - 0.5) / 0.5
      return tri * (1 - t) + saw * t
   end
end

function LFOs.init(base_values_ref)
   LFOs.base_values = base_values_ref or {}
   LFOs.data = {}
   LFOs.patch_mode = nil
   LFOs.patch_cursor = 1
   local default_freqs = {0.05, 0.12, 0.25, 0.42}
   for i = 1, 4 do
      LFOs.data[i] = {
         freq = default_freqs[i],
         shape = 0.5,    -- 0=ramp, 0.5=tri, 1=saw
         noise = 0.0,    -- 0=pure det, 1=pure LFNoise
         phase = math.random() * 2 * math.pi,
         value = 0.0,
         assignments = {},  -- {param_id, depth, contrib}
         history = {},
         history_head = 1,
         -- Sync state
         sync = false,     -- false=free-running Hz, true=clock-synced
         sync_div = 3,     -- index into sync_divisions (3=1/1)
         -- LFNoise state
         slew_target = math.random() * 2 - 1,
         slew_current = 0.0,
         slew_timer = 0.0,
      }
      for j = 1, 128 do LFOs.data[i].history[j] = 0 end
   end
   -- Stagger coroutine launches to avoid CPU spike on init
   clock.run(function()
      for i = 1, 4 do
         LFOs.clock_ids[i] = clock.run(function() LFOs._run(i) end)
         clock.sleep(0.02)
      end
   end)
end

function LFOs.cleanup()
   for i = 1, 4 do
      if LFOs.clock_ids[i] then
         clock.cancel(LFOs.clock_ids[i])
         LFOs.clock_ids[i] = nil
      end
   end
   LFOs.data = {}
   LFOs.patch_mode = nil
   LFOs.patch_cursor = 1
end

-- LFO coroutine: runs at 120Hz with delta timing
function LFOs._run(id)
   local lfo = LFOs.data[id]
   if not lfo then return end
   local last_time = util.time()
   while true do
      local now = util.time()
      local delta = now - last_time
      last_time = now
      LFOs._tick(id, delta)
      clock.sleep(1/120)
   end
end

function LFOs._tick(id, delta)
   local lfo = LFOs.data[id]
   if not lfo then return end

   -- If synced, recalculate freq from clock tempo
   if lfo.sync then
      local beat_sec = clock.get_beat_sec()
      local beats = LFOs.sync_beats[lfo.sync_div] or 4
      lfo.freq = 1 / (beats * beat_sec)
   end

   -- Advance phase using real delta time
   lfo.phase = lfo.phase + (2 * math.pi * lfo.freq * delta)
   if lfo.phase > 2 * math.pi then lfo.phase = lfo.phase - 2 * math.pi end

   local phase_norm = lfo.phase / (2 * math.pi)
   local det_wave = calc_wave(phase_norm, lfo.shape)

   -- LFNoise with slew: random target every 1/freq seconds, linear interp
   local noise_wave = lfo.slew_current
   lfo.slew_timer = lfo.slew_timer + delta
   local interval = 1 / lfo.freq
   if lfo.slew_timer >= interval then
      lfo.slew_timer = lfo.slew_timer - interval
      lfo.slew_target = math.random() * 2 - 1
   end
   local t = lfo.slew_timer / interval
   lfo.slew_current = lfo.slew_current + (lfo.slew_target - lfo.slew_current) * t * 0.5

   -- Mix deterministic + noise
   lfo.value = det_wave * (1 - lfo.noise) + noise_wave * lfo.noise

   -- Push to history ALWAYS (for scope)
   lfo.history_head = (lfo.history_head % 128) + 1
   lfo.history[lfo.history_head] = lfo.value

   -- Apply modulation: base_values + offset (fader is primary, LFO is offset)
   for _, a in ipairs(lfo.assignments) do
      local param_id, depth = a[1], a[2]
      local p = params:lookup_param(param_id)
      if p then
         local base_norm = LFOs.base_values[param_id]
         local base_val
         if base_norm then
            base_val = p.controlspec:map(base_norm)
         else
            base_val = p:get()
         end
         local range = p.controlspec.maxval - p.controlspec.minval
         local contrib = ((lfo.value + 1) / 2) * depth * range
         a[3] = contrib
         local new_val = util.clamp(base_val + contrib, p.controlspec.minval, p.controlspec.maxval)
         -- Engine bypass: call action directly so param value stays at base (fader position)
         if p.action then
            p.action(new_val)
         else
            params:set(param_id, new_val)
         end
      end
   end
end

-- Connect LFO to param, or select if already connected
function LFOs.connect_or_select(lfo_id, param_id)
   if not LFOs.data[lfo_id] then return end
   for _, a in ipairs(LFOs.data[lfo_id].assignments) do
      if a[1] == param_id then
         -- Already connected: select it in cursor
         LFOs._select_assignment(lfo_id, param_id)
         return
      end
   end
   table.insert(LFOs.data[lfo_id].assignments, {param_id, 0.25, 0.0})
   LFOs._select_assignment(lfo_id, param_id)
end

-- Set cursor to the assignment for this param
function LFOs._select_assignment(lfo_id, param_id)
   local lfo = LFOs.data[lfo_id]
   if not lfo then return end
   for idx, a in ipairs(lfo.assignments) do
      if a[1] == param_id then
         LFOs.patch_cursor = 2 + idx  -- 1=shape, 2=noise, 3+=assignments
         return
      end
   end
end

-- Enter patch mode: auto-select first assignment if available
function LFOs.enter_patch(lfo_id)
   LFOs.patch_mode = lfo_id
   local lfo = LFOs.data[lfo_id]
   if lfo and #lfo.assignments > 0 then
      LFOs.patch_cursor = 3  -- first assignment
   else
      LFOs.patch_cursor = 1  -- shape
   end
end

function LFOs.exit_patch()
   LFOs.patch_mode = nil
   LFOs.patch_cursor = 1
end

-- Remove assignment
function LFOs.remove_assignment(lfo_id, param_id)
   if not LFOs.data[lfo_id] then return end
   for idx, a in ipairs(LFOs.data[lfo_id].assignments) do
      if a[1] == param_id then
         table.remove(LFOs.data[lfo_id].assignments, idx)
         return
      end
   end
end

-- Remove assignment at current cursor position (if cursor is on an assignment)
function LFOs.remove_current()
   if not LFOs.patch_mode then return end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return end
   local assign_idx = LFOs.patch_cursor - 2
   if assign_idx >= 1 and assign_idx <= #lfo.assignments then
      table.remove(lfo.assignments, assign_idx)
      -- Adjust cursor
      if #lfo.assignments == 0 then
         LFOs.patch_cursor = 2  -- go to noise
      elseif LFOs.patch_cursor > #lfo.assignments + 2 then
         LFOs.patch_cursor = #lfo.assignments + 2
      end
   end
end

-- Clear all assignments for an LFO
function LFOs.clear_assignments(lfo_id)
   if not LFOs.data[lfo_id] then return end
   LFOs.data[lfo_id].assignments = {}
   if LFOs.patch_mode == lfo_id then
      LFOs.patch_cursor = math.min(LFOs.patch_cursor, 2)
   end
end

function LFOs.clear_all()
   for i = 1, 4 do
      if LFOs.data[i] then
         LFOs.data[i].assignments = {}
      end
   end
end

-- Cycle cursor (E2)
function LFOs.next_cursor()
   if not LFOs.patch_mode then return end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return end
   local max_cursor = 2 + #lfo.assignments
   LFOs.patch_cursor = LFOs.patch_cursor + 1
   if LFOs.patch_cursor > max_cursor then LFOs.patch_cursor = 1 end
end

-- Adjust value at current cursor (E3)
function LFOs.adjust_value(delta)
   if not LFOs.patch_mode then return end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return end
   if LFOs.patch_cursor == 1 then
      -- shape
      lfo.shape = util.clamp(lfo.shape + delta * 0.02, 0, 1)
   elseif LFOs.patch_cursor == 2 then
      -- noise
      lfo.noise = util.clamp(lfo.noise + delta * 0.02, 0, 1)
   else
      -- assignment depth
      local assign_idx = LFOs.patch_cursor - 2
      if assign_idx >= 1 and assign_idx <= #lfo.assignments then
         local a = lfo.assignments[assign_idx]
         a[2] = util.clamp(a[2] + delta / 100, -1, 1)
      end
   end
end

-- Flip polarity (K2 short tap) - only if cursor is on an assignment
function LFOs.flip_polarity()
   if not LFOs.patch_mode then return end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return end
   local assign_idx = LFOs.patch_cursor - 2
   if assign_idx >= 1 and assign_idx <= #lfo.assignments then
      lfo.assignments[assign_idx][2] = -lfo.assignments[assign_idx][2]
   end
end

-- Reset current parameter to default (K2 hold >0.5s)
function LFOs.reset_current()
   if not LFOs.patch_mode then return end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return end
   if LFOs.patch_cursor == 1 then
      lfo.shape = 0.5  -- default: triangle
   elseif LFOs.patch_cursor == 2 then
      lfo.noise = 0.0  -- default: pure deterministic
   else
      -- Assignment: disconnect (remove)
      LFOs.remove_current()
   end
end

-- Toggle sync mode (K3) - resets phase to 0 so synced LFOs align
function LFOs.toggle_sync()
   if not LFOs.patch_mode then return end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return end
   lfo.sync = not lfo.sync
   if lfo.sync then
      lfo.phase = 0  -- reset phase so all synced LFOs are aligned
      lfo.slew_timer = 0
   end
end

-- Adjust frequency/division (E1, always available in patch mode)
function LFOs.adjust_freq(delta)
   if not LFOs.patch_mode then return end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return end
   if lfo.sync then
      -- In sync mode: change division
      lfo.sync_div = util.clamp(lfo.sync_div + delta, 1, #LFOs.sync_divisions)
   else
      -- In free mode: change Hz
      lfo.freq = util.clamp(lfo.freq + delta * 0.01, 0.01, 12)
   end
end

-- Get current cursor info for display
function LFOs.get_cursor_info()
   if not LFOs.patch_mode then return nil end
   local lfo = LFOs.data[LFOs.patch_mode]
   if not lfo then return nil end
   local info = {
      lfo_id = LFOs.patch_mode,
      freq = lfo.freq,
      cursor = LFOs.patch_cursor,
      max_cursor = 2 + #lfo.assignments,
      sync = lfo.sync,
      sync_div = lfo.sync_div,
      sync_label = LFOs.sync_divisions[lfo.sync_div] or "1/1",
   }
   if LFOs.patch_cursor == 1 then
      info.label = "shape"
      info.value = lfo.shape
      info.is_assignment = false
   elseif LFOs.patch_cursor == 2 then
      info.label = "noise"
      info.value = lfo.noise
      info.is_assignment = false
   else
      local assign_idx = LFOs.patch_cursor - 2
      local a = lfo.assignments[assign_idx]
      if a then
         info.label = a[1]
         info.value = a[2]
         info.is_assignment = true
         info.assign_idx = assign_idx
         info.total_assign = #lfo.assignments
      end
   end
   return info
end

-- Get base value for a param (without this LFO's contribution)
function LFOs.get_base_value(param_id)
   for i = 1, 4 do
      if LFOs.data[i] then
         for _, a in ipairs(LFOs.data[i].assignments) do
            if a[1] == param_id then
               local p = params:lookup_param(param_id)
               if p then return p:get() - (a[3] or 0) end
            end
         end
      end
   end
   return nil
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
            noise = lfo.noise,
            sync = lfo.sync,
            sync_div = lfo.sync_div,
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
         LFOs.data[i].noise = s.noise or 0.0
         LFOs.data[i].sync = s.sync or false
         LFOs.data[i].sync_div = s.sync_div or 3
         LFOs.data[i].assignments = {}
         if s.assignments then
            for _, a in ipairs(s.assignments) do
               table.insert(LFOs.data[i].assignments, {a[1], a[2], 0.0})
            end
         end
      end
   end
end

-- Check if any LFO is modulating this param
function LFOs.param_is_modulated(param_id)
   for i = 1, 4 do
      if LFOs.data[i] then
         for _, a in ipairs(LFOs.data[i].assignments) do
            if a[1] == param_id then return true end
         end
      end
   end
   return false
end

return LFOs