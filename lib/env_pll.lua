-- lib/env_pll.lua
-- Phase-Locked Loop for envelope↔clock sync (closed-loop correction)
-- v1.1 for h-stex
--
-- Architecture: measures real envelope period via OSC feedback (/harvest_env @ 30Hz),
-- detects cycle valleys, compares against target period from EnvQuant,
-- and nudges max_release proportionally each cycle to eliminate drift.
--
-- This is the same principle as the LFO sync fix (clock.get_beats()):
--   LFO:    re-anchors phase to clock every frame (8ms)      → zero drift
--   EnvPLL: re-anchors period to clock every envelope cycle  → near-zero drift
--
-- Without this loop, the SC EnvGen runs on the audio hardware's sample clock
-- which drifts ~1% vs the system clock on real hardware (Piano Phase effect).

EnvPLL = {}

EnvPLL.active       = false     -- enabled only when poly_quant=ON + loop=ON
EnvPLL.gain         = 0.08      -- correction gain (low = smooth, no overshoot)
EnvPLL.threshold    = 0.06      -- valley detection threshold (envelope minimum)

-- per-note state
EnvPLL.notes = {}               -- [note] = {prev_val, valley_1ago, valley_2ago, ...}

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function EnvPLL.enable()
   if EnvPLL.active then return end
   EnvPLL.active = true
   EnvPLL.notes = {}
   EnvPLL.target_period = EnvQuant.last_cycle  -- seconds (from apply())
   if not EnvPLL.target_period or EnvPLL.target_period <= 0 then
      EnvPLL.target_period = 2.0  -- safe default
   end
   EnvPLL._last_correction = util.time()
   -- Save quantized baseline (not raw slider value) for PLL corrections
   EnvPLL._original_max_release = EnvQuant.last_mr_corrected or Harvest.max_release
   -- PLL's own corrected mr (accumulates corrections cycle to cycle)
   EnvPLL.corrected_mr = EnvPLL._original_max_release
   print("EnvPLL: enabled, target=" .. string.format("%.3f", EnvPLL.target_period) .. "s")
end

function EnvPLL.disable()
   if not EnvPLL.active then return end
   EnvPLL.active = false
   -- restore quantized max_release
   if EnvPLL._original_max_release then
      engine.harvest_poly_set("max_release", EnvPLL._original_max_release)
      print("EnvPLL: disabled, max_release restored to " .. string.format("%.3f", EnvPLL._original_max_release))
   end
   EnvPLL.notes = {}
   EnvPLL._original_max_release = nil
   EnvPLL.corrected_mr = nil
end

function EnvPLL.update_target(target_sec)
   if target_sec and target_sec > 0 and math.abs(target_sec - EnvPLL.target_period) > 0.001 then
      print(string.format("EnvPLL: target updated %.3fs → %.3fs", EnvPLL.target_period, target_sec))
      EnvPLL.target_period = target_sec
      -- Reset valley history (new target = new cycle structure)
      EnvPLL.notes = {}
      -- Reset corrected_mr to new quantized baseline
      EnvPLL.corrected_mr = EnvQuant.last_mr_corrected or EnvPLL.corrected_mr
      EnvPLL._original_max_release = EnvQuant.last_mr_corrected or EnvPLL._original_max_release
      EnvPLL._last_correction = util.time()
   end
end

----------------------------------------------------------------------
-- Feed: called at 30Hz from osc.event /harvest_env handler
----------------------------------------------------------------------

function EnvPLL.feed(env_val, note)
   if not EnvPLL.active then return end
   if not note then return end
   if not EnvPLL.target_period or EnvPLL.target_period <= 0 then return end

   local n = note
   if not EnvPLL.notes[n] then
      EnvPLL.notes[n] = {
         prev_val    = 0,
         valley_1ago = nil,  -- time of previous valley
         valley_2ago = nil,  -- time of valley before that
      }
   end
   local sn = EnvPLL.notes[n]

   -- Valley detection: envelope crosses threshold (prev >= threshold, current < threshold, falling)
   local crossed = sn.prev_val >= EnvPLL.threshold and env_val < EnvPLL.threshold and env_val < sn.prev_val
   sn.prev_val = env_val

   if crossed then
      local now = util.time()
      -- Shift history: 1ago → 2ago, now → 1ago
      sn.valley_2ago = sn.valley_1ago
      sn.valley_1ago = now

      -- Measure full cycle: 2 valley-to-valley intervals = 2r+a
      -- (valleys alternate r, a+r — any 2 consecutive = full cycle)
      if sn.valley_2ago then
         local period = now - sn.valley_2ago
         EnvPLL._correct(period)
      end
   end
end

----------------------------------------------------------------------
-- Internal: proportional correction
----------------------------------------------------------------------

function EnvPLL._correct(measured_period)
   if measured_period <= 0 then return end
   local target = EnvPLL.target_period
   local error = (measured_period - target) / target

   -- Ignore spurious measurements
   if measured_period < 0.05 then return end  -- too short = noise
   if math.abs(error) > 0.3 then return end   -- >30% error = glitch, skip

   -- Rate-limit: max one correction per 200ms to avoid oscillation
   local now = util.time()
   if now - EnvPLL._last_correction < 0.2 then return end
   EnvPLL._last_correction = now

   -- Use PLL's own corrected value (accumulates corrections)
   local mr = EnvPLL.corrected_mr or EnvQuant.last_mr_corrected or Harvest.max_release
   local new_mr = mr * (1 - EnvPLL.gain * error)

   -- Clamp: don't let it stray more than ±30% from original
   if EnvPLL._original_max_release and EnvPLL._original_max_release > 0 then
      local lo = EnvPLL._original_max_release * 0.7
      local hi = EnvPLL._original_max_release * 1.3
      new_mr = util.clamp(new_mr, lo, hi)
   end
   new_mr = util.clamp(new_mr, 0.001, 24)

   -- Save corrected value for next cycle (accumulates)
   EnvPLL.corrected_mr = new_mr
   -- Only send to engine — don't contaminate Harvest.max_release (raw slider)
   engine.harvest_poly_set("max_release", new_mr)

   if math.abs(error) > 0.005 then  -- only log significant corrections (>0.5%)
      print(string.format("EnvPLL: period=%.3fs error=%+.1f%% mr=%.3f→%.3f",
         measured_period, error * 100, mr, new_mr))
   end
end

return EnvPLL