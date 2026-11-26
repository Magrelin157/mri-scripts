// Painel do pescador (lunar_fishing)
(() => {
    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'lunar_fishing';
    const TEST = location.search.includes('shop');

    const $ = (sel) => document.querySelector(sel);
    const wrap = $('#shop-wrap');
    const shopEl = $('#shop');
    const listEl = $('#list');

    // ---------- Ícones (SVG próprio, sem depender de fonte externa) ----------
    const ICONS = {
        fish: '<svg viewBox="0 0 24 24"><path fill="#4f8fd6" stroke="#3b2210" stroke-width="1.6" d="M3 12c3-5 9-6 13-3l5-3v12l-5-3c-4 3-10 2-13-3z"/><circle cx="7.5" cy="11" r="1.2" fill="#3b2210"/></svg>',
        rod: '<svg viewBox="0 0 24 24"><path d="M4 21L19 3" stroke="#3b2210" stroke-width="2.4" stroke-linecap="round"/><path d="M19 3v12" stroke="#7a4f2a" stroke-width="1.2" stroke-dasharray="2 1.5"/><path d="M19 15c0 2-2 3-3 2" stroke="#3b2210" stroke-width="1.6" fill="none" stroke-linecap="round"/><circle cx="7" cy="18" r="2.4" fill="#c27c3d" stroke="#3b2210" stroke-width="1.4"/></svg>',
        worm: '<svg viewBox="0 0 24 24"><path d="M3 15c2-4 5-4 6 0s4 4 6 0 4-4 6 0" fill="none" stroke="#d98fb0" stroke-width="4" stroke-linecap="round"/><path d="M3 15c2-4 5-4 6 0s4 4 6 0 4-4 6 0" fill="none" stroke="#3b2210" stroke-width="1" stroke-linecap="round" stroke-dasharray="1 3"/></svg>',
        lock: '<svg viewBox="0 0 24 24"><rect x="5" y="10" width="14" height="11" rx="2" fill="currentColor"/><path d="M8 10V7a4 4 0 0 1 8 0v3" fill="none" stroke="currentColor" stroke-width="2.6"/></svg>',
        check: '<svg viewBox="0 0 24 24"><path d="M4 12l5 5L20 6" fill="none" stroke="currentColor" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    };

    const fillIcons = (root = document) => root.querySelectorAll('[data-icon]').forEach((el) => {
        if (!el.innerHTML) el.innerHTML = ICONS[el.dataset.icon] || '';
    });
    fillIcons();

    // ---------- Estado ----------
    let state = null;
    let tab = 'rods';
    const qty = {}; // quantidade escolhida por item

    const money = (v) => 'R$ ' + Math.round(v).toLocaleString('pt-BR');
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const img = (item) => (TEST ? `../install/images/${item.name}.png` : item.image) || '';
    const imgTag = (item, cls = '') => `<img class="${cls}" src="${esc(img(item))}" onerror="this.style.visibility='hidden'">`;

    // ---------- Sons ----------
    let audio;
    function tone(freq, dur, vol = 0.04, type = 'square') {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            const o = audio.createOscillator(), g = audio.createGain();
            o.type = type; o.frequency.value = freq;
            g.gain.setValueAtTime(vol, audio.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + dur);
            o.connect(g).connect(audio.destination); o.start(); o.stop(audio.currentTime + dur);
        } catch (e) { /* sem áudio */ }
    }
    const sfx = {
        click: () => tone(900, 0.04, 0.03),
        coins: () => { tone(1320, 0.08); setTimeout(() => tone(1760, 0.12), 80); },
        error: () => tone(180, 0.25, 0.05, 'sawtooth'),
    };

    // ---------- Comunicação ----------
    async function post(name, data = {}) {
        if (TEST) return mock(name, data);
        try {
            const res = await fetch(`https://${RES}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (e) {
            return { ok: false };
        }
    }

    // ---------- Aviso ----------
    let toastTimer;
    function toast(text, ok = true) {
        const t = $('#toast');
        t.textContent = text;
        t.className = 'toast show ' + (ok ? 'ok' : 'err');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => (t.className = 'toast'), 2600);
    }

    // ---------- Lateral ----------
    function renderSide() {
        const { level } = state;
        $('#lvl-num').textContent = level.level;

        if (level.to) {
            const pct = Math.max(0, Math.min(100, ((level.xp - level.from) / (level.to - level.from)) * 100));
            $('#xp-fill').style.width = pct + '%';
            $('#xp-text').textContent = `${level.xp - level.from} / ${level.to - level.from} XP`;
            $('#xp-next').textContent = `Faltam ${level.to - level.xp} XP pro nível ${level.level + 1}`;
        } else {
            $('#xp-fill').style.width = '100%';
            $('#xp-text').textContent = `${level.xp} XP`;
            $('#xp-next').textContent = 'Nível máximo!';
        }

        $('#wallet-label').textContent = state.account;
        $('#wallet-money').textContent = money(state.money);

        const fishByName = Object.fromEntries(state.fish.map((f) => [f.name, f]));
        $('#zone-list').innerHTML = state.zones.map((z) => `
            <li class="${z.unlocked ? '' : 'locked'}">
                <div class="zone-top">
                    <span class="name">${esc(z.label)}</span>
                    ${z.unlocked
                        ? `<span class="chip ok">${ICONS.check}Nv ${z.minLevel}</span>`
                        : `<span class="chip lock">${ICONS.lock}Nv ${z.minLevel}</span>`}
                </div>
                <div class="zone-fish">
                    ${z.fish.map((n) => fishByName[n] ? imgTag(fishByName[n]) : '').join('')}
                    ${z.withOutside ? '<small>+ peixes de fora</small>' : ''}
                </div>
            </li>`).join('');
    }

    // ---------- Itens ----------
    function rodStats(item) {
        const sizes = Object.values(state.barSizes || {}).sort((a, b) => a - b);
        const stats = [];
        if (item.barSize) {
            const rank = sizes.indexOf(item.barSize);
            const name = rank <= 0 ? 'pequena' : rank >= sizes.length - 1 ? 'grande' : 'média';
            const h = rank <= 0 ? 5 : rank >= sizes.length - 1 ? 15 : 10;
            stats.push(`<span class="stat"><span class="minibar"><i style="height:${h}px"></i></span>Barra ${name}</span>`);
        }
        if (item.breakChance != null) stats.push(`<span class="stat">Quebra ao perder: ${item.breakChance}%</span>`);
        return stats.join('');
    }

    function baitStats(item) {
        const d = Number(item.waitDivisor) || 1;
        const txt = d <= 1 ? 'Espera normal' : d === 2 ? 'Peixe morde 2x mais rápido' : `Peixe morde ${d}x mais rápido`;
        return `<span class="stat">${txt}</span>`;
    }

    function stepper(key, max) {
        const v = qty[key] ?? 1;
        return `<div class="stepper" data-key="${key}" data-max="${max}">
            <button data-step="-1">−</button>
            <input type="number" min="1" max="${max}" value="${v}">
            <button data-step="1">+</button>
        </div>`;
    }

    function renderBuy(items) {
        return items.map((item) => {
            const key = `${item.type}:${item.index}`;
            const amount = qty[key] ?? 1;
            const stats = item.type === 'fishingRods' ? rodStats(item) : baitStats(item);
            const actions = item.locked
                ? `<span class="lock-tag">${ICONS.lock}Libera no nível ${item.minLevel}</span>`
                : `${stepper(key, state.maxAmount)}
                   <button class="btn green" data-buy="${key}" ${item.price * amount > state.money ? 'disabled' : ''}>Comprar ${money(item.price * amount)}</button>`;
            return `<article class="card ${item.locked ? 'locked' : ''}" data-card="${key}">
                <div class="slot">${imgTag(item)}</div>
                <div class="card-info">
                    <h4>${esc(item.label)}</h4>
                    <div class="price">${money(item.price)} cada</div>
                    <div class="stats">${stats}</div>
                </div>
                <div class="card-actions">${actions}</div>
            </article>`;
        }).join('');
    }

    function renderSell() {
        const sorted = [...state.fish].sort((a, b) => (b.count > 0) - (a.count > 0) || a.min - b.min);
        return sorted.map((f) => {
            const key = `fish:${f.name}`;
            if (f.count > 0 && (qty[key] == null || qty[key] > f.count)) qty[key] = f.count;
            const range = f.min === f.max ? money(f.min) : `${money(f.min)} a ${money(f.max)}`;
            const actions = f.count > 0
                ? `${stepper(key, f.count)}<button class="btn blue" data-sell="${f.name}">Vender</button>`
                : `<span class="stat">Você não tem</span>`;
            return `<article class="card ${f.count > 0 ? '' : 'dim'}" data-card="${key}">
                <div class="slot">${imgTag(f)}</div>
                <div class="card-info">
                    <h4>${esc(f.label)}${f.count > 0 ? `<span class="owned">x${f.count}</span>` : ''}</h4>
                    <div class="price">${range} cada</div>
                </div>
                <div class="card-actions">${actions}</div>
            </article>`;
        }).join('');
    }

    function renderSellFooter() {
        const owned = state.fish.filter((f) => f.count > 0);
        const count = owned.reduce((s, f) => s + f.count, 0);
        const total = owned.reduce((s, f) => s + f.count * (f.min + f.max) / 2, 0);
        const badge = $('#sell-badge');
        badge.textContent = count;
        badge.classList.toggle('hidden', count === 0);
        $('#sell-summary').textContent = count === 1 ? 'Você tem 1 peixe' : `Você tem ${count} peixes`;
        $('#sell-total').textContent = '≈ ' + money(total);
        const all = $('#sell-all');
        all.disabled = count === 0;
        all.classList.remove('loading');
        all.textContent = 'Vender tudo';
        $('#sell-footer').classList.toggle('hidden', tab !== 'sell');
    }

    function renderList() {
        document.querySelectorAll('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
        if (tab === 'rods') listEl.innerHTML = renderBuy(state.rods);
        else if (tab === 'baits') listEl.innerHTML = renderBuy(state.baits);
        else listEl.innerHTML = renderSell() || '<p class="empty">Nenhum peixe configurado.</p>';
        renderSellFooter();
    }

    function render() {
        renderSide();
        renderList();
    }

    // ---------- Ações ----------
    function setQty(key, value, max) {
        let v = Math.floor(Number(value) || 1);
        v = Math.max(1, Math.min(max, v));
        qty[key] = v;
        return v;
    }

    function refreshCardButton(key) {
        const card = listEl.querySelector(`[data-card="${CSS.escape(key)}"]`);
        if (!card) return;
        const btn = card.querySelector('[data-buy]');
        if (btn) {
            const [type, index] = key.split(':');
            const item = state[type === 'fishingRods' ? 'rods' : 'baits'].find((i) => String(i.index) === index);
            const total = item.price * qty[key];
            btn.textContent = 'Comprar ' + money(total);
            btn.disabled = total > state.money;
        }
    }

    listEl.addEventListener('click', async (e) => {
        const stepBtn = e.target.closest('[data-step]');
        if (stepBtn) {
            const st = stepBtn.closest('.stepper');
            const key = st.dataset.key, max = Number(st.dataset.max);
            const input = st.querySelector('input');
            input.value = setQty(key, Number(input.value) + Number(stepBtn.dataset.step), max);
            sfx.click();
            refreshCardButton(key);
            return;
        }

        const buyBtn = e.target.closest('[data-buy]');
        if (buyBtn) {
            const key = buyBtn.dataset.buy;
            const [type, index] = key.split(':');
            const amount = qty[key] ?? 1;
            buyBtn.classList.add('loading');
            buyBtn.textContent = 'Comprando...';
            const res = await post('shopBuy', { type, index: Number(index), amount });
            if (!state) return;
            if (res && res.ok) {
                state.money = res.money;
                const list = state[type === 'fishingRods' ? 'rods' : 'baits'];
                const item = list.find((i) => String(i.index) === index);
                toast(`Comprou ${amount}x ${item ? item.label : 'item'} por ${money(res.spent)}`);
                sfx.coins();
            } else {
                const msg = { money: 'Dinheiro insuficiente', level: 'Seu nível ainda não libera isso', weight: 'Sem espaço no inventário' }[res && res.reason];
                toast(msg || 'Não deu pra comprar agora', false);
                sfx.error();
            }
            render();
            listEl.querySelector(`[data-card="${CSS.escape(key)}"]`)?.classList.add('pop');
            return;
        }

        const sellBtn = e.target.closest('[data-sell]');
        if (sellBtn) {
            const name = sellBtn.dataset.sell;
            const amount = qty['fish:' + name] ?? 1;
            await sell({ [name]: amount }, sellBtn);
        }
    });

    listEl.addEventListener('change', (e) => {
        const input = e.target.closest('.stepper input');
        if (!input) return;
        const st = input.closest('.stepper');
        input.value = setQty(st.dataset.key, input.value, Number(st.dataset.max));
        refreshCardButton(st.dataset.key);
    });

    listEl.addEventListener('input', (e) => {
        const input = e.target.closest('.stepper input');
        if (!input || input.value === '') return;
        const st = input.closest('.stepper');
        setQty(st.dataset.key, input.value, Number(st.dataset.max));
        refreshCardButton(st.dataset.key);
    });

    async function sell(items, btn) {
        if (btn) { btn.classList.add('loading'); btn.textContent = 'Vendendo...'; }
        const res = await post('shopSell', { items });
        if (!state) return;
        if (res && res.ok) {
            state.money = res.money;
            if (res.fish) state.fish.forEach((f) => { f.count = res.fish[f.name] ?? 0; });
            Object.keys(qty).filter((k) => k.startsWith('fish:')).forEach((k) => delete qty[k]);
            toast(`Vendeu ${res.sold} ${res.sold === 1 ? 'peixe' : 'peixes'} por ${money(res.earned)}`);
            sfx.coins();
        } else {
            toast('Você não tem esses peixes', false);
            sfx.error();
        }
        render();
    }

    $('#sell-all').addEventListener('click', (e) => {
        const items = {};
        state.fish.forEach((f) => { if (f.count > 0) items[f.name] = f.count; });
        if (Object.keys(items).length) sell(items, e.currentTarget);
    });

    document.querySelectorAll('.tab').forEach((b) => b.addEventListener('click', () => {
        if (tab === b.dataset.tab) return;
        tab = b.dataset.tab;
        sfx.click();
        renderList();
        listEl.scrollTop = 0;
    }));

    // ---------- Abrir / fechar ----------
    function fitScale() {
        const s = Math.min(1.15, (window.innerWidth * 0.92) / 900, (window.innerHeight * 0.9) / 580);
        shopEl.style.setProperty('--shop-scale', s.toFixed(3));
    }
    window.addEventListener('resize', fitScale);

    function open(data) {
        state = data;
        tab = 'rods';
        for (const k in qty) delete qty[k];
        $('#shop-title').textContent = data.title || 'Corporação Marítima';
        $('#shop-npc').textContent = [data.npc && data.npc.name, data.npc && data.npc.tag].filter(Boolean).join(' · ');
        fitScale();
        render();
        wrap.classList.remove('hidden');
    }

    function close(notify = true) {
        if (!state) return;
        state = null;
        wrap.classList.add('hidden');
        $('#toast').className = 'toast';
        if (notify) post('shopClose');
    }

    $('#shop-close').addEventListener('click', () => close());
    window.addEventListener('keydown', (e) => {
        if (state && (e.key === 'Escape' || e.key === 'Backspace' && e.target.tagName !== 'INPUT')) close();
    });

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'shopOpen') open(d);
        else if (d.action === 'shopClose') close(false);
    });

    // ---------- Modo de teste: abra html/index.html?shop no navegador ----------
    let mockState;
    function mock(name, data) {
        return new Promise((resolve) => setTimeout(() => {
            if (name === 'shopBuy') {
                const list = data.type === 'fishingRods' ? mockState.rods : mockState.baits;
                const item = list.find((i) => i.index === data.index);
                const cost = item.price * data.amount;
                if (cost > mockState.money) return resolve({ ok: false, reason: 'money' });
                mockState.money -= cost;
                return resolve({ ok: true, spent: cost, money: mockState.money });
            }
            if (name === 'shopSell') {
                let earned = 0, sold = 0;
                const fish = {};
                mockState.fish.forEach((f) => {
                    const n = Math.min(data.items[f.name] || 0, f.count);
                    for (let i = 0; i < n; i++) earned += f.min + Math.floor(Math.random() * (f.max - f.min + 1));
                    sold += n; f.count -= n; fish[f.name] = f.count;
                });
                mockState.money += earned;
                return resolve({ ok: sold > 0, earned, sold, money: mockState.money, fish });
            }
            resolve({ ok: true });
        }, 350));
    }

    if (TEST) {
        document.body.style.background = 'linear-gradient(#2c3a4a, #1b2128)';
        const L = (n) => ({ anchovy: 'Anchova', trout: 'Truta', haddock: 'Hadoque', salmon: 'Salmão', red_snapper: 'Vermelho', mahi_mahi: 'Mahi-mahi', grouper: 'Garoupa', piranha: 'Piranha', tuna: 'Atum', shark: 'Tubarão', basic_rod: 'Vara de pesca básica', graphite_rod: 'Vara de pesca de grafite', titanium_rod: 'Vara de pesca de titânio', worms: 'Minhocas', artificial_bait: 'Isca artificial' }[n]);
        const fish = [['anchovy', 40, 55, 7], ['trout', 55, 65, 4], ['haddock', 70, 90, 2], ['salmon', 110, 140, 1], ['red_snapper', 210, 250, 0], ['mahi_mahi', 240, 290, 0], ['grouper', 280, 340, 0], ['piranha', 510, 630, 0], ['tuna', 620, 750, 0], ['shark', 1400, 1700, 0]]
            .map(([name, min, max, count]) => ({ name, label: L(name), min, max, count }));
        mockState = {
            title: 'Corporação Marítima', npc: { name: 'João', tag: 'PESCADOR' }, account: 'Dinheiro na mão', money: 3250,
            level: { level: 1, xp: 20, from: 10, to: 25 }, maxAmount: 100,
            barSizes: { basic_rod: 104, graphite_rod: 120, titanium_rod: 136 },
            rods: [['basic_rod', 1000, 0, 20], ['graphite_rod', 2500, 2, 10], ['titanium_rod', 5000, 4, 1]].map(([name, price, minLevel, breakChance], i) => ({ type: 'fishingRods', index: i + 1, name, label: L(name), price, minLevel, locked: 1 < minLevel, breakChance, barSize: { basic_rod: 104, graphite_rod: 120, titanium_rod: 136 }[name] })),
            baits: [['worms', 5, 0, 1], ['artificial_bait', 60, 2, 2]].map(([name, price, minLevel, waitDivisor], i) => ({ type: 'baits', index: i + 1, name, label: L(name), price, minLevel, locked: 1 < minLevel, waitDivisor })),
            fish,
            zones: [
                { label: 'Qualquer água', minLevel: 0, unlocked: true, fish: ['anchovy', 'trout', 'haddock', 'salmon'] },
                { label: 'Recife de Coral', minLevel: 1, unlocked: true, fish: ['mahi_mahi', 'red_snapper'], withOutside: true },
                { label: 'Pântano', minLevel: 2, unlocked: false, fish: ['piranha'], withOutside: true },
                { label: 'Águas Profundas', minLevel: 3, unlocked: false, fish: ['grouper', 'tuna', 'shark'] },
            ],
        };
        open(mockState);
        window.__shop = { setTab: (t) => { tab = t; renderList(); } };
    }
})();
