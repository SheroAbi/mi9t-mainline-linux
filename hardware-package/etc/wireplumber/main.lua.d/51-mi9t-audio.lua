-- The Mi 9T amplifier and Q6AFE backend use 48 kHz, 16-bit samples.
-- Keep the desktop frontend at that native format too.
table.insert(alsa_monitor.rules, {
  matches = {
    { { "node.name", "equals", "alsa_output.platform-sound.HiFi__hw_X9T_0__sink" } },
  },
  apply_properties = {
    ["audio.format"] = "S16LE",
    ["audio.rate"] = 48000,
  },
})
