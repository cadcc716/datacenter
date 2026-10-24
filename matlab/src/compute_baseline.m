function [base, ref] = compute_baseline(par, inp)
%COMPUTE_BASELINE  DR baseline per the Jiangsu rule (mean load of the 5 previous normal workdays,
%   each simulated with business-as-usual operation) and the no-DR reference on the DR day.
nb = numel(inp.base.flex);
P = zeros(par.Tsim, nb);
noev = struct('s', {}, 'e', {}, 'win', {});
for i = 1:nb
    D = struct('flex', inp.base.flex{i}, 'fix', inp.base.fix{i}, 'inf', inp.base.inf{i}, 'pv', inp.base.pv{i}, 'cop', inp.base.cop{i});
    if isfield(inp.base, 'qdh'), D.qdh = inp.base.qdh{i}; end
    o = run_closed_loop(par, D, zeros(par.Tsim,1), noev, @(st, data, ctx) wrap_nom(st, data, ctx), struct('par', par, 'inp', inp));
    P(:, i) = o.log.pg;
end
base = mean(P, 2);
base(par.Tday+1:end) = base(1:par.Tsim - par.Tday);    % D+1 morning: same typical-day profile
ref = run_closed_loop(par, inp.real, base, noev, @(st, data, ctx) wrap_nom(st, data, ctx), struct('par', par, 'inp', inp));
ref.P_base_days = P;
end

function [u, info] = wrap_nom(st, data, ctx)
u = planner_nominal(st, ctx.par, data, ctx.inp.price(st.t));
info.ok = true; info.time = 0; info.fallback = false;
end
