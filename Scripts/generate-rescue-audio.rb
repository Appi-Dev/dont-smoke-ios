# Original procedural ambience: separate sound designs, matched loudness, seamless loops.
require 'fileutils'
RATE = 22_050; RAW_SECONDS = 38; FADE_SECONDS = 2
RAW_LENGTH = RATE * RAW_SECONDS; FADE_LENGTH = RATE * FADE_SECONDS; TAU = Math::PI * 2
OUTPUT = 'DontSmoke/Resources/Audio'; FileUtils.mkdir_p(OUTPUT)

def noise_beds(seed)
  rng = Random.new(seed); low = 0.0; deep = 0.0; previous = 0.0
  Array.new(RAW_LENGTH) do
    white = rng.rand * 2 - 1
    low += 0.035 * (white - low); deep += 0.003 * (white - deep)
    high = white - previous; previous = white
    [white, low, deep, high]
  end
end

def bird(t, start, frequency)
  age = t - start
  return 0.0 unless age.between?(0, 0.7)
  Math.sin(Math::PI * age / 0.7)**2 * Math.sin(TAU * (frequency * age + 180 * age * age))
end

def drop(t, start, frequency)
  age = t - start
  return 0.0 unless age.between?(0, 0.18)
  Math.exp(-age * 25) * Math.sin(TAU * frequency * age)
end

def synthesize(name, seed)
  beds = noise_beds(seed); rng = Random.new(seed + 100)
  drops = Array.new(125) { [rng.rand * RAW_SECONDS, rng.rand(900.0..2_800), rng.rand(0.025..0.085)] }
  birds = [[3.2, 1_320], [8.8, 1_760], [15.4, 1_480], [24.1, 1_900], [31.6, 1_550]]
  Array.new(RAW_LENGTH) do |i|
    t = i.to_f / RATE; white, low, deep, high = beds[i]
    case name
    when 'rain'
      0.12 * white + 0.28 * low + drops.sum { |start, frequency, gain| gain * drop(t, start, frequency) }
    when 'ocean'
      wave = ((Math.sin(TAU * t / 7.0 - 1.1) + 1) / 2)**2
      shore = ((Math.sin(TAU * t / 7.0 + 0.2) + 1) / 2)**5
      (0.25 * deep + 0.52 * low) * (0.28 + wave) + 0.055 * high * shore
    when 'forest'
      breeze = 0.36 * low * (0.72 + 0.28 * Math.sin(TAU * t / 9.5))
      leaves = 0.035 * high * (0.45 + 0.55 * ((Math.sin(TAU * t / 4.2) + 1) / 2))
      breeze + leaves + birds.sum { |start, frequency| 0.055 * bird(t, start, frequency) }
    when 'breeze'
      swell = 0.54 + 0.32 * Math.sin(TAU * t / 11.0) + 0.14 * Math.sin(TAU * t / 4.7)
      (0.65 * low + 0.55 * deep) * swell
    when 'night'
      gate1 = [Math.sin(TAU * 5.6 * t), 0].max**10
      gate2 = [Math.sin(TAU * 4.1 * t + 2.0), 0].max**12
      0.17 * deep + 0.09 * low + 0.032 * gate1 * Math.sin(TAU * 3_250 * t) + 0.018 * gate2 * Math.sin(TAU * 2_650 * t)
    else
      breathe = 0.82 + 0.18 * Math.sin(TAU * t / 12.0)
      chord = 0.065 * Math.sin(TAU * 110 * t) + 0.043 * Math.sin(TAU * 164.81 * t) +
        0.032 * Math.sin(TAU * 220 * t) + 0.018 * Math.sin(TAU * 329.63 * t)
      chord * breathe + 0.08 * deep
    end
  end
end

def seamless_loop(raw)
  middle = raw[FADE_LENGTH...(RAW_LENGTH - FADE_LENGTH)]
  crossfade = Array.new(FADE_LENGTH) do |i|
    mix = i.to_f / (FADE_LENGTH - 1)
    raw[RAW_LENGTH - FADE_LENGTH + i] * (1 - mix) + raw[i] * mix
  end
  middle + crossfade
end

def normalize(samples, target)
  rms = Math.sqrt(samples.sum { |sample| sample * sample } / samples.length)
  gain = target / [rms, 0.0001].max; peak = samples.map(&:abs).max * gain
  gain *= 0.82 / peak if peak > 0.82
  samples.map { |sample| sample * gain }
end

def smooth_boundary(samples)
  ramp = 512
  ramp.times do |i|
    position = i.to_f / (ramp - 1)
    mix = position * position * (3 - 2 * position)
    index = samples.length - ramp + i
    samples[index] = samples[index] * (1 - mix) + samples[0] * mix
  end
  samples
end

targets = { 'rain' => 0.19, 'ocean' => 0.19, 'forest' => 0.16,
            'breeze' => 0.17, 'night' => 0.16, 'warmAmbient' => 0.15 }
targets.each_with_index do |(name, target), index|
  samples = smooth_boundary(normalize(seamless_loop(synthesize(name, 8_100 + index)), target))
  offset = name == 'warmAmbient' ? 83 : 337
  stereo = samples.each_index.flat_map { |i| [samples[i], samples[(i + offset) % samples.length]] }
  pcm = stereo.map { |value| (value.clamp(-0.9, 0.9) * 32_767).round }.pack('s<*')
  header = 'RIFF' + [36 + pcm.bytesize].pack('V') + 'WAVEfmt ' +
    [16, 1, 2, RATE, RATE * 4, 4, 16].pack('VvvVVvv') + 'data' + [pcm.bytesize].pack('V')
  File.binwrite(File.join(OUTPUT, "#{name}.wav"), header + pcm)
end
