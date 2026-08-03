// Engine_harvest
// a part of Høst
//
// v1.8 — OSC envelope phase ground truth for grid LED sync
// imminent gloom / Josue Arias

Engine_Harvest : CroneEngine {
   var harvestParameters;
   var harvestVoices;
   var harvestVoicesOn;
   var harvestDrone;
   var harvestFx;
   var harvestBus;
   var fnNoteOn, fnNoteOnPoly, fnNoteAdd;
   var fnNoteOff, fnNoteOffPoly;
   var pedalSustainOn = false;
   var pedalSostenutoOn = false;
   var pedalSustainNotes;
   var pedalSostenutoNotes;
    var harvestPolyphonyMax = 12;
    var harvestPolyphonyCount = 0;
    var harvestRandOffsets;

   *new { arg context, doneCallback;
      ^super.new(context, doneCallback);
   }

   alloc {

      // initialize variables
      harvestParameters = Dictionary.with(*[
         "amp"->0.8,
         "drift"->0.0,
         "timbre"->0.2,
         "noise"->0.3,
         "bias"->0,
         "freq"->100.0,
         "loop"->0.0,
         "shape"->0.1,
         "max_attack"->1,
         "max_release"->24,
          "scale"->1,
          "spread"->0,
       ]);
      harvestVoices = Dictionary.new;
       harvestVoicesOn = Dictionary.new;
       harvestRandOffsets = Dictionary.new;
      pedalSustainNotes = Dictionary.new;
      pedalSostenutoNotes = Dictionary.new;

      // initialize synth defs
      SynthDef(\harvestfx, {
         var input, body, bodyLag, filter, peak1, peak2, res, delay, time, feedback, mix, gain, dist;
         var delay_raw, delay_L, delay_R;
         // === Analog tolerances (fixed per synth instance) ===
         var peak1_L_var = Rand(0.98, 1.02);
         var peak1_R_var = Rand(0.98, 1.02);
         var peak2_L_var = Rand(0.98, 1.02);
         var peak2_R_var = Rand(0.98, 1.02);
         var peak2_offset = Rand(0.99, 1.01);
         var res_L_var = Rand(0.97, 1.03);
         var res_R_var = Rand(0.97, 1.03);
         var delay_L_var = Rand(0.99, 1.01);
         var delay_R_var = Rand(0.99, 1.01);
         var fb_L_var = Rand(0.97, 1.03);
         var fb_R_var = Rand(0.97, 1.03);
         var fb_lpf_L_var = Rand(0.96, 1.04);
         var fb_lpf_R_var = Rand(0.96, 1.04);
         var gain_L_var = Rand(0.98, 1.02);
         var gain_R_var = Rand(0.98, 1.02);
         // Thermal drift
         var thermal = LFNoise2.kr(0.02, 0.005);

         input = In.ar(\inBus.ir(10), 2);

         body     = \body.kr(0.0);
         res      = LinSelectX.kr(body * 6, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]) * \res_max.kr(0.5);
         feedback = LinSelectX.kr(body * 6, [0.0, 0.50, 0.99, 0.99, 0.75, 0.55, 0.50]) * \fb_max.kr(1.0);

         // SVF peaks with L/R tolerances
         peak1 = [
            SVF.ar(input[0], (\peak1.kr(115, 0.1) * peak1_L_var).clip(20, 20000), res * res_L_var, 0, 1, 0),
            SVF.ar(input[1], (\peak1.kr(115, 0.1) * peak1_R_var).clip(20, 20000), res * res_R_var, 0, 1, 0)
         ];

         peak2 = [
            SVF.ar(input[0], (\peak2.kr(218, 0.1) * peak2_L_var * peak2_offset).clip(20, 20000), res * res_L_var, 0, 1, 0),
            SVF.ar(input[1], (\peak2.kr(218, 0.1) * peak2_R_var * peak2_offset).clip(20, 20000), res * res_R_var, 0, 1, 0)
         ];

         filter = peak1 + peak2;

         time = \time.kr(1, 0.25);
         delay_raw = XFade2.ar(filter, input, SelectX.kr(body * 6, [-1, -1, -1, 1, 1, 0, 1]));

         // Delay with L/R time + feedback LPF tolerances
         delay_L = delay_raw[0] + LPF.ar(LocalIn.ar(2)[0], ((4000 - (3000 * time * 0.5)).clip(20, 20000) * fb_lpf_L_var)) * (feedback * fb_L_var);
         delay_R = delay_raw[1] + LPF.ar(LocalIn.ar(2)[1], ((4000 - (3000 * time * 0.5)).clip(20, 20000) * fb_lpf_R_var)) * (feedback * fb_R_var);

         delay_L = DelayC.ar(delay_L, 10, time * delay_L_var);
         delay_R = DelayC.ar(delay_R, 10, time * delay_R_var);
         delay = [delay_L, delay_R];
         LocalOut.ar(delay);

         mix = SelectX.ar(body * 6, [input, filter, filter + delay * 0.7, input + delay * 0.7, (input * 0.7 + filter * 0.5 + delay * 0.5), (input * 0.55 + filter * 0.8 + delay * 0.55), input]);

         gain = \gain.kr(1, 0.1);
         dist = [
            (mix[0] * gain * gain_L_var).tanh * (1 / gain.sqrt) * \amp.kr(0.5, 0.1),
            (mix[1] * gain * gain_R_var).tanh * (1 / gain.sqrt) * \amp.kr(0.5, 0.1)
         ];

         Out.ar(\out.ir(0), dist);
      }).add;

      SynthDef(\harvestdrone, {
         var amp, amp_env, filter_env, freq, freq_fm, noise, noise_amt, timbre, drift, pulsewidth;
         var sine, saw, square, waveform;
         var bias, bias_neg, bias_pos, fm_amt, fm_mod;
         var sub, sub_amt;
         var sc_bias, threshold, min, lpg;
         var noise_out, ringmod, noise_src, dust_amt, dust_trig, dust_env, gated;
         var wr, wr2, wr3;
         // === Analog tolerances (fixed per synth instance) ===
         var sine_detune  = Rand(-0.001, 0.001);    // ±0.1% (2 cents)
         var saw_detune   = Rand(-0.003, 0.003);    // ±0.3% (5 cents)
         var square_detune = Rand(-0.003, 0.003);   // ±0.3% (5 cents)
         var sine_gain   = Rand(0.98, 1.02);        // ±2%
         var saw_gain    = Rand(0.97, 1.03);         // ±3%
         var square_gain = Rand(0.97, 1.03);         // ±3%
         var pw_L_var    = Rand(0.995, 1.005);       // ±0.5%
         var pw_R_var    = Rand(0.995, 1.005);       // ±0.5%
         var lpg_L_var   = Rand(0.95, 1.05);         // drone LPF ±5%
         var lpg_R_var   = Rand(0.95, 1.05);
         var bal_L_var   = Rand(0.98, 1.02);         // amp balance ±2%
         var bal_R_var   = Rand(0.98, 1.02);
         // Thermal drift
         var thermal = LFNoise2.kr(0.02, 0.005);     // ±0.5%

         amp = \amp.kr(0.8, 0.1);
         freq = \freq.kr(100, 0.1);
         noise = \noise.kr(0.0, 0.1);
         timbre = \timbre.kr(0.5, 0.1);
         drift = \drift.kr(0.0, 0.1);
         bias = \bias.kr(0, 0.1);  // -1 to 1: 0=clean, +=wavefold, -=FM+sub

         // Frequency noise + drift (±25 cents)
         freq = WhiteNoise.ar(noise) * freq + freq;
         freq = freq.clip(0, SampleRate.ir * 0.5);
         freq = freq * (2 ** ((LFNoise2.kr(0.01) * drift * (25/1200)) + (LFNoise2.kr(3.1) * drift * (15/1200))));

         // Bias: split negative (FM+sub) and positive (wavefold)
         bias_neg = (bias * -1).max(0);  // 0→1 as bias goes 0→-1
         bias_pos = bias.max(0);          // 0→1 as bias goes 0→+1

         // FM: ramps 0→1 between bias 0 and -0.66
         fm_amt = (bias_neg * 1.5).min(1);
         fm_mod = Delay1.ar(SinOsc.ar(freq)) * fm_amt * 3;
         freq_fm = freq * (1 + fm_mod);

         // Sub: starts appearing at bias=-0.3, full at bias=-0.96 (overlaps with FM)
         sub_amt = ((bias_neg - 0.3) * 1.5).max(0).min(1);

         // Pulsewidth with L/R asymmetry
         pulsewidth = LinSelectX.kr(timbre * 2, [0.001, 0.5, 0.98]);

         // Oscillators with FM-modulated frequency + individual detune
         sine   = SinOsc.ar(freq_fm * (1 + sine_detune)) * sine_gain;
         saw    = VarSaw.ar(freq_fm * (1 + saw_detune), 0, pulsewidth * pw_L_var, 0.61 * saw_gain);
         square = Pulse.ar(freq_fm * (1 + square_detune), pulsewidth * pw_R_var, 0.667 * square_gain);

         // Timbre crossfade with wider sine zone
         waveform = SelectX.ar(((timbre - 0.5) * 1.3 + 0.5).clip(0, 1) * 2, [saw, sine, square]);

         // Sub oscillator (clean freq, one octave down)
         sub = SinOsc.ar(freq * 0.5) * sub_amt * 0.5;
         waveform = waveform + sub;

         // === Noise section: 3 stages ===
         noise_amt = noise;

         // Stage 1 (0→0.4): ringmod fade in
         ringmod = waveform * (1 + PinkNoise.ar(noise_amt.min(0.4) * 3.75)) * 0.5;
         wr = XFade2.ar(waveform, ringmod, (noise_amt / 0.4).min(1) * 2 - 1);

         // Stage 2 (0.4→0.85): crossfade to continuous noise
         noise_src = PinkNoise.ar(1);
         wr2 = XFade2.ar(wr, noise_src, ((noise_amt - 0.4) / 0.45).max(0).min(1) * 2 - 1);

         // Stage 3 (0.85→1): dust progressively gates the noise
         dust_amt = ((noise_amt - 0.85) / 0.15).max(0).min(1);
         dust_trig = Dust.ar(20 + (dust_amt * dust_amt * 2000));
         dust_env = Decay2.ar(dust_trig, 0.001, 0.005 + (dust_amt * 0.02));
         gated = noise_src * (1 - dust_amt) + (noise_src * dust_env * dust_amt * 2);
         wr3 = XFade2.ar(wr2, gated, dust_amt * 2 - 1);

         noise_out = wr3;
         waveform = noise_out.clip(-1, 1);

         // === Wavefolding (bias > 0): half-wave rect → distortion ===
         sc_bias = 0.5 + (bias_pos * 0.5);
         threshold = -1 * (sc_bias * 2 - 1);
         min = LeakDC.ar((waveform > threshold * waveform) + (waveform <= threshold * threshold));

         // LPG: filter closes faster than amplitude (amp²), range 210–18.5kHz
         amp_env = amp;
         filter_env = amp_env * amp_env;
         lpg = LPF.ar(min, filter_env.linexp(0, 1, 210, 18500) * [lpg_L_var + thermal, lpg_R_var + thermal], amp_env);

         Out.ar(\out.ir(0), Pan2.ar(lpg * [bal_L_var, bal_R_var], \pan.kr(0)) * 0.5);
      }).add;

      SynthDef(\harvestpoly, {
         var amp, amp_env, filter_env, freq, freq_fm, noise, noise_amt, timbre, drift, pulsewidth;
         var sine, saw, square, waveform;
         var bias, bias_neg, bias_pos, fm_amt, fm_mod;
         var sub, sub_amt;
         var sc_bias, threshold, min;
         var noise_out, ringmod, noise_src, dust_amt, dust_trig, dust_env, gated;
         var wr, wr2, wr3;
         var vel, gate, loop, shape, scale, max_attack, max_release;
         var attack, release, curve, asr, ararar, env, lpg;
         var att1, att2, att3, rel1, rel2, rel3, cur1, cur2, cur3, w1, w2, w3;
         var valley_below, valley_trig;
         var note = \note.kr(60);
         // === Analog tolerances (fixed per voice) ===
         var sine_detune  = Rand(-0.001, 0.001);    // ±0.1% (2 cents)
         var saw_detune   = Rand(-0.003, 0.003);    // ±0.3% (5 cents)
         var square_detune = Rand(-0.003, 0.003);   // ±0.3% (5 cents)
         var sine_gain   = Rand(0.98, 1.02);        // ±2%
         var saw_gain    = Rand(0.97, 1.03);         // ±3%
         var square_gain = Rand(0.97, 1.03);         // ±3%
         var pw_L_var    = Rand(0.995, 1.005);       // ±0.5%
         var pw_R_var    = Rand(0.995, 1.005);       // ±0.5%
         var lpg_L_var   = Rand(0.97, 1.03);         // poly LPF ±3% (more precise than drone)
         var lpg_R_var   = Rand(0.97, 1.03);
         var bal_L_var   = Rand(0.98, 1.02);         // amp balance ±2%
         var bal_R_var   = Rand(0.98, 1.02);
         var voice_gain  = Rand(0.97, 1.03);          // per-voice gain ±3%
         // Thermal drift
         var thermal = LFNoise2.kr(0.02, 0.005);     // ±0.5%

         amp = \amp.kr(0.8, 0.1);
         freq = \freq.kr(100, 0.1);
         noise = \noise.kr(0.0, 0.1);
         timbre = \timbre.kr(0.5, 0.1);
         drift = \drift.kr(0.0, 0.1);
         bias = \bias.kr(0, 0.1);  // -1 to 1: 0=clean, +=wavefold, -=FM+sub

         // Frequency noise + drift (±25 cents)
         freq = WhiteNoise.ar(noise) * freq + freq;
         freq = freq.clip(0, SampleRate.ir * 0.5);
         freq = freq * (2 ** ((LFNoise2.kr(0.01) * drift * (25/1200)) + (LFNoise2.kr(3.1) * drift * (15/1200))));

         // Bias: split negative (FM+sub) and positive (wavefold)
         bias_neg = (bias * -1).max(0);  // 0→1 as bias goes 0→-1
         bias_pos = bias.max(0);          // 0→1 as bias goes 0→+1

         // FM: ramps 0→1 between bias 0 and -0.66
         fm_amt = (bias_neg * 1.5).min(1);
         fm_mod = Delay1.ar(SinOsc.ar(freq)) * fm_amt * 3;
         freq_fm = freq * (1 + fm_mod);

         // Sub: starts appearing at bias=-0.3, full at bias=-0.96 (overlaps with FM)
         sub_amt = ((bias_neg - 0.3) * 1.5).max(0).min(1);

         // Pulsewidth with L/R asymmetry
         pulsewidth = LinSelectX.kr(timbre * 2, [0.001, 0.5, 0.98]);

         // Oscillators with FM-modulated frequency + individual detune
         sine   = SinOsc.ar(freq_fm * (1 + sine_detune)) * sine_gain;
         saw    = VarSaw.ar(freq_fm * (1 + saw_detune), 0, pulsewidth * pw_L_var, 0.61 * saw_gain);
         square = Pulse.ar(freq_fm * (1 + square_detune), pulsewidth * pw_R_var, 0.667 * square_gain);

         // Timbre crossfade with wider sine zone
         waveform = SelectX.ar(((timbre - 0.5) * 1.3 + 0.5).clip(0, 1) * 2, [saw, sine, square]);

         // Sub oscillator (clean freq, one octave down)
         sub = SinOsc.ar(freq * 0.5) * sub_amt * 0.5;
         waveform = waveform + sub;

         // === Noise section: 3 stages ===
         noise_amt = noise;

         // Stage 1 (0→0.4): ringmod fade in
         ringmod = waveform * (1 + PinkNoise.ar(noise_amt.min(0.4) * 3.75)) * 0.5;
         wr = XFade2.ar(waveform, ringmod, (noise_amt / 0.4).min(1) * 2 - 1);

         // Stage 2 (0.4→0.85): crossfade to continuous noise
         noise_src = PinkNoise.ar(1);
         wr2 = XFade2.ar(wr, noise_src, ((noise_amt - 0.4) / 0.45).max(0).min(1) * 2 - 1);

         // Stage 3 (0.85→1): dust progressively gates the noise
         dust_amt = ((noise_amt - 0.85) / 0.15).max(0).min(1);
         dust_trig = Dust.ar(20 + (dust_amt * dust_amt * 2000));
         dust_env = Decay2.ar(dust_trig, 0.001, 0.005 + (dust_amt * 0.02));
         gated = noise_src * (1 - dust_amt) + (noise_src * dust_env * dust_amt * 2);
         wr3 = XFade2.ar(wr2, gated, dust_amt * 2 - 1);

         noise_out = wr3;
         waveform = noise_out.clip(-1, 1);

         // === Wavefolding (bias > 0): half-wave rect → distortion ===
         sc_bias = 0.5 + (bias_pos * 0.5);
         threshold = -1 * (sc_bias * 2 - 1);
         min = LeakDC.ar((waveform > threshold * waveform) + (waveform <= threshold * threshold));

         // === Continuous shape interpolation ===
         vel =    \vel.kr(1.0);
         gate =    \gate.kr(1.0);
         loop =     \loop.kr(0);
         shape =     \shape.kr(0.1, 0.1);
         max_attack = \max_attack.kr(1, 0.01);
         max_release = \max_release.kr(3, 0.01);
         scale = \scale.kr(1, 0.1);

         // Original 4-zone LinSelectX contour (restored)
         attack  = (LinSelectX.kr(shape * 3, [0.01, 0.01, max_attack, max_attack]) * scale).clip(0.01, max_attack);
         release = (LinSelectX.kr(shape * 3, [0.01, max_release, max_release, 0.01]) * scale).clip(0.01, max_release);
         curve   =  LinSelectX.kr(shape * 3, [-2, -0.5, 0, 0]);

         asr    = EnvGen.kr(Env.asr(attack, 1, release, curve: curve), gate, doneAction: 2);
         ararar = EnvGen.kr(Env.new([0, 1, 0], [attack, release], releaseNode: 1, loopNode: 0, curve: curve), gate, doneAction: 2);
         env    = LinSelectX.kr(loop.lag((release * scale).clip(0.01, release)), [asr, ararar]);

         // LPG: filter closes faster than amplitude (amp²), range 210–18.5kHz
         amp_env = env * vel * amp;
         filter_env = env * (amp * amp);
         lpg = LPF.ar(min, filter_env.linexp(0, 1, 210, 18500) * [lpg_L_var + thermal, lpg_R_var + thermal], amp_env * voice_gain);

          SendReply.kr(Impulse.kr(30), '/harvest_env', [env, note]);
          // Per-valley trigger for PLL: fires only when env crosses below threshold
          valley_below = (env < 0.06);
          valley_trig = Trig1.kr(valley_below - Delay1.kr(valley_below), 0.01);
          SendReply.kr(valley_trig, '/harvest_valley', [env, note]);
          Out.ar(\out.ir(0), Pan2.ar(lpg * [bal_L_var, bal_R_var], \pan.kr(0)) * 0.25);
       }).add;

      // initialize fx synth and bus
      context.server.sync;
      harvestBus = Bus.audio(context.server, 2);
      context.server.sync;
      harvestFx = Synth.new(\harvestfx, [\out, 0, \inBus, harvestBus]);
      context.server.sync;
      harvestDrone = Synth.new(\harvestdrone, [\out, harvestBus]);
      context.server.sync;

      fnNoteOnPoly = {
         arg note, amp, duration;
          var lowestNote = 10000;
          var sub = 0;
          var spread, pan;

         // low-note priority for sub oscillator
         harvestVoicesOn.keysValuesDo({ arg key, syn;
            if (key < lowestNote, {
               lowestNote = key;
            });
         });
         if (lowestNote < 10000,{
            if (note < lowestNote, {
               sub = 1;
               harvestVoices.at(lowestNote).set(\sub, 0);
            },{
               sub = 0;
            });
         },{
            sub = 1;
         });

          // calculate stereo pan based on spread parameter
          spread = harvestParameters.at("spread");
          pan = 0;
          if (spread < 0, {
             // random placement: each voice gets a random fixed pan
             pan = (1.0.rand2) * spread.abs;
             harvestRandOffsets.put(note, pan);
          }, {
             if (spread > 0, {
                // orchestral/piano: pan by note pitch, low=left high=right
                pan = ((note - 60) / 60).clip(-1, 1) * spread;
             });
          });

           harvestVoices.put(note,
              Synth.before(harvestFx, "harvestpoly",[
                 \amp, harvestParameters.at("amp"),
                 \out, harvestBus,
                 \freq, (note).midicps,
                 \note, note,
                \timbre, harvestParameters.at("timbre"),
                \noise, harvestParameters.at("noise"),
                \bias, harvestParameters.at("bias"),
                \shape, harvestParameters.at("shape"),
                \loop, harvestParameters.at("loop"),
                \max_attack, harvestParameters.at("max_attack"),
                \max_release, harvestParameters.at("max_release"),
                \scale, harvestParameters.at("scale"),
                \drift, harvestParameters.at("drift"),
                \pan, pan
             ]);
          );
         NodeWatcher.register(harvestVoices.at(note));
         fnNoteAdd.(note);
      };

      fnNoteAdd = {
         arg note;
         var oldestNote = 0;
         var oldestNoteVal = 10000000;
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
      };

      // intialize helper functions
      fnNoteOn = {
         arg note, amp, duration;
         fnNoteOnPoly.(note, amp, duration);
      };

      fnNoteOff = {
         arg note;
         // remove it it hasn't already been removed and synth gone
         if ((harvestVoices.at(note) == nil) || ((harvestVoices.at(note).isRunning == false) && (harvestVoicesOn.at(note) == nil)),{},{
            fnNoteOffPoly.(note);
         });
      };

      fnNoteOffPoly = {
         arg note;
         var lowestNote = 10000;

          harvestVoicesOn.removeAt(note);
          harvestRandOffsets.removeAt(note);

         if (pedalSustainOn == true, {
            pedalSustainNotes.put(note, 1);
         }, {
            if ((pedalSostenutoOn == true) && (pedalSostenutoNotes.at(note) != nil),{
               // do nothing, it is a sostenuto note
            }, {
               // remove the sound
               harvestVoices.at(note).set(\gate, 0);
            });
         });
      };

      // add norns commands
      this.addCommand("harvest_note_on", "iff", { arg msg;
         var lowestNote = 10000;
         var note = msg[1];
         if (harvestVoices.at(note) != nil, {
            if (harvestVoices.at(note).isRunning == true, {
               harvestVoices.at(note).set(\gate, 0);
            });
         });
         fnNoteOn.(msg[1], msg[2], msg[3]);
      });

      this.addCommand("harvest_note_off", "i", { arg msg;
         var note = msg[1];
         fnNoteOff.(note);
      });

      this.addCommand("harvest_sustain", "i", { arg msg;
         pedalSustainOn = (msg[1] == 1);
         if (pedalSustainOn == false, {
            // release all sustained notes
            // that aren't currently being held down
            pedalSustainNotes.keysValuesDo({ arg note, val;
               if (harvestVoicesOn.at(note) == nil, {
                  pedalSustainNotes.removeAt(note);
                  fnNoteOff.(note);
               });
            });
         },{
            // add currently down notes to the pedal
            harvestVoicesOn.keysValuesDo({ arg note, val;
               pedalSustainNotes.put(note, 1);
            });
         });
      });

      this.addCommand("harvest_sustenuto", "i", { arg msg;
         pedalSostenutoOn = (msg[1] == 1);
         if (pedalSostenutoOn == false, {
            // release all sustained notes
            // that aren't currently being held down
            pedalSostenutoNotes.keysValuesDo({ arg note, val;
               if (harvestVoicesOn.at(note) == nil, {
                  pedalSostenutoNotes.removeAt(note);
                  fnNoteOff.(note);
               });
            });
         },{
            // add currently held notes
            harvestVoicesOn.keysValuesDo({ arg note, val;
               pedalSostenutoNotes.put(note, 1);
            });
         });
      });

      this.addCommand("harvest_fx_set","sf",{ arg msg;
         var key = msg[1].asSymbol;
         var val = msg[2];
         harvestFx.set(key, val);
      });

      this.addCommand("harvest_drone_set","sf",{ arg msg;
         var key = msg[1].asSymbol;
         var val = msg[2];
         harvestDrone.set(key, val);
      });

      this.addCommand("harvest_poly_set", "sf", { arg msg;
         var key = msg[1].asString;
         var val = msg[2];
         harvestParameters.put(key, val);
          switch (key,
             "spread", {
                var spread = val;
                harvestVoices.keysValuesDo({ arg note, syn;
                   if (syn.isRunning == true, {
                      var pan = 0;
                      if (spread < 0, {
                         var offset = harvestRandOffsets.at(note) ? (1.0.rand2);
                         pan = offset * spread.abs;
                         harvestRandOffsets.put(note, pan);
                      }, {
                         if (spread > 0, {
                            pan = ((note - 60) / 60).clip(-1, 1) * spread;
                         });
                      });
                      syn.set(\pan, pan);
                   });
                });
             },
             "", {}, // add parameters here if you don't want them to change while voice is playing
            {
               harvestVoices.keysValuesDo({ arg note, syn;
                  if (syn.isRunning == true, {
                  syn.set(key.asSymbol, val);
                  });
               });
            }
         );
      });

      // Forward SendReply messages from scsynth to norns Lua (matron port 10111)
      // SendReply sends [path, nodeID, replyID, env, note]; we forward [env, note]
      OSCdef(\harvest_env_fwd, { |msg|
         NetAddr("127.0.0.1", 10111).sendMsg('/harvest_env', msg[3], msg[4]);
      }, '/harvest_env');
      // Forward per-valley messages to norns Lua (matron port 10111)
      OSCdef(\harvest_valley_fwd, { |msg|
         NetAddr("127.0.0.1", 10111).sendMsg('/harvest_valley', msg[3], msg[4]);
      }, '/harvest_valley');
   }

   free {
      OSCdef(\harvest_env_fwd).free;
      OSCdef(\harvest_valley_fwd).free;
      harvestBus.free;
      harvestFx.free;
      harvestDrone.free;
      harvestVoices.keysValuesDo({ arg key, value; value.free; });
   }
}
