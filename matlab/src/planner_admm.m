function [u, info] = planner_admm(st, data, ctx)
%PLANNER_ADMM  Distributed joint recovery JR-A on a rolling horizon (review, innovation direction 3):
%   at every step the IT scheduler and the facility EMS run ctx.admm.K iterations of ADMM_PLAN on the
%   deterministic forecast, warm-started from the previous step's price and facility plan (shifted by
%   one step). Each side applies the first step of its own plan; neither sees the other's model, they
%   exchange H prices and H power values per iteration. ctx.admm: rho, K, tol, solver (see ADMM_PLAN).
persistent mem
par = ctx.par; t0 = st.t;
H = min(ctx.H, par.Tsim - t0 + 1);
c = ctx; if strcmp(c.fmode, 'scenario'), c.fmode = 'expected'; end
sc = make_scen(ctx.inp, par, ctx.base, t0, H, c);
amode = 'ce'; if strcmp(c.fmode, 'oracle'), amode = 'oracle'; end
opt = struct('milp', false, 'nonant', true);
opt.active = event_activity(ctx, t0, sc.S, amode); opt.visible = any(opt.active, 2);
[opt.terminal, opt.Eref_end, opt.Sref_end, opt.Href_end] = terminal_ref(ctx, t0 + H - 1);
a = ctx.admm; a.solver = mpc_solver(ctx); a.ynom_now = sum(ctx.inp.real.flex(t0, :));
if ~isempty(mem) && mem.t == t0 - 1                % warm start: previous price and facility plan, shifted
    a.lam0 = shift(mem.lam, H); a.pF0 = shift(mem.pF, H);
end
tt = tic; out = admm_plan(par, st, sc, ctx.ev, opt, a);
info.time = toc(tt); info.ok = out.ok; info.fallback = false; info.it = out.it;
if ~out.ok || isempty(out.xF)
    mem = []; [u, ~] = planner_irr(st, data, ctx); info.fallback = true; return;
end
mem = struct('t', t0, 'lam', out.lam, 'pF', out.pF);
u = first_step(out.xF, out.ixF);
u.y = out.y(1, :); u.z = [0 0 0]; if ~isempty(out.z), u.z = out.z(1, :); end
end

function v = shift(x, H)
v = [x(2:end); x(end)]; v = v(1:min(H, numel(v)));
if numel(v) < H, v = [v; repmat(v(end), H - numel(v), 1)]; end
end
