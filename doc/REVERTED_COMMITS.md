# Commits Revertidos — h-stex

Este documento documenta los 3 commits que fueron revertidos de GitHub (push forzado a `e8cb062`).
Sirve como referencia para reimplementar estos cambios de forma controlada si es necesario.

**Fecha de reversión:** 2026-08-02
**Commit base actual:** `e8cb062` (feat(delay): sync de delay + modo ON/OFF para cuantización de envolvente)

---

## Commit 1: `80873f5` — feat(note): quick tap vs hold con auto note-off

**Hash completo:** `80873f5e1bc24e2946f4fd7921bd2027a9747e47`
**Fecha:** Sun Aug 2 14:09:13 2026 -0300
**Autor:** Kymatika

### Propósito
Diferenciar un quick tap (pulsación rápida) de un hold (mantener pulsado) en notas armadas con note_quant. Un quick tap dispara note_on en el boundary del reloj y luego auto note-off tras la duración. Un hold mantiene la nota activa.

### Cambios

#### `h-stex.lua` — `arm_note` (línea ~412)

**Antes:**
```lua
armed_notes[key] = {x = x, y = y}
armed_notes[key].clock_id = clock.run(function()
   clock.sleep(wait)
   armed_notes[key] = nil
   fire_armed_note(x, y)
end)
```

**Después:**
```lua
armed_notes[key] = {x = x, y = y, released = false}
armed_notes[key].clock_id = clock.run(function()
   clock.sleep(wait)
   local a = armed_notes[key]
   armed_notes[key] = nil
   if a then
      if a.released then
         -- quick tap: fire note_on with auto note_off after duration
         record_note_event(x, y, 1)
         if not hold or sostenuto then play_note(x, y, 1) else hold_note(x, y, 1) end
         clock.run(function()
            clock.sleep(duration / 1000)
            record_note_event(x, y, 0)
            if not hold or sostenuto then play_note(x, y, 0) else hold_note(x, y, 0) end
         end)
      else
         -- still held: normal fire
         fire_armed_note(x, y)
      end
   end
end)
```

#### `h-stex.lua` — `disarm_note` (línea ~424)

**Antes:**
```lua
if a then
   clock.cancel(a.clock_id)
   armed_notes[key] = nil
   return true   -- was armed: canceled, never sounded
end
```

**Después:**
```lua
if a then
   -- don't cancel: mark as released (quick tap will fire at boundary)
   a.released = true
   return true   -- was armed: will fire at boundary with auto-off
end
```

#### `lib/Harvest_engine.lua` — includes (línea ~8)

**Antes:**
```lua
local EnvQuant = include("lib/env_quant")
local LFOs = include("lib/lfos")
```

**Después:**
```lua
-- EnvQuant and LFOs are globals set by h-stex.lua includes
```

#### `lib/env_quant.lua` — global (línea ~10)

**Antes:**
```lua
local EnvQuant = {}
```

**Después:**
```lua
EnvQuant = {}
```

### Notas
- Este commit también convirtió `EnvQuant` en global (fix del bug "ENV: FREE" siempre).
- El quick tap ahora dispara en el boundary con auto note-off.

---

## Commit 2: `f0a475a` — feat(harvest): gestión de polifonía con voz robada

**Hash completo:** `f0a475a7fc03c411d4f8f9ccb11d0424db2b7d02`
**Fecha:** Sun Aug 2 15:01:13 2026 -0300
**Autor:** Kymatika

### Propósito
Implementar gestión de polifonía para evitar CPU crackling con arpegios rápidos + releases largos. Limpiar voces stale, liberar voces al exceder el límite, y añadir parámetro Max Voices.

### Cambios

#### `h-stex.lua` — grupo params (línea ~632)

**Antes:**
```lua
n    = 54
```

**Después:**
```lua
n    = 55
```

#### `h-stex.lua` — `g.key` hold toggle-off sin quant (línea ~1225)

**Antes:**
```lua
if z == 1 then
   arm_note(x, y)
```

**Después:**
```lua
if z == 1 then
   -- check if note is already playing (toggle off in hold mode = no quant)
   local already_playing = false
   for _, v in pairs(playing) do
      if v.x == x and v.y == y then already_playing = true break end
   end
   if already_playing then
      record_note_event(x, y, 1)
      if not hold or sostenuto then play_note(x, y, 1) else hold_note(x, y, 1) end
   else
      arm_note(x, y)
   end
```

#### `lib/Engine_Harvest.sc` — `fnNoteAdd` (línea ~403)

**Antes:**
```sc
harvestPolyphonyCount = harvestPolyphonyCount + 1;
harvestVoicesOn.put(note, harvestPolyphonyCount);
if (harvestVoicesOn.size > harvestPolyphonyMax, {
   // remove the oldest voice
   harvestVoicesOn.keysValuesDo({ arg key, val;
      if (val < oldestNoteVal, {
         oldestNoteVal = val;
         oldestNote = key;
      });
   });
   ("max polyphony reached, removing note "++oldestNote).postln;
   fnNoteOff.(oldestNote);
});
```

**Después:**
```sc
var staleKeys = List.new;
harvestPolyphonyCount = harvestPolyphonyCount + 1;
harvestVoicesOn.put(note, harvestPolyphonyCount);

// clean stale entries (synths freed by doneAction but not removed from dict)
harvestVoices.keysValuesDo({ arg key, synth;
   if (synth.isRunning == false, { staleKeys.add(key) })
});
staleKeys.do({ arg key;
   harvestVoices.removeAt(key);
   harvestVoicesOn.removeAt(key);
   harvestRandOffsets.removeAt(key);
});

// if total voices (active + releasing) exceed limit, free oldest immediately
if (harvestVoices.size > harvestPolyphonyMax, {
   // find oldest active voice
   harvestVoicesOn.keysValuesDo({ arg key, val;
      if (val < oldestNoteVal, { oldestNoteVal = val; oldestNote = key })
   });
   if (oldestNote > 0, {
      ("max polyphony, freeing note "++oldestNote).postln;
      harvestVoices.at(oldestNote).free;
      harvestVoicesOn.removeAt(oldestNote);
      harvestRandOffsets.removeAt(oldestNote);
      harvestVoices.removeAt(oldestNote);
   }, {
      // no active voices to free, free a releasing voice
      harvestVoices.keysValuesDo({ arg key, synth;
         if (oldestNote == 0, { oldestNote = key })
      });
      if (oldestNote > 0, {
         ("freeing releasing voice "++oldestNote).postln;
         harvestVoices.at(oldestNote).free;
         harvestVoices.removeAt(oldestNote);
      })
   })
});
```

#### `lib/Engine_Harvest.sc` — `harvest_note_on` (línea ~453)

**Antes:**
```sc
var lowestNote = 10000;
var note = msg[1];
if (harvestVoices.at(note) != nil, {
   if (harvestVoices.at(note).isRunning == true, {
      harvestVoices.at(note).set(\gate, 0);
   });
});
fnNoteOn.(msg[1], msg[2], msg[3]);
```

**Después:**
```sc
var note = msg[1];
// free existing synth for this note immediately (prevents orphan voices)
if (harvestVoices.at(note) != nil, {
   harvestVoices.at(note).free;
   harvestVoicesOn.removeAt(note);
   harvestRandOffsets.removeAt(note);
   harvestVoices.removeAt(note);
});
fnNoteOn.(msg[1], msg[2], msg[3]);
```

#### `lib/Engine_Harvest.sc` — nuevo comando `harvest_set_max_voices`

```sc
this.addCommand("harvest_set_max_voices", "i", { arg msg;
   harvestPolyphonyMax = msg[1];
   ("max voices set to " ++ harvestPolyphonyMax).postln;
});
```

#### `lib/Harvest_engine.lua` — nuevo param `poly_max_voices` (línea ~400)

```lua
params:add{
   type    = "option",
   id      = "poly_max_voices",
   name    = "Max Voices",
   options = {"6", "8", "12", "16", "24"},
   default = 3,
   action  = function(x)
      local voices = {6, 8, 12, 16, 24}
      engine.harvest_set_max_voices(voices[x])
   end
}
```

### Notas
- Este commit añadió el check `already_playing` para que el toggle-off en hold mode no se cuantice.
- El param `poly_max_voices` se añadió en la sección QUANT (después de `note_quant`).

---

## Commit 3: `efae647` — fix(harvest): liberación de notas y voces huérfanas

**Hash completo:** `efae6475cee512fc07b7039078e3affdcfdecae7`
**Fecha:** Sun Aug 2 15:27:24 2026 -0300
**Autor:** Kymatika

### Propósito
Corregir bugs introducidos por el commit anterior:
1. `play_note` marcaba TODAS las notas como held al soltar (notas congeladas).
2. `fnNoteOffPoly` fallaba si la voz ya no existía.
3. El overflow liberaba la nota activa recién tocada en lugar de releases.
4. Mover `poly_max_voices` a la sección POLY.

### Cambios

#### `h-stex.lua` — `play_note` release (línea ~370)

**Antes:**
```lua
else
   if voice == nil then
      for n = 1, #playing do
         if playing[n].held == false then
            playing[n].held = true
         end
      end
   end
end
```

**Después:**
```lua
else
   -- release: mark only the released note as held (it stays sounding)
   for n = 1, #playing do
      if playing[n].x == x and playing[n].y == y then
         playing[n].held = true
         break
      end
   end
end
```

#### `h-stex.lua` — display E3 scale (línea ~1749)

**Antes:**
```lua
-- Bottom right: E3 Env scale (+ snapped division when Env Quant active)
local scale_str = string.format("%.0f", params:get("poly_scale") * 100) .. "%"
if EnvQuant.enabled() and EnvQuant.last_div_idx > 0 then
   scale_str = scale_str .. " > " .. EnvQuant.div_labels[EnvQuant.last_div_idx]
end
```

**Después:**
```lua
-- Bottom right: E3 Env scale (always shows % only)
local scale_str = string.format("%.0f", params:get("poly_scale") * 100) .. "%"
```

#### `lib/Engine_Harvest.sc` — `fnNoteAdd` priorizar releases (línea ~404)

**Antes:**
```sc
// find oldest active voice
harvestVoicesOn.keysValuesDo({ arg key, val;
   if (val < oldestNoteVal, { oldestNoteVal = val; oldestNote = key })
});
if (oldestNote > 0, {
   ("max polyphony, freeing note "++oldestNote).postln;
   harvestVoices.at(oldestNote).free;
   harvestVoicesOn.removeAt(oldestNote);
   harvestRandOffsets.removeAt(oldestNote);
   harvestVoices.removeAt(oldestNote);
}, {
   // no active voices to free, free a releasing voice
   harvestVoices.keysValuesDo({ arg key, synth;
      if (oldestNote == 0, { oldestNote = key })
   });
   if (oldestNote > 0, {
      ("freeing releasing voice "++oldestNote).postln;
      harvestVoices.at(oldestNote).free;
      harvestVoices.removeAt(oldestNote);
   })
})
```

**Después:**
```sc
var releasingNote = 0;
var releasingVal = 10000000;
// FIRST: find oldest RELEASING voice (in harvestVoices but NOT in harvestVoicesOn)
// These are the ones that should be freed first — they're already fading out
harvestVoices.keysValuesDo({ arg key, synth;
   if (harvestVoicesOn.at(key) == nil, {
      if (key < releasingVal, { releasingVal = key; releasingNote = key })
   });
});
if (releasingNote > 0, {
   ("max polyphony, freeing releasing note "++releasingNote).postln;
   harvestVoices.at(releasingNote).free;
   harvestVoices.removeAt(releasingNote);
   harvestRandOffsets.removeAt(releasingNote);
}, {
   // no releasing voices: free oldest ACTIVE voice
   harvestVoicesOn.keysValuesDo({ arg key, val;
      if (val < oldestNoteVal, { oldestNoteVal = val; oldestNote = key })
   });
   if (oldestNote > 0, {
      ("max polyphony, freeing note "++oldestNote).postln;
      harvestVoices.at(oldestNote).free;
      harvestVoicesOn.removeAt(oldestNote);
      harvestRandOffsets.removeAt(oldestNote);
      harvestVoices.removeAt(oldestNote);
   })
})
```

#### `lib/Engine_Harvest.sc` — `fnNoteOffPoly` verificar existencia (línea ~470)

**Antes:**
```sc
// remove the sound
harvestVoices.at(note).set(\gate, 0);
```

**Después:**
```sc
// remove the sound (only if the voice still exists)
if (harvestVoices.at(note) != nil, {
   harvestVoices.at(note).set(\gate, 0);
});
```

#### `lib/Harvest_engine.lua` — mover `poly_max_voices` a POLY

**Antes (en QUANT, después de `note_quant`):**
```lua
params:add{
   type    = "option",
   id      = "poly_max_voices",
   name    = "Max Voices",
   options = {"6", "8", "12", "16", "24"},
   default = 3,
   action  = function(x)
      local voices = {6, 8, 12, 16, 24}
      engine.harvest_set_max_voices(voices[x])
   end
}
```

**Después (en POLY, después de `poly_loop`):**
```lua
params:add{
   type    = "option",
   id      = "poly_max_voices",
   name    = "Max Voices",
   options = {"6", "8", "12", "16", "24"},
   default = 3,
   action  = function(x)
      local voices = {6, 8, 12, 16, 24}
      engine.harvest_set_max_voices(voices[x])
   end
}
```

### Notas
- Este commit corrigió el bug crítico de notas congeladas (marcaba todas como held).
- También corrigió el crash SC cuando la voz ya no existía.
- El param `poly_max_voices` se movió de QUANT a POLY.

---

## Resumen de problemas detectados

| Problema | Commit que lo introdujo | Fix |
|----------|------------------------|-----|
| Notas congeladas (held=true en todas) | `f0a475a` (hold toggle-off) | `efae647` |
| Crash SC al liberar voz inexistente | `f0a475a` (free inmediato) | `efae647` |
| Overflow liberaba nota activa en vez de release | `f0a475a` | `efae647` |
| CPU alta al cambiar de script | `f0a475a` (notas congeladas) | `efae647` |
| Display E3 scale mostraba división | `e8cb062` (delay sync) | `efae647` |