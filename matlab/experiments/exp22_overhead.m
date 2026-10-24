function out = exp22_overhead(par0, root, opts)
%EXP22_OVERHEAD  Pause / resume overhead and several GPU capping levels in the fluid model (M6).
%   Settings (all under uniform commitments opts.C):
%     base         fluid model of the paper
%     ovh-base     every GPU newly paused adds (1 + 5)/60 GPU-h of work (asynchronous checkpoint + restart)
%     ovh-slow     (10 + 15)/60 GPU-h (synchronous checkpoint of a large model + slow restart)
%     cap-1        one capping level (power -30 %, throughput -12 %), as Exp10
%     cap-3        three levels: power -15/-30/-45 % cost throughput -3/-12/-30 % (convex)
%     cap-3+ovh    three capping levels and the base pause overhead
%   For each setting the benchmarks are tuned again; case day with bench_list('mc') and opts.N
%   Monte-Carlo days with bench_list('core').
%   Writes results/exp22_overhead.csv (setting, realisation, strategy, metrics) and exp22_settings.csv.
if nargin < 3, opts = struct(); end
N = getf(opts, 'N', 52);
C = getf(opts, 'C', [6 6 6]); tag = getf(opts, 'tag', '');
cfg = {'base', @(p) p; ...
       'ovh-base', @(p) setit(p, 'pause_ovh_h', (1 + 5) / 60 * [1 1 1]); ...
       'ovh-slow', @(p) setit(p, 'pause_ovh_h', (10 + 15) / 60 * [1 1 1]); ...
       'cap-1', @(p) setit(p, 'cap_on', true); ...
       'cap-3', @(p) setit(setit(setit(p, 'cap_on', true), 'cap_rho', [0.15 0.30 0.45]), 'cap_loss', [0.03 0.12 0.30]); ...
       'cap-3+ovh', @(p) setit(setit(setit(setit(p, 'cap_on', true), 'cap_rho', [0.15 0.30 0.45]), ...
                               'cap_loss', [0.03 0.12 0.30]), 'pause_ovh_h', (1 + 5) / 60 * [1 1 1])};
sel = getf(opts, 'settings', 1:size(cfg, 1));
Sc = bench_list('mc'); Sm = bench_list('core');
rows = []; hdr = {}; t0 = tic;
for k = sel
    par = cfg{k, 2}(par0);
    ctx = setup_case(par);
    c0 = apply_commit(ctx, C);
    c0 = prepare_benchmarks(c0);
    Nv = min(N, ctx.inp.mc.N);
    for r = 0:Nv
        if r == 0, c = c0; S = Sc; else, c = use_realization(c0, r); S = Sm; end
        q = zeros(size(S, 1), 2);
        for i = 1:size(S, 1)
            R = run_strategy(c, S{i, 1}, S{i, 2});
            [row, hdr] = metrics_row(R.M);
            si = find(strcmp(Sc(:, 3), S{i, 3}));
            rows = [rows; k, r, si, double([c.ev.called]), row]; %#ok<AGROW>
            q(i, :) = [R.M.n_valid, R.M.net_cost_adj / 1000];
        end
        if r == 0 || mod(r, 13) == 0
            fprintf('  exp22 %-10s r=%2d valid %s| net(k) %s (%.0f min)\n', cfg{k, 1}, r, sprintf('%d ', q(:, 1)), ...
                sprintf('%5.0f ', q(:, 2)), toc(t0) / 60);
        end
    end
end
K = numel(C);
ch = arrayfun(@(k) sprintf('called_E%d', k), 1:K, 'UniformOutput', false);
write_csv(fullfile(root, 'results', sprintf('exp22_overhead%s.csv', tag)), [{'setting', 'realisation', 'strategy'}, ch, hdr], rows);
write_csv(fullfile(root, 'results', 'exp22_settings.csv'), {'index'}, (1:size(cfg, 1))', cfg(:, 1));
write_csv(fullfile(root, 'results', 'exp22_strategies.csv'), {'index'}, (1:size(Sc, 1))', Sc(:, 3));
out.rows = rows; out.hdr = hdr;
end

function p = setit(p, f, v)
p.it.(f) = v;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
