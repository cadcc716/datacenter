function out = exp21_wind(par0, root, opts)
%EXP21_WIND  Green-power direct connection (M5): offshore wind behind the meter of the data centre
%   (NDRC/NEA Fagai Nengyuan [2025] No. 650: self-use >= 60 % of the usable generation, >= 30 % of the
%   user's consumption, no or limited feed-in). Wind capacities opts.P (MW); for each, the baseline
%   (5 typical days), forecasts, scenarios and the benchmarks are rebuilt with the wind output of the
%   same dates. Wind and PV share the curtailable on-site renewable supply (no export).
%   The Jiangsu baseline is the metered grid import of the reference days, so it inherits their
%   wind and the deliverable reduction at the meter shrinks and fluctuates with the wind of the day.
%   Commitments are therefore sized day-ahead for every capacity (opts.commit = 'dayahead': coupled
%   two-stage model with the wind-inclusive scenarios; 'uniform': opts.C for all capacities). Then
%   the case day (bench_list('mc')) and opts.N Monte-Carlo days (core strategies) are run.
%   Writes results/exp21_wind.csv: one row per capacity, realisation (0 = case day) and strategy with
%   all metrics plus the available wind energy of the day and the commitments, exp21_strategies.csv.
if nargin < 3, opts = struct(); end
P = getf(opts, 'P', [0 10 20 40]);
N = getf(opts, 'N', 52);
C = getf(opts, 'C', [6 6 6]);
cmode = getf(opts, 'commit', 'dayahead'); tag = getf(opts, 'tag', '');
Sc = bench_list('mc'); Sm = bench_list('core');
rows = []; hdr = {}; t0 = tic;
for p = P
    par = par0; par.wind.Prated = p;
    ctx = setup_case(par);
    Cp = C;
    if strcmp(cmode, 'dayahead')
        DA = dayahead_commit(ctx, 'coupled'); Cp = round(DA.C(:)' * 10) / 10;
    end
    c0 = apply_commit(ctx, Cp);
    c0 = prepare_benchmarks(c0);
    Nv = min(N, ctx.inp.mc.N);
    for r = 0:Nv
        if r == 0
            c = c0; S = Sc; wE = sum(ctx.inp.real.wind(1:par.Tday)) * par.dt;
        else
            c = use_realization(c0, r); S = Sm; wE = 0;
            if p > 0, wE = sum(ctx.inp.mc.wind(1:par.Tday, r)) * par.dt; end
        end
        q = zeros(size(S, 1), 3);
        for i = 1:size(S, 1)
            R = run_strategy(c, S{i, 1}, S{i, 2});
            [row, hdr] = metrics_row(R.M);
            si = find(strcmp(Sc(:, 3), S{i, 3}));
            rows = [rows; p, r, si, double([c.ev.called]), wE, Cp, row]; %#ok<AGROW>
            q(i, :) = [R.M.n_valid, R.M.net_cost_adj / 1000, 100 * R.M.green_share_pv];
        end
        if r == 0 || mod(r, 13) == 0
            fprintf('  exp21 wind %2g MW C = %s r=%2d wind %5.1f MWh  valid %s| net(k) %s| renewable share %s%% (%.0f min)\n', p, ...
                mat2str(Cp), r, wE, sprintf('%d ', q(:, 1)), sprintf('%5.0f ', q(:, 2)), sprintf('%4.1f ', q(:, 3)), toc(t0) / 60);
        end
    end
end
K = numel(C);
ch = arrayfun(@(k) sprintf('called_E%d', k), 1:K, 'UniformOutput', false);
cc = arrayfun(@(k) sprintf('C%d', k), 1:K, 'UniformOutput', false);
write_csv(fullfile(root, 'results', sprintf('exp21_wind%s.csv', tag)), [{'wind_MW', 'realisation', 'strategy'}, ch, {'wind_MWh_day'}, cc, hdr], rows);
write_csv(fullfile(root, 'results', 'exp21_strategies.csv'), {'index'}, (1:size(Sc, 1))', Sc(:, 3));
out.rows = rows; out.hdr = hdr;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
