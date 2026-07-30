-- lib/modbus.lua
-- Central modulation bus: sums contributions from loopers + LFOs
-- Runs at 120Hz, single params:set() per parameter per tick
-- v1.0 for h-stex

local ModBus = {}

ModBus.contributions = {}  -- [param_id] = { [source] = value }
ModBus.base_values = {}    -- [param_id] = valor_base_sin_mod
ModBus.metro = nil

function ModBus.init()
   ModBus.contributions = {}
   ModBus.base_values = {}
   ModBus.metro = metro.init()
   ModBus.metro.time = 1/120
   ModBus.metro.event = function() ModBus.apply() end
   ModBus.metro:start()
end

function ModBus.set_base(param_id, val)
   ModBus.base_values[param_id] = val
end

function ModBus.get_base(param_id)
   return ModBus.base_values[param_id]
end

function ModBus.set_contrib(source, param_id, contrib)
   if not ModBus.contributions[param_id] then
      ModBus.contributions[param_id] = {}
   end
   ModBus.contributions[param_id][source] = contrib
end

function ModBus.clear_contrib(source, param_id)
   if ModBus.contributions[param_id] then
      ModBus.contributions[param_id][source] = nil
   end
end

function ModBus.clear_source(source)
   for param_id, contribs in pairs(ModBus.contributions) do
      contribs[source] = nil
   end
end

function ModBus.clear_all()
   ModBus.contributions = {}
   ModBus.base_values = {}
end

function ModBus.get_total(param_id)
   local total = 0
   local contribs = ModBus.contributions[param_id]
   if contribs then
      for _, v in pairs(contribs) do
         total = total + v
      end
   end
   return total
end

function ModBus.apply()
   for param_id, contribs in pairs(ModBus.contributions) do
      local p = params:lookup_param(param_id)
      if p then
         local base = ModBus.base_values[param_id]
         if base == nil then base = p:get() end
         local total = 0
         local has_contrib = false
         for _, v in pairs(contribs) do
            total = total + v
            has_contrib = true
         end
         if has_contrib and math.abs(total) > 0.0001 then
            local target = util.clamp(base + total, p.controlspec.minval, p.controlspec.maxval)
            params:set(param_id, target)
         end
      end
   end
end

function ModBus.cleanup()
   if ModBus.metro then ModBus.metro:stop() end
   ModBus.contributions = {}
   ModBus.base_values = {}
end

return ModBus