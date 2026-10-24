function [u, info] = planner_jr(st, data, ctx)
%PLANNER_JR  Joint computing-storage recovery: solve the joint model on a rolling horizon and apply
%   the first-step decisions. ctx.fmode: 'oracle' | 'expected' (deterministic, certainty-equivalent
%   event calls) | 'scenario' (scenario MPC; unconfirmed events enter as a scenario tree).
%   ctx.myopic = true gives the event-by-event joint benchmark JR-M.
par = ctx.par; t0 = st.t;
H = min(ctx.H, par.Tsim - t0 + 1);
sc = make_scen(ctx.inp, par, ctx.base, t0, H, ctx);
switch ctx.fmode
    case 'scenario', amode = 'scenario';
    case 'oracle',   amode = 'oracle';
    otherwise,       amode = 'ce';
end
opt = struct('milp', ctx.milp, 'nonant', true);
opt.active = event_activity(ctx, t0, sc.S, amode);
opt.visible = any(opt.active, 2);
[opt.terminal, opt.Eref_end, opt.Sref_end] = terminal_ref(ctx, t0 + H - 1);
[P, ix] = build_model(par, st, sc, ctx.ev, opt);
sol = solve_milp(P, mpc_solver(ctx));
info.ok = sol.ok; info.time = sol.time;
if ~sol.ok
    [u, ~] = planner_irr(st, data, ctx); info.fallback = true; return;
end
info.fallback = false;
u = first_step(sol.x, ix);
info.sol = sol; info.ix = ix;
end
