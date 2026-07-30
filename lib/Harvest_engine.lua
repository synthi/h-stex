-- Harvest_engine
-- a part of Høst
--
-- v1.6- Joaue Arias
-- v1.5 imminent gloom

local Harvest = {}

-- adds a list of params
-- @bool midicontrol If false, don't build and set-up midi params
function Harvest.init(midicontrol)

-- main
   params:add{
      type        = "control",
      id          = "fx_amp",
      name        = "Volume",
      controlspec = controlspec.new(0, 2, "lin", 0.001, 0.5),
      action      = function(x)
         engine.harvest_fx_set("amp", x)
         -- Harvest.fx_amp = x * 0.5
      end
   }

-- drone
   params:add_separator("drone", "DRONE")

   params:add{
      type        = "control",
      id          = "drone_amp",
      name        = "Volume",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.8),
      action      = function(x)
         engine.harvest_drone_set("amp", x)
			-- Harvest.drone_amp = x
      end
   }

   params:add{
      type        = "control",
      id          = "drone_timbre",
      name        = "Timbre",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.5),
      action      = function(x)
         engine.harvest_drone_set("timbre", x)
			Harvest.drone_timbre = x
      end
   }

   params:add{
      type        = "control",
      id          = "drone_noise",
      name        = "Noise",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.0),
      action      = function(x)
         engine.harvest_drone_set("noise", x)
			Harvest.drone_noise = x
      end
   }

    params:add{
       type        = "control",
       id          = "drone_bias",
       name        = "Bias",
       controlspec = controlspec.new(-1, 1, "lin", 0.001, 0),
       action      = function(x)
          engine.harvest_drone_set("bias", x)
          Harvest.drone_bias = x
       end
    }

   params:add{
      type        = "control",
      id          = "drone_drift",
      name        = "Drift",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.11),
      action      = function(x)
         engine.harvest_drone_set("drift", x)
         Harvest.drone_drift = x
      end
   }

    params:add{
       type        = "control",
       id          = "drone_freq",
       name        = "Frequency",
       controlspec = controlspec.new(0.2, 2000, "exp", 0.001, 117, "hz"),
       action      = function(x)
          engine.harvest_drone_set("freq", x)
          Harvest.drone_freq = math.log(x / 0.2) / math.log(2000 / 0.2)
       end
    }

    params:add{
       type        = "control",
       id          = "drone_pan",
       name        = "Pan",
       controlspec = controlspec.new(-1, 1, "lin", 0.001, 0),
       action      = function(x)
          engine.harvest_drone_set("pan", x)
          Harvest.drone_pan = x
       end
    }
    
-- poly
   params:add_separator("poly", "POLY")
   
   params:add{
      type        = "control",
      id          = "poly_amp",
      name        = "Volume",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.8),
      action      = function(x)
         engine.harvest_poly_set("amp", x)
			-- Harvest.poly_amp = x
      end
   }

   params:add{
      type        = "control",
      id          = "poly_timbre",
      name        = "Timbre",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.2),
      action      = function(x)
         engine.harvest_poly_set("timbre", x)
			   Harvest.poly_timbre = x
      end
   }

   params:add{
      type        = "control",
      id          = "poly_noise",
      name        = "Noise",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.3),
      action      = function(x)
         engine.harvest_poly_set("noise", x)
			   Harvest.poly_noise = x
      end
   }

    params:add{
       type        = "control",
       id          = "poly_bias",
       name        = "Bias",
       controlspec = controlspec.new(-1, 1, "lin", 0.001, 0),
       action      = function(x)
          engine.harvest_poly_set("bias", x)
          Harvest.poly_bias = x
       end
    }

   params:add{
      type        = "control",
      id          = "poly_shape",
      name        = "Contour",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.1),
      action      = function(x)
         engine.harvest_poly_set("shape", x)
			   Harvest.poly_shape = x
      end
   }

    params:add{
       type        = "control",
       id          = "poly_spread",
       name        = "Spread",
       controlspec = controlspec.new(-1, 1, "lin", 0.001, 0),
       action      = function(x)
          engine.harvest_poly_set("spread", x)
          Harvest.poly_spread = x
       end
    }

-- fx
   params:add_separator("fx_filter_delay", "FX")
   
   params:add{
      type        = "control",
      id          = "fx_peak_1",
      name        = "Peak 1",
      controlspec = controlspec.new(20, 20000, "exp", 0.001, 115, "hz"),
      action      = function(x)
         engine.harvest_fx_set("peak1", x)
         Harvest.fx_peak_1 = math.log(x / 20) / math.log(20000 / 20)
      end
   }
   
   params:add{
      type        = "control",
      id          = "fx_peak_2",
      name        = "Peak 2",
      controlspec = controlspec.new(20, 20000, "exp", 0.001, 218, "hz"),
      action      = function(x)
         engine.harvest_fx_set("peak2", x)
         Harvest.fx_peak_2 = math.log(x / 20) / math.log(20000 / 20)
      end
   }

   params:add{
      type        = "control",
      id          = "fx_body",
      name        = "Body",
      controlspec = controlspec.new(0 - 0.001, 1 + 0.001, "lin", 0.001, 0),
      action      = function(x)
         if x < 0 then params:set("fx_body", 1) end
         if x > 1 then params:set("fx_body", 0) end
         engine.harvest_fx_set("body", x)
         Harvest.fx_body = x
      end
   }

   params:add{
      type        = "control",
      id          = "fx_time",
      name        = "Time",
      controlspec = controlspec.new(0.01, 2, "lin", 0.001, 1, "s"),
      action      = function(x)
         engine.harvest_fx_set("time", x)
			   Harvest.fx_time = (x - 0.01) / 1.99
      end
   }

   params:add{
      type        = "control",
      id          = "fx_res",
      name        = "Resonance",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.5),
      formatter   = function(x)
         return math.floor(x:get() * 100) .. " %"
      end,
      action      = function(x)
         engine.harvest_fx_set("res_max", x)
			-- Harvest.fx_res = x
      end
   }

   params:add{
      type        = "control",
      id          = "fx_fb",
      name        = "Feedback",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 1),
      formatter   = function(x)
         return math.floor(x:get() * 100) .. " %"
      end,
      action      = function(x)
         engine.harvest_fx_set("fb_max", x)
			-- Harvest.fx_fb = x
      end
   }

   params:add_separator("fx_distortion", "DISTORTION")

   params:add{
      type        = "control",
      id          = "fx_gain",
      name        = "Gain",
      controlspec = controlspec.new(0.5, 16, "lin", 0.001, 0.5),
      action      = function(x)
         engine.harvest_fx_set("gain", x)
			-- Harvest.fx_gain = x
      end
   }

-- noter
   params:add_separator("poly_noter", "ENVELOPE")

   local function sigmoid_map(val)
      local k = 12
      local c = 0.93
      local sig = function(v) return 1 / (1 + math.exp(-k * (v - c))) end
      local s0 = sig(0)
      local s1 = sig(1)
      local sn = (sig(val) - s0) / (s1 - s0)
      return 0.001 + (24 - 0.001) * sn
   end

   params:add{
      type        = "control",
      id          = "poly_max_attack",
      name        = "Attack",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.5),
      action      = function(x)
         local val = sigmoid_map(x)
         engine.harvest_poly_set("max_attack", val)
         Harvest.max_attack = val
      end
   }

   params:add{
      type        = "control",
      id          = "poly_max_release",
      name        = "Decay",
      controlspec = controlspec.new(0, 1, "lin", 0.001, 0.7),
      action      = function(x)
         local val = sigmoid_map(x)
         engine.harvest_poly_set("max_release", val)
         Harvest.max_release = val
      end
   }
   
   params:add{
      type        = "control",
      id          = "poly_scale",
      name        = "Scale",
      controlspec = controlspec.new(0.01, 1, "lin", 0.01, 1),
      formatter   = function(x)
         return math.floor(x:get() * 100) .. " %"
      end,
      action      = function(x)
         engine.harvest_poly_set("scale", x)
			-- Harvest.poly_scale = x
      end
   }

    params:add{
       type        = "control",
       id          = "poly_drift",
       name        = "Drift",
       controlspec = controlspec.new(0, 1, "lin", 0.001, 0.15),
       action      = function(x)
          engine.harvest_poly_set("drift", x)
          Harvest.poly_drift = x
       end
    }

    params:add{
       type        = "option",
       id          = "poly_loop",
       name        = "Loop?",
       options     = {"No", "Yes"},
       default     = 1,
       action      = function(x)
          engine.harvest_poly_set("loop", x - 1)
          Harvest.poly_loop = x - 1
       end
    }

-- looper
   params:add_separator("looper", "LOOPERS")

   params:add{
      type        = "option",
      id          = "looper_default_mode",
      name        = "Looper Mode",
      options     = {"Play", "Overdub"},
      default     = 2,
   }

-- midi
   if not midicontrol then
      return
   end
   params:add_separator("midi_sep", "midi")
   local mididevice = {}
   local mididevice_list = {"none"}
   midi_channels = {"all"}
   for i = 1, 16 do
      table.insert(midi_channels,i)
   end
   for _,dev in pairs(midi.devices) do
      if dev.port ~= nil then
         local name = string.lower(dev.name)
         table.insert(mididevice_list,name)
         print("adding " .. name .. " to port " ..dev.port)
         mididevice[name] = {
            name = name,
            port = dev.port,
            midi = midi.connect(dev.port),
            active = false,
         }
         mididevice[name].midi.event = function(data)
            if mididevice[name].active == false then
               return
            end
            local d = midi.to_msg(data)
            if d.ch ~= midi_channels[params:get("midichannel")]
               and params:get("midichannel") > 1 then
               return
            end
            if d.type == "note_on" then
               local amp = util.linexp(1, 127, 0.01, 1.0, d.vel)
               engine.harvest_note_on(d.note, amp, 600)
            elseif d.type == "note_off" then
               engine.harvest_note_off(d.note)
            elseif d.cc == 64 then -- sustain pedal
               local val = d.val > 126 and 1 or 0
               if params:get("pedal_mode") == 1 then
                     engine.harvest_sustain(val)
               else
                     engine.harvest_sostenuto(val)
               end
            end
         end
      end
   end
   tab.print(mididevice_list)

   params:add{
      type    = "option",
      id      = "pedal_mode",
      name    = "pedal mode",
      options = {"sustain", "sostenuto"},
      default = 1,
   }

   params:add{
      type    = "option",
      id      = "midi",
      name    = "midi in",
      options = mididevice_list,
      default = 1,
      action  = function(v)
         if v == 1 then return end
         for _, dev in pairs(mididevice) do
            dev.active = false
         end
         mididevice[mididevice_list[v]].active = true
      end
   }

   params:add{
      type    = "option",
      id      = "midichannel",
      name    = "midi ch",
      options = midi_channels,
      default = 1
   }

   if #mididevice_list > 1 then
      params:set("midi", 2)
   end
end

-- Note on function
-- @int note Midi note number
-- @number vel Velocity (0.0-1.0)
-- @number time Gate time (optional)
function Harvest.note_on(note, vel, time)
   if not time then time = 600 end
   engine.harvest_note_on(note, vel, time)
end

-- Note off function
-- @int note Midi note number
function Harvest.note_off(note)
   engine.harvest_note_off(note)
end

return Harvest