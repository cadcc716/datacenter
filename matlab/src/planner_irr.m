function [u, info] = planner_irr(st, data, ctx)
%PLANNER_IRR  Independent recovery, rule based (conventional practice):
%   * during an event the IT side cuts alpha*C_k (deferring the most flexible work first),
%     the facility EMS covers the rest with TES then BESS;
%   * after an event the IT side catches up ASAP (EDF, priority on the connection headroom),
%     BESS and TES recharge ASAP to max(TOU reference, readiness for the next announced event)
%     with the headroom that is left;
%   * otherwise TOU schedule.
par = ctx.par; dt = par.dt; t = st.t; d = sys_derived(par);
info.ok = true; info.time = 0; info.fallback = false;
r = rule_common(st, par, data, ctx.inp.price(t));
pdyn = d.pdyn; phi = r.phi;
ev = ctx.ev; known = event_known(ctx, t)';
kin = find(known & t >= [ev.s] & t <= [ev.e], 1);
knext = find(known & [ev.s] > t, 1);
% ---- gas engine / absorption chiller (economic rule) ----
u.pgt = r.pgt; u.hac = r.hac;
u.php = hp_rule(st, par, data, r, ~isempty(kin));    % heat pump off during a known event
qac = min(par.ac.cop * u.hac, par.ac.Qmax);
pit0 = d.Pfix + pdyn * (par.it.k_inf * data.inf + data.fix);   % IT power without deferrable work
grid_est = @(ysum, qtc, qtd, pch, pdis) (1 + par.fac.a_aux) * (pit0 + pdyn * ysum) + par.fac.P_aux0 + ...
    max(par.fac.theta * (pit0 + pdyn * ysum) + par.fac.Q0 - qac - qtd + qtc, 0) / data.cop + pch - pdis - u.pgt - data.pv;
ynom = sum(ctx.inp.real.flex(t, :));
if ~isempty(kin)
    %% ---------------- during event ----------------
    e = ev(kin);
    ytgt = max(sum(r.due), ynom - ctx.alpha * e.C / (phi * pdyn));
    ytgt = min(ytgt, min(sum(r.avail), r.gfree));
    u.y = edf_alloc(st, par, ytgt);
    target = ctx.base(t) - e.C;                              % facility must stay below this
    qtd = min([par.tes.Qmax, max(st.S - par.tes.Smin, 0) * par.tes.eta_d / dt, ...
               max(par.fac.theta * (pit0 + pdyn * sum(u.y)) + par.fac.Q0 - qac, 0)]);
    pg0 = grid_est(sum(u.y), 0, qtd, 0, 0);
    need = max(pg0 - target, 0);
    pdis = min([par.bess.Pmax, need, max(st.E - par.bess.Emin, 0) * par.bess.eta_d / dt]);
    u.qtc = 0; u.qtd = qtd; u.pch = 0; u.pdis = pdis;
else
    %% ---------------- outside events: ASAP recovery, compute first ----------------
    ycap = min(sum(r.avail), r.gfree);
    [qtc_tou, qtd_tou] = tes_rule(st, par, r);
    [pch_tou, pdis_tou] = bess_rule(st, par, r);
    % IT budget with storage idle
    yb = ycap;
    if grid_est(ycap, 0, 0, 0, 0) > d.Pcap
        lo = 0; hi = ycap;
        for it = 1:40, mid = (lo + hi) / 2; if grid_est(mid, 0, 0, 0, 0) > d.Pcap, hi = mid; else, lo = mid; end, end
        yb = max(lo, sum(r.due));
    end
    u.y = edf_alloc(st, par, yb);
    head = max(d.Pcap - grid_est(sum(u.y), 0, 0, 0, 0), 0);
    % storage targets
    Etgt = ctx.Eref(t); Stgt = ctx.Sref(t);
    if ~isempty(knext)
        e = ev(knext);
        Eready = min(par.bess.Emin + (1 - ctx.alpha) * e.C * (e.e - e.s + 1) * dt / par.bess.eta_d, par.bess.Emax);
        Etgt = max(Etgt, Eready);
        Stgt = max(Stgt, par.tes.Smax);
    end
    if st.E < Etgt - 1e-6
        pch = min([par.bess.Pmax, (Etgt - st.E) / (par.bess.eta_c * dt), head]); pdis = 0;
    else
        pch = pch_tou; pdis = pdis_tou;
        if pdis > 0 && ~isempty(knext), pdis = min(pdis, max(st.E - Etgt, 0) * par.bess.eta_d / dt); end
        pch = min(pch, head);
    end
    head = max(head - pch + pdis, 0);
    if st.S < Stgt - 1e-6
        qtc = min([par.tes.Qmax, (Stgt - st.S) / (par.tes.eta_c * dt), head * data.cop]); qtd = 0;
    else
        qtc = min(qtc_tou, head * data.cop); qtd = qtd_tou;
        if ~isempty(knext), qtd = 0; end
    end
    u.pch = pch; u.pdis = pdis; u.qtc = qtc; u.qtd = qtd;
end
end

function [pch, pdis] = bess_rule(st, par, r)
b = par.bess; pch = 0; pdis = 0;
if r.is_valley && r.valley_left > 0, pch = min(b.Pmax, max(b.Emax - st.E, 0) / (b.eta_c * r.valley_left));
elseif r.is_peak, pdis = min(b.Pmax, max(st.E - b.Emin, 0) * b.eta_d / r.peak_left); end
end

function [qtc, qtd] = tes_rule(st, par, r)
s = par.tes; qtc = 0; qtd = 0;
if r.is_valley && r.valley_left > 0, qtc = min(s.Qmax, max(s.Smax - st.S, 0) / (s.eta_c * r.valley_left));
elseif r.is_peak, qtd = min(s.Qmax, max(st.S - s.Smin, 0) * s.eta_d / r.peak_left); end
end
