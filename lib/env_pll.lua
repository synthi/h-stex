-- lib/env_pll.lua
-- Phase-Locked Loop for envelope↔clock sync (closed-loop correction)
-- v1.3 for h-stex
--
-- v1.3: AR loop (1 valley/cycle), dead zone 0.1%, jitter reduction (3-sample avg), 2-decimal telemetry
-- v1.2: Rich telemetry, SC per-valley support, gain 0.3, no valley reset on target change
-- v1.1: 2-valley measurement, corrected_mr accumulation, glitch guard
-- v1.0: Initial PLL with valley detection from 30Hz OSC feed

EnvPLL = {}

EnvPLL.active       = false
EnvPLL.gain         = 0.3       -- correction gain
EnvPLL.threshold    = 0.06      -- valley detection threshold
EnvPLL.dead_zone    = 0.001     -- don't correct if |error| < 0.1%

-- per-note state
EnvPLL.notes = {}

-- telemetry state
EnvPLL._osc_count = 0
EnvPLL._last_osc_time = 0
EnvPLL._last_valley_time = 0
EnvPLL._sc_valley_mode = false

-- jitter reduction: rolling average of last 3 period measurements
EnvPLL._period_history = {}  -- {last 3 measured periods}
EnvPLL._period_avg = nil     -- averaged period

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function EnvPLL.enable()
   if EnvPLL.active then return end
   EnvPLL.active = true
   EnvPLL.notes = {}
   EnvPLL._osc_count = 0
   EnvPLL._sc_valley_mode = false
   EnvPLL._period_history = {}
   EnvPLL._period_avg = nil
   EnvPLL.target_period = EnvQuant.last_cycle
   if not EnvPLL.target_period or EnvPLL.target_period <= 0 then
      EnvPLL.target_period = 2.0
   end
   EnvPLL._last_correction = util.time()
   EnvPLL._last_osc_time = util.time()
   EnvPLL._last_valley_time = util.time()
   EnvPLL._original_max_release = EnvQuant.last_mr_corrected or Harvest.max_release
   EnvPLL.corrected_mr = EnvPLL._original_max_release
   print(string.format("EnvPLL: enabled t=%.3f target=%.3fs mr_baseline=%.4f",
      util.time(), EnvPLL.target_period, EnvPLL._original_max_release))
end

function EnvPLL.disable()
   if not EnvPLL.active then return end
   EnvPLL.active = false
   if EnvPLL._original_max_release then
      engine.harvest_poly_set("max_release", EnvPLL._original_max_release)
      print(string.format("EnvPLL: disabled t=%.3f restored mr=%.4f",
         util.time(), EnvPLL._original_max_release))
   end
   EnvPLL.notes = {}
   EnvPLL._original_max_release = nil
   EnvPLL.corrected_mr = nil
   EnvPLL._period_history = {}
   EnvPLL._period_avg = nil
end

function EnvPLL.update_target(target_sec)
   if target_sec and target_sec > 0 and math.abs(target_sec - EnvPLL.target_period) > 0.001 then
      local old = EnvPLL.target_period
      EnvPLL.target_period = target_sec
      -- DON'T reset valley history — just reset baseline and rate limiter
      EnvPLL.corrected_mr = EnvQuant.last_mr_corrected or EnvPLL.corrected_mr
      EnvPLL._original_max_release = EnvQuant.last_mr_corrected or EnvPLL._original_max_release
      EnvPLL._last_correction = util.time()
      -- Reset jitter history (new target = new cycle structure)
      EnvPLL._period_history = {}
      EnvPLL._period_avg = nil
      print(string.format("EnvPLL: target t=%.3f %.3fs→%.3fs mr_baseline=%.4f",
         util.time(), old, target_sec, EnvPLL.corrected_mr))
   end
end

----------------------------------------------------------------------
-- Feed: called at 30Hz from osc.event /harvest_env handler
-- Used for grid LED sync + fallback valley detection (if SC doesn't send /harvest_valley)
----------------------------------------------------------------------

function EnvPLL.feed(env_val, note)
   if not EnvPLL.active then return end
   if not note then return end

   local now = util.time()
   EnvPLL._osc_count = EnvPLL._osc_count + 1
   EnvPLL._last_osc_time = now

   -- Watchdog: every ~1s (30 messages at 30Hz), check for stale feed
   if EnvPLL._osc_count % 30 == 0 then
      local since_valley = now - EnvPLL._last_valley_time
      if since_valley > 3 then
         print(string.format("EnvPLL: watchdog t=%.3f no_valley=%.1fs osc_count=%d",
            now, since_valley, EnvPLL._osc_count))
      end
   end

   -- If SC sends /harvest_valley, skip valley detection here (precise mode)
   if EnvPLL._sc_valley_mode then return end

   if not EnvPLL.target_period or EnvPLL.target_period <= 0 then return end

   local n = note
   if not EnvPLL.notes[n] then
      EnvPLL.notes[n] = {
         prev_val    = 0,
         valley_1ago = nil,
         valley_count = 0,
      }
   end
   local sn = EnvPLL.notes[n]

   -- Valley detection: envelope crosses threshold (prev >= threshold, current < threshold, falling)
   local prev = sn.prev_val
   local crossed = prev >= EnvPLL.threshold and env_val < EnvPLL.threshold and env_val < prev
   sn.prev_val = env_val

   if crossed then
      EnvPLL._process_valley(n, now, env_val, prev)
   end
end

----------------------------------------------------------------------
-- Feed valley: called from /harvest_valley OSC handler (SC per-valley)
-- SC detected the valley — we just measure and correct with exact timing
----------------------------------------------------------------------

function EnvPLL.feed_valley(env_val, note)
   if not EnvPLL.active then return end
   if not note then return end

   local now = util.time()
   EnvPLL._sc_valley_mode = true

   local n = note
   if not EnvPLL.notes[n] then
      EnvPLL.notes[n] = {
         prev_val    = 0,
         valley_1ago = nil,
         valley_count = 0,
      }
   end
   local sn = EnvPLL.notes[n]

   EnvPLL._process_valley(n, now, env_val, nil)
end

----------------------------------------------------------------------
-- Internal: process a detected valley (shared by feed() and feed_valley())
----------------------------------------------------------------------

function EnvPLL._process_valley(note, now, env_val, prev_val)
   local sn = EnvPLL.notes[note]
   if not sn then return end

   sn.valley_count = (sn.valley_count or 0) + 1
   EnvPLL._last_valley_time = now

   -- Measure 1 interval: now - valley_1ago (AR loop = 1 valley per cycle)
   local period = nil
   if sn.valley_1ago then
      period = now - sn.valley_1ago
   end
   sn.valley_1ago = now

   -- Log every valley with full debug info
   if env_val then
      print(string.format("EnvPLL: valley t=%.3f note=%d env=%.4f prev=%.4f thresh=%.2f v#=%d",
         now, note, env_val, prev_val or 0, EnvPLL.threshold, sn.valley_count))
   else
      print(string.format("EnvPLL: valley t=%.3f note=%d v#=%d (SC)",
         now, note, sn.valley_count))
   end

   -- Correct if we have a valid period
   if period and period > 0 then
      EnvPLL._correct(period)
   end
end

----------------------------------------------------------------------
-- Internal: proportional correction with jitter reduction and dead zone
----------------------------------------------------------------------

function EnvPLL._correct(measured_period)
   if measured_period <= 0 then return end
   local target = EnvPLL.target_period
   local now = util.time()

   -- Ignore spurious measurements
   if measured_period < 0.05 then
      print(string.format("EnvPLL: skip t=%.3f period=%.3f reason=too_short", now, measured_period))
      return
   end

   -- Jitter reduction: rolling average of last 3 measurements
   table.insert(EnvPLL._period_history, measured_period)
   if #EnvPLL._period_history > 3 then
      table.remove(EnvPLL._period_history, 1)
   end
   local sum = 0
   for _, v in ipairs(EnvPLL._period_history) do sum = sum + v end
   local avg_period = sum / #EnvPLL._period_history

   local error = (avg_period - target) / target

   -- Glitch guard: skip if error > 30%
   if math.abs(error) > 0.3 then
      print(string.format("EnvPLL: skip t=%.3f avg=%.3f target=%.3f error=%+.2f%% reason=glitch_guard",
         now, avg_period, target, error * 100))
      return
   end

   -- Dead zone: don't correct if |error| < 0.1%
   if math.abs(error) < EnvPLL.dead_zone then
      -- Still log for telemetry
      print(string.format("EnvPLL: stable t=%.3f avg=%.3f target=%.3f error=%+.2f%% mr=%.4f",
         now, avg_period, target, error * 100, EnvPLL.corrected_mr or 0))
      return
   end

   -- Rate-limit: max one correction per 200ms
   local since_last = now - EnvPLL._last_correction
   if since_last < 0.2 then
      print(string.format("EnvPLL: skip t=%.3f reason=rate_limit last=%.0fms ago",
         now, since_last * 1000))
      return
   end
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
   -- Only send to engine — don't contaminate Harvest.max_release
   engine.harvest_poly_set("max_release", new_mr)

   print(string.format("EnvPLL: correct t=%.3f avg=%.3f target=%.3f error=%+.2f%% mr=%.4f→%.4f accum=%.4f",
      now, avg_period, target, error * 100, mr, new_mr, EnvPLL.corrected_mr))
end

return EnvPLL