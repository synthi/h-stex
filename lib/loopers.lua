-- lib/loopers.lua
-- Parameter loopers for 16n fader automation
-- Records and plays back fader movements as relative offsets

local Loopers = {}

-- fader → param mapping (shared with 16n integration)
Loopers.fader_map = {
   [1]  = "drone_timbre",
   [2]  = "drone_noise",
   [3]  = "drone_bias",
   [4]  = "drone_freq",
   [5]  = "poly_timbre",
   [6]  = "poly_noise",
   [7]  = "poly_bias",
   [8]  = "poly_shape",
   [9]  = "fx_peak_1",
   [10] = "fx_peak_2",
   [11] = "fx_body",
   [12] = "fx_gain",
   [13] = "poly_max_attack",
   [14] = "poly_max_release",
   [15] = "drone_amp",
   [16] = "poly_amp",
   [17] = "drone_freq",
   [18] = "fx_time",
   [19] = "poly_scale",
}

Loopers.sample_rate = 0.01  -- 100Hz (10ms)
Loopers.loopers = {}
Loopers.clock_ids = {}
Loopers.fader_current = {}

-- called once during script init
function Loopers.init(base_values_ref)
   Loopers.base_values = base_values_ref or {}
   for i = 1, 6 do
       Loopers.loopers[i] = {
          data = {}, state = 0, playhead = 0, last_cpu_time = 0,
          start_time = 0, duration = 0, double_click_timer = nil, press_time = 0,
          base_values = {}, pending_change = nil,
       }
   end
   for i = 1, 19 do
      Loopers.fader_current[i] = 0
   end
    -- launch looper clock coroutines (staggered to avoid CPU spike)
    clock.run(function()
       for i = 1, 6 do
          Loopers.clock_ids[i] = clock.run(function() Loopers.run(i) end)
          clock.sleep(0.02)
       end
    end)
end

-- returns true if ANY looper is actively modifying parameters (rec/play/overdub)
function Loopers.playback_active()
   for i = 1, 6 do
      local s = Loopers.loopers[i].state
      if s == 1 or s == 2 or s == 3 then return true end
   end
   return false
end

-- called by 16n callback whenever a fader moves
function Loopers.on_fader_move(fader_id, val_norm)
   -- store raw position for playback offset calculations
   Loopers.fader_current[fader_id] = val_norm

   -- record to any active loopers (state 1 or 3)
   for i = 1, 6 do
      local l = Loopers.loopers[i]
      if l.state == 1 or l.state == 3 then
         local dt = util.time() - l.start_time
         if l.state == 3 then dt = dt % l.duration end

         -- calculate delta relative to base_value
         local base = l.base_values[fader_id] or val_norm
         local delta = val_norm - base

         -- check if delta changed enough from last entry for this fader
         local last_dv = 0
         if #l.data > 0 then
            for j = #l.data, 1, -1 do
               local rd = l.data[j].deltas[fader_id]
               if rd ~= nil then last_dv = rd; break end
            end
         end
         if math.abs(delta - last_dv) > 0.003 then
            if #l.data < 3000 then
               -- Overdub (state 3): find existing entry at same dt or insert sorted
               if l.state == 3 and l.duration > 0.01 then
                  local replaced = false
                  for j = 1, #l.data do
                     if math.abs(l.data[j].dt - dt) < 0.005 then
                        l.data[j].deltas[fader_id] = delta
                        replaced = true
                        break
                     end
                  end
                  if not replaced then
                     -- Insert sorted by dt
                     local new_entry = {dt = dt, deltas = {}}
                     new_entry.deltas[fader_id] = delta
                     -- carry forward other faders' deltas from preceding entry
                     local prev_idx = nil
                     for j = #l.data, 1, -1 do
                        if l.data[j].dt <= dt then prev_idx = j; break end
                     end
                     if prev_idx then
                        for fid, dv in pairs(l.data[prev_idx].deltas) do
                           if fid ~= fader_id then new_entry.deltas[fid] = dv end
                        end
                     end
                     local insert_idx = #l.data + 1
                     for j = 1, #l.data do
                        if l.data[j].dt > dt then insert_idx = j; break end
                     end
                     table.insert(l.data, insert_idx, new_entry)
                  end
               else
                  -- Record (state 1): append as before (chronological order guaranteed)
                  local new_deltas = {}
                  if #l.data > 0 then
                     local prev = l.data[#l.data]
                     if prev.deltas then
                        for fid, dv in pairs(prev.deltas) do
                           if fid ~= fader_id then new_deltas[fid] = dv end
                        end
                     end
                  end
                  new_deltas[fader_id] = delta
                  table.insert(l.data, {dt = dt, deltas = new_deltas})
               end
            end
         end
      end
   end
end

-- Quantize a state change to the next clock boundary (or immediate if OFF)
function Loopers._quantize_change(id, fn)
   local l = Loopers.loopers[id]
   if not l then return end
   -- Cancel any pending change
   if l.pending_change then
      clock.cancel(l.pending_change)
      l.pending_change = nil
   end
   local quant_val = params:get("looper" .. id .. "_quant") or 1
   if quant_val == 1 then
      -- OFF: execute immediately
      fn()
   else
      -- Division: schedule at next boundary
      local div_beats = {nil, 4, 2, 1, 0.5, 0.25, 0.125}
      local div = div_beats[quant_val] or 4
      local next_beat = math.ceil(clock.get_beats() / div) * div
      local wait = (next_beat - clock.get_beats()) * clock.get_beat_sec()
      if wait < 0 then wait = 0 end
      l.pending_change = clock.run(function()
         clock.sleep(wait)
         l.pending_change = nil
         fn()
      end)
   end
end

-- grid key handler for looper buttons (row 8, cols 7-12)
-- returns true if the event was consumed
function Loopers.grid_key(x, y, z, shift_held)
   if y ~= 8 or x < 7 or x > 12 then return false end

   local id = x - 6
   local l = Loopers.loopers[id]

   if z == 1 then
      if shift_held then
         -- shift+press: clear looper (immediate, not quantized)
         if l.pending_change then clock.cancel(l.pending_change); l.pending_change = nil end
         l.state = 0; l.data = {}; l.duration = 0; l.base_values = {}
         l.playhead = 0; l.start_time = 0
         return true
      end

      l.press_time = util.time()
      if l.state == 0 then
         -- start recording (quantized)
         Loopers._quantize_change(id, function()
            local ll = Loopers.loopers[id]
            ll.state = 1; ll.data = {}; ll.start_time = util.time()
            ll.base_values = {}
            for fi = 1, 19 do ll.base_values[fi] = Loopers.fader_current[fi] or 0 end
            -- auto-close timer (30s)
            clock.run(function()
               local capture_id = id
               clock.sleep(30.0)
               if Loopers.loopers[capture_id].state == 1 then
                  local ll2 = Loopers.loopers[capture_id]
                  ll2.duration = util.time() - ll2.start_time
                  if ll2.duration < 0.01 then ll2.duration = 0.01 end
                  Loopers.rebase_deltas(ll2)
                  ll2.data = Loopers.slew_compress(ll2.data)
                  local default_mode = params:get("looper_default_mode")
                  ll2.state = (default_mode == 1) and 2 or 3
                  ll2.playhead = 0; ll2.last_cpu_time = util.time()
                  ll2.start_time = util.time()
               end
            end)
         end)
      elseif l.state == 1 then
         -- close recording → play or overdub (quantized)
         Loopers._quantize_change(id, function()
            local ll = Loopers.loopers[id]
            ll.duration = util.time() - ll.start_time
            if ll.duration < 0.01 then ll.duration = 0.01 end
            Loopers.rebase_deltas(ll)
            ll.data = Loopers.slew_compress(ll.data)
            local default_mode = params:get("looper_default_mode")
            ll.state = (default_mode == 1) and 2 or 3
            ll.playhead = 0; ll.last_cpu_time = util.time()
            ll.start_time = util.time()
         end)
      elseif l.state == 2 then
         Loopers._quantize_change(id, function()
            local ll = Loopers.loopers[id]
            ll.state = 3; ll.start_time = util.time()
         end)
      elseif l.state == 3 then
         Loopers._quantize_change(id, function()
            local ll = Loopers.loopers[id]
            ll.state = 2; ll.start_time = util.time()
         end)
      elseif l.state == 4 then
         Loopers._quantize_change(id, function()
            local ll = Loopers.loopers[id]
            ll.state = 2
            ll.playhead = 0; ll.last_cpu_time = util.time()
            ll.start_time = util.time()
         end)
      end
      return true
   end

   -- z == 0: release handling
   if l.state == 2 or l.state == 3 then
      local hold_time = util.time() - (l.press_time or 0)
      if hold_time < 0.25 and l.double_click_timer then
         l.state = 4  -- double-click → stop
         l.double_click_timer = nil
      else
         l.double_click_timer = clock.run(function()
            clock.sleep(0.25)
            l.double_click_timer = nil
         end)
      end
   elseif l.state == 1 then
      local hold_time = util.time() - (l.press_time or 0)
      if hold_time > 1.0 then
         l.state = 0; l.data = {}; l.duration = 0; l.base_values = {}  -- long press → cancel
      end
   end
   return true
end

-- render looper LEDs (row 8, cols 7-11)
function Loopers.redraw_grid(g)
   for i = 1, 6 do
      local x = 6 + i
      local l = Loopers.loopers[i]
      local b = 0
      if l.state == 0 then
         b = 2
      elseif l.state == 1 then
         -- 1.1Hz pulse between 1↔5
         local wave = (math.sin(util.time() * math.pi * 2 * 1.1) + 1) / 2
         b = 1 + math.floor(4 * wave + 0.5)
      elseif l.state == 2 then
         -- progress bar from 3→14 over loop duration
         if l.duration > 0.01 then
            local progress = (l.playhead / l.duration) % 1
            b = 3 + math.floor(11 * progress + 0.5)
         else
            b = 3
         end
      elseif l.state == 3 then
         -- 1.8Hz pulse between 2↔7
         local wave = (math.sin(util.time() * math.pi * 2 * 1.8) + 1) / 2
         b = 2 + math.floor(5 * wave + 0.5)
      elseif l.state == 4 then
         b = 4
      end
      g:led(x, 8, b)
   end
end

-- re-normalize all deltas so the close point has delta=0 for every fader
function Loopers.rebase_deltas(l)
   local rebase = {}
   for fi = 1, 19 do
      local close_val = Loopers.fader_current[fi] or 0
      rebase[fi] = close_val - (l.base_values[fi] or close_val)
   end
   for _, entry in ipairs(l.data) do
      if entry.deltas then
         for fid, dv in pairs(entry.deltas) do
            entry.deltas[fid] = dv - (rebase[fid] or 0)
         end
      end
   end
end

-- stop all loopers and cancel clocks
function Loopers.cleanup()
   for i = 1, 6 do
      if Loopers.clock_ids[i] then
         clock.cancel(Loopers.clock_ids[i])
         Loopers.clock_ids[i] = nil
      end
      Loopers.loopers[i].state = 0
   end
end

----------------------------------------------------------------------
-- internal functions
----------------------------------------------------------------------

-- remove redundant data points (colinear interpolation)
function Loopers.slew_compress(data)
   if #data < 3 then return data end
   local out = {data[1]}
   for i = 2, #data - 1 do
      local prev = data[i - 1]
      local curr = data[i]
      local next_entry = data[i + 1]
      local max_delta = 0
      for fid, dv in pairs(curr.deltas or {}) do
         local pv = prev.deltas and prev.deltas[fid] or 0
         local nv = next_entry.deltas and next_entry.deltas[fid] or 0
         local d1 = math.abs(dv - pv)
         local d2 = math.abs(nv - dv)
         if d1 > max_delta then max_delta = d1 end
         if d2 > max_delta then max_delta = d2 end
      end
      if max_delta > 0.005 then
         table.insert(out, curr)
      end
   end
   table.insert(out, data[#data])
   return out
end

-- looper playback engine
function Loopers.run(id)
   local l = Loopers.loopers[id]
   l.playhead = 0
   l.last_cpu_time = util.time()
   while true do
      if (l.state == 2 or l.state == 3) and l.duration > 0.01 then
         local now = util.time()
         local delta = now - l.last_cpu_time
         l.last_cpu_time = now
         l.playhead = l.playhead + delta
         if l.playhead >= l.duration then l.playhead = l.playhead % l.duration end

         if #l.data > 0 then
            -- find interpolation pair for this looper
            local idx1, idx2 = nil, nil
            for i = 1, #l.data - 1 do
               if l.data[i].dt <= l.playhead and l.data[i + 1].dt > l.playhead then
                  idx1 = i; idx2 = i + 1; break
               end
            end
            if not idx1 then
               idx1 = #l.data; idx2 = 1
            end

            local e1, e2 = l.data[idx1], l.data[idx2]
            local dt_range = e2.dt
            if idx1 == #l.data and idx2 == 1 then dt_range = l.duration end
            local frac = 0
            if dt_range > 0 then
               local t = l.playhead - e1.dt
               if t < 0 then t = t + l.duration end
               frac = t / dt_range
            end

            -- collect all fader IDs from all active loopers
            local all_fids = {}
            for li = 1, 6 do
               local ol = Loopers.loopers[li]
               if ol.state == 2 or ol.state == 3 then
                  for _, e in ipairs(ol.data) do
                     if e.deltas then
                        for fid, _ in pairs(e.deltas) do
                           all_fids[fid] = true
                        end
                     end
                  end
               end
            end

            -- sum interpolated deltas from all active loopers for each fader
            for fid, _ in pairs(all_fids) do
               local total_delta = 0
               for li = 1, 6 do
                  local ol = Loopers.loopers[li]
                  if (ol.state == 2 or ol.state == 3) and ol.duration > 0.01 and #ol.data > 0 then
                     local oi1, oi2 = nil, nil
                     for j = 1, #ol.data - 1 do
                        if ol.data[j].dt <= ol.playhead and ol.data[j + 1].dt > ol.playhead then
                           oi1 = j; oi2 = j + 1; break
                        end
                     end
                     if not oi1 then oi1 = #ol.data; oi2 = 1 end
                     local oe1, oe2 = ol.data[oi1], ol.data[oi2]
                     local odt_range = oe2.dt
                     if oi1 == #ol.data and oi2 == 1 then odt_range = ol.duration end
                     local ofrac = 0
                     if odt_range > 0 then
                        local ot = ol.playhead - oe1.dt
                        if ot < 0 then ot = ot + ol.duration end
                        ofrac = ot / odt_range
                     end
                     local dv1 = (oe1.deltas and oe1.deltas[fid]) or 0
                     local dv2 = (oe2.deltas and oe2.deltas[fid]) or 0
                     total_delta = total_delta + dv1 + (dv2 - dv1) * ofrac
                  end
               end

               if math.abs(total_delta) > 0.0001 then
                  local p_name = Loopers.fader_map[fid]
                  if p_name then
                     local p_obj = params:lookup_param(p_name)
                      if p_obj then
                         local base = params:get_raw(p_name)
                        local target_norm = util.clamp(base + total_delta, 0, 1)
                        local target_val = p_obj.controlspec:map(target_norm)
                        -- Engine bypass: call action directly so param value stays at base
                        if p_obj.action then
                           p_obj.action(target_val)
                        else
                           params:set(p_name, target_val)
                        end
                     end
                  end
               end
            end
         end
         clock.sleep(Loopers.sample_rate)
      else
         l.last_cpu_time = util.time()
         l.playhead = 0
         clock.sleep(0.1)
      end
   end
end

-- Check if any looper is modulating this param
function Loopers.param_is_modulated(param_id)
   for fid, pname in pairs(Loopers.fader_map) do
      if pname == param_id then
         for i = 1, 6 do
            local l = Loopers.loopers[i]
            if (l.state == 2 or l.state == 3) and l.duration > 0.01 and #l.data > 0 then
               for _, e in ipairs(l.data) do
                  if e.deltas and e.deltas[fid] ~= nil then return true end
               end
            end
         end
      end
   end
   return false
end

return Loopers