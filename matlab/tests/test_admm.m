% Smoke test of the distributed joint recovery (ADMM_PLAN, PLANNER_ADMM): the open-loop ADMM plan of the
% case day reaches the joint optimum (implementable cost within 0.05 %), and the closed-loop JR-A keeps
% every event valid.
here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); dcdr_setup_paths();
par0 = dcdr_params(); ctx = setup_case(par0); par = ctx.par;
c = ctx; c.fmode = 'oracle';
st = state_init(par, 3); st = add_arrivals(st, ctx.inp.real.flex(1, :), par);
sc = make_scen(ctx.inp, par, ctx.base, 1, par.Tsim, c);
act = event_activity(ctx, 1, 1, 'oracle');
opt = struct('milp', false, 'visible', any(act, 2), 'active', act, 'terminal', true, ...
             'Eref_end', ctx.Eref(end), 'Sref_end', ctx.Sref(end), 'Href_end', 0);
[P, ix] = build_model(par, st, sc, ctx.ev, opt);
Zv = []; for k = 1:numel(ix.ev), Zv = [Zv; ix.ev(k).Z(:)]; end
P.intcon = []; P.lb(Zv) = 1; s = solve_milp(P, ctx.solver);
out = admm_plan(par, st, sc, ctx.ev, opt, struct('rho', 200, 'K', 60, 'solver', ctx.solver));
o = opt; o.fix_y = out.y; [Pf, ixf] = build_model(par, st, sc, ctx.ev, o);
Zf = []; for k = 1:numel(ixf.ev), Zf = [Zf; ixf.ev(k).Z(:)]; end
Pf.intcon = []; Pf.lb(Zf) = 1; sf = solve_milp(Pf, ctx.solver);
gap = sf.fval / s.fval - 1;
fprintf('ADMM: %d iterations, primal residual %.3f MW, implementable gap %.4f%%\n', out.it, out.hist(end, 2), 100 * gap);
assert(sf.ok && gap < 5e-4, 'ADMM plan does not reach the joint optimum');
c = ctx; c.admm = struct('rho', 200, 'K', 3, 'tol', 0.01);
R = run_strategy(c, 'JR-A', 'expected');
fprintf('closed loop JR-A (K = 3): net %.0f, valid %d\n', R.M.net_cost_adj, R.M.n_valid);
assert(R.M.n_valid == 3, 'JR-A lost an event');
disp('test_admm passed');
