function DA = dayahead_commit(ctx, mode, Smode, risk)
%DAYAHEAD_COMMIT  Day-ahead DR commitment of the AIDC-IES.
%   mode = 'coupled' : two-stage stochastic MILP over the whole day; commitments C_k are first-stage
%                      decisions shared by all scenarios, the second stage is the joint
%                      computing-storage recovery model (all events together -> cross-event coupling)
%        = 'single'  : conventional single-event capability assessment - each event is assessed
%                      alone from the nominal state, ignoring the other events
%   Smode = 'scenario' (default) or 'expected'.
%   risk  = [] (expected cost, two-stage stochastic programme) or a risk measure of the scenario costs
%           (Proposition 3): struct('type','dro','delta',d) - worst case over the l1 ball of radius d
%           around the empirical scenario probabilities (d = 2: scenario-robust), or
%           struct('type','cvar','beta',b,'w',w) - (1-w) E + w CVaR_b. Exact MILP reformulation.
%   DA.fs: in-sample second-stage cost of every scenario at the optimum.
if nargin < 3 || isempty(Smode), Smode = 'scenario'; end
if nargin < 4, risk = []; end
par = ctx.par; K = numel(ctx.ev);
c = ctx; c.fmode = Smode; c.da = true;
sc = make_scen(ctx.inp, par, ctx.base, 1, par.Tsim, c);
st = state_init(par, K);
st = add_arrivals(st, sc.flex(1, :, 1), par);
sc.flex(1, :, :) = repmat(sc.flex(1, :, 1), [1 1 sc.S]);   % identical first step
sc.inf(1, :) = sc.inf(1, 1); sc.fix(1, :) = sc.fix(1, 1); sc.pv(1, :) = sc.pv(1, 1);
% events with call probability < 1 occur only in round(prob*S) of the scenarios (scen_called)
amode = 'scenario'; if sc.S == 1, amode = 'ce'; end
act = event_activity(ctx, 1, sc.S, amode);
opt = struct('milp', true, 'visible', any(act, 2), 'active', act, 'terminal', true, 'Eref_end', ctx.Eref(end), ...
             'Sref_end', ctx.Sref(end), 'Cmax', 15);
opt.risk = risk;
DA.C = zeros(K, 1); DA.mode = mode;
switch mode
    case 'coupled'
        ev = ctx.ev; for k = 1:K, ev(k).mode = 'commit'; end
        [P, ix] = build_model(par, st, sc, ev, opt);
        sol = solve_milp(P, ctx.solver);
        if ~sol.ok, error('dayahead_commit:infeasible', 'coupled day-ahead model not solved'); end
        for k = 1:K, DA.C(k) = sol.x(ix.ev(k).C); end
        DA.obj = sol.fval; DA.time = sol.time;
        DA.Eplan = mean(sol.x(ix.E), 2); DA.Splan = mean(sol.x(ix.SS), 2);
        DA.valid_prob = zeros(K,1);
        for k = 1:K, DA.valid_prob(k) = mean(round(sol.x(ix.ev(k).Z))); end
        DA.prob = sc.prob(:); DA.risk = risk;
        if ~isempty(ix.G)
            DA.fs = sol.x(ix.G);
        else                                   % expected-cost model: rebuild f_s from the weighted costs
            DA.fs = zeros(sc.S, 1);
            for s = 1:sc.S, j = ix.scen == s; DA.fs(s) = P.f(j)' * sol.x(j) / sc.prob(s); end
        end
        DA.Z = zeros(K, sc.S);
        for k = 1:K, DA.Z(k, :) = round(sol.x(ix.ev(k).Z(:)))'; end
    case 'single'
        DA.time = 0;
        for k = 1:K
            ev = ctx.ev; for j = 1:K, ev(j).mode = 'none'; end
            ev(k).mode = 'commit';
            [P, ix] = build_model(par, st, sc, ev, opt);
            sol = solve_milp(P, ctx.solver);
            if ~sol.ok, error('dayahead_commit:infeasible', 'single-event model not solved'); end
            DA.C(k) = sol.x(ix.ev(k).C); DA.time = DA.time + sol.time;
        end
end
end
