-- lib/env_quant.lua
-- Envelope cycle quantization to musical clock divisions ("magnets")
-- Mirrors SC LinSelectX duration math; applies corrective factor k
-- to max_attack/max_release so attack+release snaps to a division.
-- Works for loop mode (cycle period) and ASR (swell = attack+release).
-- v1.0 for h-stex

local LFOs = include("lib/lfos")

EnvQuant = {}

-- long divisions (user spec) + 16/1, 12/1 for very long drone cycles
local LONG_LABELS = {"16/1", "12/1", "8/1", "7/1", "6/1", "5/1", "4/1", "3/1", "2/1", "1.5/1", "1/1"}
local LONG_BEATS  = { 64,     48,     32,   28,   24,   20,   16,   12,   8,     6,      4}

EnvQuant.div_labels = {}
EnvQuant.div_beats  = {}
for i = 1, #LONG_LABELS do
   table.insert(EnvQuant.div_labels, LONG_LABELS[i])
   table.insert(EnvQuant.div_beats, LONG_BEATS[i])
end
-- reuse LFO divisions for everything below 1/1 (indices 4..18: 1/2. ... 1/64)
for i = 4, #LFOs.sync_divisions do
   table.insert(EnvQuant.div_labels, LFOs.sync_divisions[i])
   table.insert(EnvQuant.div_beats, LFOs.sync_beats[i])
end

-- option labels for the poly_quant param ("OFF" + all divisions)
EnvQuant.option_labels = {"OFF"}
for _, l in ipairs(EnvQuant.div_labels) do table.insert(EnvQuant.option_labels, l) end

-- state
EnvQuant.last_cycle   = 0      -- last quantized attack+release (seconds)
EnvQuant.last_div_idx = 0
EnvQuant.last_delay_div = 0    -- last delay sync division index
EnvQuant.min_cycle    = 0.02   -- hard floor: attack 0.01 + release 0.01
EnvQuant.max_cycle    = 48     -- conservative ceiling: 24s + 24s

local function linselect(idx, arr)
   local i = math.floor(idx)
   local frac = idx - i
   if i < 0 then return arr[1]
   elseif i >= #arr - 1 then return arr[#arr]
   else return arr[i + 1] * (1 - frac) + arr[i + 2] * frac end
end

-- exact replica of SC duration math (including clips)
local function calc_ar(shape, max_a, max_r, scale_val)
   local idx = shape * 3
   local a = util.clamp(linselect(idx, {0.01, 0.01, max_a, max_a}) * scale_val, 0.01, max_a)
   local r = util.clamp(linselect(idx, {0.01, max_r, max_r, 0.01}) * scale_val, 0.01, max_r)
   return a, r
end

function EnvQuant.enabled()
   local q = params:get("poly_quant")
   return q ~= nil and q == 2
end

-- nearest reachable division to d_beats (reachability in seconds)
local function nearest_division(d_beats, beat_sec)
   local best, best_err = nil, math.huge
   for i = 1, #EnvQuant.div_beats do
      local sec = EnvQuant.div_beats[i] * beat_sec
      if sec >= EnvQuant.min_cycle and sec <= EnvQuant.max_cycle then
         local err = math.abs(EnvQuant.div_beats[i] - d_beats)
         if err < best_err then
            best_err = err
            best = i
         end
      end
   end
   return best
end

-- recompute corrective factor and send to SC engine (all voices + future)
function EnvQuant.apply()
   if not EnvQuant.enabled() then return end
   local shape     = params:get("poly_shape")
   local scale_val = params:get("poly_scale")
   local max_a     = Harvest.max_attack or 0.197
   local max_r     = Harvest.max_release or 1
   local beat_sec  = clock.get_beat_sec()

   local a, r = calc_ar(shape, max_a, max_r, scale_val)
   local d_nat = a + r
   if d_nat <= 0 then return end

   local div_idx = nearest_division(d_nat / beat_sec, beat_sec)
   if not div_idx then return end  -- nothing reachable: leave as-is
   local d_q = EnvQuant.div_beats[div_idx] * beat_sec

   -- iterate k (handles clip non-linearities; converges in <=3 passes)
   local k = d_q / d_nat
   local ma, mr = max_a, max_r
   for _ = 1, 3 do
      ma = util.clamp(max_a * k, 0.001, 24)
      mr = util.clamp(max_r * k, 0.001, 24)
      local a2, r2 = calc_ar(shape, ma, mr, scale_val)
      local d2 = a2 + r2
      if d2 <= 0 or math.abs(d2 - d_q) / d_q < 0.001 then break end
      k = k * (d_q / d2)
   end

   engine.harvest_poly_set("max_attack", ma)
   engine.harvest_poly_set("max_release", mr)
   EnvQuant.last_cycle   = d_q
   EnvQuant.last_div_idx = div_idx
end

-- delay sync: map fx_time normalized value to LFO division, send beats*beat_sec to engine
function EnvQuant.apply_delay_sync()
   if params:get("delay_sync") ~= 2 then return end
   local raw = params:get_raw("fx_time")
   local div_idx = util.clamp(math.floor(raw * #LFOs.sync_divisions) + 1, 1, #LFOs.sync_divisions)
   local beats = LFOs.sync_beats[div_idx]
   local t = util.clamp(beats * clock.get_beat_sec(), 0.001, 10)
   engine.harvest_fx_set("time", t)
   EnvQuant.last_delay_div = div_idx
end

-- === Sync mode: phasor-based envelope locked to clock ===

-- Get current division in beats (0 if not set)
function EnvQuant.get_div_beats()
   if EnvQuant.last_div_idx > 0 and EnvQuant.last_div_idx <= #EnvQuant.div_beats then
      return EnvQuant.div_beats[EnvQuant.last_div_idx]
   end
   return 0
end

-- Compute phase percentage (0-1) for a note triggered at a given beat
function EnvQuant.compute_phase_pct(trigger_beat)
   local div = EnvQuant.get_div_beats()
   if div <= 0 then return 0 end
   return (trigger_beat % div) / div
end

-- Apply sync params to SC engine (called when sync mode is active)
-- Sets cycle_sec, att_frac, env_curve globally; env_sync=1
function EnvQuant.apply_sync()
   if not EnvQuant.enabled() then return end
   local shape     = params:get("poly_shape")
   local scale_val = params:get("poly_scale")
   local max_a     = Harvest.max_attack or 0.197
   local max_r     = Harvest.max_release or 1
   local beat_sec  = clock.get_beat_sec()

   -- Compute attack/release for att_frac (use natural durations, not quantized)
   local a, r = calc_ar(shape, max_a, max_r, scale_val)
   local total = a + r
   if total <= 0 then return end

   -- Find nearest division
   local div_idx = nearest_division(total / beat_sec, beat_sec)
   if not div_idx then return end
   local div_beats = EnvQuant.div_beats[div_idx]
   local cycle_sec = div_beats * beat_sec

   -- Attack fraction within cycle (from shape, not from quantized durations)
   local att_frac = util.clamp(a / total, 0.001, 0.999)

   -- Curve from shape (same LinSelectX as SC)
   local idx = shape * 3
   local env_curve = linselect(idx, {-2, -0.5, 0, 0})

   -- Send global sync params to engine
   engine.harvest_poly_set("env_sync", 1)
   engine.harvest_poly_set("cycle_sec", cycle_sec)
   engine.harvest_poly_set("att_frac", att_frac)
   engine.harvest_poly_set("env_curve", env_curve)

   -- Update state
   EnvQuant.last_cycle   = div_beats * beat_sec
   EnvQuant.last_div_idx = div_idx

   -- Re-sync all playing voices (callback set by h-stex.lua)
   if EnvQuant.on_sync_applied then EnvQuant.on_sync_applied() end
end

-- Disable sync mode (called when poly_quant is turned OFF)
function EnvQuant.disable_sync()
   engine.harvest_poly_set("env_sync", 0)
end

return EnvQuant
