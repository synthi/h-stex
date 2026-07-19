--
--  A remake by Joaue Arias
--  v1.7 - Joaue Arias
--      .                   
--                         
--          .          .     
--   .
--                .         
--    .                     
--                         .
-- .
-- original v1.1 / imminent gloom

-- setup
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

engine.name = "Harvest"
    Harvest = include("lib/Harvest_engine")
        tab = require("tabutil")
    Storage = include("lib/storage")
          UI = include("lib/ui")
         _16n = include("lib/16n")

local save_on_exit = true

local g = grid.connect()
local a = arc.connect()

local          s = screen
local        fps = 30
local  arc_dirty = true
local     splash = true
local      frame = 1
local  intensity = 8
local  particles = {}
local    density = 96

local      focus = 3
local prev_focus = 1

local    playing = {}
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
local pending_notes = {}
for i = 1, 16 do fader_latched[i] = false end
local      trail = 8

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

local function redraw_event()
   while true do
      clock.sleep(1/fps)
      if frame > fps then
         frame = 1
      else
         frame = frame + 1
      end
      arc_dirty = true
      redraw()
      redraw_grid()
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
   for n = 1, #playing do
      engine.harvest_note_off(playing[n].note + playing[n].transpose)
   end
   playing = {}
end

local function stop_held()
   for n = #playing, 1, -1 do
      if playing[n].held then
         engine.harvest_note_off(playing[n].note + playing[n].transpose)
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

local function play_note(x, y, z, note)
   note = note or xy_to_note(x, y)
   transpose = 12 * oct
   if z == 1 then 
      if #playing >= 12 then
         engine.harvest_note_off(playing[1].note + playing[1].transpose)
         table.remove(playing, 1)
      end
      table.insert(playing, {note = note, transpose = transpose, x = x, y = y, held = false, timestamp = util.time()})
      engine.harvest_note_on(note + transpose, velocity, duration)
   else
      for i, v in pairs(playing) do
         if v.x == x and v.y == y then
            engine.harvest_note_off(playing[i].note + playing[i].transpose)
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
            engine.harvest_note_off(playing[i].note + playing[i].transpose)
            table.remove(playing, i)
            voice = i
            break
         end
      end
      if voice == nil then
         if #playing >= 12 then
            engine.harvest_note_off(playing[1].note + playing[1].transpose)
            table.remove(playing, 1)
         end
         table.insert(playing, {note = note, transpose = transpose, x = x, y = y, held = false, timestamp = util.time()})
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
   local shape = params:get("poly_shape")
   local scale_val = params:get("poly_scale")
   local max_a = Harvest.max_attack or 0.197
   local max_r = Harvest.max_release or 1
   local idx = shape * 3
   local attack = util.clamp(linselect(idx, {0.01, 0.01, max_a, max_a}) * scale_val, 0.01, max_a)
   local release = util.clamp(linselect(idx, {0.01, max_r, max_r, 0.01}) * scale_val, 0.01, max_r)
   return attack + release
end

-- init
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function init()
   seed(particles, density)

   clk_redraw = clock.run(redraw_event)
   clk_redraw_arc = clock.run(redraw_arc_event)
   clk_splash = clock.run(splash_event)

   params:add{
      type = "group",
      id   = "harvest",
      name = "HØST",
      n    = 31
   }

   params:add{
      type        = "option",
      id          = "focus",
      name        = "Fokus",
      options     = {"Jord", "Løv", "Lys"},
      default     = 1, 
      action      = function(x)
         prev_focus = focus
         focus = x
         if focus == 1 then
            seed(particles, density)
         elseif focus == 2 then
            seed(particles, density)
         elseif focus == 3 then
            seed(particles, density)
         end
      end
   }

   Harvest.init(false)

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
         -- retrigger active notes with new root
         for i, v in ipairs(playing) do
            local new_note = xy_to_note(v.x, v.y)
            engine.harvest_note_off(v.note + v.transpose)
            engine.harvest_note_on(new_note + v.transpose, velocity, duration)
            v.note = new_note
         end
      end
   }

   params:add{
      type        = "option",
      id          = "poly_hold",
      name        = "Hold?",
      options     = {"Nei", "Ja"},
      default     = 1,
      action      = function(x)
         if x == 1 then
            hold = false
         else
            hold = true
         end
         Harvest.poly_hold= x - 1
      end
   }

   -- per-PSET state persistence (like ncoco)
   params.action_write = function(filename, name, number)
      Storage.save_pset(number, playing, hold, Harvest.poly_loop == 1, oct, calc_cycle_len())
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

   params:set("focus", 3)

   -- 16n fader controller initialization with soft takeover
   clock.run(function()
      clock.sleep(2.0)
      _16n.init(function(msg)
         local id = _16n.cc_2_slider_id(msg.cc)
         if not id then return end

         -- fader -> param mapping
         local fader_map = {
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
            [12] = "fx_time",
            [13] = "poly_max_attack",
            [14] = "poly_max_release",
            [15] = "drone_amp",
            [16] = "poly_amp",
         }
         local p_name = fader_map[id]
         if not p_name then return end

         local p_obj = params:lookup_param(p_name)
         if not p_obj then return end

          -- normalize midi value (0-127) to 0-1
          local val_norm = util.clamp(msg.val / 127, 0, 1)
         local current_norm = params:get_raw(p_name)

         -- map through controlspec and back (ncoco pattern)
         local target_real = p_obj.controlspec:map(val_norm)
         local target_norm_check = p_obj.controlspec:unmap(target_real)
         local diff = math.abs(target_norm_check - current_norm)

         local target_val = target_real
         local current_val = params:get(p_name)

         local fader_display = p_obj:string()

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
                  current_display = string.format("%.2f s", current_val)
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
   if n == 2 and z == 1 and not k3_held then params:set("focus", 1) end
   if n == 3 and z == 1 and not k2_held then params:set("focus", 2) end
   if k2_held and k3_held then params:set("focus", 3) end
end

-- norns: encoders
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function enc(n, d)
   if n == 1 then params:delta("drone_freq", d * 0.05) end
   if n == 2 then params:delta("fx_gain"   , d) end
   if n == 3 then params:delta("poly_scale", d) end
end

-- grid: keys
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

g.key = function(x, y, z)
   if x == 1 and y == 1 then
      if z == 1 then
         if shift_held then
            -- solo si hold está ON se activa/desactiva sostenuto
            if params:get("poly_hold") == 2 then
               sostenuto = not sostenuto
            end
         elseif params:get("poly_hold") == 2 then
             -- hold ON → OFF (incluso desde sostenuto)
             params:set("poly_hold", 1)
             sostenuto = false
             stop_keys()
         else
            -- hold OFF → ON
            params:set("poly_hold", 2)
            for n = 1, #playing do
               playing[n].held = true
            end
         end
      end
   elseif x == 1 and y == 2 then
      if z == 1 then
         if params:get("poly_loop") == 2 then
            params:set("poly_loop", 1)
         else
            params:set("poly_loop", 2)
         end
      end
   elseif x == 1 and y == 8 then
      shift_held = (z == 1)
   elseif y == 8 and x == 2 and z == 1 then
      -- botón izquierdo: baja una octava (-2 → -1 → 0 → +1 → +2)
      oct = math.max(0, oct - 1)
   elseif y == 8 and x == 3 and z == 1 then
      -- botón centro: acerca al centro (0 = oct 2)
      if oct < 2 then oct = oct + 1 elseif oct > 2 then oct = oct - 1 end
   elseif y == 8 and x == 4 and z == 1 then
      -- botón derecho: sube una octava
      oct = math.min(4, oct + 1)
   else
      if y <= 7 and x >= math.max(1, 7 - y) then
         if not hold or sostenuto then play_note(x, y, z) else hold_note(x, y, z) end
      end
   end
end

-- arc: key
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

a.key = function(n, z)
   if n == 1 then
      if z == 1 then
         if focus == 3 then -- to previous
            focus = prev_focus
         else               -- to Lys
            prev_focus = focus
            focus = 3
         end
      end
      if z == 0 then
         if focus == 3 then
            focus = prev_focus
         else
            focus = 3
         end
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
end

-- norns: drawing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw()
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
            if frame % 4 == 1 then
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
      if frame % 4 == 1 then
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

   UI.draw_popup()

   s.update()
   s.ping()
end

-- grid: drawing
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw_grid()
   local background = 1
   g:all(0)

   -- background (diagonal pattern = original design, rows 1-7 only)
   if current_scale == "Chromatic" then
      for n = 6, 16 do g:led(n, 1, background) end
      for n = 5, 16 do g:led(n, 2, background) end
      for n = 4, 16 do g:led(n, 3, background) end
      for n = 3, 16 do g:led(n, 4, background) end
      for n = 2, 16 do g:led(n, 5, background) end
      for n = 1, 16 do g:led(n, 6, background) end
      for n = 1, 16 do g:led(n, 7, background) end
   else
      -- same diagonal but only light columns within scale pattern
      local steps = #scales[current_scale]
      for n = 6, 16 do if ((n - 1) % steps) + 1 <= steps then g:led(n, 1, background) end end
      for n = 5, 16 do if ((n - 1) % steps) + 1 <= steps then g:led(n, 2, background) end end
      for n = 4, 16 do if ((n - 1) % steps) + 1 <= steps then g:led(n, 3, background) end end
      for n = 3, 16 do if ((n - 1) % steps) + 1 <= steps then g:led(n, 4, background) end end
      for n = 2, 16 do if ((n - 1) % steps) + 1 <= steps then g:led(n, 5, background) end end
      for n = 1, 16 do if ((n - 1) % steps) + 1 <= steps then g:led(n, 6, background) end end
      for n = 1, 16 do if ((n - 1) % steps) + 1 <= steps then g:led(n, 7, background) end end
   end
   
   -- coll 1
   local hold_brightness = (Harvest.poly_hold == 1) and 10 or 4
   if sostenuto then
      local wave = (math.sin(frame * 0.08) + 1) / 2
      hold_brightness = 4 + math.floor(6 * wave + 0.5)
   end
   g:led(1, 1, hold_brightness)
   g:led(1, 2, 4)   -- loop off → visible but dim
   g:led(1, 3, 0)   -- unused → off
   g:led(1, 4, 0)   -- unused → off
   g:led(1, 5, 0)   -- unused → off
   g:led(1, 6, background)  -- background for playable area
   g:led(1, 7, background)  -- background for playable area
   g:led(1, 8, shift_held and 14 or 2)  -- shift button

   -- tonic notes at level 3, only within keyboard diagonal area (rows 1-7)
   for x = 2, 16 do
      for y = 1, 7 do
         if x >= math.max(1, 7 - y) then
            local n = xy_to_note(x, y)
            if (n % 12) == scale_root then
               g:led(x, y, 3)
            end
         end
      end
   end

   -- cast shadows (off/level 0) and light up held keys
   for n = 1, #playing do
      for m = 1, math.min(trail, playing[n].x - 1, g.rows - playing[n].y) do
         g:led(playing[n].x - m, playing[n].y + m, 0)
      end
   end
   for n = 1, #playing do
      g:led(playing[n].x, playing[n].y, 10)
   end

   -- pending notes blink (1↔6 fast)
   local pending_wave = (math.sin(frame * 0.20) + 1) / 2
   for _, pn in ipairs(pending_notes) do
      g:led(pn.x, pn.y, 1 + math.floor(5 * pending_wave + 0.5))
   end

   -- col 1 on
   if Harvest.poly_loop == 1 then g:led(1, 2, 10) end
   -- octave LEDs in row 8 (linear 0..4: -2,-1,0,+1,+2)
   local oct_wave = (math.sin(frame * 0.10) + 1) / 2
   local oct_led_1 = 0  -- x=2 (left)
   local oct_led_2 = 0  -- x=3 (center)
   local oct_led_3 = 0  -- x=4 (right)

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

   g:led(2, 8, oct_led_1)
   g:led(3, 8, oct_led_2)
   g:led(4, 8, oct_led_3)

   g:refresh()
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

   if focus == 3 then -- Lys
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
   Storage.save(playing, hold, Harvest.poly_loop == 1, oct, calc_cycle_len())
   stop_keys()
   if save_on_exit then params:write(norns.state.data .. "state.pset") end
end
