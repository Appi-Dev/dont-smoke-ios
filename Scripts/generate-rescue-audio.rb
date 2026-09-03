# Original, procedurally synthesized ambience. No recordings or third-party assets.
# Run from the repository root with Ruby's standard library only.
require 'fileutils'

rate = 22_050
duration = 24
overlap = rate
length = rate * duration
output = 'DontSmoke/Resources/Audio'
FileUtils.mkdir_p(output)

%w[rain ocean forest breeze night warmAmbient].each_with_index do |name, index|
  rng = Random.new(7100 + index)
  low = 0.0
  deep = 0.0
  samples = Array.new(length + overlap) do |i|
    t = i.to_f / rate
    noise = rng.rand * 2 - 1
    low += 0.08 * (noise - low)
    deep += 0.009 * (noise - deep)
    case name
    when 'rain'
      0.13 * noise + 0.4 * low
    when 'ocean'
      swell = 0.35 + 0.65 * ((Math.sin(t * Math::PI / 4) + 1) / 2)
      (0.7 * low + 1.4 * deep) * swell
    when 'forest'
      # A soft foliage bed with gently enveloped, sparse bird-like tones.
      pulse = [Math.sin(t * Math::PI / 2), 0].max ** 16
      0.4 * low + 0.025 * pulse * Math.sin(2 * Math::PI * 1700 * t + 4 * Math.sin(18 * t))
    when 'breeze'
      swell = 0.65 + 0.35 * Math.sin(t * Math::PI / 6)
      (0.65 * low + 1.3 * deep) * swell
    when 'night'
      pulse = ((Math.sin(t * Math::PI * 7) + 1) / 2) ** 6
      0.2 * low + 0.018 * pulse * Math.sin(2 * Math::PI * 2800 * t)
    else
      0.07 * Math.sin(2 * Math::PI * 110 * t) +
        0.045 * Math.sin(2 * Math::PI * 165 * t) +
        0.025 * Math.sin(2 * Math::PI * 220 * t) + 0.12 * deep
    end
  end
  # Crossfade the tail into the head; the last sample then joins its natural successor.
  overlap.times do |i|
    mix = i.to_f / overlap
    samples[i] = samples[length + i] * (1 - mix) + samples[i] * mix
  end
  pcm = samples.first(length).map { |value| (value.clamp(-0.9, 0.9) * 32767).round }.pack('s<*')
  header = 'RIFF' + [36 + pcm.bytesize].pack('V') + 'WAVEfmt ' +
    [16, 1, 1, rate, rate * 2, 2, 16].pack('VvvVVvv') + 'data' + [pcm.bytesize].pack('V')
  File.binwrite(File.join(output, "#{name}.wav"), header + pcm)
end
