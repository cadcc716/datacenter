function out = run_closed_loop(par, D, base, ev, planner, ctx)
%RUN_CLOSED_LOOP  Simulate the plant over par.Tsim steps with a planner function handle.
%   D: realised data (flex Tx3, inf, pv, cop). Returns logged time series and final state.
T = par.Tsim;
st = state_init(par, numel(ev));
if isfield(ctx, 'st0') && ~isempty(ctx.st0), st = state_fit_events(ctx.st0, numel(ev)); end
t1 = st.t; t2 = T; if isfield(ctx, 't_stop') && ~isempty(ctx.t_stop), t2 = ctx.t_stop; end
f = {'pg','pit','pch','pdis','E','S','pgt','qac','qec','qtc','qtd','ppv','pv','cop','overdue','over','inf','TH','qth','povh', ...
     'php','qb','H','qdh'};
for i = 1:numel(f), L.(f{i}) = zeros(T, 1); end
L.y = zeros(T, 3); L.z = zeros(T, 3); L.backlog = zeros(T, 3); L.solve_time = zeros(T,1); L.fallback = false(T,1);
for t = t1:t2
    st = add_arrivals(st, D.flex(t, :), par);
    data = struct('inf', D.inf(t), 'fix', D.fix(t), 'pv', D.pv(t), 'cop', D.cop(t), 'qdh', 0);
    if isfield(D, 'qdh'), data.qdh = D.qdh(t); end           % heat-network demand (waste-heat recovery option)
    [u, info] = planner(st, data, ctx);
    [st, rec] = plant_step(st, u, par, data, base, ev);
    for i = 1:numel(f), L.(f{i})(t) = rec.(f{i}); end
    L.y(t, :) = rec.y; L.z(t, :) = rec.z; L.backlog(t, :) = rec.backlog;
    L.solve_time(t) = info.time; L.fallback(t) = info.fallback;
end
out.log = L; out.st = st;
end
