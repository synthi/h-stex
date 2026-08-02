--
--  A expanding universe 
--  by Jaue Arias
--  v4.2 - Støy EX
--      .                   
--                         
--          .          .     
--   .
--                .         
--    .                     
--                         .
-- .
-- original v1.1 / imminent gloom
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

engine.name = "Harvest"
    Harvest = include("lib/Harvest_engine")
        tab = require("tabutil")
    Storage = include("lib/storage")
          UI = include("lib/ui")
         _16n = include("lib/16n")
    Loopers = include("lib/loopers")
    LFOs = include("lib/lfos")
  EnvQuant = include("lib/env_quant")

local save_on_exit = true

local g = grid.connect()
local a = arc.connect()

local          s = screen
local screen_fps = 60
local  grid_fps = 60

-- grid LED cache for differential updates (ncoco-style: only send LEDs that change)
local grid_cache = {}
for x = 1, 16 do
   grid_cache[x] = {}
   for y = 1, 8 do
      grid_cache[x][y] = -1
   end
end

local  arc_dirty = true
local     splash = true
local  intensity = 8
local  particles = {}
local    density = 96

-- stars for PLAY mode (Terrario espacial)
-- Each star has a life cycle: born → brighten → fade → respawn at new position
-- Varied sizes: ~85% 1px, ~13% 2px (cross), ~2% 3px "gorditas" (diamond)
local stars = {}
for i = 1, 96 do
   local r = math.random()
   local size = 1
   if r > 0.98 then size = 3 elseif r > 0.85 then size = 2 end
   stars[i] = {
      x = math.random(1, 128),
      y = math.random(1, 64),
      size = size,
      phase = math.random() * 2 * math.pi,
      speed = 0.1 + math.random() * 0.2,
      base_level = 3 + math.random() * 5,
      twinkle = 0,
      life = math.random() * 2 * math.pi,  -- life cycle phase
      life_speed = 0.05 + math.random() * 0.15,  -- how fast it lives/dies
      alive = true,
   }
end

-- Light orbs: subtle & slow, ALWAYS diagonal drift (top-right → bottom-left, like shadows)
-- Respawn anywhere on screen, keeping the same diagonal trajectory
local orbs = {}
for i = 1, 4 do
   local spd = 0.02 + math.random() * 0.03
   orbs[i] = {
      x = math.random(1, 128),
      y = math.random(1, 64),
      vx = -spd,                        -- always left
      vy = spd * (0.7 + math.random() * 0.6),  -- always down (diagonal)
      size = 1,
      max_size = 1 + math.random(),     -- radius 1-2px (subtle)
      life = math.random() * 2 * math.pi,
      life_speed = 0.03 + math.random() * 0.08,
      alive = false,
      wobble = math.random() * 2 * math.pi,
   }
end

-- Shooting stars (estrellas fugaces): fast diagonal streaks spawned by drone_noise
local shooters = {}
for i = 1, 3 do
   shooters[i] = {x = 0, y = 0, vx = 0, vy = 0, len = 4, life = 0, alive = false}
end

local      focus = 4
local prev_focus = 3

local    playing = {}
local note_to_playing = {}  -- midi_note -> playing index (O(1) lookup for OSC env)
local armed_notes = {}       -- note_quant: pads armed to fire on next clock boundary
local disarm_all_notes       -- forward declaration (assigned after hold_note)
local      voice = 1
local  transpose = 0
local       note
local   velocity = 100
local   duration = 600
local         ch = 1
local       hold = false
local   shift_held = false
local  sostenuto = false
local        oct = 2
local fader_latched = {}
local base_values = {}  -- param_id -> normalized 0-1, set by faders/encoders (before LFO/looper offsets)

-- Populate base_values from current param values (call after PSET load)
local function init_base_values()
   for _, p_name in pairs(Loopers.fader_map) do
      base_values[p_name] = params:get_raw(p_name)
   end
end
local pending_notes = {}
for i = 1, 16 do fader_latched[i] = false end
local      trail = 8

-- sequencers
local sequencers = {}
for i = 1, 3 do
   sequencers[i] = {data = {}, state = 0, playhead = 0, last_cpu_time = 0,
                    start_time = 0, duration = 0, double_click_timer = nil, press_time = 0,
                    pending_change = nil}
end
local seq_clock_ids = {}

-- Quantize a sequencer state change to the next clock boundary (or immediate if OFF)
local function _quantize_seq_change(id, fn)
   local s = sequencers[id]
   if not s then return end
   if s.pending_change then
      clock.cancel(s.pending_change)
      s.pending_change = nil
   end
   local quant_val = params:get("seq" .. id .. "_quant") or 1
   if quant_val == 1 then
      fn()
   else
      local div_beats = {nil, 4, 2, 1, 0.5, 0.25, 0.125}
      local div = div_beats[quant_val] or 4
      local next_beat = math.ceil(clock.get_beats() / div) * div
      local wait = (next_beat - clock.get_beats()) * clock.get_beat_sec()
      if wait < 0 then wait = 0 end
      s.pending_change = clock.run(function()
         clock.sleep(wait)
         s.pending_change = nil
         fn()
      end)
   end
end

-- drone snapshots (ncoco-style)
local drone_snaps = {nil, nil, nil, nil}
local active_drone_snap = 0
local drone_snap_timers = {}

local scales = {
   ["Chromatic"]        = {0,1,2,3,4,5,6,7,8,9,10,11},
   ["Major"]            = {0,2,4,5,7,9,11},
   ["Natural Minor"]    = {0,2,3,5,7,8,10},
   ["Harmonic Minor"]   = {0,2,3,5,7,8,11},
   ["Dorian"]           = {0,2,3,5,7,9,10},
   ["Phrygian"]         = {0,1,3,5,7,8,10},
   ["Lydian"]           = {0,2,4,6,7,9,11},
   ["Mixolydian"]       = {0,2,4,5,7,9,10},
   ["Major Pentatonic"] = {0,2,4,7,9},
   ["Minor Pentatonic"] = {0,3,5,7,10},
   ["In Sen"]           = {0,1,5,7,10},
   ["Hirajoshi"]        = {0,2,3,7,8},
   ["Iwato"]            = {0,1,5,6,10},
   ["Kumoi"]            = {0,2,3,7,9},
   ["Yo"]               = {0,2,5,7,9},
   ["Hijaz"]            = {0,1,4,5,7,8,11},
   ["Todi"]             = {0,1,3,6,7,8,11},
   ["Marwa"]            = {0,1,4,6,7,9,11},
   ["Purvi"]            = {0,1,4,6,7,8,11},
   ["Saba"]             = {0,1,3,5,6,8,11},
   ["Nawa Athar"]       = {0,1,4,5,7,9,10},
}
local current_scale = "Chromatic"
local scale_root = 0

-- clock events
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local function screen_event()
   local sframe = 1
   while true do
      clock.sleep(1 / screen_fps)
      sframe = sframe + 1
      redraw(sframe)
   end
end

local function grid_event()
   local frame = 1
   while true do
      clock.sleep(1 / grid_fps)
      frame = frame + 1
      redraw_grid(frame)
   end
end

local function redraw_arc_event()
   while true do
      clock.sleep(1/90)
      if arc_dirty then
         redraw_arc()
         arc_dirty = false
      end
   end
end

local function splash_event()
   if splash then
      splash_level = 15
      while splash_level > 0 do
         clock.sleep(0.05)
         splash_level = splash_level - 1
      end
      splash = false
   end
end

local function chaos_event()
   while true do
      
   end
end

-- functions
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local function seed(t, n)
   for n = 1, n do
      if n == 1 then
         t[n] = {x = math.random(32, 96), y = math.random(16, 48), on = true, level = 15, noise = 0}
      else
         t[n] = {x = math.random(1, 128), y = math.random(1, 64), on = true, level = 15, noise = 0}
      end
   end
end

local function stop_keys()
   if disarm_all_notes then disarm_all_notes() end
   for n = 1, #playing do
      engine.harvest_note_off(playing[n].note + playing[n].transpose)
   end
   playing = {}
   note_to_playing = {}
end

local function stop_held()
   for n = #playing, 1, -1 do
      if playing[n].held then
         engine.harvest_note_off(playing[n].note + playing[n].transpose)
         local key = playing[n].note + playing[n].transpose
         if note_to_playing[key] == playing[n] then
            note_to_playing[key] = nil
         end
         table.remove(playing, n)
      end
   end
end

local function xy_to_note(x, y)
   local scale = scales[current_scale]
   local steps = #scale
   if current_scale == "Chromatic" then
      note = 12 + scale_root
      note = note + x
      note = note + 5 * (8 - y)
   else
      -- x maps to scale steps, y maps to "fifths" (4 scale steps per row)
      local octave_offset = math.floor((x - 1) / steps)
      local step_index = ((x - 1) % steps) + 1
      local row_offset = 4 * (8 - y)
      local total_steps = step_index + row_offset
      local octave_shift = math.floor((total_steps - 1) / steps)
      local final_step = ((total_steps - 1) % steps) + 1
      note = 12 + scale_root + (octave_offset + octave_shift) * 12 + scale[final_step]
   end
   return note
end

-- reverse lookup: note -> grid position (all scales, keyboard area only)
local function note_to_xy(n)
   for y = 1, 7 do
      for x = math.max(1, 9 - y), 16 do
         if xy_to_note(x, y) == n then
            return x, y
         end
      end
   end
   return nil, nil
end

local function play_note(x, y, z, note, seq_note)
   note = note or xy_to_note(x, y)
   transpose = 12 * oct
   if z == 1 then 
      if #playing >= 12 then
         local evicted = playing[1]
         engine.harvest_note_off(evicted.note + evicted.transpose)
         local ekey = evicted.note + evicted.transpose
         if note_to_playing[ekey] == evicted then
            note_to_playing[ekey] = nil
         end
         table.remove(playing, 1)
      end
      local entry = {note = note, transpose = transpose, x = x, y = y, held = false, timestamp = util.time(), seq_note = seq_note or false, env_val = 0}
      table.insert(playing, entry)
      note_to_playing[note + transpose] = entry
      engine.harvest_note_on(note + transpose, velocity, duration)
    else
       for i, v in pairs(playing) do
          if v.x == x and v.y == y and not v.held then
             engine.harvest_note_off(v.note + v.transpose)
             local key = v.note + v.transpose
             if note_to_playing[key] == v then
                note_to_playing[key] = nil
             end
             table.remove(playing, i)
             break
          end
       end
    end
 end
 
 local function hold_note(x, y, z, note)
   local voice = nil
   if z == 1 then
      note = note or xy_to_note(x, y)
      transpose = 12 * oct
      for i, v in pairs(playing) do
         if v.x == x and v.y == y then
            engine.harvest_note_off(v.note + v.transpose)
            local key = v.note + v.transpose
            if note_to_playing[key] == v then
               note_to_playing[key] = nil
            end
            table.remove(playing, i)
            voice = i
            break
         end
      end
      if voice == nil then
         if #playing >= 12 then
            local evicted = playing[1]
            engine.harvest_note_off(evicted.note + evicted.transpose)
            local ekey = evicted.note + evicted.transpose
            if note_to_playing[ekey] == evicted then
               note_to_playing[ekey] = nil
            end
            table.remove(playing, 1)
         end
         local entry = {note = note, transpose = transpose, x = x, y = y, held = false, timestamp = util.time(), env_val = 0}
         table.insert(playing, entry)
         note_to_playing[note + transpose] = entry
         engine.harvest_note_on(note + transpose, velocity, duration)
      end
   else
      if voice == nil then
         for n = 1, #playing do
            if playing[n].held == false then
               playing[n].held = true
            end
         end
      end
   end
end

-- note quantization: armed notes fire on next clock boundary
-- (manual grid presses only; sequencers/PSET/retrigger bypass this)
local note_quant_beats = {nil, 4, 2, 1, 0.5, 0.25, 0.125}  -- index = note_quant option

local function record_note_event(x, y, z)
   for i = 1, 3 do
      local s = sequencers[i]
      if s.state == 1 or s.state == 4 then
         local dt = util.time() - s.start_time
         if s.state == 4 then dt = dt % s.duration end
         if #s.data < 10000 then
            table.insert(s.data, {x = x, y = y, z = z, dt = dt, note = xy_to_note(x, y), oct = oct})
         end
      end
   end
end

local function fire_armed_note(x, y)
   record_note_event(x, y, 1)  -- record at fire time: playback matches what was heard
   if not hold or sostenuto then play_note(x, y, 1) else hold_note(x, y, 1) end
end

local function arm_note(x, y)
   local key = x .. "_" .. y
   if armed_notes[key] then return end
   local div = note_quant_beats[params:get("note_quant")] or 1
   local beats_now = clock.get_beats()
   local wait = (math.ceil(beats_now / div) * div - beats_now) * clock.get_beat_sec()
   if wait < 0.001 then
      fire_armed_note(x, y)  -- already on boundary
      return
   end
   armed_notes[key] = {x = x, y = y}
   armed_notes[key].clock_id = clock.run(function()
      clock.sleep(wait)
      armed_notes[key] = nil
      fire_armed_note(x, y)
   end)
end

local function disarm_note(x, y)
   local key = x .. "_" .. y
   local a = armed_notes[key]
   if a then
      clock.cancel(a.clock_id)
      armed_notes[key] = nil
      return true   -- was armed: canceled, never sounded
   end
   return false      -- already fired: caller must pass release through
end

disarm_all_notes = function()
   for key, a in pairs(armed_notes) do
      clock.cancel(a.clock_id)
      armed_notes[key] = nil
   end
end

local function arc_bar(enc, val, level)
   local range = util.clamp(math.floor(val * 33), 0, 32.999)
   for n = 1, range do
      if n < range then 
         a:led(enc, 33 + n, level)
         a:led(enc, 33 - n, level)
      else
         if n > 33 then
            a:led(enc, 1, math.floor(level * (val * 33 - range)))
         else
            a:led(enc, 33 + n, math.floor(level * (val * 33 - range)))
            a:led(enc, 33 - n, math.floor(level * (val * 33 - range)))
         end
      end
   end
end

-- LinSelectX replica from SuperCollider
local function linselect(idx, arr)
   local i = math.floor(idx)
   local frac = idx - i
   if i < 0 then return arr[1]
   elseif i >= #arr - 1 then return arr[#arr]
   else return arr[i + 1] * (1 - frac) + arr[i + 2] * frac end
end

-- Calculate envelope cycle length matching SC harvestpoly synth
-- shape=0 → attack=0.01, release=0.01 → cycle=0.02
-- shape=0.33 → attack=0.01, release=max_r*scale → cycle=0.01+max_r*scale
-- shape=0.67 → attack=max_a*scale, release=max_r*scale → cycle=(max_a+max_r)*scale
-- shape=1 → attack=max_a*scale, release=0.01 → cycle=max_a*scale+0.01
local function calc_cycle_len()
   if EnvQuant.enabled() and EnvQuant.last_cycle > 0 then
      return 2 * EnvQuant.last_cycle
   end
   local shape = params:get("poly_shape")
   local scale_val = params:get("poly_scale")
   local max_a = Harvest.max_attack or 0.197
   local max_r = Harvest.max_release or 1
   local idx = shape * 3
   local attack = util.clamp(linselect(idx, {0.01, 0.01, max_a, max_a}) * scale_val, 0.01, max_a)
   local release = util.clamp(linselect(idx, {0.01, max_r, max_r, 0.01}) * scale_val, 0.01, max_r)
   return 2 * (attack + release)
end

-- drone snapshot helper functions (ncoco-style)
local function drone_snap_capture()
   return {
      timbre = params:get("drone_timbre"),
      noise  = params:get("drone_noise"),
      bias   = params:get("drone_bias"),
      freq   = params:get("drone_freq"),
      drift  = params:get("drone_drift"),
   }
end
local function drone_snap_apply(data)
   if not data then return end
   if data.timbre then params:set("drone_timbre", data.timbre) end
   if data.noise  then params:set("drone_noise",  data.noise) end
   if data.bias   then params:set("drone_bias",   data.bias) end
   if data.freq   then params:set("drone_freq",   data.freq) end
   if data.drift  then params:set("drone_drift",  data.drift) end
end
local function drone_snap_save(id)
   drone_snaps[id] = drone_snap_capture()
   active_drone_snap = id
   UI.show_popup("DRONE SNAP " .. id, "SAVED", 1.5)
end
local function drone_snap_update(id)
   drone_snaps[id] = drone_snap_capture()
   UI.show_popup("DRONE SNAP " .. id, "UPDATED", 1.5)
end
local function drone_snap_load(id)
   if drone_snaps[id] then
      drone_snap_apply(drone_snaps[id])
      active_drone_snap = id
      UI.show_popup("DRONE SNAP " .. id, "LOADED", 1.5)
   end
end
local function drone_snap_clear(id)
   drone_snaps[id] = nil
   if active_drone_snap == id then active_drone_snap = 0 end
   UI.show_popup("DRONE SNAP " .. id, "CLEARED", 1.5)
end

-- sequencer playback engine (ported from ncoco)
local function run_sequencer(id)
   local s = sequencers[id]
   s.playhead = 0
   s.last_cpu_time = util.time()
   while true do
      if (s.state == 2 or s.state == 4) and s.duration > 0.01 then
         local now = util.time()
         local delta = now - s.last_cpu_time
         s.last_cpu_time = now
         local old_head = s.playhead
         s.playhead = s.playhead + delta
         if s.playhead >= s.duration then
            for _, e in ipairs(s.data) do
               if e.dt >= old_head or e.dt < s.playhead - s.duration then
                if e.y == 8 and e.x >= 2 and e.x <= 5 then
                   if e.z == 1 then
                      local snap_id = e.x - 1
                        if drone_snaps[snap_id] == nil then drone_snap_save(snap_id)
                        else drone_snap_load(snap_id) end
                     end
                     -- z==0 for snapshots: no-op (ignore release)
                  else
                     play_note(e.x, e.y, e.z, e.note, true)
                  end
               end
            end
            s.playhead = s.playhead % s.duration
            for _, e in ipairs(s.data) do
               if e.dt < s.playhead then
             if e.y == 8 and e.x >= 2 and e.x <= 5 then
                if e.z == 1 then
                   local snap_id = e.x - 1
                        if drone_snaps[snap_id] == nil then drone_snap_save(snap_id)
                        else drone_snap_load(snap_id) end
                     end
                  else
                     play_note(e.x, e.y, e.z, e.note, true)
                  end
               end
            end
         else
            for _, e in ipairs(s.data) do
               if e.dt >= old_head and e.dt < s.playhead then
          if e.y == 8 and e.x >= 2 and e.x <= 5 then
             if e.z == 1 then
                local snap_id = e.x - 1
                        if drone_snaps[snap_id] == nil then drone_snap_save(snap_id)
                        else drone_snap_load(snap_id) end
                     end
                  else
                     play_note(e.x, e.y, e.z, e.note, true)
                  end
               end
            end
         end
         clock.sleep(1/30)
      else
         s.last_cpu_time = util.time()
         s.playhead = 0
         clock.sleep(0.1)
      end
   end
end

-- init
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function init()
   seed(particles, density)

   clk_screen = clock.run(screen_event)
   clk_grid = clock.run(grid_event)
   clk_redraw_arc = clock.run(redraw_arc_event)
   clk_splash = clock.run(splash_event)

   -- tempo monitor: re-snap envelope quant when clock tempo changes
   clk_env_quant = clock.run(function()
      local last_bs = clock.get_beat_sec()
      while true do
         clock.sleep(1/15)
         local bs = clock.get_beat_sec()
         if math.abs(bs - last_bs) > 0.0001 then
            last_bs = bs
            if EnvQuant.enabled() then EnvQuant.apply() end
            if params:get("delay_sync") == 2 then EnvQuant.apply_delay_sync() end
         end
      end
   end)

   params:add{
      type = "group",
      id   = "harvest",
      name = "HØST",
      n    = 54
   }

   params:add_separator("kontroll", "CONTROL")

   params:add{
      type        = "option",
      id          = "focus",
      name        = "Focus",
      options     = {"Jord", "Løv", "Lys", "Play"},
      default     = 4,
      action      = function(x)
         prev_focus = focus
         focus = x
         if focus >= 1 and focus <= 3 then
            seed(particles, density)
         end
      end
   }

   params:add{
      type        = "option",
      id          = "poly_hold",
      name        = "Hold?",
      options     = {"No", "Yes"},
      default     = 1,
      action      = function(x)
         if x == 1 then hold = false else hold = true end
         Harvest.poly_hold = x - 1
      end
   }

   params:add{
      type        = "option",
      id          = "sostenuto",
      name        = "Sostenuto",
      options     = {"No", "Yes"},
      default     = 1,
      action      = function(x)
         sostenuto = (x == 2)
      end
   }

   Harvest.init(false)

   params:add_separator("skala", "SCALE")

   -- scale selector
   local scale_names = {}
   for name, _ in pairs(scales) do
      table.insert(scale_names, name)
   end
   params:add{
      type        = "option",
      id          = "scale",
      name        = "Scale",
      options     = scale_names,
      default     = 1,
      action      = function(x)
         current_scale = scale_names[x]
      end
   }

   -- root note selector
   local root_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
   params:add{
      type        = "option",
      id          = "root_note",
      name        = "Root Note",
      options     = root_names,
      default     = 1,
      action      = function(x)
         scale_root = x - 1
         -- retrigger active notes with new root + rebuild voice lookup
         note_to_playing = {}
         for i, v in ipairs(playing) do
            local new_note = xy_to_note(v.x, v.y)
            engine.harvest_note_off(v.note + v.transpose)
            engine.harvest_note_on(new_note + v.transpose, velocity, duration)
            v.note = new_note
            note_to_playing[new_note + v.transpose] = v
         end
      end
   }

   -- per-PSET state persistence (like ncoco)
   params.action_write = function(filename, name, number)
      -- filter out sequencer-triggered notes (seq_note=true) so they don't get saved
      local manual_playing = {}
      for _, n in ipairs(playing) do
         if not n.seq_note then table.insert(manual_playing, n) end
      end
      Storage.save_pset(number, manual_playing, hold, Harvest.poly_loop == 1, oct, calc_cycle_len(), sequencers, drone_snaps, active_drone_snap, Loopers.loopers, LFOs.get_state())
   end
   params.action_read = function(filename, silent, number)
      stop_keys()
      pending_notes = {}
      local saved = Storage.load_pset(number)
      if saved then
         oct = saved.oct or 2
         if saved.hold then params:set("poly_hold", 2) end
         if saved.loop then params:set("poly_loop", 2) end
         local cycle_len = saved.cycle_len or 0.02
         if saved.notes then
            -- sort by timestamp
            table.sort(saved.notes, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
            local min_ts = saved.notes[1] and saved.notes[1].timestamp or 0
            for _, n in ipairs(saved.notes) do
               local offset = (n.timestamp or min_ts) - min_ts
               if saved.loop and cycle_len > 0.02 then
                  offset = offset % cycle_len
               end
               if offset < 0.02 then
                  if saved.hold then hold_note(n.x, n.y, 1, n.note) else play_note(n.x, n.y, 1, n.note) end
               else
                  table.insert(pending_notes, {note = n.note, x = n.x, y = n.y, held = saved.hold, offset = offset, fire_time = util.time() + offset})
                  clock.run(function()
                     clock.sleep(offset)
                     for i = #pending_notes, 1, -1 do
                        if pending_notes[i] and pending_notes[i].x == n.x and pending_notes[i].y == n.y then
                           if pending_notes[i].held then
                              hold_note(n.x, n.y, 1, n.note)
                           else
                              play_note(n.x, n.y, 1, n.note)
                           end
                           table.remove(pending_notes, i)
                           break
                        end
                     end
                  end)
               end
            end
            -- fix: notes loaded via hold_note() have held=false, but they should be held
            if saved.hold then
               for i = 1, #playing do
                  playing[i].held = true
               end
            end
         end
         if saved.sequencers then
            for i = 1, 3 do
               local ss = saved.sequencers[i]
               if ss then
                  sequencers[i].data = ss.data or {}
                  if ss.data and #ss.data > 0 then
                     sequencers[i].state = 3  -- stopped with data (like ncoco)
                  else
                     sequencers[i].state = 0
                  end
                  sequencers[i].duration = ss.duration or 0
                  sequencers[i].playhead = 0
                  sequencers[i].last_cpu_time = util.time()
                  sequencers[i].start_time = 0
                  sequencers[i].double_click_timer = nil
                  sequencers[i].press_time = 0
               end
            end
         else
            -- old PSET without sequencer data: reset all sequencers
            for i = 1, 3 do
               sequencers[i] = {data = {}, state = 0, playhead = 0, last_cpu_time = util.time(),
                                start_time = 0, duration = 0, double_click_timer = nil, press_time = 0}
            end
         end
         -- restore drone snapshots (backward compatible)
         if saved.drone_snaps then
            drone_snaps = saved.drone_snaps
         else
            drone_snaps = {nil, nil, nil, nil}
         end
         active_drone_snap = saved.active_drone_snap or 0

         -- restore loopers (always reset first, then restore if this PSET has data)
         for i = 1, 6 do
            Loopers.loopers[i].data = {}
            Loopers.loopers[i].state = 0
            Loopers.loopers[i].duration = 0
            Loopers.loopers[i].playhead = 0
            Loopers.loopers[i].base_values = {}
         end
         if saved.loopers then
            for i = 1, 6 do
               local sl = saved.loopers[i]
               if sl and sl.data and #sl.data > 0 then
                  Loopers.loopers[i].data = sl.data
                  Loopers.loopers[i].duration = sl.duration or 0
                  Loopers.loopers[i].state = 4  -- stopped with data
                  Loopers.loopers[i].last_cpu_time = util.time()
               end
            end
         end
         -- restore LFOs (backward compatible: old PSETs have no lfos field)
         LFOs.clear_all()
         if saved.lfos then LFOs.set_state(saved.lfos) end
      else
         -- no saved data at all: reset everything
         for i = 1, 3 do
            sequencers[i] = {data = {}, state = 0, playhead = 0, last_cpu_time = util.time(),
                             start_time = 0, duration = 0, double_click_timer = nil, press_time = 0}
         end
         drone_snaps = {nil, nil, nil, nil}
         active_drone_snap = 0
         for i = 1, 6 do
            Loopers.loopers[i] = {data = {}, state = 0, playhead = 0, last_cpu_time = util.time(),
                                  start_time = 0, duration = 0, double_click_timer = nil, press_time = 0,
                                  base_values = {}}
         end
         LFOs.clear_all()
      end
   end

   if save_on_exit then params:read(norns.state.data .. "state.pset") end

   -- restore from global state if no PSET data loaded
   if #playing == 0 and #pending_notes == 0 then
      local saved = Storage.load()
      if saved then
         if saved.hold then params:set("poly_hold", 2) end
         if saved.loop then params:set("poly_loop", 2) end
         oct = saved.oct or 2
         if saved.notes then
            for _, n in ipairs(saved.notes) do
               if saved.hold then hold_note(n.x, n.y, 1, n.note) else play_note(n.x, n.y, 1, n.note) end
            end
         end
      end
   end

   params:bang()

   -- OSC handler: receive real envelope phase from SC engine (ground truth for grid LED sync)
   -- OSCdef in Engine_Harvest.sc forwards SendReply [env, note] to port 10111
   osc.event = function(path, args, from)
      if path == '/harvest_env' then
         local p = note_to_playing[args[2] or 60]
         if p then
            p.env_val = args[1] or 0
         end
      end
   end

   -- Initialize base_values from loaded PSET params (compatibility with old PSETs)
   init_base_values()

   params:set("focus", 4)

   -- launch sequencer clock coroutines (staggered to avoid CPU spike)
   clock.run(function()
      for i = 1, 3 do
         seq_clock_ids[i] = clock.run(function() run_sequencer(i) end)
         clock.sleep(0.02)
      end
   end)

   -- launch looper clock coroutines
   Loopers.init(base_values)

   -- initialize LFOs
   LFOs.init(base_values)

   -- 16n fader controller initialization with soft takeover
   clock.run(function()
      clock.sleep(2.0)
      _16n.init(function(msg)
         local id = _16n.cc_2_slider_id(msg.cc)
         if not id then return end

         local p_name = Loopers.fader_map[id]
         if not p_name then return end

         local p_obj = params:lookup_param(p_name)
         if not p_obj then return end

         -- normalize midi value (0-127) to 0-1
         local val_norm = util.clamp(msg.val / 127, 0, 1)

         -- LFO patch mode: fader movement connects/selects target, no param change
         if LFOs.patch_mode then
            LFOs.connect_or_select(LFOs.patch_mode, p_name)
            return
         end

         -- Soft takeover: params:get_raw() is always the base value (engine bypass ensures it's never modulated)
         local current_norm = params:get_raw(p_name)

         -- notify loopers of fader movement (for recording & playback offset)
         Loopers.on_fader_move(id, val_norm)

         -- bypass soft takeover during looper rec/overdub
         if Loopers.playback_active() then fader_latched[id] = true end

         -- map through controlspec and back (ncoco pattern)
         local target_real = p_obj.controlspec:map(val_norm)
         local target_norm_check = p_obj.controlspec:unmap(target_real)
         local diff = math.abs(target_norm_check - current_norm)

         local target_val = target_real
         local current_val = params:get(p_name)

         local fader_display
         if p_name == "poly_max_attack" or p_name == "poly_max_release" then
            local k, c = 5, 0.55
            local sig = function(v) return 1/(1+math.exp(-k*(v-c))) end
            local s0, s1 = sig(0), sig(1)
            local sn = (sig(target_val) - s0) / (s1 - s0)
            fader_display = string.format("%.2f s", 0.001 + (24-0.001) * sn)
         else
            fader_display = p_obj:string()
         end

         if not fader_latched[id] then
            if diff < 0.05 then
               fader_latched[id] = true
            else
               -- takeover: show target -> current
               local current_display
               if p_name == "drone_freq" or p_name == "fx_peak_1" or p_name == "fx_peak_2" then
                  current_display = string.format("%.0f Hz", current_val)
               elseif p_name == "fx_time" then
                  current_display = string.format("%.2f s", current_val)
                elseif p_name == "poly_max_attack" or p_name == "poly_max_release" then
                   local k, c = 5, 0.55
                   local sig = function(v) return 1/(1+math.exp(-k*(v-c))) end
                   local s0, s1 = sig(0), sig(1)
                   local sn = (sig(current_val) - s0) / (s1 - s0)
                   current_display = string.format("%.2f s", 0.001 + (24-0.001) * sn)
               else
                  current_display = string.format("%.2f", current_val)
               end
               UI.show_popup("* " .. p_obj.name, fader_display .. " -> " .. current_display, 1.5)
               return
            end
         end

         if fader_latched[id] then
            if diff > 0.15 then
               fader_latched[id] = false
            else
               -- Always write to params (fader and menu stay synchronized)
               if p_name == "fx_body" then target_val = util.clamp(target_val, 0, 1) end
               params:set(p_name, target_val)
               UI.show_popup(p_obj.name, fader_display, 1.5)
            end
         end
      end)
      print("16n initialized.")
   end)
end

-- norns: keys
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function key(n, z)
   if n == 1 and z == 1 then k1_held = true  end
   if n == 1 and z == 0 then k1_held = false end
   if n == 2 and z == 1 then k2_held = true  end
   if n == 2 and z == 0 then k2_held = false end
   if n == 3 and z == 1 then k3_held = true  end
   if n == 3 and z == 0 then k3_held = false end

   -- LFO patch mode: K2=tap flip polarity / hold disconnect+reset, K3=toggle sync
   if LFOs.patch_mode then
      if n == 2 and z == 1 then
         lfo_k2_press_time = util.time()
      elseif n == 2 and z == 0 then
         local hold = util.time() - (lfo_k2_press_time or 0)
         if hold > 0.5 then
            LFOs.reset_current()
         else
            LFOs.flip_polarity()
         end
      elseif n == 3 and z == 1 then
         LFOs.toggle_sync()
      end
      return
   end

   -- K2/K3 cycle circularly through 4 focus modes
   if n == 2 and z == 1 and not k3_held then
      local next_focus = focus - 1
      if next_focus < 1 then next_focus = 4 end
      params:set("focus", next_focus)
   end
   if n == 3 and z == 1 and not k2_held then
      local next_focus = focus + 1
      if next_focus > 4 then next_focus = 1 end
      params:set("focus", next_focus)
   end
 end

-- norns: encoders
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function enc(n, d)
   -- LFO patch mode: E1=freq, E2=next cursor, E3=adjust value
   if LFOs.patch_mode then
      if n == 1 then
         LFOs.adjust_freq(d)
      elseif n == 2 then
         LFOs.next_cursor()
      elseif n == 3 then
         LFOs.adjust_value(d)
      end
      return
   end

   local enc_map = {
      [1] = {param = "drone_freq", delta = 0.05, id = 17},
      [2] = {param = "fx_time",    delta = 0.05,  id = 18},
      [3] = {param = "poly_scale", delta = 1,    id = 19},
   }
   local m = enc_map[n]
   if m then
      params:delta(m.param, d * m.delta)
      local val_norm = params:get_raw(m.param)
      base_values[m.param] = val_norm
      Loopers.on_fader_move(m.id, val_norm)
   end
end

-- grid: keys
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

g.key = function(x, y, z)
   -- drone snapshot buttons (row 8, cols 2-5, ncoco-style)
   -- no return here so sequencer recording block below can capture button presses
   if y == 8 and x >= 2 and x <= 5 then
      local id = x - 1
      if z == 1 then
         drone_snap_timers[id] = util.time()
         clock.run(function()
            local this_timer = drone_snap_timers[id]
            clock.sleep(1.6)
            if drone_snap_timers[id] == this_timer then
               drone_snap_clear(id)
               drone_snap_timers[id] = -1
            end
         end)
      elseif z == 0 then
         if drone_snap_timers[id] == -1 then
            drone_snap_timers[id] = 0
         else
            local t = util.time() - (drone_snap_timers[id] or 0)
            drone_snap_timers[id] = 0
            if t < 1.6 then
               if shift_held then
                  drone_snap_update(id)
               elseif drone_snaps[id] == nil then
                  drone_snap_save(id)
               elseif active_drone_snap ~= id then
                  drone_snap_load(id)
               end
               -- if active and filled: do nothing (no save, no load)
            end
         end
      end
   end

   -- LFO buttons: rows 3-5, cols 1-2 (hold=patch, release=exit, SHIFT+hold=clear)
   if y >= 3 and y <= 5 and x >= 1 and x <= 2 then
      local lfo_id = (y - 3) * 2 + x
      if z == 1 then
         if shift_held then
            LFOs.clear_assignments(lfo_id)
         else
            LFOs.enter_patch(lfo_id)
            for i = 1, 16 do fader_latched[i] = false end
         end
      elseif z == 0 then
         if LFOs.patch_mode == lfo_id then
            LFOs.exit_patch()
         end
      end
      return
   end

   -- parameter looper buttons (delegated to Loopers module, row 8 cols 7-12)
   if Loopers.grid_key(x, y, z, shift_held) then return end

   -- sequencer buttons (row 8, cols 14-16) with quantization
   if y == 8 and x >= 14 and x <= 16 and z == 1 then
      local id = x - 13
      local s = sequencers[id]
      s.press_time = util.time()
      if s.state == 0 then
         _quantize_seq_change(id, function()
            local ss = sequencers[id]
            ss.state = 1; ss.data = {}; ss.start_time = util.time()
         end)
      elseif s.state == 1 then
         _quantize_seq_change(id, function()
            local ss = sequencers[id]
            ss.duration = util.time() - ss.start_time
            if ss.duration < 0.1 then ss.duration = 0.1 end
            ss.state = 2; ss.start_time = util.time()
         end)
      elseif s.state == 2 or s.state == 4 then
         if s.double_click_timer then
            _quantize_seq_change(id, function()
               local ss = sequencers[id]
               ss.state = 3; ss.double_click_timer = nil
            end)
         else
            s.double_click_timer = clock.run(function()
               clock.sleep(0.25)
               if s.state == 3 then return end
               _quantize_seq_change(id, function()
                  local ss = sequencers[id]
                  if ss.state == 2 then ss.state = 4 else ss.state = 2 end
               end)
               s.double_click_timer = nil
            end)
         end
      elseif s.state == 3 then
         _quantize_seq_change(id, function()
            local ss = sequencers[id]
            ss.state = 2; ss.start_time = util.time()
         end)
      end
      return
   end
   if y == 8 and x >= 14 and x <= 16 and z == 0 then
      local s = sequencers[x - 13]
      if util.time() - (s.press_time or 0) > 1.0 then
         if s.pending_change then clock.cancel(s.pending_change); s.pending_change = nil end
         s.state = 0; s.data = {}
      end
      return
   end

   -- keyboard: record for active sequencers
   -- (with note_quant active, manual presses are recorded at fire time instead)
   if (z == 1 or z == 0) and y <= 7 and x >= math.max(1, 9 - y) and params:get("note_quant") == 1 then
      record_note_event(x, y, z)
   end

   -- record snapshot button presses for active sequencers
   if y == 8 and x >= 2 and x <= 5 and (z == 1 or z == 0) then
      for i = 1, 3 do
         local s = sequencers[i]
         if s.state == 1 or s.state == 4 then
            local dt = util.time() - s.start_time
            if s.state == 4 then dt = dt % s.duration end
            if #s.data < 10000 then
               table.insert(s.data, {x = x, y = y, z = z, dt = dt, note = nil, oct = 0})
            end
         end
      end
   end

   if x == 1 and y == 1 then
      if z == 1 then
         if shift_held then
             if params:get("poly_hold") == 2 then
                sostenuto = not sostenuto
                params:set("sostenuto", sostenuto and 2 or 1)
             end
          elseif params:get("poly_hold") == 2 then
             params:set("poly_hold", 1)
             sostenuto = false
             params:set("sostenuto", 1)
             stop_keys()
         else
            params:set("poly_hold", 2)
            for n = 1, #playing do
               playing[n].held = true
            end
         end
      end
   elseif x == 2 and y == 1 then
      if z == 1 then
         if params:get("poly_loop") == 2 then
            params:set("poly_loop", 1)
         else
            params:set("poly_loop", 2)
         end
      end
   elseif x == 1 and y == 8 then
      shift_held = (z == 1)
      -- SHIFT while in LFO patch mode: delete current item (if assignment)
      if z == 1 and LFOs.patch_mode then
         LFOs.remove_current()
      end
   elseif y == 1 and x == 4 and z == 1 then
      oct = math.max(0, oct - 1)
   elseif y == 1 and x == 5 and z == 1 then
      if oct < 2 then oct = oct + 1 elseif oct > 2 then oct = oct - 1 end
   elseif y == 1 and x == 6 and z == 1 then
      oct = math.min(4, oct + 1)
   else
      if y <= 7 and x >= math.max(1, 9 - y) then
         if params:get("note_quant") > 1 then
            if z == 1 then
               arm_note(x, y)
            elseif not disarm_note(x, y) then
               -- already fired: release passes through unquantized, record now
               record_note_event(x, y, 0)
               if not hold or sostenuto then play_note(x, y, 0) else hold_note(x, y, 0) end
            end
         else
            if not hold or sostenuto then play_note(x, y, z) else hold_note(x, y, z) end
         end
      end
   end
end

-- arc: key
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

a.key = function(n, z)
   if n == 1 then
      if z == 1 then
         -- cycle forward through 4 modes
         local next_f = focus + 1
         if next_f > 4 then next_f = 1 end
         params:set("focus", next_f)
      end
   end
end

-- arc: encoders
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

a.delta = function(n, d)
   arc_dirty = true

   if focus == 1 then -- Jord
      if n == 1 then params:delta("drone_timbre", d * 0.10) end
      if n == 2 then params:delta("drone_noise" , d * 0.10) end
      if n == 3 then params:delta("drone_bias"  , d * 0.15) end
      if n == 4 then params:delta("drone_freq"  , d * 0.05) end
   end

   if focus == 2 then -- Løv
      if n == 1 then params:delta("poly_timbre", d * 0.10) end
      if n == 2 then params:delta("poly_noise" , d * 0.10) end
      if n == 3 then params:delta("poly_bias"  , d * 0.15) end
      if n == 4 then params:delta("poly_shape" , d * 0.10) end
   end

   if focus == 3 then -- Lys
      if n == 1 then params:delta("fx_peak_1", d * 0.10) end
      if n == 2 then params:delta("fx_peak_2", d * 0.10) end
      if n == 3 then params:delta("fx_body"  , d * 0.10) end
      if n == 4 then params:delta("fx_time"  , d * 0.05) end
   end

   if focus == 4 then -- Play (same as Lys)
      if n == 1 then params:delta("fx_peak_1", d * 0.10) end
      if n == 2 then params:delta("fx_peak_2", d * 0.10) end
      if n == 3 then params:delta("fx_body"  , d * 0.10) end
      if n == 4 then params:delta("fx_time"  , d * 0.05) end
   end
end

-- norns: drawing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw(sframe)
   sframe = sframe or 1
   s.clear()
   
   if splash then
      s.aa(0)
      s.level(splash_level)
      s.move(63, 55)
      s.font_face(12)
      s.font_size(60)
	    s.text_center("Høst")
   end

   if focus == 1 then -- Jord      
      for n = 1, util.clamp(math.floor(#particles * (Harvest.drone_bias)), 1, #particles) do
         if particles[n].on then

            -- noise
            if sframe % 4 == 1 then
               if math.random() < Harvest.drone_noise * 0.1 then
                  particles[n].noise = 0.49
               else
                  particles[n].noise = 1
               end
            end

            -- detrius
            particles[n].level = 1

            if Harvest.drone_timbre < 0.5 then
               particles[n].level = 1 + math.floor(13 * (Harvest.drone_timbre * -2 + 1))
            else
               if particles[n].x % 32 > 16 then
                  particles[n].level = 1 + math.floor(13 * (Harvest.drone_timbre * 2 - 1))
               end
            end
               
            s.level(1 + math.floor(particles[n].level * particles[n].noise))
            s.pixel(particles[n].x, particles[n].y)
            s.fill()   
         end
      end
   end
   
   if focus == 2 then -- Løv
      local offset = 64 * Harvest.poly_timbre

      -- light
      s.level(7)
      s.rect(0, 0, 128, 64)
      s.fill()

      -- noise
      if sframe % 4 == 1 then
         for n = 1, math.max(math.floor(#particles * (Harvest.poly_bias)), 1) do
            if math.random() < Harvest.poly_noise * 0.1 then
               particles[n].level = 10
            else
               particles[n].level = 15
            end
         end
      end
      
      -- shadow
      for n = 1, math.max(math.floor(#particles * Harvest.poly_bias), 1) do
         x = particles[n].x
         y = particles[n].y
         for n = 1, 2 do
            if particles[n].on == true then
               s.pixel(x - n, y + n)
            end
         end
         s.level(3)
         s.fill()
      end

      -- dark
      if Harvest.poly_timbre < 0.5 then
         s.level(0)
         s.move(64 + offset,  0)
         s.line( 0 + offset, 64)
         s.line( 0, 64)
         s.line( 0,  0)
         s.fill()
      else
         s.level(0)
         s.move(88,  0)
         s.line(24, 64)
         s.line( 0, 64)
         s.line( 0,  0)
         s.fill()
         s.move(56 + offset,  0)
         s.line(-8 + offset, 64)
         s.line( 0 + offset * 2 - 32, 64)
         s.line(64 + offset * 2 - 32,  0)
         s.fill()
      end
      
      -- detrius
      for n = 1, math.max(math.floor(#particles * Harvest.poly_bias), 1) do
         x = particles[n].x
         y = particles[n].y
         if particles[n].on == true then
            s.pixel(x, y)
            s.level(particles[n].level)
            s.fill()
         end
      end
   end

   if focus == 3 then -- Lys
      -- light
      s.level(7)
      s.rect(0, 0, 128, 64)
      s.fill()

      -- shadow
      s.level(3)
      for n = 1, math.max(math.floor(#particles * (1 - Harvest.fx_time)), 1) do
         x = particles[n].x
         y = particles[n].y
         for n = 1, 2 + math.floor(62 * 2 * math.abs(((Harvest.fx_body - 0.5) % 1) - 0.5)) do
            if particles[n].on == true then
               s.pixel(x - n, y + n)
            end
         end
      end
      s.fill()

      -- dark
      s.level(1)
      s.blend_mode(5)
     
      local offset_1 = 128 * Harvest.fx_peak_1
      s.move(( 32 - 32) + offset_1,  0)
      s.line((-32 - 32) + offset_1, 64)
      s.line((-32 + 32) + offset_1, 64)
      s.line(( 32 + 32) + offset_1,  0)
      s.fill()
   
      local offset_2 = 128 * Harvest.fx_peak_2
      s.move(( 32 - 32) + offset_2,  0)
      s.line((-32 - 32) + offset_2, 64)
      s.line((-32 + 32) + offset_2, 64)
      s.line(( 32 + 32) + offset_2,  0)
      s.fill()
    
      s.blend_mode(0)

      -- detrius
      s.level(15)
      for n = 1, math.max(math.floor(#particles * (1 - Harvest.fx_time)), 1) do
         x = particles[n].x
         y = particles[n].y
         if particles[n].on == true then
            s.pixel(x, y)
         end
      end
      s.fill()
   end

   if focus == 4 then -- Play (Terrario espacial)
      -- Respiración global: poly_shape controla velocidad (0=rápida, 1=lenta)
      local breath_speed = util.clamp(0.3 + (1 - (Harvest.poly_shape or 0.1)) * 0.7, 0.1, 1.0)
      local t = util.time() * breath_speed

      -- fx_gain casi nunca pasa de 3 (rango 0.5-16): normalizar pronto (0.5→0, ~3→1)
      local gain_val = params:get("fx_gain") or 0.5
      local gain_norm = util.clamp((gain_val - 0.5) / 2.5, 0, 1)

      -- bias: rango -1..1 con centro 0 → 0..1 (centro = 0.5)
      local bias_norm = util.clamp(((Harvest.drone_bias or 0) + 1) / 2, 0, 1)
      local poly_bias_norm = util.clamp(((Harvest.poly_bias or 0) + 1) / 2, 0, 1)

      -- noise casi siempre bajo: ×10 + curva suave para ver efecto desde valores mínimos
      local noise_val = util.clamp((Harvest.drone_noise or 0) * 10, 0, 1) ^ 0.7
      local poly_noise_val = util.clamp((Harvest.poly_noise or 0) * 10, 0, 1) ^ 0.7

      local timbre_val = Harvest.drone_timbre or 0.5
      local body_val = Harvest.fx_body or 0
      local time_val = Harvest.fx_time or 0.5

      -- === 1. CAPA GRIS OSCURA (nebulosa de fondo, densidad = poly_bias) ===
      local neb_count = math.floor(#particles * poly_bias_norm * 0.6)
      for n = 1, neb_count do
         local p = particles[n]
         local nx = p.x + math.sin(t * 0.15 + n * 0.7) * 2
         local ny = p.y + math.cos(t * 0.12 + n * 1.3) * 1.5
         s.level(n % 5 == 1 and 2 or 1)
         s.pixel(util.clamp(math.floor(nx), 1, 128), util.clamp(math.floor(ny), 1, 64))
      end
      s.fill()

      -- === 2. VELOS LYS (triángulos peak1/peak2, blend exclusion 13 entre ellos) ===
      s.level(1)
      s.blend_mode(13)  -- exclusion: peaks interact instead of covering each other

      local offset_1 = 128 * Harvest.fx_peak_1
      s.move(( 32 - 32) + offset_1,  0)
      s.line((-32 - 32) + offset_1, 64)
      s.line((-32 + 32) + offset_1, 64)
      s.line(( 32 + 32) + offset_1,  0)
      s.fill()

      local offset_2 = 128 * Harvest.fx_peak_2
      s.move(( 32 - 32) + offset_2,  0)
      s.line((-32 - 32) + offset_2, 64)
      s.line((-32 + 32) + offset_2, 64)
      s.line(( 32 + 32) + offset_2,  0)
      s.fill()

      -- === VELO POLY (triángulo tenue de Løv, blend multiply 3 con los peaks) ===
      s.blend_mode(3)  -- multiply: se mezcla oscureciendo con los peaks

      local poly_offset = 64 * (Harvest.poly_timbre or 0.2)
      if (Harvest.poly_timbre or 0) < 0.5 then
         s.move(64 + poly_offset, 0)
         s.line(0 + poly_offset, 64)
         s.line(0, 64)
         s.line(0, 0)
         s.fill()
      else
         s.move(88, 0)
         s.line(24, 64)
         s.line(0, 64)
         s.line(0, 0)
         s.fill()
      end
      s.blend_mode(0)

      -- === 3. SOMBRAS LYS (largas diagonales, controladas por fx_body, NO por time) ===
      local body_dist = 2 * math.abs(((body_val - 0.5) % 1) - 0.5)  -- 0 centro, 1 extremos
      local shad_len = 2 + math.floor(62 * body_dist)
      local shad_count = math.floor(#particles * util.clamp(0.3 + 0.7 * body_dist, 0, 1))
      s.level(2)
      for n = 1, shad_count do
         local p = particles[n]
         for k = 1, shad_len do
            s.pixel(p.x - k, p.y + k)  -- diagonal: arriba-derecha → abajo-izquierda
         end
      end
      s.fill()

      -- === 4. SOMBRAS POLY (cortas 2px, tono más claro, densidad = poly_bias) ===
      local pshad_count = math.floor(#particles * poly_bias_norm)
      s.level(4)
      for n = 1, pshad_count do
         local p = particles[n]
         s.pixel(p.x - 1, p.y + 1)
         s.pixel(p.x - 2, p.y + 2)
      end
      s.fill()

      -- === 5. PUNTOS ESTÁTICOS (densidad = 1 - fx_time, flicker = poly_noise) ===
      local stat_count = math.max(math.floor(#particles * (1 - time_val)), 1)
      if sframe % 4 == 1 then
         for n = 1, stat_count do
            if math.random() < poly_noise_val * 0.1 then
               particles[n].level = 2
            else
               particles[n].level = 7
            end
         end
      end
      for n = 1, stat_count do
         local p = particles[n]
         s.level(p.level)
         s.pixel(p.x, p.y)
      end
      s.fill()

      -- === 6. ESTRELLAS (cantidad = drone_bias, tamaños variados, ciclo vida + respawn) ===
      local num_stars = math.floor(24 + 72 * bias_norm)  -- centro(0) = 60 estrellas
      for i = 1, num_stars do
         local star = stars[i]
         star.life = star.life + star.life_speed * breath_speed
         if star.life > 2 * math.pi then
            star.life = 0
            star.x = math.random(1, 128)
            star.y = math.random(1, 64)
            star.alive = true
         end

         local life_norm = star.life / (2 * math.pi)
         local env = math.sin(life_norm * math.pi) ^ 2

         -- twinkle por drone_noise (sensible a valores bajos)
         if math.random() < noise_val * 0.05 then
            star.twinkle = 1.0
         end
         star.twinkle = star.twinkle * 0.9

         -- brillo base por drone_timbre (estilo Jord)
         local base_bright = timbre_val < 0.5 and (2 + timbre_val * 8) or (6 + timbre_val * 6)
         local brightness = env * 0.7 + star.twinkle * 0.3
         local level = math.floor(util.clamp(base_bright * brightness, 1, 12))

         if level > 1 then
            s.level(level)
            local sx, sy = star.x, star.y
            if star.size == 3 and level > 5 then
               -- gordita: diamante 3px
               s.pixel(sx, sy)
               s.pixel(sx - 1, sy) s.pixel(sx + 1, sy)
               s.pixel(sx, sy - 1) s.pixel(sx, sy + 1)
               s.pixel(sx - 1, sy - 1) s.pixel(sx + 1, sy - 1)
               s.pixel(sx - 1, sy + 1) s.pixel(sx + 1, sy + 1)
            elseif star.size == 2 and level > 4 then
               -- mediana: cruz 2px
               s.pixel(sx, sy)
               s.pixel(sx - 1, sy) s.pixel(sx + 1, sy)
               s.pixel(sx, sy - 1) s.pixel(sx, sy + 1)
            else
               s.pixel(sx, sy)
            end
            -- bloom por gain (sensible: desde gain ~1.2)
            if gain_norm > 0.25 and level > 7 and star.size >= 2 then
               s.pixel(sx - 2, sy) s.pixel(sx + 2, sy)
               s.pixel(sx, sy - 2) s.pixel(sx, sy + 2)
            end
            s.fill()
         end
      end

      -- === 7. ESTRELLAS FUGACES (drone_noise: rachas diagonales rápidas) ===
      if noise_val > 0.03 and math.random() < noise_val * 0.015 then
         for i = 1, 3 do
            if not shooters[i].alive then
               local spd = 1.2 + math.random() * 0.8
               shooters[i].x = math.random(40, 128)
               shooters[i].y = math.random(1, 30)
               shooters[i].vx = -spd
               shooters[i].vy = spd * 0.8
               shooters[i].len = 3 + math.random() * 3
               shooters[i].life = 1
               shooters[i].alive = true
               break
            end
         end
      end
      for i = 1, 3 do
         local sh = shooters[i]
         if sh.alive then
            sh.x = sh.x + sh.vx
            sh.y = sh.y + sh.vy
            sh.life = sh.life - 0.02
            if sh.life <= 0 or sh.x < 1 or sh.y > 64 then
               sh.alive = false
            else
               local head = math.floor(util.clamp(3 + sh.life * 7, 2, 10))
               for k = 0, math.floor(sh.len) do
                  local px = math.floor(sh.x + k * 0.8)
                  local py = math.floor(sh.y - k * 0.64)
                  if px >= 1 and px <= 128 and py >= 1 and py <= 64 then
                     s.level(util.clamp(head - k * 2, 1, 10))
                     s.pixel(px, py)
                  end
               end
               s.fill()
            end
         end
      end

      -- === 8. ORBES (cantidad = poly_bias, sutiles, deriva diagonal lenta, respawn anywhere) ===
      local num_orbs = math.floor(1 + 3 * poly_bias_norm)
      for i = 1, num_orbs do
         local orb = orbs[i]
         orb.life = orb.life + orb.life_speed * breath_speed
         if orb.life > 2 * math.pi then
            orb.life = 0
            orb.alive = true
            -- respawn en cualquier lugar; trayectoria SIEMPRE diagonal (como las sombras)
            orb.x = math.random(10, 118)
            orb.y = math.random(6, 58)
            orb.max_size = 1 + math.random()
            local spd = 0.02 + math.random() * 0.03
            orb.vx = -spd
            orb.vy = spd * (0.7 + math.random() * 0.6)
         end

         local life_norm = orb.life / (2 * math.pi)
         local env = math.sin(life_norm * math.pi)

         -- wobble de brillo por poly_noise (sensible a valores bajos)
         orb.wobble = orb.wobble + 0.1
         local wob = 1 + math.sin(orb.wobble) * poly_noise_val * 0.5

         -- deriva diagonal lenta: arriba-derecha → abajo-izquierda (~0.6-1.5 px/s)
         orb.x = orb.x + orb.vx
         orb.y = orb.y + orb.vy
         -- si sale de pantalla → respawn en cualquier lugar (nunca mismo sitio)
         if orb.x < 2 or orb.y > 62 then
            orb.x = math.random(10, 118)
            orb.y = math.random(6, 58)
            orb.life = 0
         end

         local size = math.max(1, math.floor(orb.max_size * env + 0.5))
         local level = math.floor(util.clamp((3 + env * 5) * wob, 2, 8))
         local ox, oy = math.floor(orb.x), math.floor(orb.y)

         -- cola diagonal corta detrás del orbe (coherente con su trayectoria)
         s.level(2)
         s.pixel(ox + 1, oy - 1)
         s.pixel(ox + 2, oy - 2)
         s.fill()

         -- cuerpo suave: centro brillante, bordes tenues
         s.level(level)
         s.pixel(ox, oy)
         s.fill()
         s.level(math.max(2, level - 3))
         s.pixel(ox - 1, oy) s.pixel(ox + 1, oy)
         s.pixel(ox, oy - 1) s.pixel(ox, oy + 1)
         s.fill()
         if size >= 2 then
            s.level(math.max(1, level - 5))
            s.pixel(ox - 1, oy - 1) s.pixel(ox + 1, oy - 1)
            s.pixel(ox - 1, oy + 1) s.pixel(ox + 1, oy + 1)
            s.fill()
         end

         -- bloom por gain (sensible: desde gain ~1.2)
         if gain_norm > 0.2 and env > 0.6 then
            s.level(2)
            s.pixel(ox - 2, oy) s.pixel(ox + 2, oy)
            s.pixel(ox, oy - 2) s.pixel(ox, oy + 2)
            s.fill()
         end
      end
   end

   -- E1/E2/E3 value displays (overlaid on background graphics)
   s.font_face(1)
   s.font_size(8)
   s.level(15)
   -- Top left: E1 Drone freq
   s.move(2, 8)
   s.text("E1 freq: " .. string.format("%.0f", params:get("drone_freq")) .. "Hz")
   -- Top right: Env Quant status (FREE or current division)
   local env_status = "FREE"
   if EnvQuant.enabled() and EnvQuant.last_div_idx > 0 then
      env_status = EnvQuant.div_labels[EnvQuant.last_div_idx]
   end
   s.move(126, 8)
   s.text_right("ENV: " .. env_status)
   -- Bottom left: E2 Delay time
   s.move(2, 62)
   s.text("E2 time: " .. string.format("%.2f", params:get("fx_time")) .. "s")
   -- Bottom right: E3 Env scale (always shows % only)
   local scale_str = string.format("%.0f", params:get("poly_scale") * 100) .. "%"
   s.move(126, 62)
   s.text_right("E3 scale: " .. scale_str)

   UI.draw_popup()

   -- LFO patch overlay
   if LFOs.patch_mode and LFOs.data[LFOs.patch_mode] then
      local lfo = LFOs.data[LFOs.patch_mode]
      local info = LFOs.get_cursor_info()

      s.level(0)
      s.rect(2, 1, 124, 62)
      s.fill()
      s.level(15)
      s.rect(2, 1, 124, 62)
      s.stroke()

      -- Title: LFO N (right) + E1 freq/div value (left)
      s.level(15)
      s.move(122, 10)
      s.text_right("LFO " .. LFOs.patch_mode)
      s.move(6, 10)
      if lfo.sync then
         s.text("E1: " .. (LFOs.sync_divisions[lfo.sync_div] or "1/1"))
      else
         s.text("E1: " .. string.format("%.2fHz", lfo.freq))
      end

      -- Scope
      local sx, sy, sw, sh = 10, 14, 108, 16
      s.level(4)
      s.rect(sx, sy, sw, sh)
      s.stroke()
      local hist = lfo.history
      local head = lfo.history_head
      s.level(15)
      local last_px, last_py = nil, nil
      for i = 0, sw - 1 do
         local idx = (head - 1 - i - 1) % 128 + 1
         local val = util.clamp(hist[idx], -1, 1)
         local px = sx + sw - i
         local py = sy + sh - (util.clamp((val + 1) / 2, 0, 1) * sh)
         if last_px then
            s.move(last_px, last_py)
            s.line(px, py)
         else
            s.pixel(px, py)
         end
         last_px = px
         last_py = py
      end
      s.stroke()

      -- Menu items with 3-line scroll
      local visible_items = 3
      local scroll_offset = 0
      if info then
         scroll_offset = math.max(0, math.min(info.cursor - 1, math.max(0, info.max_cursor - visible_items)))
      end
      local y_start = 36
      local y_step = 8
      for vis_idx = 1, visible_items do
         local item_idx = scroll_offset + vis_idx
         if info and item_idx <= info.max_cursor then
            local is_selected = (item_idx == info.cursor)
            s.level(is_selected and 15 or 4)
            s.move(6, y_start + (vis_idx - 1) * y_step)
         if item_idx == 1 then
            local marker = is_selected and "> " or "  "
            s.text(marker .. "shape   " .. string.format("%.2f", lfo.shape))
         elseif item_idx == 2 then
            local marker = is_selected and "> " or "  "
            s.text(marker .. "noise   " .. string.format("%.2f", lfo.noise))
         else
            local assign_idx = item_idx - 2
            local a = lfo.assignments[assign_idx]
            if a then
               local marker = is_selected and "> " or "  "
               local name = a[1]
               if #name > 10 then name = string.sub(name, 1, 7) .. ".." end
               s.text(marker .. name .. " " .. string.format("%+.1f%%", a[2] * 100))
               if is_selected then
                  s.move(122, y_start + (vis_idx - 1) * y_step)
                  s.text_right("[" .. assign_idx .. "/" .. #lfo.assignments .. "]")
               end
            end
         end
      end
      end

      -- Controls hint
      s.level(4)
      s.move(4, 60)
      s.text("E2:sel E3:val K2:± K3:sync")
   end

   s.update()
   s.ping()
end

-- grid: drawing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw_grid(frame)
   local background = 1
   local changed = false

   -- Helper: set LED only if brightness changed from cache
   local function set_led(x, y, b)
      if grid_cache[x][y] ~= b then
         g:led(x, y, b)
         grid_cache[x][y] = b
         changed = true
      end
   end

   -- background (diagonal pattern, two lines shorter: 9-y boundary)
   if current_scale == "Chromatic" then
      for n = 8, 16 do set_led(n, 1, background) end
      for n = 7, 16 do set_led(n, 2, background) end
      for n = 6, 16 do set_led(n, 3, background) end
      for n = 5, 16 do set_led(n, 4, background) end
      for n = 4, 16 do set_led(n, 5, background) end
      for n = 3, 16 do set_led(n, 6, background) end
      for n = 2, 16 do set_led(n, 7, background) end
   else
      -- same diagonal but only light columns within scale pattern
      local steps = #scales[current_scale]
      for n = 8, 16 do if ((n - 1) % steps) + 1 <= steps then set_led(n, 1, background) end end
      for n = 7, 16 do if ((n - 1) % steps) + 1 <= steps then set_led(n, 2, background) end end
      for n = 6, 16 do if ((n - 1) % steps) + 1 <= steps then set_led(n, 3, background) end end
      for n = 5, 16 do if ((n - 1) % steps) + 1 <= steps then set_led(n, 4, background) end end
      for n = 4, 16 do if ((n - 1) % steps) + 1 <= steps then set_led(n, 5, background) end end
      for n = 3, 16 do if ((n - 1) % steps) + 1 <= steps then set_led(n, 6, background) end end
      for n = 2, 16 do if ((n - 1) % steps) + 1 <= steps then set_led(n, 7, background) end end
   end

   -- Darken cells outside keyboard area (row 8 cells 6-16, row 7 col 1, row 1 cols 7-16)
   -- These were previously set to 0 by g:all(0); now we explicitly set them to 0
   -- (only via cache diff so they're not re-sent every frame)
   for y = 1, 8 do
      for x = 1, 16 do
         local is_keyboard = (y <= 7 and x >= math.max(1, 9 - y))
         local is_col1 = (x == 1)
         local is_row1_controls = (y == 1 and x >= 4 and x <= 6)
         local is_row2 = (y == 2 and x == 1)
         local is_snap_row = (y == 8 and x >= 2 and x <= 5)
         local is_lfo_cols = (y >= 3 and y <= 5 and x >= 1 and x <= 2)
         local is_looper_row = (y == 8 and x >= 7 and x <= 12)
         local is_seq_row = (y == 8 and x >= 14 and x <= 16)
         local is_shift = (x == 1 and y == 8)
         if not (is_keyboard or is_col1 or is_row1_controls or is_row2 or is_snap_row or is_lfo_cols or is_looper_row or is_seq_row or is_shift) then
            set_led(x, y, 0)
         end
      end
   end
   
   -- coll 1
   local hold_brightness = (Harvest.poly_hold == 1) and 10 or 4
   if sostenuto then
      local wave = (math.sin(frame * 0.116) + 1) / 2  -- 1.11 Hz at 60fps
      hold_brightness = 3 + math.floor(8 * wave + 0.5)  -- 3↔11
   end
   set_led(1, 1, hold_brightness)
   set_led(1, 2, 0)   -- freed (env loop moved to 2,1)
   set_led(1, 3, 0)   -- unused → off
   set_led(1, 4, 0)   -- unused → off
   set_led(1, 5, 0)   -- unused → off
   set_led(1, 6, 0)   -- freed from keyboard
   set_led(1, 7, 0)   -- freed from keyboard
   set_led(1, 8, shift_held and 14 or 4)  -- shift button

   -- tonic notes at level 2, only within keyboard diagonal area (rows 1-7)
   for x = 2, 16 do
      for y = 1, 7 do
          if x >= math.max(1, 9 - y) then
            local n = xy_to_note(x, y)
            if (n % 12) == scale_root then
               set_led(x, y, 2)
            end
         end
      end
   end

   -- light up all playing notes with envelope-driven brightness (4-15)
   -- Uses real envelope phase from SC engine via OSC (ground truth)
   for n = 1, #playing do
      local p = playing[n]
      local env_val = p.env_val or 0
      set_led(p.x, p.y, 4 + math.floor(11 * env_val))
   end

   -- pending notes blink (1↔6 fast)
   local pending_wave = (math.sin(frame * 0.20) + 1) / 2
   for _, pn in ipairs(pending_notes) do
      set_led(pn.x, pn.y, 1 + math.floor(5 * pending_wave + 0.5))
   end

   -- armed notes (note_quant) blink same as pending
   for _, a in pairs(armed_notes) do
      set_led(a.x, a.y, 1 + math.floor(5 * pending_wave + 0.5))
   end

   -- env loop LED at (2,1): same brightness pattern as hold button
   set_led(2, 1, Harvest.poly_loop == 0 and 4 or 10)
   -- octave LEDs in row 1 cols 4-5-6 (linear 0..4: -2,-1,0,+1,+2)
   local oct_wave = (math.sin(frame * 0.10) + 1) / 2
   local oct_led_1 = 1  -- x=4 (left), brillo 1 when not selected
   local oct_led_2 = 1  -- x=5 (center)
   local oct_led_3 = 1  -- x=6 (right)

   if oct == 0 then
      oct_led_1 = 2 + math.floor(4 * oct_wave + 0.5)  -- -2: blink 6↔2
   elseif oct == 1 then
      oct_led_1 = 5  -- -1: fixed
   elseif oct == 2 then
      oct_led_2 = 5  -- 0: center fixed
   elseif oct == 3 then
      oct_led_3 = 5  -- +1: fixed
   elseif oct == 4 then
      oct_led_3 = 2 + math.floor(4 * oct_wave + 0.5)  -- +2: blink 6↔2
   end

   set_led(4, 1, oct_led_1)
   set_led(5, 1, oct_led_2)
   set_led(6, 1, oct_led_3)

   -- drone snapshot LEDs (row 8, cols 2-5, ncoco-style)
   for i = 1, 4 do
      local x = 1 + i
      local b = 0
      if drone_snap_timers[i] and drone_snap_timers[i] > 0 then b = 15
      elseif active_drone_snap == i then b = 10
      elseif drone_snaps[i] ~= nil then b = 6
      else b = 2 end
      set_led(x, 8, b)
   end

   -- LFO LEDs (rows 3-5: cols 1-2, 6 LFOs top-to-bottom left-to-right)
   for i = 1, 6 do
      local row = math.floor((i - 1) / 2) + 3
      local col = ((i - 1) % 2) + 1
      local lfo = LFOs.data[i]
      local b = 2
      if lfo then
         if LFOs.patch_mode == i then
            b = 14
         elseif shift_held then
            local wave = (math.sin(frame * 0.25) + 1) / 2
            b = 2 + math.floor(6 * wave + 0.5)
         else
            b = math.floor(util.linlin(-1, 1, 2, 12, lfo.value))
         end
      end
      set_led(col, row, b)
   end

   -- parameter looper LEDs (delegated to Loopers module)
   Loopers.redraw_grid_set(g, set_led)

   -- sequencer LEDs (row 8, cols 14-16)
   for i = 0, 2 do
      local x = 14 + i
      local s = sequencers[i + 1]
      local b = 0
      if s.state == 0 then b = 2
      elseif s.state == 1 then b = math.floor(util.linlin(-1, 1, 5, 15, math.sin(util.time() * 5)))
      elseif s.state == 2 then b = 12
      elseif s.state == 3 then b = 5
      elseif s.state == 4 then b = math.floor(util.linlin(-1, 1, 5, 15, math.sin(util.time() * 15)))
      end
      set_led(x, 8, b)
   end

   if changed then g:refresh() end
end

-- arc: drawing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw_arc()
   a:all(0)
   local offset = 5.625 * -31 -- 1 led = 5.625 degrees
   local  level = 5
   local s1
   local s2
   
   if focus == 1 then -- Jord
      -- e1
      local val = Harvest.drone_timbre * 2 - 1
      if val < 0 then
         s1 = math.rad(val * 5.625 * 31)
         s2 = math.rad(0)
      else
         s1 = math.rad(0)
         s2 = math.rad(val * 5.625 * 32)
      end
      a:segment(1, s1, s2, level)
      a:led(1,  1, 1)
      a:led(1, 33, 1)
      
      -- e2
      s1 = math.rad(offset)
      s2 = math.rad(Harvest.drone_noise * 5.625 * 63 + offset)
      a:segment(2, s1, s2, level)
      a:led(2,  1, 1)
      a:led(2, 33, 1)
      
      -- e3
      arc_bar(3, Harvest.drone_bias, level)
      --a:led(3,  1, 1)
      a:led(3, 33, 1)

      -- e4
      s1 = math.rad(offset)
      s2 = math.rad(Harvest.drone_freq * 5.625 * 63 + offset)
      a:segment(4, s1, s2, level)
      a:led(4,  1, 1)
      a:led(4, 33, 1)
   end
   
   if focus == 2 then -- Løv
      -- e1
      local val = Harvest.poly_timbre * 2 - 1
      if val < 0 then
         s1 = math.rad(val * 5.625 * 31)
         s2 = math.rad(0)
      else
         s1 = math.rad(0)
         s2 = math.rad(val * 5.625 * 32)
      end
      a:segment(1, s1, s2, level)
      a:led(1,  1, 1)
      a:led(1, 33, 1)
      
      -- e2
      s1 = math.rad(offset)
      s2 = math.rad(Harvest.poly_noise * 5.625 * 63 + offset)
      a:segment(2, s1, s2, level)
      a:led(2,  1, 1)
      a:led(2, 33, 1)
      
      -- e3
      arc_bar(3, Harvest.poly_bias, level)
      a:led(3, 33, 1)
      
      -- e4
      s1 = math.rad(offset)
      s2 = math.rad(Harvest.poly_shape * 5.625 * 63 + offset)
      a:segment(4, s1, s2, level)
      a:led(4, 33, 1)
      a:led(4, 12, 1)
      a:led(4, 54, 1)
   end

   if focus == 3 or focus == 4 then -- Lys / Play (same arc display)
      local width = 8
      local p

      -- e1
      s1 = math.rad(Harvest.fx_peak_1 * 5.625 * (63 - width) + offset)
      s2 = math.rad(Harvest.fx_peak_1 * 5.625 * (63 - width) + 5.625 * width + offset)
      a:segment(1, s1, s2, 6)
      a:led(1, 33, 1)
      
      -- e2
      s1 = math.rad(Harvest.fx_peak_2 * 5.625 * (63 - width) + offset)
      s2 = math.rad(Harvest.fx_peak_2 * 5.625 * (63 - width) + 5.625 * width + offset)
      a:segment(2, s1, s2, 6)
      a:led(2, 33, 1)

      -- e3
      s1 = math.rad(Harvest.fx_body * 5.625 * 64 - 5.625 * 8 + offset)
      s2 = math.rad(Harvest.fx_body * 5.625 * 64 + 5.625 * 7 + offset)
      a:segment(3, s1, s2, level)
      local shift = 8
      a:led(3,  1 + shift, 1)
      a:led(3, 17 + shift, 1)
      a:led(3, 33 + shift, 1)
      a:led(3, 49 + shift, 1)

      -- e4
      s1 = math.rad(offset)
      s2 = math.rad(Harvest.fx_time * 5.625 * 63 + offset)
      a:segment(4, s1, s2, level)
      a:led(4, 33, 1)
   end

   a:refresh()
end

-- cleanup
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function cleanup()
   if clk_env_quant then clock.cancel(clk_env_quant) end
   if disarm_all_notes then disarm_all_notes() end
   if clk_screen then clock.cancel(clk_screen) end
   if clk_grid then clock.cancel(clk_grid) end
   for i = 1, 3 do
      if seq_clock_ids[i] then clock.cancel(seq_clock_ids[i]) end
   end
   LFOs.cleanup()
   Loopers.cleanup()
   Storage.save(playing, hold, Harvest.poly_loop == 1, oct, calc_cycle_len())
   stop_keys()
   if save_on_exit then params:write(norns.state.data .. "state.pset") end
end