function [st, rec] = plant_step(st, u, par, data, base, ev)
%PLANT_STEP  Execute decisions u for step st.t on the realised data and update the state.
%   data: struct with fields inf, pv, cop (scalars for this step); base: baseline grid power (Tsim x 1)
%   u: y (1x3 GPUs), pch, pdis, pgt, hac, qtc, qtd  (qec and grid follow from balances)
d = sys_derived(par); dt = par.dt; t = st.t;
it = par.it; fac = par.fac;
%% compute execution (EDF within class, clipped to capacity)
y = max(u.y(:)', 0);
cv = cap_curve(par); zr = zeros(1, 3);
if cv.on && isfield(u, 'z'), zr = max(u.z(:)', 0); end
% busy GPUs are limited by the work available; capped GPUs are slower, so they may exceed the
% available work by the throughput they lose (the work done, y - loss, is what the backlog limits)
lr = zeros(1, 3);
if cv.on, for c = 1:3, zc = min(zr(c), cv.rmax * y(c)); lr(c) = max([0; cv.s * zc + cv.i * y(c)]); end, end
avail = sum(st.rem, 1) / dt + lr;
% rigid-job recovery bound (par.it.rec_tau): at most B_prev/tau_c GPUs above the nominal load of the class
if isfield(it, 'rec_tau') && any(it.rec_tau > 0) && isfield(st, 'arr')
    for c = find(it.rec_tau(:)' > 0)
        Bp = max(sum(st.rem(:, c)) - st.arr(c) * dt, 0);
        avail(c) = min(avail(c), st.arr(c) + Bp / it.rec_tau(c));
    end
end
y = min(y, avail);
gfree = it.u_max * it.Ngpu - data.inf - data.fix;
if sum(y) > gfree + 1e-9
    due = sum(st.rem(1:t, :), 1) / dt;
    extra = max(y - due, 0);
    cut = sum(y) - gfree;
    red = min(extra, extra / max(sum(extra), 1e-9) * cut);
    y = y - red;
end
% physical limit on the swing of deferrable IT power (if set): applies to every controller
if isfinite(it.ramp_max) && isfield(st, 'y_prev') && ~isnan(st.y_prev)
    Rr = it.ramp_max / d.pdyn; ys = sum(y);
    if ys > st.y_prev + Rr + 1e-9                    % too fast up: defer the least urgent work
        due = sum(st.rem(1:t, :), 1) / dt;
        extra = max(y - due, 0); cut = ys - (st.y_prev + Rr);
        y = y - min(extra, extra / max(sum(extra), 1e-9) * cut);
    elseif ys < st.y_prev - Rr - 1e-9                % too fast down: keep running available work
        room = max(avail - y, 0); add = min([sum(room), st.y_prev - Rr - ys, max(gfree - ys, 0)]);
        y = y + room / max(sum(room), 1e-9) * add;
    end
end
% optional power capping: z = capped dynamic power in GPU equivalents (<= rmax*y), throughput loss from
% the convex capping curve (CAP_CURVE; one level: loss = beta*z)
z = zeros(1, 3); loss = zeros(1, 3);
if cv.on
    z = min(zr, cv.rmax * y);
    for c = 1:3, loss(c) = max([0; cv.s * z(c) + cv.i * y(c)]); end
end
for c = 1:3
    x = (y(c) - loss(c)) * dt;
    r = st.rem(:, c);
    cs = cumsum(r);
    take = min(r, max(0, x - (cs - r)));
    st.rem(:, c) = r - take;
end
%% IT power and cooling
% optional pause / resume overhead (par.it.pause_ovh_h): GPUs newly paused w.r.t. the nominal load add
% checkpoint + restart work to the current cohort
povh = 0;
if isfield(it, 'pause_ovh_h') && any(it.pause_ovh_h > 0) && isfield(st, 'arr')
    if ~isfield(st, 'dprev'), st.dprev = zeros(1, 3); end
    dnow = st.arr - y;
    w = it.pause_ovh_h(:)' .* max(dnow - st.dprev, 0);
    for c = 1:3, st.rem(t + d.lag(c), c) = st.rem(t + d.lag(c), c) + w(c); end
    povh = sum(w); st.dprev = dnow;
end
pit = d.Pfix + d.pdyn * (it.k_inf * data.inf + data.fix + sum(y) - sum(z));
qload = fac.theta * pit + fac.Q0;
pgt = min(max(u.pgt, 0), par.gt.Pmax);
pgt = min(max(pgt, st.pgt_prev - par.gt.ramp), st.pgt_prev + par.gt.ramp);
qac = min([par.ac.cop * max(u.hac, 0), par.ac.cop * d.kh * pgt, par.ac.Qmax]);
qtd = min([max(u.qtd, 0), par.tes.Qmax, max(st.S - par.tes.Smin, 0) * par.tes.eta_d / dt]);
qtc = min([max(u.qtc, 0), par.tes.Qmax, max(par.tes.Smax - st.S, 0) / (par.tes.eta_c * dt)]);
% optional thermal inertia: qth = heat accumulating in the hall (cooling below the load), within the band
qth = 0; th_on = isfield(par, 'th') && par.th.on;
if th_on
    if isfield(u, 'qth'), qth = u.qth; end
    keep = 1 - par.th.loss * dt;
    qth = min(max(qth, (-par.th.C * par.th.dT_dn - keep * st.TH) / dt), (par.th.C * par.th.dT_up - keep * st.TH) / dt);
end
qec = qload - qac - qtd + qtc - qth;
if qec < 0          % too much cold supplied: reduce TES discharge, then heat accumulation, then AC output
    r1 = min(qtd, -qec); qtd = qtd - r1; qec = qec + r1;
    if qec < 0 && qth > 0, r1 = min(qth, -qec); qth = qth - r1; qec = qec + r1; end
    if qec < 0, qac = qac + qec; qec = 0; end
end
%% optional waste-heat recovery: the heat pump takes (cop - 1) * php of heat from the chilled-water loop (relieving
%  the electric chillers) and delivers cop * php to the hot-water tank; the heat network draws data.qdh from the
%  tank, a gas boiler covers what the tank cannot, surplus heat above the tank capacity goes to the cooling tower
php = 0; qb = 0; hp_on = isfield(par, 'hp') && par.hp.on;
if hp_on
    hp = par.hp;
    php = 0; if isfield(u, 'php'), php = min(max(u.php, 0), hp.Pmax); end
    php = min(php, max(qec, 0) / (hp.cop - 1));
    qec = qec - (hp.cop - 1) * php;
    Hn = (1 - hp.loss * dt) * st.H + (hp.cop * php - data.qdh) * dt;
    if Hn < 0, qb = -Hn / dt; Hn = 0; end
    st.H = min(Hn, hp.E);
end
%% battery
pdis = min([max(u.pdis, 0), par.bess.Pmax, max(st.E - par.bess.Emin, 0) * par.bess.eta_d / dt]);
pch  = min([max(u.pch, 0),  par.bess.Pmax, max(par.bess.Emax - st.E, 0) / (par.bess.eta_c * dt)]);
if pch > 0 && pdis > 0, net = pch - pdis; pch = max(net, 0); pdis = max(-net, 0); end
ppv = data.pv;
% grid import from the balance (ppv and pgt passed explicitly: an anonymous function would freeze them)
grid = @(pch_, pdis_, qec_, ppv_, pgt_) (1 + fac.a_aux) * pit + fac.P_aux0 + qec_ / data.cop + pch_ - pdis_ - pgt_ - ppv_ + php;
pg = grid(pch, pdis, qec, ppv, pgt);
%% connection-limit enforcement (facility controller): storage first, then compute throttling
over = pg - d.Pcap;
if over > 1e-9
    r = min(pch, over); pch = pch - r; over = over - r;
    if over > 1e-9
        add = min([over, par.bess.Pmax - pdis, max(st.E - par.bess.Emin, 0) * par.bess.eta_d / dt - pdis]);
        add = max(add, 0); pdis = pdis + add; over = over - add;
    end
    if over > 1e-9 && qtc > 0
        r = min(qtc, over * data.cop); qtc = qtc - r; qec = qec - r; over = over - r / data.cop;
    end
    pg = grid(pch, pdis, qec, ppv, pgt);
end
if pg < par.cap.Pmin            % keep the minimum import (no export): throttle the gas engine within its ramp,
    lack = par.cap.Pmin - pg;   % curtail PV / wind, then reduce storage discharge
    gmin = max(st.pgt_prev - par.gt.ramp, 0);
    if pgt > gmin
        [pgt, qac, qec] = gt_down(pgt, max(pgt - lack, gmin), qac, qec, par, d);
        pg = grid(pch, pdis, qec, ppv, pgt); lack = max(par.cap.Pmin - pg, 0);
    end
    r = min(ppv, lack); ppv = ppv - r; lack = lack - r;
    r = min(pdis, lack); pdis = pdis - r; lack = lack - r;
    r = min(qtd, lack * data.cop); qtd = qtd - r; qec = qec + r; lack = lack - r / data.cop;
    pg = grid(pch, pdis, qec, ppv, pgt);
    if pg < 0                   % still exporting: the gas engine trips below its ramp limit
        [pgt, qac, qec] = gt_down(pgt, max(pgt + pg, 0), qac, qec, par, d);
        pg = grid(pch, pdis, qec, ppv, pgt);
    end
end
%% state update
st.E = st.E + (par.bess.eta_c * pch - pdis / par.bess.eta_d) * dt;
st.S = (1 - par.tes.loss * dt) * st.S + (par.tes.eta_c * qtc - qtd / par.tes.eta_d) * dt;
if th_on, st.TH = (1 - par.th.loss * dt) * st.TH + qth * dt; end
if ~isfield(st, 'acc'), st.acc = zeros(1, 4); end
st.acc = st.acc + dt * [(1 + fac.a_aux) * pit + fac.P_aux0 + qec / data.cop, pit, ppv, pg + ppv + pgt];
st.pgt_prev = pgt;
st.pg_prev = pg;
st.y_prev = sum(y);
overdue = sum(sum(st.rem(1:t, :)));
st.late = st.late + overdue * dt;
for k = 1:numel(ev)
    if t >= ev(k).s && t <= ev(k).e
        st.ev_r(k) = st.ev_r(k) + (base(t) - pg);
        st.ev_n(k) = st.ev_n(k) + 1;
        st.ev_mx(k) = max(st.ev_mx(k), pg);
    end
    if any(ev(k).win == t)
        st.rb(k) = max(st.rb(k), pg - base(t));
    end
end
rec = struct('pg', pg, 'pit', pit, 'y', y, 'z', z, 'pch', pch, 'pdis', pdis, 'E', st.E, 'S', st.S, ...
    'pgt', pgt, 'qac', qac, 'qec', qec, 'qtc', qtc, 'qtd', qtd, 'ppv', ppv, 'pv', data.pv, ...
    'cop', data.cop, 'overdue', overdue, 'backlog', sum(st.rem, 1), 'over', max(pg - d.Pcap, 0), ...
    'inf', data.inf, 'TH', st.TH, 'qth', qth, 'povh', povh, 'php', php, 'qb', qb, 'H', st.H, 'qdh', data.qdh);
st.t = t + 1;
end

function [pgt, qac, qec] = gt_down(pgt, pnew, qac, qec, par, d)
% lower the gas-engine output to pnew; the absorption chiller loses the corresponding waste heat and the
% electric chiller takes over its cooling
pgt = pnew;
qa2 = min(qac, par.ac.cop * d.kh * pgt); qec = qec + (qac - qa2); qac = qa2;
end
