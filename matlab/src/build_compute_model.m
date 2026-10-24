function [P, ix] = build_compute_model(par, st, sc, ev, opt)
%BUILD_COMPUTE_MODEL  IT-side scheduler used by the independent-recovery benchmarks (stage 1).
%   The IT scheduler sees only its own state (backlog), an IT power budget that keeps the facility
%   under the connection limit assuming storage is idle, and the TOU price. Two variants:
%     IR-O / IR-O* : its own DR share alpha*C_k as a per-step power-reduction target;
%     IR-P         : no fixed share; instead it pays a day-ahead shadow price opt.lambda (CNY/MWh) on
%                    facility power (price-coordinated independent recovery).
%   It never sees the storage state or the storage recovery needs.
d = sys_derived(par); dt = par.dt; H = sc.H; t0 = st.t;
a = par.fac.a_aux; th = par.fac.theta;
m = lpb_new();
phi = 1 + a + th ./ sc.cop(:, 1);                       % facility MW per IT MW
lam = zeros(H, 1); if isfield(opt, 'lambda') && ~isempty(opt.lambda), lam = opt.lambda(:); end
use_share = ~isfield(opt, 'use_share') || opt.use_share;
for c = 1:3
    [m, Y{c}] = lpb_addvar(m, H, 0, Inf, dt * (sc.price + lam) .* phi * d.pdyn);
    [m, B{c}] = lpb_addvar(m, H, 0, Inf, dt * par.qos.c_jct);
    [m, V{c}] = lpb_addvar(m, H, 0, Inf, dt * par.qos.c_late);
end
r = (1:H)'; one = ones(H,1);
% optional power capping during (visible) DR events: Z{c} capped dynamic power (GPU equivalents)
% <= rmax*Y{c}, throughput loss as in BUILD_MODEL (CAP_CURVE)
cv = cap_curve(par); capon = cv.on;
if capon
    evstep = false(H, 1);
    for k = 1:numel(ev)
        if ~opt.visible(k), continue; end
        hk = (max(ev(k).s, t0):min(ev(k).e, t0 + H - 1)) - t0 + 1;
        if ~isempty(hk) && hk(1) >= 1, evstep(hk) = true; end
    end
    for c = 1:3
        [m, Z{c}] = lpb_addvar(m, H, 0, Inf, -dt * (sc.price + lam) .* phi * d.pdyn);
        m.ub(Z{c}(~evstep)) = 0;
        m = lpb_addle(m, [r; r], [Z{c}; Y{c}], [one; -cv.rmax * one], zeros(H, 1));
        LZ{c} = [];
        if ~cv.linear
            [m, LZ{c}] = lpb_addvar(m, H, 0, Inf, 0); m.ub(LZ{c}(~evstep)) = 0;
            for k = 1:cv.K
                m = lpb_addle(m, [r; r; r], [Z{c}; Y{c}; LZ{c}], [cv.s(k) * one; cv.i(k) * one; -one], zeros(H, 1));
            end
        end
    end
end
povh = zeros(1, 3); if isfield(par.it, 'pause_ovh_h'), povh = par.it.pause_ovh_h(:)'; end
capfree = par.it.u_max * par.it.Ngpu - sc.inf(:,1) - sc.fix(:,1);
m = lpb_addle(m, [r; r; r], [Y{1}; Y{2}; Y{3}], [one; one; one], capfree);
% IT power budget: connection limit plus the on-site generation the facility EMS can dispatch (gas
% engine up to its ramp-feasible maximum), storage idle; compute has priority on this headroom.
% par.bench.it_gas = 'nominal' reproduces the earlier, weaker benchmark (gas engine at its no-DR schedule).
pgt_b = min(par.gt.Pmax, st.pgt_prev + par.gt.ramp * (1:H)');
if isfield(par, 'bench') && isfield(par.bench, 'it_gas') && strcmp(par.bench.it_gas, 'nominal'), pgt_b = opt.pgt_nom(:); end
base_it = d.Pfix + d.pdyn * (par.it.k_inf * sc.inf(:,1) + sc.fix(:,1));
qac = min(par.ac.cop * d.kh * pgt_b, par.ac.Qmax);
fac_other = (1 + a) * base_it + par.fac.P_aux0 + (th * base_it + par.fac.Q0 - qac) ./ sc.cop(:,1) ...
            - pgt_b - sc.pv(:,1);
budget = d.Pcap - fac_other;
if capon
    m = lpb_addle(m, repmat(r, 6, 1), [Y{1}; Y{2}; Y{3}; Z{1}; Z{2}; Z{3}], [repmat(phi * d.pdyn, 3, 1); -repmat(phi * d.pdyn, 3, 1)], max(budget, 0));
else
    m = lpb_addle(m, [r; r; r], [Y{1}; Y{2}; Y{3}], repmat(phi * d.pdyn, 3, 1), max(budget, 0));
end
for c = 1:3
    L = d.lag(c); remc = st.rem(:, c); B0 = sum(remc);
    Dk = cumsum(remc); Dk = Dk(min(t0 + (0:H-1)', numel(Dk)));
    arr = sc.flex(:, c, 1) * dt; arr(1) = 0;
    A = B0 + cumsum(arr); Dn = zeros(H,1);
    if H > L, Dn(L+1:end) = cumsum(arr(1:H-L)); end
    Bmax = max(A - (Dk + Dn), 0);
    I = [r; r; (2:H)']; J = [B{c}; Y{c}; B{c}(1:end-1)]; Vv = [one; dt*one; -ones(H-1,1)];
    if capon && cv.linear, I = [I; r]; J = [J; Z{c}]; Vv = [Vv; -dt * cv.s(1) * one]; end
    if capon && ~cv.linear, I = [I; r]; J = [J; LZ{c}]; Vv = [Vv; -dt * one]; end
    if povh(c) > 0                      % pause / resume overhead (as in BUILD_MODEL)
        [m, PIc] = lpb_addvar(m, H, 0, Inf, 0);
        I = [I; r]; J = [J; PIc]; Vv = [Vv; -povh(c) * one];
        a0 = 0; if isfield(st, 'arr'), a0 = st.arr(c); end
        dp = 0; if isfield(st, 'dprev'), dp = st.dprev(c); end
        fl = sc.flex(:, c, 1); fl(1) = a0;
        m = lpb_addle(m, [r; r; (2:H)'], [PIc; Y{c}; Y{c}(1:end-1)], [-one; -one; ones(H-1, 1)], -[fl(1) - dp; diff(fl)]);
    end
    rhs = arr; rhs(1) = rhs(1) + B0;
    m = lpb_addeq(m, I, J, Vv, rhs);
    m = lpb_addle(m, [r; r], [B{c}; V{c}], [one; -one], Bmax);
    if t0 + H - 1 >= par.Tsim, m.f(B{c}(H)) = m.f(B{c}(H)) + d.c_B_end; end
    % optional rigid-job recovery bound (as in BUILD_MODEL)
    if isfield(par.it, 'rec_tau') && numel(par.it.rec_tau) >= c && par.it.rec_tau(c) > 0
        tau = par.it.rec_tau(c); a0 = 0; if isfield(st, 'arr'), a0 = st.arr(c); end
        rb = sc.flex(:, c, 1); rb(1) = a0 + max(B0 - a0 * dt, 0) / tau;
        m = lpb_addle(m, [r; (2:H)'], [Y{c}; B{c}(1:end-1)], [one; -ones(H-1, 1) / tau], rb);
    end
end
% limit on the swing of deferrable IT power (same soft limit as in the joint model)
if isfinite(par.it.ramp_max)
    Rr = par.it.ramp_max / d.pdyn;
    [m, RU] = lpb_addvar(m, H, 0, Inf, dt * par.it.c_ramp * d.pdyn);
    [m, RD] = lpb_addvar(m, H, 0, Inf, dt * par.it.c_ramp * d.pdyn);
    if isfield(st, 'y_prev') && ~isnan(st.y_prev)
        m = lpb_addle(m, ones(4,1), [Y{1}(1); Y{2}(1); Y{3}(1); RU(1)], [1;1;1;-1], Rr + st.y_prev);
        m = lpb_addle(m, ones(4,1), [Y{1}(1); Y{2}(1); Y{3}(1); RD(1)], [-1;-1;-1;-1], Rr - st.y_prev);
    end
    if H > 1
        rr = (1:H-1)'; I = repmat(rr, 7, 1);
        J = [Y{1}(2:H); Y{2}(2:H); Y{3}(2:H); Y{1}(1:H-1); Y{2}(1:H-1); Y{3}(1:H-1)];
        vv = [ones(3*(H-1), 1); -ones(3*(H-1), 1)];
        m = lpb_addle(m, I, [J; RU(2:H)], [vv; -ones(H-1, 1)], Rr * ones(H-1, 1));
        m = lpb_addle(m, I, [J; RD(2:H)], [-vv; -ones(H-1, 1)], Rr * ones(H-1, 1));
    end
end
% DR share of the IT side (per-step power-reduction target relative to nominal execution)
ynom = sum(sc.flex(:, :, 1), 2); ynom(1) = opt.ynom_now;
for k = 1:numel(ev)
    e = ev(k);
    if ~use_share, break; end
    if ~opt.visible(k) || e.e < t0 || e.s > t0 + H - 1, continue; end
    hk = (max(e.s, t0):min(e.e, t0 + H - 1)) - t0 + 1; nh = numel(hk);
    [m, SFC] = lpb_addvar(m, nh, 0, Inf, dt * e.price * (1 + par.dr.kappa_dev));
    tgt = opt.alpha * e.C;
    rr = (1:nh)';
    I = [rr; rr; rr; rr]; J = [Y{1}(hk); Y{2}(hk); Y{3}(hk); SFC];
    Vv = [repmat(phi(hk) * d.pdyn, 3, 1); -ones(nh,1)];
    if capon
        I = [I; rr; rr; rr]; J = [J; Z{1}(hk); Z{2}(hk); Z{3}(hk)]; Vv = [Vv; -repmat(phi(hk) * d.pdyn, 3, 1)];
    end
    m = lpb_addle(m, I, J, Vv, phi(hk) * d.pdyn .* ynom(hk) - tgt);
end
P = lpb_finalize(m);
ix.Y = Y; ix.B = B; ix.V = V; ix.H = H; ix.Zc = []; if capon, ix.Zc = Z; end
end
