function out = exp14_timing(ctx, root, opts)
%EXP14_TIMING  Computational performance of Algorithm 1 (run on an otherwise idle machine).
%   (a) one intraday MPC solve at 16:00 (all events in the horizon) for horizon H x scenarios S;
%   (b) the day-ahead coupled commitment model and one MPC solve for 2, 3 and 4 events.
%   Reports model size (variables, binaries, constraints) and wall-clock solve time (median of reps).
if nargin < 3, opts = struct(); end
Hs = getf(opts, 'Hs', [24 48 72]); Ss = getf(opts, 'Ss', [1 5 10]); reps = getf(opts, 'reps', 3);
rows = [];
for S = Ss
    par = ctx.par; par.mpc.S = S;
    c = setup_case(par, ctx.inp); c = apply_commit(c, [6 6 6]);
    for H = Hs
        [nv, nb, nc, tt] = mpc_once(c, H, S, reps);
        rows = [rows; 1, H, S, 3, nv, nb, nc, tt]; %#ok<AGROW>
        fprintf('  exp14 MPC H=%d S=%d: %d vars (%d binary), %d rows, %.2f s\n', H, S, nv, nb, nc, tt);
    end
end
for K = [2 3 4]
    t0h = 17 + 2 * (0:K-1);
    c = set_events(ctx, t0h, 1, 6, 24 * ones(1, K), ones(1, K));
    [nv, nb, nc, tt] = mpc_once(c, 72, 5, reps);
    rows = [rows; 1, 72, 5, K, nv, nb, nc, tt]; %#ok<AGROW>
    t = tic; DA = dayahead_commit(c, 'coupled'); td = toc(t);
    rows = [rows; 2, c.par.Tsim, 5, K, NaN, NaN, NaN, td]; %#ok<AGROW>
    fprintf('  exp14 K=%d events: MPC %.2f s, day-ahead coupled %.2f s (C = %s)\n', K, tt, td, mat2str(round(DA.C' * 100) / 100));
end
write_csv(fullfile(root, 'results', 'exp14_timing.csv'), {'model', 'H', 'S', 'K', 'n_var', 'n_bin', 'n_con', 'time_s'}, rows);
out.rows = rows;
end

function [nv, nb, nc, tt] = mpc_once(c, H, S, reps)
par = c.par; t0 = 65;                                    % 16:00, all events ahead
c0 = struct('par', par, 'inp', c.inp, 't_stop', t0 - 1);  % nominal operation until 15:45
o = run_closed_loop(par, c.inp.real, c.base, struct('s', {}, 'e', {}, 'win', {}), @nominal_wrap, c0);
st = state_fit_events(o.st, numel(c.ev));
st = add_arrivals(st, c.inp.real.flex(t0, :), par);
cc = c; cc.fmode = 'scenario'; if S == 1, cc.fmode = 'expected'; end
Hh = min(H, par.Tsim - t0 + 1);
sc = make_scen(c.inp, par, c.base, t0, Hh, cc);
act = event_activity(c, t0, sc.S, 'scenario');
opt = struct('milp', true, 'nonant', true, 'visible', any(act, 2), 'active', act, 'terminal', true, ...
             'Eref_end', c.Eref(min(t0 + Hh - 1, end)), 'Sref_end', c.Sref(min(t0 + Hh - 1, end)));
[P, ~] = build_model(par, st, sc, c.ev, opt);
nv = numel(P.f); nb = numel(P.intcon); nc = size(P.Aineq, 1) + size(P.Aeq, 1);
ts = zeros(reps, 1);
for r = 1:reps, s = solve_milp(P, c.solver); ts(r) = s.time; end
tt = median(ts);
end

function [u, info] = nominal_wrap(st, data, ctx)
u = planner_nominal(st, ctx.par, data, ctx.inp.price(st.t));
info.ok = true; info.time = 0; info.fallback = false;
end

function v = getf(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end
