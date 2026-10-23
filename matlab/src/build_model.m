function [P, ix] = build_model(par, st, sc, ev, opt)
%BUILD_MODEL  Joint computing-storage recovery model of the AIDC-IES over a (rolling) horizon.
%
%   State at t0 = st.t (work arriving in t0 already in st.rem).  Scenario data sc:
%     sc.H, sc.S, sc.prob(Sx1), sc.flex(Hx3xS) nominal busy GPUs, sc.inf(HxS), sc.pv(HxS),
%     sc.cop(HxS), sc.price(Hx1) CNY/MWh, sc.Pb(Hx1) DR baseline (MW)
%   Events ev(k): s,e (absolute steps), C, price, win, Pbmax, and ev(k).mode in
%     'settle'  Jiangsu settlement (validity >= 80 %, pay <= 120 %), MILP if opt.milp
%     'hard'    reduction >= C in every step (capability analysis)
%     'max'     maximise a common reduction level (capability analysis)
%     'commit'  day-ahead: commitment C is a first-stage decision variable
%     'none'    ignored
%   opt: milp, nonant, fix_y (Hx3), terminal, Eref_end, Sref_end, no_late, visible (Kx1 logical),
%        active (KxS logical, event happens in scenario s; default = visible), Cmax (for 'commit'),
%        w_max (weight of 'max'), risk (risk measure of the scenario costs instead of their
%        expectation, see ADD_RISK: struct with type 'dro' (delta) or 'cvar' (beta, w); [] = expectation)
%   Optional par fields used: par.dr.c_pre (pre-event load-up assessment), par.it.ramp_max (limit on
%   deferrable IT power swings), terminal backlog value d.c_B_end when the horizon reaches par.Tsim.
%
%   Decision variables per step and scenario: y_c (busy GPUs, 3 classes), backlog B_c, overdue v_c,
%   grid pg, overflow pov, BESS pch/pdis/E, gas engine pgt, absorption heat hac, electric chiller qec,
%   TES qtc/qtd/S, PV ppv.
if nargin < 5, opt = struct(); end
opt = defaults(opt, numel(ev));
d = sys_derived(par); dt = par.dt; H = sc.H; S = sc.S; t0 = st.t;
if isempty(opt.active), opt.active = repmat(logical(opt.visible(:)), 1, S); end
if size(opt.active, 2) == 1 && S > 1, opt.active = repmat(opt.active, 1, S); end
pr = sc.prob(:)';
m = lpb_new();
W = @(c) dt * repmat(pr, H, 1) .* c;     % cost weight helper (c: HxS or scalar)

%% variables
for c = 1:3
    [m, Y{c}] = addb(m, H, S, 0, Inf, 0);
    [m, B{c}] = addb(m, H, S, 0, Inf, W(par.qos.c_jct));
    vub = Inf; if opt.no_late, vub = 0; end
    [m, V{c}] = addb(m, H, S, 0, vub, W(par.qos.c_late));
end
[m, PG]  = addb(m, H, S, par.cap.Pmin, Inf, W(repmat(sc.price(:), 1, S)));
[m, POV] = addb(m, H, S, 0, Inf, W(par.cap.c_over));
[m, PCH] = addb(m, H, S, 0, par.bess.Pmax, W(par.bess.c_deg));
[m, PDS] = addb(m, H, S, 0, par.bess.Pmax, W(par.bess.c_deg));
[m, E]   = addb(m, H, S, par.bess.Emin, par.bess.Emax, 0);
[m, PGT] = addb(m, H, S, 0, par.gt.Pmax, W(par.price.gas / par.gt.eta_e));
[m, HAC] = addb(m, H, S, 0, par.ac.Qmax / par.ac.cop, 0);
[m, QEC] = addb(m, H, S, 0, par.fac.Qec_max, 0);
[m, QTC] = addb(m, H, S, 0, par.tes.Qmax, 0);
[m, QTD] = addb(m, H, S, 0, par.tes.Qmax, 0);
[m, SS]  = addb(m, H, S, par.tes.Smin, par.tes.Smax, 0);
[m, PPV] = addb(m, H, S, 0, Inf, 0);
m.ub(PPV(:)) = max(sc.pv(:), 0);
% optional thermal inertia of the data hall: stored heat TH above the set-point (third recovery state)
th_on = isfield(par, 'th') && par.th.on;
if th_on
    [m, TH]  = addb(m, H, S, -par.th.C * par.th.dT_dn, par.th.C * par.th.dT_up, 0);
    [m, QHC] = addb(m, H, S, 0, Inf, 0);          % heat accumulating in the hall (cooling below the load)
    [m, QHD] = addb(m, H, S, 0, Inf, 0);          % stored heat removed / pre-cooling (cooling above the load)
else
    TH = []; QHC = []; QHD = [];
end
if ~isempty(opt.fix_y)
    for c = 1:3
        v = repmat(opt.fix_y(:, c), 1, S);
        m.lb(Y{c}(:)) = v(:); m.ub(Y{c}(:)) = v(:);
    end
end
n = H * S; one = ones(n, 1); r = (1:n)';

%% optional GPU power capping during DR events (Z = capped GPUs, Z <= Y, only in event steps)
capon = isfield(par.it, 'cap_on') && par.it.cap_on;
for c = 1:3
    if capon, [m, ZC{c}] = addb(m, H, S, 0, Inf, 0); else, ZC{c} = zeros(H, S); end
end
if capon
    evstep = false(H, S);
    for k = 1:numel(ev)
        if strcmp(ev(k).mode, 'none'), continue; end
        hk = (max(ev(k).s, t0):min(ev(k).e, t0 + H - 1)) - t0 + 1;
        if isempty(hk) || hk(1) < 1, continue; end
        for s = 1:S, if opt.active(k, s), evstep(hk, s) = true; end, end
    end
    rc = (1:H*S)';
    for c = 1:3
        m.ub(ZC{c}(~evstep)) = 0;
        m = lpb_addle(m, [rc; rc], [ZC{c}(:); Y{c}(:)], [ones(H*S,1); -ones(H*S,1)], zeros(H*S,1));
        if ~isempty(opt.fix_z)
            v = repmat(opt.fix_z(:, c), 1, S); m.lb(ZC{c}(:)) = v(:); m.ub(ZC{c}(:)) = v(:);
        end
    end
end

%% GPU capacity
capfree = par.it.u_max * par.it.Ngpu - sc.inf - sc.fix;
m = lpb_addle(m, [r; r; r], [Y{1}(:); Y{2}(:); Y{3}(:)], [one; one; one], capfree(:));

%% workload backlog (computing recovery state) with lag-bounded deadlines
for c = 1:3
    L = d.lag(c);
    remc = st.rem(:, c);
    B0 = sum(remc);
    Dk = cumsum(remc); Dk = Dk(min(t0 + (0:H-1)', numel(Dk)));      % known work due by end of step
    arr = squeeze(sc.flex(:, c, :)) * dt; if S == 1, arr = arr(:); end
    arr(1, :) = 0;                                                     % arrivals of t0 already in backlog
    A = B0 + cumsum(arr, 1);
    Dn = zeros(H, S);
    if H > L, Dn(L+1:end, :) = cumsum(arr(1:H-L, :), 1); end
    Bmax = A - (Dk + Dn);
    Bmax = max(Bmax, 0);
    % B(h) - B(h-1) + dt*y(h) = arr(h)
    Bc = B{c}; rhs = arr; rhs(1, :) = rhs(1, :) + B0;
    I = [r; r]; J = [Bc(:); Y{c}(:)]; Vv = [one; dt * one];
    if capon, I = [I; r]; J = [J; ZC{c}(:)]; Vv = [Vv; -dt * par.it.cap_beta * par.it.cap_rho * one]; end
    prev = Bc(1:end-1, :); cur = (2:H)' + (0:S-1) * H;
    I = [I; cur(:)]; J = [J; prev(:)]; Vv = [Vv; -ones(numel(prev), 1)];
    [m, ix.row_B{c}] = lpb_addeq(m, I, J, Vv, rhs(:));
    [m, ix.row_Bmax{c}] = lpb_addle(m, [r; r], [Bc(:); V{c}(:)], [one; -one], Bmax(:));
    ix.Bmax{c} = Bmax;
end

%% cooling balance:  qec + COP_ac*hac + qtd - qtc - theta*pdyn*sum(y) = theta*(Pfix + pdyn*k_inf*inf) + Q0
th = par.fac.theta; a = par.fac.a_aux;
base_it = d.Pfix + d.pdyn * (par.it.k_inf * sc.inf + sc.fix);
I = [r; r; r; r; r; r; r]; J = [QEC(:); HAC(:); QTD(:); QTC(:); Y{1}(:); Y{2}(:); Y{3}(:)];
Vv = [one; par.ac.cop * one; one; -one; -th * d.pdyn * [one; one; one]];
if th_on, I = [I; r; r]; J = [J; QHC(:); QHD(:)]; Vv = [Vv; one; -one]; end   % supply + accumulation = load
if capon
    I = [I; r; r; r]; J = [J; ZC{1}(:); ZC{2}(:); ZC{3}(:)]; Vv = [Vv; th * d.pdyn * par.it.cap_rho * [one; one; one]];
end
m = lpb_addeq(m, I, J, Vv, th * base_it(:) + par.fac.Q0);

%% electric balance: pg + ppv + pgt + pdis - pch - qec/cop - (1+a)*pdyn*sum(y) = (1+a)*base_it + P_aux0
I = repmat(r, 9, 1);
J = [PG(:); PPV(:); PGT(:); PDS(:); PCH(:); QEC(:); Y{1}(:); Y{2}(:); Y{3}(:)];
Vv = [one; one; one; one; -one; -1 ./ sc.cop(:); -(1 + a) * d.pdyn * [one; one; one]];
if capon
    I = [I; r; r; r]; J = [J; ZC{1}(:); ZC{2}(:); ZC{3}(:)]; Vv = [Vv; (1 + a) * d.pdyn * par.it.cap_rho * [one; one; one]];
end
[m, ix.row_el] = lpb_addeq(m, I, J, Vv, (1 + a) * base_it(:) + par.fac.P_aux0);

%% leftover backlog at the end of the evaluation window is valued at its energy cost (flat price)
if t0 + H - 1 >= par.Tsim
    for c = 1:3, m.f(B{c}(H, :)) = m.f(B{c}(H, :)) + d.c_B_end * pr(:); end
end

%% optional limit on deferrable IT power swings (pause / resume of large jobs); soft, so that GPUs
%  can still go idle when the work runs out (excess ramp priced at par.it.c_ramp CNY per MW and step)
if isfinite(par.it.ramp_max)
    Rr = par.it.ramp_max / d.pdyn;                       % GPUs per step
    [m, RU] = addb(m, H, S, 0, Inf, W(par.it.c_ramp * d.pdyn));
    [m, RD] = addb(m, H, S, 0, Inf, W(par.it.c_ramp * d.pdyn));
    for s = 1:S
        for h = 1:H
            if h == 1
                if ~isfield(st, 'y_prev') || isnan(st.y_prev), continue; end
                cols = [Y{1}(1, s); Y{2}(1, s); Y{3}(1, s)];
                m = lpb_addle(m, ones(4,1), [cols; RU(1, s)], [1;1;1;-1], Rr + st.y_prev);
                m = lpb_addle(m, ones(4,1), [cols; RD(1, s)], [-1;-1;-1;-1], Rr - st.y_prev);
            else
                cols = [Y{1}(h, s); Y{2}(h, s); Y{3}(h, s); Y{1}(h-1, s); Y{2}(h-1, s); Y{3}(h-1, s)];
                vv = [1;1;1;-1;-1;-1];
                m = lpb_addle(m, ones(7,1), [cols; RU(h, s)], [vv; -1], Rr);
                m = lpb_addle(m, ones(7,1), [cols; RD(h, s)], [-vv; -1], Rr);
            end
        end
    end
end

%% grid connection limit
[m, ix.row_cap] = lpb_addle(m, [r; r], [PG(:); POV(:)], [one; -one], d.Pcap * one);

%% storage dynamics
[m, ix.row_E] = add_store(m, E,  PCH, PDS, par.bess.eta_c, 1 / par.bess.eta_d, 1, st.E, dt, H, S);
[m, ix.row_S] = add_store(m, SS, QTC, QTD, par.tes.eta_c,  1 / par.tes.eta_d, 1 - par.tes.loss * dt, st.S, dt, H, S);
if th_on
    th0 = 0; if isfield(st, 'TH'), th0 = st.TH; end
    [m, ix.row_TH] = add_store(m, TH, QHC, QHD, 1, 1, 1 - par.th.loss * dt, th0, dt, H, S);
end

%% gas engine heat recovery and ramping
m = lpb_addle(m, [r; r], [HAC(:); PGT(:)], [one; -d.kh * one], zeros(n, 1));
cur = (2:H)' + (0:S-1) * H; cur = cur(:); nr = numel(cur); rr = (1:nr)';
if nr > 0
    m = lpb_addle(m, [rr; rr], [PGT(cur); PGT(cur - 1)], [ones(nr,1); -ones(nr,1)], par.gt.ramp * ones(nr,1));
    m = lpb_addle(m, [rr; rr], [PGT(cur); PGT(cur - 1)], [-ones(nr,1); ones(nr,1)], par.gt.ramp * ones(nr,1));
end
m.ub(PGT(1, :)) = min(par.gt.Pmax, st.pgt_prev + par.gt.ramp);
m.lb(PGT(1, :)) = max(0, st.pgt_prev - par.gt.ramp);

%% non-anticipativity of the first-step decisions
if S > 1 && opt.nonant
    X = {Y{1}, Y{2}, Y{3}, PCH, PDS, PGT, HAC, QEC, QTC, QTD, PPV};
    if capon, X = [X, {ZC{1}, ZC{2}, ZC{3}}]; end
    if th_on, X = [X, {QHC, QHD}]; end
    for q = 1:numel(X)
        xx = X{q}; ns = S - 1; rr = (1:ns)';
        m = lpb_addeq(m, [rr; rr], [xx(1, 2:S)'; repmat(xx(1, 1), ns, 1)], [ones(ns,1); -ones(ns,1)], zeros(ns,1));
    end
end

%% demand-response events (Jiangsu settlement), rebound windows
ix.ev = struct('R', {}, 'Z', {}, 'SF', {}, 'MX', {}, 'RHO', {}, 'C', {}, 'row_rb', {}, 'hw', {});
tend = t0 + H - 1;
act = opt.active;
for k = 1:numel(ev)
    e = ev(k); ix.ev(k).C = [];
    if strcmp(e.mode, 'none') || ~any(act(k, :)), continue; end
    % ---- event window ----
    if e.e >= t0 && e.e <= tend
        hk = (max(e.s, t0):e.e) - t0 + 1; nk = e.e - e.s + 1; Dh = nk * dt;
        rhs0 = (st.ev_r(k) + sum(sc.Pb(hk))) / nk;
        nh = numel(hk);
        vmar = 0; if isfield(par.dr, 'valid_margin'), vmar = par.dr.valid_margin; end   % planning margin above 80 %
        switch e.mode
            case 'settle'
                [m, R]  = addb(m, 1, S, 0, par.dr.pay_hi * e.C, -e.price * Dh * pr);
                [m, Z]  = addb(m, 1, S, 0, 1, 0); m.isint(Z) = opt.milp;
                [m, SF] = addb(m, 1, S, 0, Inf, par.dr.kappa_dev * e.price * Dh * pr);
                [m, MX] = addb(m, 1, S, 0, Inf, par.dr.c_maxload * pr);
                if st.ev_mx(k) > e.Pbmax + 1e-6, m.ub(Z) = 0; end
                for s = 1:S
                    if ~act(k, s), m.ub([R(s); Z(s); SF(s); MX(s)]) = 0; continue; end
                    pgk = PG(hk, s);
                    m = lpb_addle(m, ones(nh+1,1), [R(s); pgk], [1; ones(nh,1)/nk], rhs0);
                    m = lpb_addle(m, [1; 1], [R(s); Z(s)], [1; -par.dr.pay_hi * e.C], 0);
                    m = lpb_addle(m, ones(nh+1,1), [Z(s); pgk], [par.dr.valid_lo * e.C + vmar; ones(nh,1)/nk], rhs0);
                    m = lpb_addle(m, ones(nh+1,1), [SF(s); pgk], [-1; ones(nh,1)/nk], rhs0 - e.C);
                    m = lpb_addle(m, [(1:nh)'; (1:nh)'], [pgk; repmat(MX(s), nh, 1)], [ones(nh,1); -ones(nh,1)], e.Pbmax * ones(nh,1));
                end
                ix.ev(k).R = R; ix.ev(k).Z = Z; ix.ev(k).SF = SF; ix.ev(k).MX = MX;
            case 'commit'
                [m, Cv] = addb(m, 1, 1, 0, opt.Cmax, -par.dr.eps_commit); m.scen(Cv) = 0;   % first stage
                [m, R]  = addb(m, 1, S, 0, Inf, -e.price * Dh * pr);
                [m, Z]  = addb(m, 1, S, 0, 1, 0); m.isint(Z) = opt.milp;
                [m, Wv] = addb(m, 1, S, 0, opt.Cmax, 0);
                [m, SF] = addb(m, 1, S, 0, Inf, par.dr.kappa_dev * e.price * Dh * pr);
                [m, MX] = addb(m, 1, S, 0, Inf, par.dr.c_maxload * pr);
                Cm = opt.Cmax;
                for s = 1:S
                    if ~act(k, s), m.ub([R(s); Z(s); Wv(s); SF(s); MX(s)]) = 0; continue; end
                    pgk = PG(hk, s);
                    m = lpb_addle(m, [1;1], [Wv(s); Z(s)], [1; -Cm], 0);
                    m = lpb_addle(m, [1;1], [Wv(s); Cv], [1; -1], 0);
                    m = lpb_addle(m, [1;1;1], [Cv; Wv(s); Z(s)], [1; -1; Cm], Cm);
                    m = lpb_addle(m, ones(nh+1,1), [R(s); pgk], [1; ones(nh,1)/nk], rhs0);
                    m = lpb_addle(m, [1;1], [R(s); Wv(s)], [1; -par.dr.pay_hi], 0);
                    m = lpb_addle(m, ones(nh+2,1), [Wv(s); Z(s); pgk], [par.dr.valid_lo; vmar; ones(nh,1)/nk], rhs0);
                    m = lpb_addle(m, ones(nh+2,1), [Cv; SF(s); pgk], [1; -1; ones(nh,1)/nk], rhs0);
                    m = lpb_addle(m, [(1:nh)'; (1:nh)'], [pgk; repmat(MX(s), nh, 1)], [ones(nh,1); -ones(nh,1)], e.Pbmax * ones(nh,1));
                end
                ix.ev(k).R = R; ix.ev(k).Z = Z; ix.ev(k).SF = SF; ix.ev(k).MX = MX; ix.ev(k).C = Cv;
            case 'hard'
                for s = find(act(k, :))
                    m.ub(PG(hk, s)) = min(m.ub(PG(hk, s)), max(sc.Pb(hk) - e.C, 0));
                end
            case 'max'
                [m, Cv] = addb(m, 1, 1, 0, Inf, -opt.w_max); m.scen(Cv) = 0;
                for s = find(act(k, :))
                    m = lpb_addle(m, [(1:nh)'; (1:nh)'], [PG(hk, s); repmat(Cv, nh, 1)], ones(2*nh,1), sc.Pb(hk));
                end
                ix.ev(k).C = Cv;
        end
    end
    % ---- post-event rebound window ----
    if any(strcmp(e.mode, {'settle', 'commit'})) && ~isempty(e.win)
        w = e.win(e.win >= t0 & e.win <= tend);
        if ~isempty(w) && e.e <= tend
            hw = w - t0 + 1; nw = numel(hw);
            [m, RHO] = addb(m, 1, S, max(st.rb(k), 0), Inf, par.dr.c_rb * pr);
            rows_rb = zeros(nw, S);
            for s = 1:S
                if ~act(k, s), m.lb(RHO(s)) = 0; m.ub(RHO(s)) = 0; continue; end
                [m, rows_rb(:, s)] = lpb_addle(m, [(1:nw)'; (1:nw)'], [PG(hw, s); repmat(RHO(s), nw, 1)], [ones(nw,1); -ones(nw,1)], sc.Pb(hw));
            end
            ix.ev(k).RHO = RHO; ix.ev(k).row_rb = rows_rb; ix.ev(k).hw = hw;
        end
    end
end

%% optional pre-event load-up assessment: (pg - baseline)^+ in the window before the first event
if par.dr.c_pre > 0 && ~isempty(ev)
    s1 = min([ev(any(act, 2)).s]);
    if ~isempty(s1)
        wp = max(1, s1 - round(par.dr.pre_win_h / dt)):(s1 - 1);
        wp = wp(wp >= t0 & wp <= tend);
        if ~isempty(wp)
            hp = wp - t0 + 1; np = numel(hp);
            [m, UP] = addb(m, np, S, 0, Inf, par.dr.c_pre * dt * repmat(pr, np, 1));
            for s = 1:S
                m = lpb_addle(m, [(1:np)'; (1:np)'], [PG(hp, s); UP(:, s)], [ones(np,1); -ones(np,1)], sc.Pb(hp));
            end
        end
    end
end

%% terminal state values (rolling horizon shorter than the simulation)
if opt.terminal
    [m, eE] = addb(m, 1, S, 0, Inf, par.term.c_E * pr);
    [m, eS] = addb(m, 1, S, 0, Inf, par.term.c_S * pr);
    for s = 1:S
        m = lpb_addle(m, [1;1], [E(H, s); eE(s)], [-1; -1], -opt.Eref_end);
        m = lpb_addle(m, [1;1], [SS(H, s); eS(s)], [-1; -1], -opt.Sref_end);
    end
    if th_on                                   % heat still stored at the end must be removed later
        [m, eT] = addb(m, 1, S, 0, Inf, par.term.c_S * pr);
        for s = 1:S, m = lpb_addle(m, [1;1], [TH(H, s); eT(s)], [1; -1], 0); end
    end
end

%% optional cumulative policy constraints over the window 1..t0+H-1 (accrued values in st.acc), soft
%  acc = [facility MWh, IT MWh, PV MWh used, consumption MWh (grid + PV + gas engine)]
acc = zeros(1, 4); if isfield(st, 'acc'), acc = st.acc(1:4); end
pol = struct('pue_max', Inf, 'green_min', 0);
if isfield(par, 'pol'), pol = par.pol; end
if pol.pue_max < Inf                          % electric PUE: sum facility <= PUE_max * sum IT
    U = pol.pue_max; kk = (1 + a - U) * d.pdyn;
    [m, SLP] = addb(m, 1, S, 0, Inf, pol.c_pue * pr);
    for s = 1:S
        cols = [Y{1}(:, s); Y{2}(:, s); Y{3}(:, s); QEC(:, s); SLP(s)];
        vals = [repmat(dt * kk, 3 * H, 1); dt ./ sc.cop(:, s); -1];
        if capon
            cols = [cols; ZC{1}(:, s); ZC{2}(:, s); ZC{3}(:, s)]; vals = [vals; repmat(-dt * kk * par.it.cap_rho, 3 * H, 1)];
        end
        rhs = -acc(1) + U * acc(2) - sum(dt * ((1 + a - U) * base_it(:, s) + par.fac.P_aux0));
        m = lpb_addle(m, ones(numel(cols), 1), cols, vals, rhs);
    end
end
GG = [];
if pol.green_min > 0                          % green share: PV + purchased green power >= g * consumption
    g = pol.green_min;
    [m, GG] = addb(m, H, S, 0, Inf, W(pol.c_green));
    m = lpb_addle(m, [r; r], [GG(:); PG(:)], [one; -one], zeros(n, 1));
    [m, SLG] = addb(m, 1, S, 0, Inf, pol.c_green_short * pr);
    for s = 1:S
        cols = [PPV(:, s); GG(:, s); PG(:, s); PGT(:, s); SLG(s)];
        vals = [repmat(-dt * (1 - g), H, 1); repmat(-dt, H, 1); repmat(g * dt, H, 1); repmat(g * dt, H, 1); -1];
        m = lpb_addle(m, ones(numel(cols), 1), cols, vals, acc(3) - g * acc(4));
    end
end

%% risk measure of the scenario costs (day-ahead commitment, Proposition 3)
ix.G = []; ix.risk = [];
if ~isempty(opt.risk) && S > 1
    [m, ix.G, ix.risk] = add_risk(m, pr, opt.risk);
end

P = lpb_finalize(m);
ix.Y = Y; ix.Zc = []; if capon, ix.Zc = ZC; end
ix.B = B; ix.V = V; ix.PG = PG; ix.POV = POV; ix.PCH = PCH; ix.PDS = PDS; ix.E = E;
ix.PGT = PGT; ix.HAC = HAC; ix.QEC = QEC; ix.QTC = QTC; ix.QTD = QTD; ix.SS = SS; ix.PPV = PPV;
ix.TH = TH; ix.QHC = QHC; ix.QHD = QHD; ix.GG = GG;
ix.H = H; ix.S = S; ix.t0 = t0;
ix.scen = zeros(m.n, 1); ix.scen(1:numel(m.scen)) = m.scen(:);
end

%% ----------------------------------------------------------------------
function [m, X] = addb(m, H, S, lb, ub, f)
if numel(f) == 1, f = f * ones(H*S, 1); end
[m, id] = lpb_addvar(m, H*S, lb, ub, f(:));
X = reshape(id, H, S);
if ~isfield(m, 'scen'), m.scen = zeros(0, 1); end
m.scen(id, 1) = kron((1:S)', ones(H, 1));        % scenario of each variable (0 = first stage)
end

function [m, G, rv] = add_risk(m, pr, rk)
%ADD_RISK  Replace the expected scenario cost sum_s pr_s f_s(x) by a risk measure (exact LP reformulation).
%   Every cost coefficient of a scenario variable was built as pr_s * c_j, so f_s(x) = sum_{j in s} c_j x_j.
%   rk.type = 'dro' : worst-case expectation over the l1 ball {p in simplex: ||p - pr||_1 <= rk.delta}
%                     = min eta + sum_s pr_s lam_s + delta*nu  s.t.  f_s <= eta + lam_s, |lam_s| <= nu
%                     (LP duality; delta = 0 -> expectation, delta >= 2(1 - min pr) -> worst scenario)
%           'cvar': (1 - w) E[f] + w CVaR_beta[f],  CVaR = min eta + 1/(1-beta) sum_s pr_s (f_s - eta)^+
S = numel(pr); n0 = m.n;
sc = zeros(n0, 1); sc(1:numel(m.scen)) = m.scen(:);
f = m.f;
big = 1e9;
[m, G] = lpb_addvar(m, S, -big, big, 0);                 % scenario costs f_s(x)
for s = 1:S
    js = find(sc == s & f ~= 0);
    m = lpb_addeq(m, [1; ones(numel(js), 1)], [G(s); js], [-1; f(js) / pr(s)], 0);
end
m.f(sc > 0) = 0;                                         % remove the expectation
rv = struct('type', rk.type);
switch rk.type
    case 'dro'
        [m, eta] = lpb_addvar(m, 1, -big, big, 1);
        [m, lam] = lpb_addvar(m, S, -big, big, pr(:));
        [m, nu]  = lpb_addvar(m, 1, 0, big, rk.delta);
        for s = 1:S
            m = lpb_addle(m, [1; 1; 1], [G(s); eta; lam(s)], [1; -1; -1], 0);
            m = lpb_addle(m, [1; 1], [lam(s); nu], [1; -1], 0);
            m = lpb_addle(m, [1; 1], [lam(s); nu], [-1; -1], 0);
        end
        rv.eta = eta; rv.lam = lam; rv.nu = nu;
    case 'cvar'
        w = rk.w; b = rk.beta;
        m.f(G) = (1 - w) * pr(:);
        [m, eta] = lpb_addvar(m, 1, -big, big, w);
        [m, piv] = lpb_addvar(m, S, 0, big, w / (1 - b) * pr(:));
        for s = 1:S
            m = lpb_addle(m, [1; 1; 1], [G(s); eta; piv(s)], [1; -1; -1], 0);
        end
        rv.eta = eta; rv.pi = piv;
    otherwise
        error('build_model:risk', 'unknown risk type %s', rk.type);
end
end

function [m, rows] = add_store(m, X, PC, PD, eta_c, inv_eta_d, keep, X0, dt, H, S)
% X(h) - keep*X(h-1) - eta_c*dt*PC(h) + dt/eta_d*PD(h) = 0 ; X(0) = X0
n = H*S; r = (1:n)'; one = ones(n,1);
I = [r; r; r]; J = [X(:); PC(:); PD(:)]; V = [one; -eta_c*dt*one; inv_eta_d*dt*one];
cur = (2:H)' + (0:S-1) * H; prev = X(1:end-1, :);
I = [I; cur(:)]; J = [J; prev(:)]; V = [V; -keep * ones(numel(prev), 1)];
rhs = zeros(H, S); rhs(1, :) = keep * X0;
[m, rows] = lpb_addeq(m, I, J, V, rhs(:));
end

function opt = defaults(opt, K)
f = {'milp', true; 'nonant', true; 'fix_y', []; 'terminal', false; 'Eref_end', 0; 'Sref_end', 0; ...
     'no_late', false; 'fix_z', []; 'visible', true(K,1); 'Cmax', 15; 'w_max', 1e7; 'active', []; 'risk', []};
for i = 1:size(f,1)
    if ~isfield(opt, f{i,1}), opt.(f{i,1}) = f{i,2}; end
end
if numel(opt.visible) == 1, opt.visible = repmat(opt.visible, K, 1); end
end
