function out = exp23_scenarios(par0, root, opts)
%EXP23_SCENARIOS  Day-ahead scenario generation (A3): K-means reduction and seasonal drift.
%   Part A (summer case): the coupled day-ahead commitment is built from
%     quantile-5   the base scenario set (quantiles of the daily load / PV level, equal probabilities)
%     kmeans-K     K-means reduction (K = 5, 10, 20) of all compute-day x weather-day pairings of the
%                  pools, medoids with non-uniform probabilities (KMEANS_SCEN)
%     kmeans-K-DRO the l1-ball DRO commitment (Proposition 3, delta = opts.delta) around those
%                  non-uniform probabilities
%   Part B (season drift, winter case 2025-01-10): K-means scenarios (K = 10, with the COP of the
%   weather days) built from the right (winter) weather pool or from the summer pool, the latter as
%   SP and as DRO. Every commitment vector is operated by JR-D on opts.N Monte-Carlo days of its own
%   season (out of sample).
%   Writes results/exp23_commit.csv (part, setting, commitments, in-sample cost, time),
%   exp23_settings.csv and exp23_oos.csv (part, setting, realisation, metrics).
if nargin < 3, opts = struct(); end
N = getf(opts, 'N', 52); NB = getf(opts, 'NB', 26); delta = getf(opts, 'delta', 0.4);
parts = getf(opts, 'parts', [1 2]);
crow = []; lab = {}; orow = []; hdr = {}; t0 = tic;
for part = parts
    if part == 1
        ctx = setup_case(par0); cev = ctx;
        cfg = {'quantile-5', ctx.sidx, []};
        for K = [5 10 20], cfg(end + 1, :) = {sprintf('kmeans-%d', K), kmeans_scen(ctx.inp, par0, K), []}; end %#ok<AGROW>
        for K = [5 10]
            cfg(end + 1, :) = {sprintf('kmeans-%d-DRO%.2g', K, delta), kmeans_scen(ctx.inp, par0, K), ...
                               struct('type', 'dro', 'delta', delta)}; %#ok<AGROW>
        end
        Nn = N;
    else
        pw = par0;
        pw.case.weather_file = 'weather_suzhou_2024winter.csv'; pw.case.weather_date = '2025-01-10';
        pw.case.base_dates = {'2025-01-03', '2025-01-06', '2025-01-07', '2025-01-08', '2025-01-09'};
        ctx = setup_case(pw); cev = ctx;
        summer = load_inputs(par0);
        drift = ctx;                                   % winter day, summer weather pool (PV and COP)
        drift.inp.pool.pv = summer.pool.pv; drift.inp.pool.cop = summer.pool.cop;
        so = struct('cop', true);
        sw = kmeans_scen(ctx.inp, pw, 10, so); ss = kmeans_scen(drift.inp, pw, 10, so);
        cfg = {'winter-SP', sw, [], ctx; 'summer-SP', ss, [], drift; ...
               sprintf('summer-DRO%.2g', delta), ss, struct('type', 'dro', 'delta', delta), drift; ...
               'summer-DRO1.2', ss, struct('type', 'dro', 'delta', 1.2), drift; ...
               sprintf('winter-DRO%.2g', delta), sw, struct('type', 'dro', 'delta', delta), ctx};
        Nn = NB;
    end
    ns = size(cfg, 1); K = numel(ctx.ev); Cm = zeros(ns, K);
    for i = 1:ns
        cda = ctx; if size(cfg, 2) >= 4, cda = cfg{i, 4}; end
        cda.sidx = cfg{i, 2};
        t1 = tic;
        DA = dayahead_commit(cda, 'coupled', 'scenario', cfg{i, 3});
        Cm(i, :) = round(DA.C(:)' * 100) / 100;
        p = DA.prob(:); fs = DA.fs(:);
        srt = sortrows([fs, p], -1); cv = cvar_of(srt, 0.2);
        crow = [crow; part, i, Cm(i, :), numel(p), p' * fs, max(fs), cv, DA.obj, toc(t1)]; %#ok<AGROW>
        lab{end + 1, 1} = cfg{i, 1}; %#ok<AGROW>
        fprintf('  exp23 part %d %-16s S=%2d C = %s  in-sample mean %.0f  worst %.0f  (%.0f s)\n', part, cfg{i, 1}, ...
                numel(p), mat2str(Cm(i, :)), p' * fs, max(fs), toc(t1));
    end
    % out of sample: JR-D on the Monte-Carlo days of the season, once per distinct commitment vector
    [Cu, ~, map] = unique(Cm, 'rows'); Nv = min(Nn, cev.inp.mc.N);
    for u = 1:size(Cu, 1)
        c0 = apply_commit(cev, Cu(u, :)); res = [];
        for r = 1:Nv
            c = use_realization(c0, r);
            R = run_strategy(c, 'JR', 'expected');
            [row, hdr] = metrics_row(R.M);
            res = [res; r, row]; %#ok<AGROW>
        end
        for i = find(map(:)' == u), orow = [orow; part * ones(Nv, 1), i * ones(Nv, 1), res]; end %#ok<AGROW>
        q = res(:, 1 + find(strcmp(hdr, 'net_cost_adj')));
        fprintf('  exp23 part %d out-of-sample C = %s: mean %.0f (%.0f min)\n', part, mat2str(Cu(u, :)), mean(q), toc(t0) / 60);
    end
end
ch = arrayfun(@(k) sprintf('C%d', k), 1:3, 'UniformOutput', false);
write_csv(fullfile(root, 'results', 'exp23_commit.csv'), [{'part', 'setting'}, ch, {'S', 'is_mean', 'is_worst', 'is_cvar80', 'obj', 'time_s'}], crow);
write_csv(fullfile(root, 'results', 'exp23_settings.csv'), {'part', 'setting'}, crow(:, 1:2), lab);
write_csv(fullfile(root, 'results', 'exp23_oos.csv'), [{'part', 'setting', 'realisation'}, hdr], orow);
out.crow = crow; out.orow = orow; out.hdr = hdr;
end

function v = cvar_of(srt, a)
% mean of the worst fraction a of a discrete distribution (rows [cost, prob] sorted descending)
w = 0; s = 0;
for k = 1:size(srt, 1)
    take = min(srt(k, 2), a - w); if take <= 0, break; end
    s = s + take * srt(k, 1); w = w + take;
end
v = s / max(w, 1e-12);
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
