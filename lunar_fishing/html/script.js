// Minigame de pesca estilo Stardew Valley para o lunar_fishing
// A física usa as mesmas unidades do jogo original (trilho de 568 unidades, 60 ticks/s).

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'lunar_fishing';

const root = document.getElementById('minigame');
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
const resultEl = document.getElementById('result');
const hintEl = document.getElementById('hint');
let hintTimer = null;
ctx.imageSmoothingEnabled = false;

const W = canvas.width;   // 46
const H = canvas.height;  // 164

// ---------- Layout (pixels lógicos) ----------
const L = {
    bubble: { x: 3, y: 0, w: 43, h: 164 },
    rodX: 6,
    reel: { x: 9, y: 150, r: 4 },
    bamboo: { x: 12, y: 3, w: 22, h: 158 },
    water: { x: 15, y: 6, w: 16, h: 152 },
    prog: { x: 35, y: 3, w: 7, h: 158 },
    progInner: { x: 37, y: 6, w: 3, h: 152 },
};

// ---------- Constantes do Stardew ----------
const TRACK = 568;      // altura do trilho
const FISH_SIZE = 24;   // "altura" do peixe em unidades
const FISH_MAX = TRACK - FISH_SIZE;
const K = L.water.h / TRACK; // unidades -> pixels

const BEHAVIORS = { mixed: 0, dart: 1, smooth: 2, sinker: 3, floater: 4 };

// ---------- Estado ----------
let state = null;
let holding = false;
let rafId = null;
let lastTime = 0;
let acc = 0;
let soundOn = true;

const rand = (min, max) => Math.random() * (max - min) + min;
const randInt = (min, max) => Math.floor(Math.random() * (max - min)) + min; // [min, max)
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ---------- Áudio (sintetizado, sem arquivos) ----------
let audio = null;
function beep(freq, dur, type = 'square', vol = 0.04, slide = 0) {
    if (!soundOn) return;
    try {
        audio = audio || new (window.AudioContext || window.webkitAudioContext)();
        const o = audio.createOscillator();
        const g = audio.createGain();
        o.type = type;
        o.frequency.setValueAtTime(freq, audio.currentTime);
        if (slide) o.frequency.linearRampToValueAtTime(freq + slide, audio.currentTime + dur);
        g.gain.setValueAtTime(vol, audio.currentTime);
        g.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + dur);
        o.connect(g).connect(audio.destination);
        o.start();
        o.stop(audio.currentTime + dur);
    } catch (e) { /* sem áudio */ }
}

// ---------- Cores ----------
function hexToRgb(hex) {
    const h = hex.replace('#', '');
    return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
}
function shade([r, g, b], f) {
    const c = (v) => clamp(Math.round(f < 0 ? v * (1 + f) : v + (255 - v) * f), 0, 255);
    return `rgb(${c(r)},${c(g)},${c(b)})`;
}

// ---------- Desenho em pixel ----------
function px(x, y, w, h, color) {
    ctx.fillStyle = color;
    ctx.fillRect(Math.round(x), Math.round(y), w, h);
}

function pixelCircle(cx, cy, r, color) {
    ctx.fillStyle = color;
    for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
            if (dx * dx + dy * dy <= r * r + r * 0.6) ctx.fillRect(cx + dx, cy + dy, 1, 1);
        }
    }
}

const FISH_SPRITE = [
    '...DDD....',
    '..DBBBD...',
    '.DEBBBBD.D',
    'DBBBBBBBDD',
    '.DLLLLLD.D',
    '..DLLLD...',
    '...DDD....',
];

function drawFish(x, y, rgb) {
    const colors = {
        D: shade(rgb, -0.55),
        B: shade(rgb, 0),
        L: shade(rgb, 0.45),
        E: '#111',
    };
    for (let r = 0; r < FISH_SPRITE.length; r++) {
        const row = FISH_SPRITE[r];
        for (let c = 0; c < row.length; c++) {
            const ch = row[c];
            if (ch === '.') continue;
            px(x + c, y + r, 1, 1, colors[ch]);
        }
    }
}

function drawBubble() {
    const { x, y, w, h } = L.bubble;
    // contorno externo
    px(x + 2, y, w - 4, h, '#7a4f2a');
    px(x, y + 2, w, h - 4, '#7a4f2a');
    px(x + 1, y + 1, w - 2, h - 2, '#7a4f2a');
    // preenchimento
    px(x + 2, y + 1, w - 4, h - 2, '#f6e3bd');
    px(x + 1, y + 2, w - 2, h - 4, '#f6e3bd');
    // brilho / sombra interna
    px(x + 2, y + 1, w - 4, 1, '#fff4d9');
    px(x + 2, y + h - 2, w - 4, 1, '#d9b47c');
    // ponteiro do balão (esquerda)
    const py = 76;
    px(0, py + 4, 1, 3, '#7a4f2a');
    px(1, py + 2, 1, 7, '#7a4f2a');
    px(2, py + 1, 1, 9, '#7a4f2a');
    px(2, py + 3, 1, 5, '#f6e3bd');
    px(1, py + 5, 1, 1, '#f6e3bd');
    px(3, py + 2, 1, 7, '#f6e3bd');
}

function drawRod(reelAngle) {
    const x = L.rodX;
    // vara
    px(x, 6, 2, 140, '#4b4b5c');
    px(x, 6, 1, 140, '#8f8fa6');
    // passadores
    for (let gy = 16; gy < 140; gy += 26) {
        px(x - 1, gy, 4, 1, '#3a3a48');
        px(x - 1, gy + 1, 1, 1, '#c9c9d8');
        px(x + 2, gy + 1, 1, 1, '#c9c9d8');
    }
    // cabo de cortiça
    px(x - 1, 138, 4, 8, '#a8693a');
    px(x - 1, 138, 1, 8, '#d49a5c');
    for (let cy = 139; cy < 146; cy += 2) px(x, cy, 2, 1, '#8a5229');

    // molinete
    const { x: rx, y: ry, r } = L.reel;
    pixelCircle(rx, ry, r, '#5c3417');
    pixelCircle(rx, ry, r - 1, '#c27c3d');
    pixelCircle(rx, ry, r - 2, '#e0a25e');
    px(rx, ry, 1, 1, '#5c3417');
    // manivela girando
    const hx = rx + Math.round(Math.cos(reelAngle) * (r + 1));
    const hy = ry + Math.round(Math.sin(reelAngle) * (r + 1));
    ctx.strokeStyle = '#3a2210';
    px(hx, hy, 2, 2, '#3a2210');
    px(hx, hy, 1, 1, '#f0c27a');
}

function drawBamboo(x, y, w, h) {
    const dark = '#6b3f17', mid = '#b8743a', light = '#e5ab64', node = '#8a5224';
    px(x, y, w, h, dark);
    px(x + 1, y + 1, w - 2, h - 2, mid);
    // brilhos verticais
    px(x + 1, y + 1, 1, h - 2, light);
    // nós do bambu
    for (let ny = y + 14; ny < y + h - 6; ny += 24) {
        px(x, ny, w, 2, node);
        px(x + 1, ny, w - 2, 1, light);
    }
}

function drawFrame() {
    const b = L.bamboo;
    // colunas de bambu
    drawBamboo(b.x, b.y, 3, b.h);
    drawBamboo(b.x + b.w - 3, b.y, 3, b.h);
    drawBamboo(b.x, b.y, b.w, 3);
    drawBamboo(b.x, b.y + b.h - 3, b.w, 3);

    // barra de progresso
    const p = L.prog;
    drawBamboo(p.x, p.y, p.w, p.h);
    px(L.progInner.x - 1, L.progInner.y - 1, L.progInner.w + 2, L.progInner.h + 2, '#3d2410');
}

const WATER_BANDS = ['#a9d3ff', '#94c4fb', '#7fb3f4', '#6aa1ec', '#5890e3', '#477ed8', '#3a6dcb', '#2f5dbd'];

function drawWater(t) {
    const w = L.water;
    const bandH = Math.ceil(w.h / WATER_BANDS.length);
    for (let i = 0; i < WATER_BANDS.length; i++) {
        const y = w.y + i * bandH;
        px(w.x, y, w.w, Math.min(bandH, w.y + w.h - y), WATER_BANDS[i]);
    }
    // brilho na lateral
    px(w.x, w.y, 1, w.h, 'rgba(255,255,255,0.18)');

    // algas no fundo
    const sway = Math.round(Math.sin(t / 380));
    const baseY = w.y + w.h;
    const weeds = [[w.x + 2, 6], [w.x + 4, 9], [w.x + 6, 5], [w.x + 11, 8], [w.x + 13, 5]];
    for (const [wx, wh] of weeds) {
        for (let i = 0; i < wh; i++) {
            const off = i > wh / 2 ? sway : 0;
            px(wx + off, baseY - 1 - i, 1, 1, i % 3 === 0 ? '#2e8b3a' : '#43b04c');
        }
    }

    // bolhas
    for (const bub of state.bubbles) {
        px(w.x + bub.x, w.y + bub.y, 1, 1, 'rgba(230,245,255,0.85)');
    }
}

function drawCatchBar(inBar) {
    const w = L.water;
    const y = w.y + state.barPos * K;
    const h = Math.max(4, Math.round(state.barH * K));
    const x = w.x + 1;
    const bw = w.w - 2;
    const alpha = inBar ? 0.95 : 0.6;
    ctx.globalAlpha = alpha;
    px(x, y, bw, h, '#5fd35a');
    px(x, y, bw, 1, '#c8ffb8');
    px(x, y + 1, bw, 1, '#9cf28c');
    px(x, y + h - 1, bw, 1, '#2f8f2c');
    px(x, y, 1, h, '#9cf28c');
    px(x + bw - 1, y, 1, h, '#3aa536');
    ctx.globalAlpha = 1;
}

function progressColor(p) {
    // vermelho -> laranja -> amarelo -> verde (igual ao Stardew)
    const hue = Math.round(clamp(p, 0, 1) * 120);
    return `hsl(${hue}, 85%, 50%)`;
}

function drawProgress() {
    const pi = L.progInner;
    const fill = Math.round(state.progress * pi.h);
    px(pi.x, pi.y, pi.w, pi.h, '#2a1a0c');
    if (fill > 0) {
        px(pi.x, pi.y + pi.h - fill, pi.w, fill, progressColor(state.progress));
        px(pi.x, pi.y + pi.h - fill, 1, fill, 'rgba(255,255,255,0.35)');
    }
}

function render(t) {
    ctx.clearRect(0, 0, W, H);
    const inBar = state.inBar;

    drawBubble();
    drawRod(state.reelAngle);
    drawFrame();
    drawWater(t);
    drawCatchBar(inBar);

    // peixe
    const fx = L.water.x + 3 + (inBar ? randInt(-1, 2) : 0);
    const fy = L.water.y + state.fishPos * K + (inBar ? randInt(-1, 2) : 0) - 0.5;
    drawFish(fx, Math.round(fy), state.color);

    drawProgress();

    hintEl.classList.toggle('pressed', holding);
}

// ---------- Física ----------
function tick() {
    const s = state;
    const d = s.difficulty;
    const m = s.motion;

    // ===== movimento do peixe =====
    if (Math.random() < (d * (m !== 2 ? 1 : 20)) / 4000 && (m !== 2 || s.target === -1)) {
        const spaceBelow = FISH_MAX - s.fishPos;
        const spaceAbove = s.fishPos;
        const percent = Math.min(99, d + randInt(10, 45)) / 100;
        s.target = s.fishPos + randInt(-Math.floor(spaceAbove), Math.floor(spaceBelow)) * percent;
    }

    if (m === 4) s.floatAcc = Math.max(s.floatAcc - 0.01, -1.5);       // floater sobe
    else if (m === 3) s.floatAcc = Math.min(s.floatAcc + 0.01, 1.5);   // sinker afunda

    if (Math.abs(s.fishPos - s.target) > 3 && s.target !== -1) {
        const accel = (s.target - s.fishPos) / (randInt(10, 30) + (100 - Math.min(100, d)));
        s.fishSpeed += (accel - s.fishSpeed) / 5;
    } else if (m !== 2 && Math.random() < d / 2000) {
        s.target = s.fishPos + (Math.random() < 0.5 ? randInt(-100, -51) : randInt(50, 101));
    } else {
        s.target = -1;
    }

    if (m === 1 && Math.random() < d / 1000) {
        s.target = s.fishPos + (Math.random() < 0.5 ? randInt(-100 - d * 2, -51) : randInt(50, 101 + d * 2));
    }

    s.target = clamp(s.target, -1, FISH_MAX);
    s.fishPos += s.fishSpeed + s.floatAcc;
    if (s.fishPos > FISH_MAX) { s.fishPos = FISH_MAX; s.fishSpeed = 0; }
    if (s.fishPos < 0) { s.fishPos = 0; s.fishSpeed = 0; }

    // ===== barra verde =====
    const fishCenter = s.fishPos + FISH_SIZE / 2;
    s.inBar = fishCenter >= s.barPos && fishCenter <= s.barPos + s.barH;

    let gravity = holding ? -0.25 : 0.25;
    if (holding && (s.barPos === 0 || s.barPos === TRACK - s.barH)) {
        s.barSpeed = 0;
    }
    if (s.inBar) gravity *= 0.6;

    s.barSpeed += gravity;
    s.barPos += s.barSpeed;

    if (s.barPos + s.barH > TRACK) {
        s.barPos = TRACK - s.barH;
        s.barSpeed = -s.barSpeed * 2 / 3;
        if (Math.abs(s.barSpeed) < 0.3) s.barSpeed = 0;
    } else if (s.barPos < 0) {
        s.barPos = 0;
        s.barSpeed = -s.barSpeed * 2 / 3;
        if (Math.abs(s.barSpeed) < 0.3) s.barSpeed = 0;
    }

    // ===== progresso =====
    if (s.inBar) {
        s.progress += s.gainRate;
        s.reelAngle += 0.35;
        if (++s.reelTick % 7 === 0) beep(1300, 0.03, 'square', 0.025);
    } else {
        s.progress -= s.lossRate;
        s.perfect = false;
        s.reelAngle -= 0.08;
    }
    s.progress = clamp(s.progress, 0, 1);

    // ===== bolhas =====
    if (Math.random() < 0.06) s.bubbles.push({ x: randInt(2, L.water.w - 2), y: L.water.h - 2, speed: rand(0.15, 0.4) });
    for (const b of s.bubbles) {
        b.y -= b.speed;
        if (Math.random() < 0.1) b.x = clamp(b.x + randInt(-1, 2), 1, L.water.w - 2);
    }
    s.bubbles = s.bubbles.filter((b) => b.y > 1);

    if (s.progress >= 1) return finish(true);
    if (s.progress <= 0) return finish(false);
}

function loop(now) {
    if (!state || state.over) return;
    if (!lastTime) lastTime = now;
    acc += Math.min(100, now - lastTime);
    lastTime = now;

    const step = 1000 / 60;
    while (acc >= step && state && !state.over) {
        if (state.started) tick();
        acc -= step;
    }
    if (state) render(now);
    if (state && !state.over) rafId = requestAnimationFrame(loop);
}

// ---------- Ciclo do minigame ----------
function start(data) {
    soundOn = data.sound !== false;
    const barH = clamp(Number(data.barSize) || 96, 40, 400);
    const motion = BEHAVIORS[data.behavior] ?? 0;

    state = {
        difficulty: clamp(Number(data.difficulty) || 30, 1, 120),
        motion,
        color: hexToRgb(data.color || '#e8913a'),
        barH,
        barPos: TRACK - barH,
        barSpeed: 0,
        fishPos: FISH_MAX - 20,
        fishSpeed: 0,
        target: -1,
        floatAcc: 0,
        progress: clamp(Number(data.startProgress) || 0.3, 0.05, 0.95),
        gainRate: Number(data.gainRate) || 0.002,
        lossRate: Number(data.lossRate) || 0.003,
        inBar: false,
        perfect: true,
        reelAngle: 0,
        reelTick: 0,
        bubbles: [],
        started: false,
        over: false,
    };

    holding = false;
    root.style.setProperty('--pos-x', (data.posX ?? 62) + '%');
    root.style.setProperty('--pos-y', (data.posY ?? 50) + '%');

    const maxScale = (window.innerHeight * 0.8 - (data.hint === false ? 0 : 110)) / H;
    const scale = Math.min(Number(data.scale) || 3.6, maxScale);
    canvas.style.width = Math.round(W * scale) + 'px';
    canvas.style.height = Math.round(H * scale) + 'px';
    resultEl.className = '';
    resultEl.textContent = '';
    hintEl.style.display = data.hint === false ? 'none' : '';
    hintEl.classList.remove('faded', 'pressed');
    clearTimeout(hintTimer);
    hintTimer = setTimeout(() => hintEl.classList.add('faded'), 5000);
    root.classList.remove('hidden');

    beep(520, 0.12, 'square', 0.05, 380);
    setTimeout(() => { if (state) state.started = true; }, 350);

    lastTime = 0;
    acc = 0;
    cancelAnimationFrame(rafId);
    rafId = requestAnimationFrame(loop);
}

function finish(success) {
    if (!state || state.over) return;
    state.over = true;
    const perfect = success && state.perfect;
    render(performance.now());

    if (success) {
        resultEl.textContent = perfect ? 'PERFEITO!' : 'FISGOU!';
        resultEl.className = 'show ' + (perfect ? 'perfect' : 'win');
        beep(660, 0.1, 'square', 0.05);
        setTimeout(() => beep(880, 0.1, 'square', 0.05), 100);
        setTimeout(() => beep(1320, 0.18, 'square', 0.05), 200);
    } else {
        resultEl.textContent = 'ESCAPOU...';
        resultEl.className = 'show lose';
        root.classList.add('shake');
        beep(300, 0.35, 'sawtooth', 0.04, -180);
    }

    setTimeout(() => {
        hide();
        fetch(`https://${RESOURCE}/minigameEnd`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ success, perfect }),
        }).catch(() => {});
    }, 900);
}

function hide() {
    cancelAnimationFrame(rafId);
    root.classList.add('hidden');
    root.classList.remove('shake');
    resultEl.className = '';
    state = null;
    holding = false;
}

window.addEventListener('message', (e) => {
    const data = e.data || {};
    switch (data.action) {
        case 'start': start(data); break;
        case 'input': holding = !!data.holding; break;
        case 'stop': hide(); break;
    }
});

// Teste no navegador: abra html/index.html e use ?test
if (location.search.includes('test')) {
    document.body.style.background = '#2b3a2b';
    window.addEventListener('mousedown', () => (holding = true));
    window.addEventListener('mouseup', () => (holding = false));
    window.addEventListener('keydown', (e) => { if (e.code === 'Space') holding = true; });
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') holding = false; });
    window.fetch = (url, opts) => {
        console.log('[minigame] fim:', opts && opts.body);
        setTimeout(() => start({ difficulty: 40, behavior: 'mixed', barSize: 110, color: '#4fa3e0' }), 800);
        return Promise.resolve();
    };
    start({ difficulty: 40, behavior: 'mixed', barSize: 110, color: '#4fa3e0' });
}
