# HØST — Manual de Uso

**Versión:** 1.2  
**Autor:** synthi (modificado)  
**Plataforma:** norns (compatible Pi 4B)  
**Hardware:** Grid 16×8, 16n faders (MIDI), norns keys/encoders

---

## 1. Descripción General

Høst es un sintetizador para norns inspirado en el módulo **Just Friends** (Mannequins). Emula su comportamiento de auto-modulación, morphing de formas de onda, inyección de ruido y lógica de threshold analógica.

El motor de sonido tiene 3 componentes principales:

| Componente | Nombre | Descripción |
|------------|--------|-------------|
| **Jord** (Tierra) | Drone | Oscilador continuo con morphing saw→sine→square, ruido, threshold |
| **Løv** (Hoja) | Poly-synth | Polifonía de 8 voces, misma arquitectura que el drone + envolvente |
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

---

## 3. Controles del Grid (16×8)

### Columna 1 — Control

| Posición | Función |
|----------|---------|
| (1,1) | **Hold** — Toggle mantener notas (Nei/Ja) |
| (1,2) | **Loop** — Toggle repetición de envolvente (Nei/Ja) |
| (1,3) | **Octava 3** (aguda) |
| (1,4) | **Octava 2** (media) |
| (1,5) | **Octava 1** (grave) |
| (1,6) | **Fokus 1** — Jord |
| (1,7) | **Fokus 2** — Løv |
| (1,8) | **Fokus 3** — Lys |

### Columnas 2-16 — Teclado

El grid funciona como un teclado musical:

- **Eje X (columnas):** Avanza por las notas de la escala seleccionada
- **Eje Y (filas):** Cada fila hacia arriba equivale a una "quinta" (4 pasos de escala)
- **Nota base:** Do# (MIDI 12 + tónica de escala)

**Con escala Chromatic (default):** 12 columnas por octava, comportamiento original.

**Con otras escalas:** El grid se re-mapea automáticamente. Solo existen las notas de la escala seleccionada. Las columnas que no pertenecen a la escala no se iluminan ni responden al tacto.

### Visualización en el Grid

| Elemento | Nivel LED | Descripción |
|----------|-----------|-------------|
| Fondo de teclas activas | 3 | Notas que pertenecen a la escala |
| Tónica de la escala | 5 | Nota raíz de la escala (más brillante) |
| Nota pulsada | 10 | Nota que está sonando actualmente |
| Sombra proyectada | 1 | Sombra sutil desde notas activas |
| Columna 1 — indicadores | 5/10 | Estado de hold, loop, octava, fokus |

---

## 4. Controles en Norns

### Teclas físicas (K1, K2, K3)

| Combinación | Acción |
|-------------|--------|
| K2 | Seleccionar Fokus 1 (Jord) |
| K3 | Seleccionar Fokus 2 (Løv) |
| K2 + K3 | Seleccionar Fokus 3 (Lys) |

### Encoders físicos (E1, E2, E3)

| Encoder | Parámetro |
|---------|-----------|
| E1 | Fokus (cambia entre Jord/Løv/Lys) |
| E2 | Ganancia de distorsión (FX) |
| E3 | Escala de envolvente (poly) |

---

## 5. Parámetros del Menú (PARAMS)

### Grupo HØST

#### JORD (Drone)

| Parámetro | ID | Rango | Default | Descripción |
|-----------|-----|-------|---------|-------------|
| Volum | `drone_amp` | 0–1 | 0.8 | Volumen del drone |
| Klangfarge | `drone_timbre` | 0–1 | 0.5 | Morphing saw→sine→square |
| Støy | `drone_noise` | 0–1 | 0.0 | Inyección de ruido (white→pink) |
| Terskel | `drone_bias` | 0–1 | 0.0 | Threshold de lógica analógica |
| Frekvens | `drone_freq` | 0.2–2000 Hz | 117 Hz | Frecuencia base del drone |

#### LØV (Poly)

| Parámetro | ID | Rango | Default | Descripción |
|-----------|-----|-------|---------|-------------|
| Volum | `poly_amp` | 0–1 | 0.8 | Volumen del poly |
| Klangfarge | `poly_timbre` | 0–1 | 0.2 | Morphing saw→sine→square |
| Støy | `poly_noise` | 0–1 | 0.3 | Inyección de ruido |
| Terskel | `poly_bias` | 0–1 | 0.6 | Threshold de lógica analógica |
| Kontur | `poly_shape` | 0–1 | 0.1 | Control de forma de envolvente |

#### LYS (FX)

| Parámetro | ID | Rango | Default | Descripción |
|-----------|-----|-------|---------|-------------|
| Første | `fx_peak_1` | 20–20000 Hz | 115 Hz | Frecuencia del primer filtro bandpass |
| Andre | `fx_peak_2` | 20–20000 Hz | 218 Hz | Frecuencia del segundo filtro bandpass |
| Kropp | `fx_body` | 0–1 | 0.0 | Morph: dry→filter→filter+delay→dry+delay→dry |
| Tid | `fx_time` | 0.01–2 s | 1 s | Tiempo del delay |
| Resonans | `fx_res` | 0–100% | 50% | Resonancia de los filtros |
| Ekko | `fx_fb` | 0–100% | 100% | Feedback del delay |

#### FORVITRING (Distorsión)

| Parámetro | ID | Rango | Default | Descripción |
|-----------|-----|-------|---------|-------------|
| Styrke | `fx_gain` | 0.5–16 | 0.5 | Ganancia de distorsión (tanh) |

#### NOTER (Notas)

| Parámetro | ID | Rango | Default | Descripción |
|-----------|-----|-------|---------|-------------|
| Vekst | `poly_max_attack` | 0.001–20 s | 1 s | Tiempo máximo de ataque |
| Forfall | `poly_max_release` | 0.001–20 s | 3 s | Tiempo máximo de release |
| Skala | `poly_scale` | 1–100% | 100% | Escala global de la envolvente |
| Repeter? | `poly_loop` | Nei/Ja | Nei | Loop de envolvente (ararar) |

#### Scale (Escala Musical)

| Parámetro | ID | Opciones | Default |
|-----------|-----|----------|---------|
| Scale | `scale` | 21 escalas (ver abajo) | Chromatic |

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

### 16n Faders (recomendación de mapeo)

El 16n envía MIDI CC por USB. Mapeo sugerido:

| Fader | CC | Parámetro |
|-------|-----|-----------|
| 1 | 1 | `drone_timbre` |
| 2 | 2 | `drone_noise` |
| 3 | 3 | `drone_bias` |
| 4 | 4 | `drone_freq` |
| 5 | 5 | `poly_timbre` |
| 6 | 6 | `poly_noise` |
| 7 | 7 | `poly_bias` |
| 8 | 8 | `poly_shape` |
| 9 | 9 | `fx_peak_1` |
| 10 | 10 | `fx_peak_2` |
| 11 | 11 | `fx_body` |
| 12 | 12 | `fx_time` |
| 13 | 13 | `fx_gain` |
| 14 | 14 | `poly_max_attack` |
| 15 | 15 | `poly_max_release` |
| 16 | 16 | `poly_scale` |

---

## 7. Especificaciones Técnicas

### Motor de Audio (SuperCollider)

- **Polifonía:** 8 voces simultáneas
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

---

## 8. Consejos de Uso

- **Drone + Poly:** Usa Jord como base armónica y Løv para melodías/texturas
- **Shape en 0:** Ataque instantáneo, release corto → percusivo
- **Shape en 0.5:** Ataque y release largos → pads/ambient
- **Shape en 1:** Ataque largo, release instantáneo → swell/buildup
- **Body en FX:** 0 = dry, ~0.25 = filtros, ~0.5 = filtros+delay, ~0.75 = dry+delay, 1 = dry
- **Escalas:** Cambia la escala para explorar diferentes modos y texturas armónicas
- **Hold + Loop:** Activa hold y loop para crear secuencias/texturas en capas

---

## 9. Mejoras Implementadas (v1.2)

| # | Mejora | Descripción |
|---|--------|-------------|
| 1 | **21 escalas musicales** | Grid re-mapeado: solo existen las notas de la escala seleccionada |
| 2 | **Sombras sutiles** | Brillo de sombras reducido a nivel 1 |
| 3 | **Tónicas iluminadas** | Notas raíz de la escala a nivel 5 en el grid |
| 4 | **Attack/Release 20s** | Tiempos máximos de envolvente extendidos a 20 segundos |
| 5 | **Polifonía 8 voces** | De 4 a 8 voces simultáneas |

---

*Høst — v1.2*