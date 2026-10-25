function out = exp26_admm(ctx, root, opts)
%EXP26_ADMM  Distributed joint recovery (review, innovation direction 3): the IT scheduler and the
%   facility EMS keep their own models and exchange only the deferrable IT power plan and its price
%   (ADMM_PLAN, PLANNER_ADMM). Uniform commitment opts.C (default 6 MW).
%   (a) open loop on the case day (perfect information, whole-day plan, every event valid): ADMM for
%       rho in opts.rhos (default [50 200 800]) and opts.Kopen iterations (default 100). For every
%       iteration: primal / dual residual and the cost of the IT side's schedule when the facility
%       responds optimally to it ("implementable cost"); references: the joint optimum, the IT
%       schedules of IR-P (one-shot perfect-information channel price) and of IR-O (static share, best
%       of par.bench.alpha_grid with hindsight); final ADMM price vs the channel price of Proposition 2
%       -> results/exp26_conv.csv, exp26_ref.csv, exp26_price.csv
%   (b) closed loop on the case day (realisation 0) and the Monte-Carlo days opts.r (default 0:52):
%       IR-O*, IR-P, JR-D and JR-A with opts.Ks iterations per MPC step (default [1 3 10], rho =
%       opts.rho, default 200), day-ahead benchmarks as in Exp4; written after every day
%       -> results/exp26_mc<tag>.csv, exp26_strategies.csv; on the case day also K = 3 with the other
%       rhos -> results/exp26_rho<tag>.csv
%   opts.parts: subset of 'ab' (default 'ab'); opts.tag: suffix of the (b) files (split runs).
if nargin < 3, opts = struct(); end
parts = getf(opts, 'parts', 'ab'); tag = getf(opts, 'tag', '');
C = getf(opts, 'C', 6); rhos = getf(opts, 'rhos', [50 200 800]); Kopen = getf(opts, 'Kopen', 100);
Ks = getf(opts, 'Ks', [1 3 10]); rho = getf(opts, 'rho', 200);
rr = getf(opts, 'r', 0:ctx.inp.mc.N);
t0 = tic;
c0 = apply_commit(ctx, C * [1 1 1]);
out = struct();
%% (a) open-loop convergence
if any(parts == 'a')
    par = c0.par; c = c0; c.fmode = 'oracle';
    st = state_init(par, numel(c0.ev)); st = add_arrivals(st, c0.inp.real.flex(1, :), par);
    sc = make_scen(c0.inp, par, c0.base, 1, par.Tsim, c);
    act = event_activity(c0, 1, 1, 'oracle');
    opt = struct('milp', false, 'visible', any(act, 2), 'active', act, 'terminal', true, ...
                 'Eref_end', c0.Eref(end), 'Sref_end', c0.Sref(end), 'Href_end', 0);
    ev = c0.ev;
    [Jstar, sJ, ixJ] = impl_cost(par, st, sc, ev, opt, [], [], c0.solver);
    lamJ = sJ.marg_eq(ixJ.row_el) / par.dt;                      % channel price (CNY/MWh)
    % IR-P: IT side answers the one-shot perfect-information channel price (TOU added by the IT side)
    o1 = struct('alpha', 0, 'lambda', max(lamJ, 0) - sc.price(:), 'use_share', false, 'visible', opt.visible, ...
                'pgt_nom', c0.pgt_nom, 'ynom_now', sum(c0.inp.real.flex(1, :)));
    [P1, ix1] = build_compute_model(par, st, sc, ev, o1); s1 = solve_milp(P1, c0.solver);
    [JP, ~, ~, vP] = impl_cost(par, st, sc, ev, opt, ysol(s1.x, ix1), zsol(s1.x, ix1), c0.solver);
    % IR-O: static share, best of the grid with hindsight
    JO = Inf; aO = NaN; vO = 0;
    for al = par.bench.alpha_grid
        o1 = struct('alpha', al, 'visible', opt.visible, 'pgt_nom', c0.pgt_nom, 'ynom_now', sum(c0.inp.real.flex(1, :)));
        [P1, ix1] = build_compute_model(par, st, sc, ev, o1); s1 = solve_milp(P1, c0.solver);
        [Ja, ~, ~, va] = impl_cost(par, st, sc, ev, opt, ysol(s1.x, ix1), zsol(s1.x, ix1), c0.solver);
        if Ja < JO, JO = Ja; aO = al; vO = va; end
    end
    write_csv(fullfile(root, 'results', 'exp26_ref.csv'), {'J_joint', 'J_IRP', 'valid_IRP', 'J_IROs', 'alpha_IROs', 'valid_IROs'}, ...
              [Jstar, JP, vP, JO, aO, vO]);
    fprintf('  exp26 open loop: joint %.0f, IR-P %+.2f%%, IR-O* %+.2f%% (alpha %.1f)\n', Jstar, 100 * (JP / Jstar - 1), 100 * (JO / Jstar - 1), aO);
    Rc = []; Rp = [];
    phi = 1 + par.fac.a_aux + par.fac.theta ./ sc.cop(:, 1);
    for rh = rhos
        oa = admm_plan(par, st, sc, ev, opt, struct('rho', rh, 'K', Kopen, 'tol', -1, 'keep_y', true, 'solver', c0.solver));
        for k = 1:oa.it
            [Jk, ~, ~, vk] = impl_cost(par, st, sc, ev, opt, oa.Yh{k}, [], c0.solver);
            Rc = [Rc; rh, k, oa.hist(k, 2:3), Jk, vk, oa.hist(k, 4) + oa.hist(k, 5)]; %#ok<AGROW>
        end
        Rp = [Rp; repmat(rh, sc.H, 1), (1:sc.H)', lamJ, oa.lam ./ (phi * par.dt)]; %#ok<AGROW>
        fprintf('  exp26 rho %4g: residual %.3f MW after %d it, implementable %+.3f%% (%.1f min)\n', rh, oa.hist(end, 2), oa.it, ...
            100 * (Rc(end, 5) / Jstar - 1), toc(t0) / 60);
    end
    write_csv(fullfile(root, 'results', 'exp26_conv.csv'), {'rho', 'k', 'r_primal', 'r_dual', 'J_impl', 'valid', 'J_sum'}, Rc);
    write_csv(fullfile(root, 'results', 'exp26_price.csv'), {'rho', 'step', 'lambda_joint', 'lambda_admm'}, Rp);
    out.conv = Rc; out.ref = [Jstar, JP, JO];
end
%% (b) closed loop
if any(parts == 'b')
    c0 = prepare_benchmarks(c0, struct('verbose', false));
    S = {'IR-O*', 'expected', 'IR-O*', 0; 'IR-P', 'expected', 'IR-P', 0; 'JR', 'expected', 'JR-D', 0};
    for K = Ks, S(end + 1, :) = {'JR-A', 'expected', sprintf('JR-A%d', K), K}; end %#ok<AGROW>
    write_csv(fullfile(root, 'results', 'exp26_strategies.csv'), {'index', 'K'}, [(1:size(S, 1))', [S{:, 4}]'], S(:, 3));
    rows = []; hdr = {}; Rr = [];
    for r = rr
        if r == 0, c = c0; else, c = use_realization(c0, r); end
        q = zeros(size(S, 1), 3);
        for i = 1:size(S, 1)
            ci = c; if S{i, 4} > 0, ci.admm = struct('rho', rho, 'K', S{i, 4}, 'tol', 0.01); end
            tt = tic; R = run_strategy(ci, S{i, 1}, S{i, 2}); el = toc(tt);
            [row, hdr] = metrics_row(R.M);
            rows = [rows; r, i, el, row]; %#ok<AGROW>
            q(i, :) = [R.M.n_valid, R.M.net_cost_adj / 1000, el];
        end
        if r == 0
            for rh = setdiff(rhos, rho)
                ci = c; ci.admm = struct('rho', rh, 'K', 3, 'tol', 0.01);
                R = run_strategy(ci, 'JR-A', 'expected'); [row, hr] = metrics_row(R.M);
                Rr = [Rr; rh, 3, row]; %#ok<AGROW>
                write_csv(fullfile(root, 'results', sprintf('exp26_rho%s.csv', tag)), [{'rho', 'K'}, hr], Rr);
            end
        end
        write_csv(fullfile(root, 'results', sprintf('exp26_mc%s.csv', tag)), [{'realisation', 'strategy', 'run_time_s'}, hdr], rows);
        fprintf('  exp26 r=%2d valid %s| net(k) %s| time(s) %s (%.0f min)\n', r, sprintf('%d ', q(:, 1)), ...
            sprintf('%6.1f ', q(:, 2)), sprintf('%4.0f ', q(:, 3)), toc(t0) / 60);
    end
    out.rows = rows; out.hdr = hdr;
end
end

function [J, s, ix, valid] = impl_cost(par, st, sc, ev, opt, y, z, slv)
% cost of the whole-day plan when the IT schedule y (and capping z) is fixed and the facility responds
% optimally, every event valid (validity relaxed, valid = 0, if that is impossible)
o = opt; o.fix_y = y; o.fix_z = z;
[P, ix] = build_model(par, st, sc, ev, o);
Zv = [];
if isfield(ix.ev, 'Z'), for k = 1:numel(ix.ev), Zv = [Zv; ix.ev(k).Z(:)]; end, end %#ok<AGROW>
P.intcon = []; P.lb(Zv) = 1; valid = 1;
s = solve_milp(P, slv);
if ~s.ok, P.lb(Zv) = 0; s = solve_milp(P, slv); valid = 0; end
J = NaN; if s.ok, J = s.fval; end
end

function y = ysol(x, ix)
y = [x(ix.Y{1}), x(ix.Y{2}), x(ix.Y{3})];
end

function z = zsol(x, ix)
z = []; if ~isempty(ix.Zc), z = [x(ix.Zc{1}), x(ix.Zc{2}), x(ix.Zc{3})]; end
end

function v = getf(s, f, dflt)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = dflt; end
end
