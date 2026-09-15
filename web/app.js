/**
 * TinyQV RV2A03 NES APU Web Serial Dashboard
 * 
 * Hardware Controller & Interactive Synthesizer
 * Target: Sipeed Tang Console 60K (COM19) / Tang Nano 20K (COM17)
 * Author: @fjpolo & Antigravity
 */

(function () {
  'use strict';

  // --------------------------------------------------------------------------
  // State Management
  // --------------------------------------------------------------------------
  const state = {
    port: null,
    reader: null,
    writer: null,
    isConnected: false,
    baudRate: 115200,

    // APU Synthesizer State
    currentOctave: 4,
    currentChannel: 0, // 0: Pulse 1, 1: Pulse 2, 2: Triangle, 3: Noise
    currentDuty: 2,    // 0: 12.5%, 1: 25%, 2: 50%, 3: 75%
    currentVol: 12,    // 0 to 15
    barrelDistortion: 1, // 0: Clean, 1: Warm, 2: Fuzz, 3: Doom
    jukeboxPlaying: null,

    // Audio Visualizer State
    activeFreq: 440,
    activeWaveType: 'pulse',
    activeDutyRatio: 0.5,
    isSoundActive: false,
    lastSampleVal: 0
  };

  const CHANNEL_NAMES = ['Pulse 1', 'Pulse 2', 'Triangle', 'Noise'];
  const DUTY_LABELS = ['12.5%', '25.0%', '50.0%', '75.0%'];
  const DUTY_RATIOS = [0.125, 0.25, 0.5, 0.75];
  const DIST_NAMES = ['Clean Acoustic', 'Warm Saturation', 'Metallic Fuzz', 'Industrial Doom'];

  // Note Frequencies in Octave 4 (Semitones 0 to 11)
  const BASE_FREQS = [
    261.63, 277.18, 293.66, 311.13, 329.63, 349.23,
    369.99, 392.00, 415.30, 440.00, 466.16, 493.88
  ];

  // --------------------------------------------------------------------------
  // DOM Element Selectors
  // --------------------------------------------------------------------------
  const dom = {
    // Header & Connection
    btnConnect: document.getElementById('btn-connect'),
    btnConnectText: document.getElementById('btn-connect-text'),
    statusIndicator: document.getElementById('status-indicator'),
    statusLabel: document.getElementById('status-label'),
    baudRateSelect: document.getElementById('baud-rate-select'),

    // Badges
    badgeOctave: document.getElementById('badge-octave'),
    badgeChannel: document.getElementById('badge-channel'),
    badgeDuty: document.getElementById('badge-duty'),
    badgeVol: document.getElementById('badge-vol'),
    distModeName: document.getElementById('dist-mode-name'),
    jukeboxState: document.getElementById('jukebox-state'),

    // Synth Controls
    channelButtons: document.querySelectorAll('#channel-selector .btn-toggle'),
    dutyButtons: document.querySelectorAll('#duty-selector .btn-toggle'),
    sliderVolume: document.getElementById('slider-volume'),
    valVolume: document.getElementById('val-volume'),
    sliderOctave: document.getElementById('slider-octave'),
    valOctave: document.getElementById('val-octave'),
    btnOctaveDown: document.getElementById('btn-octave-down'),
    btnOctaveUp: document.getElementById('btn-octave-up'),
    btnMute: document.getElementById('btn-mute'),

    // Piano Keyboard
    pianoKeys: document.querySelectorAll('.piano-key'),

    // Soundboard
    soundboardButtons: document.querySelectorAll('.pad-btn'),

    // Jukebox
    jukeboxPlayButtons: document.querySelectorAll('.btn-play-track'),

    // Terminal
    terminalScreen: document.getElementById('terminal-screen'),
    btnDumpRegs: document.getElementById('btn-dump-regs'),
    btnSelfTest: document.getElementById('btn-self-test'),
    btnClearTerm: document.getElementById('btn-clear-term'),
    btnHelpGuide: document.getElementById('btn-help-guide'),

    // Scope Canvas
    scopeCanvas: document.getElementById('scope-canvas'),
    freqTag: document.getElementById('freq-tag'),
    sampleTag: document.getElementById('sample-tag')
  };

  // --------------------------------------------------------------------------
  // Web Serial Driver
  // --------------------------------------------------------------------------

  // Verify Web Serial API availability
  function checkWebSerialSupport() {
    if (!('serial' in navigator)) {
      logTerminal(
        '⚠️ Web Serial API is NOT supported in this browser!\n' +
        'Please use Google Chrome, Microsoft Edge, or Opera (version 89+) on desktop.',
        'error'
      );
      dom.btnConnect.disabled = true;
      dom.statusLabel.textContent = 'NO WEB SERIAL';
      return false;
    }
    return true;
  }

  async function connectSerial() {
    if (!checkWebSerialSupport()) return;

    try {
      state.baudRate = parseInt(dom.baudRateSelect.value, 10) || 115200;
      
      // Request user to select hardware COM port (filters for BL616 / FTDI USB-UART)
      state.port = await navigator.serial.requestPort();
      await state.port.open({
        baudRate: state.baudRate,
        dataBits: 8,
        stopBits: 1,
        parity: 'none',
        bufferSize: 4096
      });

      state.isConnected = true;
      updateConnectionUI(true);

      logTerminal(`Connected to serial port @ ${state.baudRate} baud 8N1!`, 'system');

      // Initialize reader and writer
      const textDecoder = new TextDecoderStream();
      state.port.readable.pipeTo(textDecoder.writable);
      state.reader = textDecoder.readable.getReader();

      const textEncoder = new TextEncoderStream();
      textEncoder.readable.pipeTo(state.port.writable);
      state.writer = textEncoder.writable.getWriter();

      // Start asynchronous read loop
      readSerialLoop();

      // Send a guide query to receive current board status
      setTimeout(() => sendSerialChar('?'), 300);

    } catch (err) {
      console.error('Serial connection error:', err);
      logTerminal(`Connection failed: ${err.message || err}`, 'error');
      disconnectSerial();
    }
  }

  async function disconnectSerial() {
    state.isConnected = false;
    updateConnectionUI(false);

    try {
      if (state.reader) {
        await state.reader.cancel();
        state.reader.releaseLock();
        state.reader = null;
      }
      if (state.writer) {
        await state.writer.close();
        state.writer.releaseLock();
        state.writer = null;
      }
      if (state.port) {
        await state.port.close();
        state.port = null;
      }
    } catch (err) {
      console.warn('Error during disconnect:', err);
    }

    logTerminal('Disconnected from hardware serial port.', 'system');
  }

  function updateConnectionUI(connected) {
    if (connected) {
      dom.statusIndicator.className = 'status-indicator connected';
      dom.statusLabel.textContent = 'CONNECTED';
      dom.btnConnect.classList.add('btn-disconnect');
      dom.btnConnectText.textContent = 'Disconnect';
    } else {
      dom.statusIndicator.className = 'status-indicator disconnected';
      dom.statusLabel.textContent = 'DISCONNECTED';
      dom.btnConnect.classList.remove('btn-disconnect');
      dom.btnConnectText.textContent = 'Connect Board';
    }
  }

  // --------------------------------------------------------------------------
  // Serial Transmission (TX)
  // --------------------------------------------------------------------------

  async function sendSerialChar(char) {
    if (!state.isConnected || !state.writer) {
      // Simulate local acoustic preview if board is not physically connected
      handleVirtualNote(char);
      return;
    }

    try {
      await state.writer.write(char);
    } catch (err) {
      console.error('Failed to write char to serial:', err);
      logTerminal(`Write error: ${err.message}`, 'error');
    }
  }

  async function sendSerialString(str) {
    if (!state.isConnected || !state.writer) return;
    try {
      await state.writer.write(str);
    } catch (err) {
      console.error('Failed to write string to serial:', err);
    }
  }

  // --------------------------------------------------------------------------
  // Serial Reception & Telemetry Parser (RX)
  // --------------------------------------------------------------------------

  let rxBuffer = '';

  async function readSerialLoop() {
    while (state.isConnected && state.reader) {
      try {
        const { value, done } = await state.reader.read();
        if (done) break;
        if (value) {
          handleIncomingData(value);
        }
      } catch (err) {
        console.error('Read loop error:', err);
        break;
      }
    }
    if (state.isConnected) {
      disconnectSerial();
    }
  }

  function handleIncomingData(chunk) {
    rxBuffer += chunk;
    const lines = rxBuffer.split(/\r?\n/);
    rxBuffer = lines.pop(); // Keep last incomplete line in buffer

    for (const line of lines) {
      if (!line.trim()) continue;
      parseTelemetryLine(line);
      logTerminal(line);
    }
  }

  function stripAnsi(text) {
    return text.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '');
  }

  function parseTelemetryLine(rawLine) {
    const clean = stripAnsi(rawLine).trim();

    // 1. Initial State Banner: [OCT: 4] [CH: Pulse 1] [VOL: 12] [DUTY: 50.0%] [DRUM DIST: WarmSat]
    const stateMatch = clean.match(/\[OCT:\s*(\d+)\]\s*\[CH:\s*(.*?)\]\s*\[VOL:\s*(\d+)\]\s*\[DUTY:\s*(.*?)\]/i);
    if (stateMatch) {
      updateOctave(parseInt(stateMatch[1], 10));
      updateChannelByName(stateMatch[2]);
      updateVolume(parseInt(stateMatch[3], 10));
    }

    // 2. Volume Update: [VOL] [###########----] 11/15
    const volMatch = clean.match(/\[VOL\]\s*\[.*?\]\s*(\d+)\/15/);
    if (volMatch) {
      updateVolume(parseInt(volMatch[1], 10));
    }

    // 3. Octave Update: [OCTAVE] >> Octave UP/DOWN: 5
    const octMatch = clean.match(/\[OCTAVE\]\s*>>\s*Octave\s*(?:UP|DOWN):\s*(\d+)/i);
    if (octMatch) {
      updateOctave(parseInt(octMatch[1], 10));
    }

    // 4. Channel Selection: [SWITCH] >> Selected Pulse 1 (Lead)
    const chMatch = clean.match(/\[SWITCH\]\s*>>\s*Selected\s*([A-Za-z0-9\s]+)/i);
    if (chMatch) {
      updateChannelByName(chMatch[1]);
    }

    // 5. Duty Cycle: [CTRL] >> Duty Cycle set to: 25.0%
    const dutyMatch = clean.match(/\[CTRL\]\s*>>\s*Duty Cycle set to:\s*([0-9\.]+%)/i);
    if (dutyMatch) {
      updateDutyByLabel(dutyMatch[1]);
    }

    // 6. Barrel Distortion: [DISTORTION] >> Barrel Distortion set to: Level 2/3 (Metallic Fuzz)
    const distMatch = clean.match(/\[DISTORTION\]\s*>>.*?Level\s*(\d+)\/3\s*\((.*?)\)/i);
    if (distMatch) {
      state.barrelDistortion = parseInt(distMatch[1], 10);
      dom.distModeName.textContent = distMatch[2];
    }

    // 7. Jukebox Playback: [JUKEBOX] >> Playing 'BlasNESmous Theme'
    if (clean.includes('[JUKEBOX] >> Playing')) {
      dom.jukeboxState.textContent = 'PLAYING';
      dom.jukeboxState.style.color = 'var(--arcade-cyan)';
    } else if (clean.includes('[JUKEBOX] Done!') || clean.includes('[MUTE]')) {
      dom.jukeboxState.textContent = 'IDLE';
      dom.jukeboxState.style.color = 'var(--emerald)';
      resetJukeboxButtons();
    }

    // 8. Note Playback Telemetry: -> C4 (261 Hz)
    const noteMatch = clean.match(/->\s*([A-G][#\-]?\d*)\s*\((\d+)\s*Hz\)/);
    if (noteMatch) {
      state.activeFreq = parseInt(noteMatch[2], 10);
      dom.freqTag.textContent = `${noteMatch[1]} (${state.activeFreq} Hz)`;
      state.isSoundActive = true;
      triggerVisualizerBurst();
    }

    // 9. Hardware Mixed Sample Peak
    const sampleMatch = clean.match(/Hardware Mixed Sample:\s*(-?\d+)/);
    if (sampleMatch) {
      state.lastSampleVal = parseInt(sampleMatch[1], 10);
      dom.sampleTag.textContent = `Mixed Peak: ${state.lastSampleVal >= 0 ? '+' : ''}${state.lastSampleVal}`;
    }
  }

  // --------------------------------------------------------------------------
  // State Synchronization Functions
  // --------------------------------------------------------------------------

  function updateVolume(vol) {
    state.currentVol = Math.max(0, Math.min(15, vol));
    dom.sliderVolume.value = state.currentVol;
    dom.valVolume.textContent = `${state.currentVol} / 15`;
    dom.badgeVol.textContent = `VOL: ${state.currentVol}/15`;
  }

  function updateOctave(oct) {
    state.currentOctave = Math.max(2, Math.min(6, oct));
    dom.sliderOctave.value = state.currentOctave;
    dom.valOctave.textContent = `Octave ${state.currentOctave}`;
    dom.badgeOctave.textContent = `OCTAVE: ${state.currentOctave}`;

    // Update piano key labels (C4..C5 dynamically reflects current octave)
    updatePianoLabels();
  }

  function updatePianoLabels() {
    dom.pianoKeys.forEach(k => {
      const semitone = parseInt(k.dataset.note, 10);
      const octOffset = parseInt(k.dataset.octOff, 10);
      const oct = state.currentOctave + octOffset;
      const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
      const displayName = `${noteNames[semitone]}${oct}`;
      k.querySelector('.key-name').textContent = displayName;
    });
  }

  function updateChannel(idx) {
    state.currentChannel = idx;
    dom.channelButtons.forEach(btn => {
      btn.classList.toggle('active', parseInt(btn.dataset.channel, 10) === idx);
    });
    dom.badgeChannel.textContent = `CH: ${CHANNEL_NAMES[idx].toUpperCase()}`;

    // Map wave type for oscilloscope
    if (idx === 0 || idx === 1) state.activeWaveType = 'pulse';
    else if (idx === 2) state.activeWaveType = 'triangle';
    else state.activeWaveType = 'noise';
  }

  function updateChannelByName(name) {
    const lower = name.toLowerCase();
    if (lower.includes('pulse 1')) updateChannel(0);
    else if (lower.includes('pulse 2')) updateChannel(1);
    else if (lower.includes('triangle')) updateChannel(2);
    else if (lower.includes('noise')) updateChannel(3);
  }

  function updateDuty(idx) {
    state.currentDuty = idx;
    state.activeDutyRatio = DUTY_RATIOS[idx];
    dom.dutyButtons.forEach(btn => {
      btn.classList.toggle('active', parseInt(btn.dataset.duty, 10) === idx);
    });
    dom.badgeDuty.textContent = `DUTY: ${DUTY_LABELS[idx]}`;
  }

  function updateDutyByLabel(label) {
    for (let i = 0; i < DUTY_LABELS.length; i++) {
      if (DUTY_LABELS[i].startsWith(label.replace('%', ''))) {
        updateDuty(i);
        break;
      }
    }
  }

  function resetJukeboxButtons() {
    dom.jukeboxPlayButtons.forEach(btn => {
      btn.classList.remove('playing');
      const key = btn.dataset.key;
      btn.querySelector('span').textContent = `▶ Play [${key}]`;
    });
    state.jukeboxPlaying = null;
  }

  // --------------------------------------------------------------------------
  // Virtual / Local Note Audio & Visualizer Feedback
  // --------------------------------------------------------------------------

  function handleVirtualNote(char) {
    const keyElem = document.querySelector(`.piano-key[data-char="${char.toLowerCase()}"]`);
    if (keyElem) {
      const semitone = parseInt(keyElem.dataset.note, 10);
      const octOffset = parseInt(keyElem.dataset.octOff, 10);
      const targetOctave = state.currentOctave + octOffset;
      const freq = BASE_FREQS[semitone] * Math.pow(2, targetOctave - 4);

      state.activeFreq = Math.round(freq);
      dom.freqTag.textContent = `${keyElem.querySelector('.key-name').textContent} (${state.activeFreq} Hz)`;
      state.isSoundActive = true;
      triggerVisualizerBurst();
    }
  }

  // --------------------------------------------------------------------------
  // UI Terminal Logger
  // --------------------------------------------------------------------------

  function logTerminal(text, type = '') {
    const line = document.createElement('div');
    line.className = 'terminal-line';

    const clean = stripAnsi(text);

    if (type === 'system' || clean.startsWith('==') || clean.startsWith('--')) {
      line.classList.add('system');
    } else if (clean.includes('[SFX]') || clean.includes('[DRUM]')) {
      line.classList.add('sfx');
    } else if (clean.includes('[JUKEBOX]')) {
      line.classList.add('jukebox');
    } else if (clean.includes('PASS')) {
      line.classList.add('test-pass');
    } else if (clean.includes('FAIL') || clean.includes('[ERROR]') || type === 'error') {
      line.classList.add('error');
    }

    line.textContent = clean;
    dom.terminalScreen.appendChild(line);

    // Limit screen lines to keep rendering fast
    if (dom.terminalScreen.childNodes.length > 350) {
      dom.terminalScreen.removeChild(dom.terminalScreen.firstChild);
    }

    // Auto-scroll to bottom
    dom.terminalScreen.scrollTop = dom.terminalScreen.scrollHeight;
  }

  // --------------------------------------------------------------------------
  // HTML5 Canvas Oscilloscope Visualizer
  // --------------------------------------------------------------------------

  const ctx = dom.scopeCanvas.getContext('2d');
  let animId = null;
  let wavePhase = 0;
  let waveDecay = 0;

  function triggerVisualizerBurst() {
    waveDecay = 1.0;
  }

  function drawOscilloscope() {
    const w = dom.scopeCanvas.width;
    const h = dom.scopeCanvas.height;
    const midY = h / 2;

    ctx.fillStyle = 'rgba(6, 8, 13, 0.35)';
    ctx.fillRect(0, 0, w, h);

    // Grid lines
    ctx.strokeStyle = 'rgba(0, 240, 255, 0.07)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, midY);
    ctx.lineTo(w, midY);
    ctx.stroke();

    // Wave color based on active channel
    let waveColor = 'var(--ch-pulse1)';
    if (state.currentChannel === 0) waveColor = '#00f0ff';
    else if (state.currentChannel === 1) waveColor = '#00b4d8';
    else if (state.currentChannel === 2) waveColor = '#00ff88';
    else waveColor = '#ffd700';

    ctx.strokeStyle = waveColor;
    ctx.lineWidth = 2.5;
    ctx.shadowBlur = 10;
    ctx.shadowColor = waveColor;

    ctx.beginPath();

    const freqFactor = (state.activeFreq / 440) * 0.05;
    const amplitude = (h * 0.38) * (state.currentVol / 15) * (0.3 + waveDecay * 0.7);

    for (let x = 0; x < w; x++) {
      const t = x * freqFactor + wavePhase;
      let y = 0;

      if (state.activeWaveType === 'pulse') {
        const cycle = t % 1;
        y = (cycle < state.activeDutyRatio) ? -amplitude : amplitude;
      } else if (state.activeWaveType === 'triangle') {
        const cycle = (t % 1);
        y = (cycle < 0.5) ? (-amplitude + 4 * amplitude * cycle) : (3 * amplitude - 4 * amplitude * cycle);
      } else {
        // Noise
        y = (Math.random() * 2 - 1) * amplitude;
      }

      if (x === 0) ctx.moveTo(x, midY + y);
      else ctx.lineTo(x, midY + y);
    }

    ctx.stroke();
    ctx.shadowBlur = 0;

    wavePhase += 0.08;
    if (waveDecay > 0.1) waveDecay *= 0.96;

    animId = requestAnimationFrame(drawOscilloscope);
  }

  // --------------------------------------------------------------------------
  // Event Listeners & Hardware Action Dispatchers
  // --------------------------------------------------------------------------

  function setupEventListeners() {
    // 1. Connection Toggle
    dom.btnConnect.addEventListener('click', () => {
      if (state.isConnected) {
        disconnectSerial();
      } else {
        connectSerial();
      }
    });

    // 2. Channel Selector Buttons
    dom.channelButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const key = btn.dataset.key;
        sendSerialChar(key);
        updateChannel(parseInt(btn.dataset.channel, 10));
      });
    });

    // 3. Duty Cycle Buttons
    dom.dutyButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        sendSerialChar('q');
        updateDuty(parseInt(btn.dataset.duty, 10));
      });
    });

    // 4. Volume Slider
    dom.sliderVolume.addEventListener('input', (e) => {
      const targetVol = parseInt(e.target.value, 10);
      const diff = targetVol - state.currentVol;
      if (diff > 0) {
        for (let i = 0; i < diff; i++) sendSerialChar('+');
      } else if (diff < 0) {
        for (let i = 0; i < -diff; i++) sendSerialChar('-');
      }
      updateVolume(targetVol);
    });

    // 5. Octave Steppers & Slider
    dom.btnOctaveDown.addEventListener('click', () => {
      sendSerialChar(',');
      updateOctave(state.currentOctave - 1);
    });

    dom.btnOctaveUp.addEventListener('click', () => {
      sendSerialChar('.');
      updateOctave(state.currentOctave + 1);
    });

    dom.sliderOctave.addEventListener('input', (e) => {
      const targetOct = parseInt(e.target.value, 10);
      const diff = targetOct - state.currentOctave;
      if (diff > 0) {
        for (let i = 0; i < diff; i++) sendSerialChar('.');
      } else if (diff < 0) {
        for (let i = 0; i < -diff; i++) sendSerialChar(',');
      }
      updateOctave(targetOct);
    });

    // 6. Mute Button
    dom.btnMute.addEventListener('click', () => {
      sendSerialChar(' ');
      logTerminal('[MUTE] >> Audio muted.', 'system');
    });

    // 7. Piano Key Clicks
    dom.pianoKeys.forEach(k => {
      const char = k.dataset.char;
      k.addEventListener('mousedown', () => {
        k.classList.add('active');
        sendSerialChar(char);
      });
      k.addEventListener('mouseup', () => k.classList.remove('active'));
      k.addEventListener('mouseleave', () => k.classList.remove('active'));
    });

    // 8. Soundboard Pads
    dom.soundboardButtons.forEach(pad => {
      const key = pad.dataset.key;
      pad.addEventListener('click', () => {
        pad.classList.add('active');
        setTimeout(() => pad.classList.remove('active'), 200);
        sendSerialChar(key);
      });
    });

    // 9. Jukebox Tracks
    dom.jukeboxPlayButtons.forEach(btn => {
      const key = btn.dataset.key;
      btn.addEventListener('click', () => {
        if (btn.classList.contains('playing')) {
          // Stop playback by sending Space / Mute
          sendSerialChar(' ');
          btn.classList.remove('playing');
          btn.querySelector('span').textContent = `▶ Play [${key}]`;
        } else {
          resetJukeboxButtons();
          btn.classList.add('playing');
          btn.querySelector('span').textContent = `⏹ Stop [${key}]`;
          sendSerialChar(key);
        }
      });
    });

    // 10. Terminal Tools
    dom.btnDumpRegs.addEventListener('click', () => sendSerialChar('r'));
    dom.btnSelfTest.addEventListener('click', () => sendSerialChar('*'));
    dom.btnClearTerm.addEventListener('click', () => {
      dom.terminalScreen.innerHTML = '';
      logTerminal('Terminal cleared.', 'system');
    });
    dom.btnHelpGuide.addEventListener('click', () => sendSerialChar('?'));

    // 11. Physical Keyboard Event Binding
    window.addEventListener('keydown', handlePhysicalKeyDown);
    window.addEventListener('keyup', handlePhysicalKeyUp);
  }

  // --------------------------------------------------------------------------
  // Keyboard Handler (QWERTZ & QWERTY Chromatic Mapping)
  // --------------------------------------------------------------------------

  function handlePhysicalKeyDown(e) {
    // Ignore keystrokes when typing inside an input or select
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;

    const key = e.key;

    // Arrow Keys
    if (key === 'ArrowUp') {
      e.preventDefault();
      sendSerialChar('+');
      updateVolume(state.currentVol + 1);
      return;
    } else if (key === 'ArrowDown') {
      e.preventDefault();
      sendSerialChar('-');
      updateVolume(state.currentVol - 1);
      return;
    } else if (key === 'ArrowRight') {
      e.preventDefault();
      sendSerialChar('.');
      updateOctave(state.currentOctave + 1);
      return;
    } else if (key === 'ArrowLeft') {
      e.preventDefault();
      sendSerialChar(',');
      updateOctave(state.currentOctave - 1);
      return;
    }

    // Spacebar (Mute)
    if (key === ' ') {
      e.preventDefault();
      sendSerialChar(' ');
      return;
    }

    const lowerKey = key.toLowerCase();

    // Check Piano Keys
    const pianoKey = document.querySelector(`.piano-key[data-char="${lowerKey}"]`);
    if (pianoKey) {
      pianoKey.classList.add('active');
      sendSerialChar(lowerKey);
      return;
    }

    // Channel Selection: 1, 2, 3, 4
    if (['1', '2', '3', '4'].includes(key)) {
      sendSerialChar(key);
      updateChannel(parseInt(key, 10) - 1);
      return;
    }

    // Soundboard: c, b, l, x, v, n, i, 0, d
    if (['c', 'b', 'l', 'x', 'v', 'n', 'i', '0', 'd', '8', '9'].includes(lowerKey)) {
      const pad = document.querySelector(`.pad-btn[data-key="${lowerKey}"]`);
      if (pad) {
        pad.classList.add('active');
        setTimeout(() => pad.classList.remove('active'), 180);
      }
      sendSerialChar(lowerKey);
      return;
    }

    // Jukebox: 5, 6, 7
    if (['5', '6', '7'].includes(key)) {
      sendSerialChar(key);
      return;
    }

    // Controls: q, m, r, *, ?
    if (['q', 'm', 'r', '*', '?'].includes(lowerKey)) {
      sendSerialChar(lowerKey);
    }
  }

  function handlePhysicalKeyUp(e) {
    const lowerKey = e.key.toLowerCase();
    const pianoKey = document.querySelector(`.piano-key[data-char="${lowerKey}"]`);
    if (pianoKey) {
      pianoKey.classList.remove('active');
    }
  }

  // --------------------------------------------------------------------------
  // Initialization
  // --------------------------------------------------------------------------

  function init() {
    checkWebSerialSupport();
    setupEventListeners();
    updateOctave(4);
    updateVolume(12);
    updateChannel(0);
    updateDuty(2);
    drawOscilloscope();
  }

  // Boot on DOM content loaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
