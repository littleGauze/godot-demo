const fs = require("fs");
const path = require("path");
const { sfxr } = require("jsfxr");

const outDir = path.join(__dirname, "..", "Audio");
fs.mkdirSync(outDir, { recursive: true });

function writeWave(filename, params) {
  const wave = sfxr.toWave(params);
  const base64 = wave.dataURI.split(",")[1];
  const buffer = Buffer.from(base64, "base64");
  fs.writeFileSync(path.join(outDir, filename), buffer);
  console.log(`wrote ${filename}`);
}

function preset(name, opts = {}, mutate = null) {
  const p = sfxr.generate(name, {
    sound_vol: opts.sound_vol ?? 0.25,
    sample_rate: opts.sample_rate ?? 44100,
    sample_size: opts.sample_size ?? 16,
  });
  if (mutate) {
    mutate(p);
  }
  return p;
}

writeWave("player_attack1.wav", preset("laserShoot", {}, (p) => {
  p.wave_type = 1;
  p.p_base_freq = 0.36;
  p.p_freq_limit = 0.12;
  p.p_freq_ramp = -0.18;
  p.p_env_sustain = 0.05;
  p.p_env_decay = 0.11;
  p.p_hpf_freq = 0.08;
}));

writeWave("player_attack2.wav", preset("laserShoot", {}, (p) => {
  p.wave_type = 0;
  p.p_base_freq = 0.28;
  p.p_freq_limit = 0.1;
  p.p_freq_ramp = -0.16;
  p.p_duty = 0.38;
  p.p_env_sustain = 0.08;
  p.p_env_decay = 0.16;
  p.p_hpf_freq = 0.04;
}));

writeWave("player_attack3.wav", preset("explosion", {}, (p) => {
  p.wave_type = 3;
  p.p_base_freq = 0.2;
  p.p_freq_ramp = -0.08;
  p.p_env_attack = 0;
  p.p_env_sustain = 0.09;
  p.p_env_decay = 0.2;
  p.p_lpf_freq = 0.74;
  p.p_hpf_freq = 0.02;
}));

writeWave("enemy_attack1.wav", preset("laserShoot", {}, (p) => {
  p.wave_type = 3;
  p.p_base_freq = 0.16;
  p.p_freq_limit = 0.06;
  p.p_freq_ramp = -0.14;
  p.p_env_sustain = 0.08;
  p.p_env_decay = 0.16;
  p.p_hpf_freq = 0.03;
}));

writeWave("enemy_attack2.wav", preset("laserShoot", {}, (p) => {
  p.wave_type = 0;
  p.p_base_freq = 0.18;
  p.p_freq_limit = 0.08;
  p.p_freq_ramp = -0.12;
  p.p_duty = 0.28;
  p.p_env_sustain = 0.1;
  p.p_env_decay = 0.18;
  p.p_hpf_freq = 0.02;
}));

writeWave("enemy_attack3.wav", preset("explosion", {}, (p) => {
  p.wave_type = 3;
  p.p_base_freq = 0.14;
  p.p_freq_ramp = -0.06;
  p.p_env_attack = 0;
  p.p_env_sustain = 0.1;
  p.p_env_decay = 0.24;
  p.p_lpf_freq = 0.58;
  p.p_hpf_freq = 0.01;
}));

writeWave("player_hurt.wav", preset("hitHurt", {}, (p) => {
  p.wave_type = 3;
  p.p_base_freq = 0.16;
  p.p_env_sustain = 0.06;
  p.p_env_decay = 0.22;
  p.p_lpf_freq = 0.72;
}));

writeWave("enemy_hurt.wav", preset("hitHurt", {}, (p) => {
  p.wave_type = 3;
  p.p_base_freq = 0.11;
  p.p_env_sustain = 0.09;
  p.p_env_decay = 0.26;
  p.p_lpf_freq = 0.6;
}));

writeWave("block.wav", preset("blipSelect", {}, (p) => {
  p.wave_type = 1;
  p.p_base_freq = 0.62;
  p.p_env_sustain = 0.04;
  p.p_env_decay = 0.1;
  p.p_pha_offset = 0.18;
  p.p_pha_ramp = -0.12;
  p.p_hpf_freq = 0.1;
}));
