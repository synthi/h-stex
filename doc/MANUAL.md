# HØST — Manual de Uso

**Versión:** 1.5  
**Autor:** Joaue Arias (basado en støy by inminetglow)  
**Plataforma:** norns (compatible Pi 4B)  
**Hardware:** Grid 16×8, 16n faders (MIDI), norns keys/encoders

---

## 1. Descripción General

Høst es un sintetizador para norns inspirado en el módulo **Just Friends** (Mannequins). Emula su comportamiento de auto-modulación, morphing de formas de onda, inyección de ruido y lógica de threshold analógica.

El motor de sonido tiene 3 componentes principales:

| Componente | Nombre | Descripción |
|------------|--------|-------------|
| **Jord** (Tierra) | Drone | Oscilador continuo con morphing saw→sine→square, ruido, threshold |
| **Løv** (Hoja) | Poly-synth | Polifonía de 12 voces, misma arquitectura que el drone + envolvente |
| **Lys** (Luz) | FX | 2 filtros SVF bandpass + delay con feedback + distorsión tanh |

Flujo de señal: `Drone + Voces Poly → Bus interno → FX (filtros → delay → distorsión) → Salida`

---

## 2. Los 3 Fokus (Modos)

El script tiene 3 modos llamados **Fokus**. Cada modo expone 4 parámetros diferentes.

| Fokus | Nombre | Significado | Parámetros |
|-------|--------|-------------|------------|
| 1 | **Jord** | Tierra (Drone) | Timbre, Noise, Bias, Frecuencia |
| 2 | **Løv** | Hoja (Poly) | Timbre, Noise, Bias, Shape |
| 3 | **Lys** | Luz (FX) | Peak 1, Peak 2, Body, Time |

Al iniciar el script, el Fokus default es **Lys (3)**.

---

## 3. Controles del Grid (16×8)

### Columna 1 — Control

| Posición | Función |
|----------|---------|
| (1,1) | **Hold** — Toggle mantener notas (Nei/Ja). Shift+Hold = Sostenuto |
| (1,2) | **Loop** — Toggle repetición de envolvente (Nei/Ja) |
| (1,3) | Sin función (apagado) |
| (1,4) | Sin función (apagado) |
| (1,5) | Sin función (apagado) |
| (1,6) | Zona playable (background) |
| (1,7) | Zona playable (background) |
| (1,8) | **Shift** — Botón momentáneo (brillo 2 reposo, 14 pulsado) |

### Fila 8 — Octavas y Shift

| Posición | Función |
|----------|---------|
| (1,8) | **Shift** — Botón momentáneo |
| (2,8) | **Octava -** — 1er tap: -1 oct (LED 5), 2º tap: -2 oct (LED parpadea 6↔2), 3er tap: vuelve a 0 |
| (3,8) | **Octava 0** — Siempre vuelve a octava base (LED 5 fijo) |
| (4,8) | **Octava +** — 1er tap: +1 oct (LED 5), 2º tap: +2 oct (LED parpadea 6↔2), 3er tap: vuelve a 0 |
| (5-16,8) | Sin función (apagado) |

### Columnas 2-16 — Teclado (filas 1-7)

El grid funciona como un teclado musical:

- **Eje X (columnas):** Avanza por las notas de la escala seleccionada
- **Eje Y (filas):** Cada fila hacia arriba equivale a una "quinta" (4 pasos de escala)
- **Nota base:** Do (MIDI 12 + tónica de escala)
- **Fila 8:** Libre (no forma parte del teclado)

**Con escala Chromatic (default):** 12 columnas por octava, comportamiento original.

**Con otras escalas:** El grid se re-mapea automáticamente. Solo existen las notas de la escala seleccionada. Las columnas que no pertenecen a la escala no se iluminan ni responden al tacto.

### Visualización en el Grid

| Elemento | Nivel LED | Descripción |
|----------|-----------|-------------|
| Fondo de teclas activas | 1 | Patrón diagonal original (escalonado, filas 1-7) |
| Tónica de la escala | 3 | Nota raíz de la escala |
| Nota pulsada | 10 | Nota que está sonando actualmente (sobrescribe a la tónica) |
| Sombra proyectada | 0 | Apagada (marca la dirección de las notas activas) |
| Columna 1 — apagado | 4 | Botones de control en estado off |
| Columna 1 — activo | 5/10 | Estado de hold, loop, octava |
| Shift (1,8) reposo | 2 | Brillo tenue cuando no está pulsado |
| Shift (1,8) pulsado | 14 | Brillo alto momentáneo |
| Octava activa (2-4,8) | 5 | Octava seleccionada en fila 8 |
| Hold con Sostenuto | 1→10 | Parpadeo suave entre nivel 1 y nivel base |
| Octava extendida | 2↔6 | Parpadeo medio en -2/+2 octavas |

---

## 4. Controles en Norns

### Teclas físicas (K1, K2, K3)

| Combinación | Acción |
|-------------|--------|
| K2 | Seleccionar Fokus 1 (Jord) |
| K3 | Seleccionar Fokus 2 (Løv) |
| K2 + K3 | Seleccionar Fokus 3 (Lys) |

### Encoders físicos (E1, E2, E3)

| Encoder | Parámetro | Traducción | Descripción |
|---------|-----------|------------|-------------|
| E1 | `drone_freq` | Frecuencia (drone) | Ajuste fino de la frecuencia base del drone |
| E2 | `fx_gain` | Fuerza (distorsión) | Ganancia de distorsión (tanh) |
| E3 | `poly_scale` | Escala de envolvente | Escala global de la envolvente (1–100%) |

---

## 5. Parámetros del Menú (PARAMS)

### Traducciones de Parámetros (Sueco → Español)

| Sueco | Pronunciación | Español | Descripción |
|-------|--------------|---------|-------------|
| Volum | vó-lum | Volumen | Nivel de audio |
| Klangfarge | klang-far-ge | Timbre | Morfología de onda (saw→sine→square) |
| Støy | stoy | Ruido | Cantidad de ruido inyectado |
| Terskel | tersh-el | Umbral/Threshold | Lógica de comparación analógica |
| Frekvens | frek-vens | Frecuencia | Frecuencia del oscilador |
| Kontur | kon-tur | Contorno | Forma de la envolvente |
| Første | fersh-te | Primero | 1er filtro bandpass |
| Andre | an-dre | Segundo | 2º filtro bandpass |
| Kropp | krop | Cuerpo | Morph entre dry, filtros y delay |
| Tid | tid | Tiempo | Tiempo de delay |
| Resonans | re-so-nans | Resonancia | Resonancia de filtros |
| Ekko | ek-o | Eco | Feedback del delay |
| Styrke | styr-ke | Fuerza | Ganancia de distorsión |
| Vekst | vekst | Crecimiento | Tiempo máximo de ataque |
| Forfall | for-fal | Decaimiento | Tiempo máximo de release |
| Skala | ska-la | Escala | Escala global de envolvente |
| Repeter? | re-pe-ter | ¿Repetir? | Loop de envolvente |
| Nei/Ja | nei/ya | No/Sí | Off/On |
| Jord | yord | Tierra | Modo drone |
| Løv | lov | Hoja | Modo poly-synth |
| Lys | lis | Luz | Modo FX |
| Fokus | fo-kus | Foco/Mode | Selector de modo |

### Grupo HØST

#### JORD (Tierra — Drone)

| Parámetro (sueco) | Traducción | ID | Rango | Default | Descripción |
|-------------------|------------|-----|-------|---------|-------------|
| Volum | Volumen | `drone_amp` | 0–1 | 0.8 | Volumen del drone |
| Klangfarge | Timbre | `drone_timbre` | 0–1 | 0.5 | Morphing saw→sine→square |
| Støy | Ruido | `drone_noise` | 0–1 | 0.0 | Inyección de ruido (white→pink) |
| Terskel | Umbral | `drone_bias` | 0–1 | 0.0 | Threshold de lógica analógica |
| Frekvens | Frecuencia | `drone_freq` | 0.2–2000 Hz | 117 Hz | Frecuencia base del drone |

#### LØV (Hoja — Poly)

| Parámetro (sueco) | Traducción | ID | Rango | Default | Descripción |
|-------------------|------------|-----|-------|---------|-------------|
| Volum | Volumen | `poly_amp` | 0–1 | 0.8 | Volumen del poly |
| Klangfarge | Timbre | `poly_timbre` | 0–1 | 0.2 | Morphing saw→sine→square |
| Støy | Ruido | `poly_noise` | 0–1 | 0.3 | Inyección de ruido |
| Terskel | Umbral | `poly_bias` | 0–1 | 0.6 | Threshold de lógica analógica |
| Kontur | Contorno | `poly_shape` | 0–1 | 0.1 | Forma de envolvente (0=perc, 0.5=pad, 1=swell) |

#### LYS (Luz — FX)

| Parámetro (sueco) | Traducción | ID | Rango | Default | Descripción |
|-------------------|------------|-----|-------|---------|-------------|
| Første | Primero | `fx_peak_1` | 20–20000 Hz | 115 Hz | Frecuencia del 1er filtro bandpass |
| Andre | Segundo | `fx_peak_2` | 20–20000 Hz | 218 Hz | Frecuencia del 2º filtro bandpass |
| Kropp | Cuerpo | `fx_body` | 0–1 | 0.0 | Morph: dry→filter→filter+delay→dry+delay→dry |
| Tid | Tiempo | `fx_time` | 0.01–2 s | 1 s | Tiempo del delay |
| Resonans | Resonancia | `fx_res` | 0–100% | 50% | Resonancia de los filtros |
| Ekko | Eco | `fx_fb` | 0–100% | 100% | Feedback del delay |

#### FORVITRING (Distorsión)

| Parámetro (sueco) | Traducción | ID | Rango | Default | Descripción |
|-------------------|------------|-----|-------|---------|-------------|
| Styrke | Fuerza | `fx_gain` | 0.5–16 | 0.5 | Ganancia de distorsión (tanh) |

#### NOTER (Notas)

| Parámetro (sueco) | Traducción | ID | Rango | Default | Descripción |
|-------------------|------------|-----|-------|---------|-------------|
| Vekst | Crecimiento | `poly_max_attack` | 0.001–24 s | ~2 s | Tiempo máximo de ataque (curva sigmoid) |
| Forfall | Decaimiento | `poly_max_release` | 0.001–24 s | ~3 s | Tiempo máximo de release (curva sigmoid) |
| Skala | Escala | `poly_scale` | 1–100% | 100% | Escala global de la envolvente |
| Repeter? | ¿Repetir? | `poly_loop` | Nei/Ja | Nei | Loop de envolvente (ararar) |

#### Scale (Escala Musical)

| Parámetro | ID | Opciones | Default |
|-----------|-----|----------|---------|
| Scale | `scale` | 21 escalas (ver abajo) | Chromatic |

#### Root Note

| Parámetro | ID | Opciones | Default |
|-----------|-----|----------|---------|
| Root Note | `root_note` | C, C#, D, D#, E, F, F#, G, G#, A, A#, B | C |

**Escalas disponibles:**

| # | Nombre | Notas/octava |
|---|--------|:------------:|
| 1 | Chromatic | 12 |
| 2 | Major | 7 |
| 3 | Natural Minor | 7 |
| 4 | Harmonic Minor | 7 |
| 5 | Dorian | 7 |
| 6 | Phrygian | 7 |
| 7 | Lydian | 7 |
| 8 | Mixolydian | 7 |
| 9 | Major Pentatonic | 5 |
| 10 | Minor Pentatonic | 5 |
| 11 | In Sen | 5 |
| 12 | Hirajoshi | 5 |
| 13 | Iwato | 5 |
| 14 | Kumoi | 5 |
| 15 | Yo | 5 |
| 16 | Hijaz | 7 |
| 17 | Todi | 7 |
| 18 | Marwa | 7 |
| 19 | Purvi | 7 |
| 20 | Saba | 7 |
| 21 | Nawa Athar | 7 |

---

## 6. MIDI

El script soporta entrada MIDI para control externo (teclados, controladores, 16n faders).

### Configuración

1. Conecta el dispositivo MIDI por USB
2. En el menú PARAMS, ve a la sección MIDI
3. Selecciona el dispositivo en `midi in`
4. Selecciona el canal MIDI en `midi ch`

### Mapeo MIDI

| Mensaje | Acción |
|---------|--------|
| Note On | Dispara nota poly |
| Note Off | Apaga nota poly |
| CC 64 (Sustain) | Sustain/Sostenuto pedal |

### 16n Faders (nativo)

El script detecta automáticamente el 16n por USB y lo configura con soft takeover.

#### Soft Takeover

Cada fader tiene protección soft takeover: si el valor del fader no coincide con el valor actual del parámetro, se muestra un popup en pantalla indicando `* NOMBRE: fader → actual` hasta que iguales la posición. Una vez sincronizado, el fader toma control y muestra el nombre y valor actual.

#### Mapeo de Faders

| Fader | Parámetro | Nombre |
|-------|-----------|--------|
| 1 | `drone_timbre` | Klangfarge (Drone) |
| 2 | `drone_noise` | Støy (Drone) |
| 3 | `drone_bias` | Terskel (Drone) |
| 4 | `drone_freq` | Frekvens (Drone) |
| 5 | `poly_timbre` | Klangfarge (Poly) |
| 6 | `poly_noise` | Støy (Poly) |
| 7 | `poly_bias` | Terskel (Poly) |
| 8 | `poly_shape` | Kontur |
| 9 | `fx_peak_1` | Første |
| 10 | `fx_peak_2` | Andre |
| 11 | `fx_body` | Kropp |
| 12 | `fx_time` | Tid |
| 13 | `poly_max_attack` | Vekst |
| 14 | `poly_max_release` | Forfall |
| 15 | `drone_amp` | Volum (Drone) |
| 16 | `poly_amp` | Volum (Poly) |

---

## 7. Especificaciones Técnicas

### Motor de Audio (SuperCollider)

- **Polifonía:** 12 voces simultáneas
- **Prioridad:** Low-note priority (la nota más grave tiene prioridad para sub-oscillator)
- **Drone:** 1 voz continua
- **FX:** 2 SVF bandpass en paralelo → delay con feedback (LPF interno) → distorsión tanh
- **Frecuencia de muestreo:** La del sistema (44.1 kHz o 48 kHz)

### Arquitectura del SynthDef `\harvestpoly`

```
freq = WhiteNoise(noise) * freq + freq
waveform = SelectX(timbre*2, [saw, sine, square])
waveform = SelectX(noise*2, [waveform, waveform*PinkNoise, PinkNoise])
threshold = -1 * (bias*2 - 1)
min = LeakDC((waveform > threshold*waveform) + (waveform <= threshold*threshold))
env = ASR o ARARAR (loop) según parámetro loop
lpg = LPF(min, env.linexp(0,1,200,20000), env * vel * amp)
```

### Curva Sigmoid (Attack/Release)

Los parámetros `poly_max_attack` y `poly_max_release` usan una curva sigmoid con k=12, c=0.93:

- **0% knob:** ~0.001s
- **70% knob:** ~2s
- **100% knob:** 24s

Esto permite control fino en el rango bajo (0-2s) con la mayor parte del recorrido del knob, y acceso a valores extremos (hasta 24s) al final.

---

## 8. Sostenuto (Shift + Hold)

Mantén **Shift** (1,8) pulsado y pulsa **Hold** (1,1) para activar/desactivar el modo **Sostenuto**.

- **Con Sostenuto activo:** Las notas que ya están en hold se mantienen sonando, pero las notas nuevas que toques **no** se quedan en hold (se comportan como notas normales).
- **Indicador visual:** El LED de Hold parpadea suavemente entre su nivel normal y 3 niveles menos de brillo.
- Útil para mantener un pedal armónico mientras sigues tocando melodías nuevas.

---

## 9. Persistencia de Estado

Al salir del script (o al hacer PSET), se guarda automáticamente:

- **Notas activas** (posición en grid y nota MIDI)
- **Estado de Hold** (Nei/Ja)
- **Estado de Loop** (Nei/Ja)
- **Octava seleccionada** y estados multi-tap de octava

Al cargar el script, el estado se restaura automáticamente después de cargar los parámetros.

---

## 10. Consejos de Uso

- **Drone + Poly:** Usa Jord como base armónica y Løv para melodías/texturas
- **Shape en 0:** Ataque instantáneo, release corto → percusivo
- **Shape en 0.5:** Ataque y release largos → pads/ambient
- **Shape en 1:** Ataque largo, release instantáneo → swell/buildup
- **Body en FX:** 0 = dry, ~0.25 = filtros, ~0.5 = filtros+delay, ~0.75 = dry+delay, 1 = dry
- **Escalas:** Cambia la escala para explorar diferentes modos y texturas armónicas
- **Root Note:** Cambia la tónica de la escala (se ilumina a nivel 3 en el grid)
- **Hold + Loop:** Activa hold y loop para crear secuencias/texturas en capas
- **Shift:** Botón momentáneo en (1,8) — preparado para futuras funciones

---

## 11. Mejoras Implementadas (v1.5)

| # | Mejora | Descripción |
|---|--------|-------------|
| 1 | **21 escalas musicales** | Grid re-mapeado: solo existen las notas de la escala seleccionada |
| 2 | **Tónicas iluminadas** | Notas raíz de la escala a nivel 3 en el grid |
| 3 | **Attack/Release 24s** | Tiempos máximos de envolvente extendidos a 24s con curva sigmoid |
| 4 | **Polifonía 12 voces** | De 4 a 12 voces simultáneas |
| 5 | **Shift momentáneo** | Botón (1,8) momentáneo con LED 5/14 |
| 6 | **Fila 8 libre** | La fila 8 del grid no forma parte del teclado |
| 7 | **Background extendido** | Columnas (1,6) y (1,7) iluminadas como zona playable |
| 8 | **Root Note** | Nuevo parámetro para cambiar la tónica (C..B) |
| 9 | **Persistencia de estado** | Notas activas, hold, loop, octava y estados multi-tap se guardan al salir |
| 10 | **Fokus default Lys** | El script inicia en modo FX (Lys) |
| 11 | **Sostenuto** | Shift+Hold toggle: mantiene notas hold, nuevas no se holdean |
| 12 | **Octavas en fila 8** | Botones de octava movidos a (2-4,8) |
| 13 | **E3 → poly_scale** | Encoder 3 ahora controla escala de envolvente |
| 14 | **Root Note retrigger** | Cambiar root note re-pitcha notas activas |
| 15 | **Shift LED brillo 2** | Shift en reposo a nivel 2 |
| 16 | **Octavas multi-tap** | Botón 2: -1/-2 oct, botón 4: +1/+2 oct (LED 6↔2 en -2/+2) |
| 17 | **16n nativo** | Detección automática con soft takeover y popup en pantalla |
| 18 | **Headroom poly** | Reducción de ganancia poly -6dB para evitar clipping con 12 voces |

---

*Høst — v1.5*
