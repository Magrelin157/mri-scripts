const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'qbx_vehicleshop';
const $ = (id) => document.getElementById(id);

const post = (name, data = {}) =>
    fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })
        .then((r) => r.json()).catch(() => null);

const money = (v) => 'R$ ' + Number(v || 0).toLocaleString('pt-BR');

// Ícones (sem fotos)
const ICONS = {
    car: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 21v-5l6-2 8-6h20l9 6 11 2 2 5h-4M14 21h30M4 21h4"/><circle cx="11" cy="22" r="4"/><circle cx="48" cy="22" r="4"/><path d="M20 14l4-4h12l6 4z"/></svg>',
    suv: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 21v-8l4-6h30l8 7 12 2 2 5h-4M15 21h28M4 21h4"/><circle cx="11" cy="22" r="4"/><circle cx="48" cy="22" r="4"/><path d="M12 13l3-4h10v4zM29 9h8l5 4H29z"/></svg>',
    van: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 21V5h38l10 8 8 2v6h-4M15 21h28M4 21h4"/><circle cx="11" cy="22" r="4"/><circle cx="48" cy="22" r="4"/><path d="M42 6v7h10"/></svg>',
    moto: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><circle cx="12" cy="20" r="7"/><circle cx="52" cy="20" r="7"/><path d="M12 20l12-8h12l6-6h6M30 12l6 8h8l8 0M40 6l4 4"/></svg>',
    bike: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><circle cx="13" cy="19" r="8"/><circle cx="51" cy="19" r="8"/><path d="M13 19l10-12h16l12 12M23 7l8 12 8-12M20 4h8M37 4l2 3"/></svg>',
    boat: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 16h56l-8 9H12zM18 16V9h18l8 7M2 28c6-3 10 3 16 0s10 3 16 0 10 3 16 0 10 3 14 0"/></svg>',
    heli: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M8 4h44M30 4v5M18 18c0-6 6-9 14-9h6l6 9-4 4H24c-4 0-6-2-6-4zM44 14h16l2-4M22 27h22M28 22v5M38 22v5"/></svg>',
    plane: '<svg viewBox="0 0 64 30" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 16h44c6 0 12 1 12 3s-6 3-12 3H14L6 12h4l6 4M28 16L20 4h6l14 12M28 22l-6 7h6l10-7"/></svg>',
};

const state = {
    shop: null, categories: [], vehicles: [], colors: [], options: {},
    cat: 0, list: [], index: 0, color: 0, stock: null, modal: null, search: '',
};

function current() { return state.list[state.index]; }

function renderTabs() {
    $('tabs').innerHTML = state.categories.map((c, i) =>
        `<div class="tab ${i === state.cat ? 'on' : ''}" data-i="${i}">${c.label}</div>`).join('');
}

function filterList() {
    const q = state.search.trim().toLowerCase();
    if (q) {
        state.list = state.vehicles.filter((v) => `${v.brand} ${v.name} ${v.model}`.toLowerCase().includes(q));
    } else {
        const cat = state.categories[state.cat];
        state.list = cat ? state.vehicles.filter((v) => v.category === cat.id) : [];
    }
}

function renderCards() {
    const el = $('cards');
    if (!state.list.length) {
        el.innerHTML = '<div class="empty">Nenhum veículo nesta categoria.</div>';
        return;
    }
    el.innerHTML = state.list.map((v, i) => `
        <div class="card ${i === state.index ? 'on' : ''}" data-i="${i}">
            <div class="tag"><span class="c">${v.stats.class}</span>
                <span class="av ${v.inGame ? '' : 'out'}">${v.inGame ? 'DISPONÍVEL' : 'SEM MODELO'}</span></div>
            ${ICONS[v.icon] || ICONS.car}
            <div class="foot">
                <div class="nm"><small>${v.brand || '&nbsp;'}</small><b>${v.name}</b></div>
                <span class="pr">${money(v.price)}</span>
            </div>
        </div>`).join('');
    const on = el.querySelector('.card.on');
    if (on) on.scrollIntoView({ inline: 'center', block: 'nearest' });
}

function renderInfo() {
    const v = current();
    const has = !!v;
    $('vBrand').textContent = has ? v.brand : '';
    $('vName').textContent = has ? v.name : '—';
    $('vSeats').textContent = has && v.stats.seats ? `${v.stats.seats} lugares` : '';
    $('vClass').textContent = has ? v.stats.class : '-';
    $('vScore').textContent = has ? v.stats.score : 0;
    $('vScoreBar').style.width = has ? `${v.stats.score / 10}%` : '0';
    const b = has ? v.stats.bars : {};
    $('sSpeed').style.width = `${(b.speed || 0) * 100}%`;
    $('sAccel').style.width = `${(b.accel || 0) * 100}%`;
    $('sBrake').style.width = `${(b.brake || 0) * 100}%`;
    $('sTraction').style.width = `${(b.traction || 0) * 100}%`;
    $('vTop').textContent = has ? v.stats.speed : 0;

    const out = state.stock === 0;
    $('vStock').textContent = !has ? '' : state.stock === null || state.stock === undefined ? '' : out ? 'ESGOTADO' : `ESTOQUE: ${state.stock}`;
    $('vStock').classList.toggle('out', out);

    const managed = state.shop && state.shop.managed;
    $('buyLabel').textContent = managed ? 'VENDER' : 'COMPRAR';
    $('btnBuy').disabled = !has || out || !v.inGame || !state.options.buy;
    $('btnTest').disabled = !has || !v.inGame;
    $('btnFinance').disabled = !has || out || !v.inGame;
    $('btnTest').classList.toggle('hidden', !state.options.testDrive);
    $('btnFinance').classList.toggle('hidden', !state.options.finance);
}

let selectTimer;
function select(i) {
    if (!state.list.length) { state.index = 0; state.stock = null; renderCards(); renderInfo(); return; }
    state.index = Math.max(0, Math.min(state.list.length - 1, i));
    state.stock = null;
    renderCards();
    renderInfo();
    clearTimeout(selectTimer);
    const v = current();
    selectTimer = setTimeout(async () => {
        const res = await post('select', { model: v.model });
        if (res && current() && current().model === res.model) {
            state.stock = res.stock ?? null;
            renderInfo();
        }
    }, 120);
}

function setCategory(i) {
    if (!state.categories.length) return;
    state.cat = (i + state.categories.length) % state.categories.length;
    state.search = '';
    $('search').value = '';
    renderTabs();
    filterList();
    select(0);
}

function renderColors() {
    $('colors').innerHTML = state.colors.map((c, i) => {
        const bg = c.rgb ? `background: rgb(${c.rgb.join(',')})` : '';
        return `<div class="swatch ${c.rgb ? '' : 'original'} ${i === state.color ? 'on' : ''}" style="${bg}" title="${c.label}" data-i="${i}"></div>`;
    }).join('');
}

/* ---------------- modal ---------------- */
function openModal(type) {
    const v = current();
    if (!v) return;
    if ((type === 'buy' || type === 'finance') && (state.stock === 0 || !v.inGame)) return;
    const managed = state.shop.managed;

    // test drive na loja pública não precisa de confirmação
    if (type === 'test' && !managed) {
        post('action', { type: 'test', model: v.model });
        return;
    }

    state.modal = type;
    $('mTitle').textContent = type === 'test' ? 'Test drive' : type === 'finance' ? 'Financiar veículo' : managed ? 'Vender veículo' : 'Confirmar compra';
    $('mVeh').textContent = `${v.brand} ${v.name}`.trim();
    $('mPrice').textContent = money(v.price);
    $('fPlayer').classList.toggle('hidden', !managed);
    $('iPlayer').value = '';
    $('financeFields').classList.toggle('hidden', type !== 'finance');

    if (type === 'finance') {
        const minDown = Math.ceil(v.price * state.options.minimumDown / 100);
        $('minDownTxt').textContent = money(minDown);
        $('iDown').min = minDown;
        $('iDown').max = v.price;
        $('iDown').value = minDown;
        $('iPays').max = state.options.maximumPayments;
        $('iPays').value = Math.min(12, state.options.maximumPayments);
        updateSummary();
    }

    $('modal').classList.remove('hidden');
    setTimeout(() => (managed ? $('iPlayer') : type === 'finance' ? $('iDown') : $('mConfirm')).focus(), 30);
}

function updateSummary() {
    const v = current();
    if (!v) return;
    const down = Math.max(0, Number($('iDown').value) || 0);
    const pays = Number($('iPays').value);
    $('paysTxt').textContent = `${pays}x`;
    const rest = Math.max(0, v.price - down);
    $('financeSummary').innerHTML = `Entrada: <b>${money(down)}</b><br>Restante: <b>${money(rest)}</b> em <b>${pays}x</b> de aprox. <b>${money(Math.ceil(rest / pays))}</b>`;
}

function closeModal() {
    state.modal = null;
    $('modal').classList.add('hidden');
}

function confirmModal() {
    const v = current();
    if (!v || !state.modal) return;
    const data = { type: state.modal, model: v.model };
    if (state.shop.managed) {
        data.playerId = Number($('iPlayer').value);
        if (!data.playerId) { $('iPlayer').focus(); return; }
    }
    if (state.modal === 'finance') {
        data.downPayment = Number($('iDown').value);
        data.payments = Number($('iPays').value);
        const minDown = Math.ceil(v.price * state.options.minimumDown / 100);
        if (!data.downPayment || data.downPayment < minDown || data.downPayment > v.price) { $('iDown').focus(); return; }
    }
    closeModal();
    post('action', data);
}

/* ---------------- abrir / fechar ---------------- */
function open(data) {
    state.shop = data.shop;
    state.categories = data.categories || [];
    state.vehicles = data.vehicles || [];
    state.colors = data.colors || [];
    state.options = data.options || {};
    state.color = 0;
    state.search = '';
    $('search').value = '';
    $('shopLabel').textContent = data.shop.label;
    $('mCash').textContent = money(data.money.cash);
    $('mBank').textContent = money(data.money.bank);
    closeModal();
    renderColors();
    $('app').classList.remove('hidden');
    setCategory(0);
}

function close() {
    closeModal();
    $('app').classList.add('hidden');
}

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'open') open(d);
    else if (d.action === 'close') close();
});

/* ---------------- eventos ---------------- */
$('tabs').addEventListener('click', (e) => { const t = e.target.closest('.tab'); if (t) setCategory(+t.dataset.i); });
$('cards').addEventListener('click', (e) => { const c = e.target.closest('.card'); if (c) select(+c.dataset.i); });
$('cards').addEventListener('wheel', (e) => { e.stopPropagation(); $('cards').scrollLeft += e.deltaY; }, { passive: true });
$('colors').addEventListener('click', (e) => {
    const s = e.target.closest('.swatch');
    if (!s) return;
    state.color = +s.dataset.i;
    renderColors();
    post('color', { index: state.color + 1 });
});
$('btnBuy').addEventListener('click', () => openModal('buy'));
$('btnTest').addEventListener('click', () => openModal('test'));
$('btnFinance').addEventListener('click', () => openModal('finance'));
$('btnClose').addEventListener('click', () => post('close'));
$('mCancel').addEventListener('click', closeModal);
$('mConfirm').addEventListener('click', confirmModal);
$('iDown').addEventListener('input', updateSummary);
$('iPays').addEventListener('input', updateSummary);
$('search').addEventListener('input', (e) => {
    state.search = e.target.value;
    if (!state.search.trim()) { setCategory(state.cat); return; }
    filterList();
    select(0);
});

// girar com o mouse / zoom com a roda
let dragging = false, lastX = 0, pendingDx = 0, raf = 0;
$('drag').addEventListener('mousedown', (e) => { dragging = true; lastX = e.clientX; });
window.addEventListener('mouseup', () => { dragging = false; });
window.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    pendingDx += e.clientX - lastX;
    lastX = e.clientX;
    if (!raf) raf = requestAnimationFrame(() => { raf = 0; const dx = pendingDx; pendingDx = 0; if (dx) post('rotate', { dx }); });
});
$('drag').addEventListener('wheel', (e) => { post('zoom', { delta: e.deltaY > 0 ? 1 : -1 }); }, { passive: true });

window.addEventListener('keydown', (e) => {
    if ($('app').classList.contains('hidden')) return;
    const typing = ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName);

    if (state.modal) {
        if (e.key === 'Escape') closeModal();
        else if (e.key === 'Enter') confirmModal();
        return;
    }
    if (e.key === 'Escape') {
        if (typing) { document.activeElement.blur(); return; }
        post('close');
        return;
    }
    if (typing) return;

    switch (e.key.toLowerCase()) {
        case 'arrowright': select(state.index + 1); break;
        case 'arrowleft': select(state.index - 1); break;
        case 'q': setCategory(state.cat - 1); break;
        case 'e': setCategory(state.cat + 1); break;
        case 'enter': if (!$('btnBuy').disabled) openModal('buy'); break;
        case 't': if (state.options.testDrive && !$('btnTest').disabled) openModal('test'); break;
        case 'f': if (state.options.finance && !$('btnFinance').disabled) openModal('finance'); break;
        case 'c': post('camera'); break;
        case '/': e.preventDefault(); $('search').focus(); break;
    }
});


/* ---------------- cronômetro do test drive ---------------- */
let tdTimer = null;
function testDriveStart(total, vehicle) {
    clearInterval(tdTimer);
    const end = Date.now() + total * 1000;
    const td = $('td');
    $('tdVeh').textContent = vehicle ? `· ${vehicle}` : '';
    td.classList.remove('hidden', 'warn');
    const tick = () => {
        const left = Math.max(0, Math.round((end - Date.now()) / 1000));
        const m = String(Math.floor(left / 60)).padStart(2, '0');
        const s = String(left % 60).padStart(2, '0');
        $('tdTime').textContent = `${m}:${s}`;
        const pct = total > 0 ? left / total : 0;
        $('tdRing').style.strokeDashoffset = String(119.4 * (1 - pct));
        $('tdBar').style.width = `${pct * 100}%`;
        td.classList.toggle('warn', left <= 30);
        if (left <= 0) clearInterval(tdTimer);
    };
    tick();
    tdTimer = setInterval(tick, 1000);
}
function testDriveEnd() {
    clearInterval(tdTimer);
    $('td').classList.add('hidden');
}
window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'testdrive') testDriveStart(Number(d.time) || 0, d.vehicle);
    else if (d.action === 'testdriveEnd') testDriveEnd();
});
