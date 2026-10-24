function [b, T] = region_bound(ctx, runs)
%REGION_BOUND  Multi-event energy bound of the joint-recovery capability region (Proposition 4, the
%   K-event form of the energy bound (ii) of Proposition 1, without assumption H1). For a run
%   S = {i, ..., j} of consecutive called events, every deliverable commitment vector satisfies
%     sum_{k in S} C_k D_k <= Xbar(e_j) + Es_max + H_S + g D_S + Delta_S,
%   Xbar(e_j) : deadline-limited virtual-storage capacity at the end of the run, facility MWh
%               (eps * sum_c of the class-c arrivals in the last L_c before e_j, eps at its maximum
%               over the events of the run);
%   Es_max    : energy the BESS and TES can discharge from full (TES at the lowest COP of the events);
%   H_S       : recovery channel of the intervals inside the run, i.e. the connection headroom over
%               the no-DR import with storage idle plus the spare gas-engine output;
%   g D_S     : spare gas-engine output (plus absorption cooling) during the events;
%   Delta_S   : baseline minus no-DR import with storage idle during the events (< 0 when the day's
%               load is above its baseline; 0 under assumption H1).
%   The no-DR import is taken from ctx.ref_eval (the day's own reference run), with its storage actions
%   and PV curtailment removed. Other flexible loads (heat pump of par.hp) are not counted.
%   runs: cell array of index vectors (default: every run of consecutive events, length >= 1).
%   b(r): bound of run r (MWh); T(r, :) = [Xbar, Es_max, H_S, g D_S, Delta_S].
par = ctx.par; d = ctx.d; dt = par.dt; ev = ctx.ev; K = numel(ev);
if nargin < 2 || isempty(runs)
    runs = {};
    for i = 1:K, for j = i:K, runs{end+1} = i:j; end, end %#ok<AGROW>
end
if isfield(ctx, 'ref_eval'), L = ctx.ref_eval.log; else, L = ctx.ref.log; end
cop = ctx.inp.real.cop(:); n = numel(L.pg);
pnom = L.pg(:) - L.pch(:) + L.pdis(:) - (L.qtc(:) - L.qtd(:)) ./ cop(1:n) ...   % storage idle,
       - (L.pv(:) - L.ppv(:));                                                    % no PV curtailment
phi = 1 + par.fac.a_aux + par.fac.theta ./ cop;
b = zeros(numel(runs), 1); T = zeros(numel(runs), 5);
for r = 1:numel(runs)
    S = runs{r}; tE = [];
    for k = S, tE = [tE, ev(k).s:ev(k).e]; end %#ok<AGROW>
    eps_ = max(phi(tE)) * d.pdyn; copmin = min(cop(tE));
    Xbar = 0; ej = ev(S(end)).e;
    for c = 1:3
        w = max(1, ej - d.lag(c) + 1):ej;
        Xbar = Xbar + eps_ * sum(ctx.inp.real.flex(w, c)) * dt;
    end
    Es = par.bess.eta_d * (par.bess.Emax - par.bess.Emin) + par.tes.eta_d * (par.tes.Smax - par.tes.Smin) / copmin;
    gt_add = max(par.gt.Pmax - min(L.pgt(tE)), 0);
    g = gt_add + min(d.kh * gt_add * par.ac.cop, par.ac.Qmax) / copmin;
    H = 0;
    for q = 1:numel(S) - 1
        iv = (ev(S(q)).e + 1):(ev(S(q + 1)).s - 1);
        if isempty(iv), continue; end
        H = H + sum(max(d.Pcap - pnom(iv), 0)) * dt + g * numel(iv) * dt;
    end
    Db = sum(ctx.base(tE) - pnom(tE)) * dt;
    T(r, :) = [Xbar, Es, H, g * numel(tE) * dt, Db];
    b(r) = sum(T(r, :));
end
end
