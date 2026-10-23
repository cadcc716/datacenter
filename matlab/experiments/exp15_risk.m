function out = exp15_risk(ctx, root, opts)
%EXP15_RISK  Risk-averse day-ahead commitment (Proposition 3) and its out-of-sample value.
%   The coupled day-ahead model (dayahead_commit) is solved with Sda joint historical scenarios under
%     SP          expected cost (two-stage stochastic programme, the base method)
%     DRO(delta)  worst-case expected cost over the l1 ball of radius delta around the empirical
%                 scenario probabilities (exact MILP via LP duality)
%     RO          delta = 2: worst scenario (scenario-robust)
%     CVaR(b, w)  (1 - w) E + w CVaR_b
%     single      conventional single-event capability assessment (reference)
%   Every distinct commitment vector is then operated by JR-D (deterministic MPC) on the same N
%   Monte-Carlo days that were not used to build the scenarios (out of sample).
%   Writes results/exp15_commit.csv (one row per setting: commitments, in-sample statistics, time) and
%   results/exp15_oos.csv (one row per setting and day: all metrics).
if nargin < 3, opts = struct(); end
Sda = getf(opts, 'Sda', 10);
N = min(getf(opts, 'N', ctx.inp.mc.N), ctx.inp.mc.N);
deltas = getf(opts, 'deltas', [0.1 0.2 0.4 0.8 1.2 2]);
cvars = getf(opts, 'cvars', [0.8 1.0; 0.9 0.5]);          % rows [beta w]
% day-ahead context with Sda scenarios (everything else as in ctx)
par = ctx.par; par.mpc.S = Sda;
tmp = setup_case(par, ctx.inp);
cda = ctx; cda.sidx = tmp.sidx;
% risk settings cfg: {label, kind (0 SP, 1 DRO/RO, 2 CVaR, 3 single-event), p1, p2, risk struct}
cfg = {'SP', 0, 0, 0, []};
for d = deltas
    if d >= 2, lab = 'RO'; else, lab = sprintf('DRO-%.2g', d); end
    cfg(end+1, :) = {lab, 1, d, 0, struct('type', 'dro', 'delta', d)}; %#ok<AGROW>
end
for i = 1:size(cvars, 1)
    cfg(end+1, :) = {sprintf('CVaR-%.2g-w%.2g', cvars(i, 1), cvars(i, 2)), 2, cvars(i, 1), cvars(i, 2), ...
                     struct('type', 'cvar', 'beta', cvars(i, 1), 'w', cvars(i, 2))}; %#ok<AGROW>
end
cfg(end+1, :) = {'single', 3, 0, 0, []};
ns = size(cfg, 1); K = numel(ctx.ev);
Cm = zeros(ns, K); crow = zeros(ns, 0);
for i = 1:ns
    t1 = tic;
    if cfg{i, 2} == 3
        DA = dayahead_commit(cda, 'single');
        fs = NaN(Sda, 1); obj = NaN; vp = NaN(K, 1);
    else
        DA = dayahead_commit(cda, 'coupled', 'scenario', cfg{i, 5});
        fs = DA.fs; obj = DA.obj; vp = DA.valid_prob;
    end
    Cm(i, :) = round(DA.C(:)' * 100) / 100;
    srt = sort(fs, 'descend'); nw = max(1, round(0.2 * Sda));
    crow(i, 1:(8 + 2 * K)) = [cfg{i, 2}, cfg{i, 3}, cfg{i, 4}, Cm(i, :), mean(fs), max(fs), mean(srt(1:nw)), ...
                              obj, vp(:)', toc(t1)];
    fprintf('  exp15 %-14s C = %s  in-sample mean %.0f  worst %.0f  (%.0f s)\n', cfg{i, 1}, mat2str(Cm(i, :)), ...
            mean(fs), max(fs), toc(t1));
end
ch = arrayfun(@(k) sprintf('C%d', k), 1:K, 'UniformOutput', false);
vh = arrayfun(@(k) sprintf('valid_prob_E%d', k), 1:K, 'UniformOutput', false);
hdr1 = [{'kind', 'p1', 'p2'}, ch, {'is_mean', 'is_worst', 'is_cvar80', 'obj'}, vh, {'time_s'}];
write_csv(fullfile(root, 'results', 'exp15_commit.csv'), [{'setting'}, hdr1], [(1:ns)', crow]);
write_csv(fullfile(root, 'results', 'exp15_settings.csv'), {'index'}, (1:ns)', cfg(:, 1));
% out of sample: JR-D on N Monte-Carlo days, once per distinct commitment vector
[Cu, ~, map] = unique(Cm, 'rows');
rows = []; hdr = {}; t0 = tic;
for u = 1:size(Cu, 1)
    c0 = apply_commit(ctx, Cu(u, :));
    res = [];
    for r = 1:N
        c = use_realization(c0, r);
        R = run_strategy(c, 'JR', 'expected');
        [row, hdr] = metrics_row(R.M);
        res = [res; r, double([c.ev.called]), row]; %#ok<AGROW>
    end
    for i = find(map(:)' == u)
        rows = [rows; i * ones(N, 1), res]; %#ok<AGROW>
    end
    q = res(:, 1 + K + find(strcmp(hdr, 'net_cost_adj')));
    qs = sort(q, 'descend');
    fprintf('  exp15 out-of-sample C = %s: mean %.0f, CVaR90 %.0f (%.0f min)\n', mat2str(Cu(u, :)), mean(q), ...
            mean(qs(1:max(1, round(0.1 * N)))), toc(t0) / 60);
end
kh = arrayfun(@(k) sprintf('called_E%d', k), 1:K, 'UniformOutput', false);
write_csv(fullfile(root, 'results', 'exp15_oos.csv'), [{'setting', 'realisation'}, kh, hdr], rows);
out.cfg = cfg; out.C = Cm; out.rows = rows; out.hdr = hdr;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
