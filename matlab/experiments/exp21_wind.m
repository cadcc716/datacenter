function out = exp21_wind(par0, root, opts)
%EXP21_WIND  Green-power direct connection (M5): offshore wind behind the meter of the data centre
%   (NDRC/NEA Fagai Nengyuan [2025] No. 650: self-use >= 60 % of the usable generation, >= 30 % of the
%   user's consumption, no or limited feed-in). Wind capacities opts.P (MW); for each, the baseline
%   (5 typical days), forecasts, scenarios and the benchmarks are rebuilt with the wind output of the
%   same dates. Wind and PV share the curtailable on-site renewable supply (no export).
%   The Jiangsu baseline is the metered grid import of the reference days, so it inherits their
%   wind and the deliverable reduction at the meter shrinks and fluctuates with the wind of the day.
%   Commitments are therefore sized day-ahead, for every capacity and every day from that day's wind
%   forecast (opts.commit = 'dayahead': coupled two-stage model with the forecast-error scenarios; the
%   IR-P prices are recomputed with them, the IR-O* split is tuned on the case day; 'uniform': opts.C
%   for all capacities and days). Then the case day (bench_list('mc')) and opts.N Monte-Carlo days
%   (default 26, core strategies) are run.
%   The grid connection limit is kept at its value without wind (par.cap.Pcap_fixed; otherwise it would
%   shrink with the wind-reduced baseline peak), and the event rows of the planning model are relaxed for
%   a given-up event (par.dr.relax_invalid): with a large wind farm the event-day net load can exceed the
%   baseline when the day is less windy than the reference days. An event confirmed with C = 0 carries no
%   obligation (par.dr.exempt_zero: no pay, no shortfall or rebound assessment).
%   Writes results/exp21_wind.csv (rewritten after every capacity): one row per capacity, realisation
%   (0 = case day) and strategy with all metrics plus the available wind energy of the day and the
%   commitments, exp21_strategies.csv.
%   Green-power curve (opts.Pcurve, default 0:5:40 MW; [] = skip): no-DR operation of the case day and
%   all Monte-Carlo days per capacity, renewable share of the consumption and self-use share of the
%   available generation (the two Document 650 thresholds), results/exp21_curve.csv.
if nargin < 3, opts = struct(); end
P = getf(opts, 'P', [0 5 10 20]);
N = getf(opts, 'N', 26);
C = getf(opts, 'C', [6 6 6]);
cmode = getf(opts, 'commit', 'dayahead'); tag = getf(opts, 'tag', '');
Pc = getf(opts, 'Pcurve', 0:5:40); if isfield(opts, 'Pcurve') && isempty(opts.Pcurve), Pc = []; end
Sc = bench_list('mc'); Sm = bench_list('core');
rows = []; hdr = {}; t0 = tic;
p0 = par0; p0.wind.Prated = 0; c00 = setup_case(p0);
crow = [];
for p = Pc
    par = par0; par.wind.Prated = p; par.cap.Pcap_fixed = c00.d.Pcap;
    ctx = setup_case(par); Td = par.Tday;
    for r = 0:ctx.inp.mc.N
        if r == 0, c = ctx; else, c = use_realization(ctx, r); end
        L = c.ref_eval.log; ix = 1:Td;
        used = sum(L.ppv(ix)) * par.dt; avail = sum(L.pv(ix)) * par.dt; wE = sum(c.inp.real.wind(ix)) * par.dt;
        cons = sum(L.pg(ix) + L.ppv(ix) + L.pgt(ix)) * par.dt;
        crow = [crow; p, r, wE, avail, used, cons, used / max(cons, 1e-9), used / max(avail, 1e-9), ...
                sum(c.inp.price(ix) .* L.pg(ix)) * par.dt]; %#ok<AGROW>
    end
    q = crow(crow(:, 1) == p, :);
    fprintf('  exp21 curve %2g MW: renewable share of consumption %.1f%% (min %.1f), self-use %.1f%% (min %.1f) over %d days\n', ...
        p, 100 * mean(q(:, 7)), 100 * min(q(:, 7)), 100 * mean(q(:, 8)), 100 * min(q(:, 8)), size(q, 1));
end
if ~isempty(Pc)
    write_csv(fullfile(root, 'results', 'exp21_curve.csv'), {'wind_MW', 'realisation', 'wind_MWh', 'res_avail_MWh', ...
        'res_used_MWh', 'consumption_MWh', 'res_share_cons', 'res_selfuse', 'grid_cost_CNY'}, crow);
end
K = numel(C);
ch = arrayfun(@(k) sprintf('called_E%d', k), 1:K, 'UniformOutput', false);
cc = arrayfun(@(k) sprintf('C%d', k), 1:K, 'UniformOutput', false);
for p = P
    par = par0; par.wind.Prated = p;
    par.cap.Pcap_fixed = c00.d.Pcap; par.dr.relax_invalid = true; par.dr.exempt_zero = true;
    ctx = setup_case(par);
    Cp = C;
    if strcmp(cmode, 'dayahead')
        DA = dayahead_commit(ctx, 'coupled'); Cp = round(DA.C(:)' * 10) / 10;
    end
    c0 = apply_commit(ctx, Cp);
    c0 = prepare_benchmarks(c0);
    Nv = min(N, ctx.inp.mc.N);
    for r = 0:Nv
        Cr = Cp;
        if r == 0
            c = c0; S = Sc; wE = sum(ctx.inp.real.wind(1:par.Tday)) * par.dt;
        else
            c = use_realization(c0, r); S = Sm; wE = 0;
            if p > 0, wE = sum(ctx.inp.mc.wind(1:par.Tday, r)) * par.dt; end
            if strcmp(cmode, 'dayahead')     % the day's own commitments and IR-P prices (its wind forecast)
                DA = dayahead_commit(c, 'coupled'); Cr = round(DA.C(:)' * 10) / 10;
                c = apply_commit(c, Cr); c.lambda_hr_da = dayahead_prices(c);
            end
        end
        q = zeros(size(S, 1), 3);
        for i = 1:size(S, 1)
            R = run_strategy(c, S{i, 1}, S{i, 2});
            [row, hdr] = metrics_row(R.M);
            si = find(strcmp(Sc(:, 3), S{i, 3}));
            rows = [rows; p, r, si, double([c.ev.called]), wE, Cr, row]; %#ok<AGROW>
            q(i, :) = [R.M.n_valid, R.M.net_cost_adj / 1000, 100 * R.M.green_share_pv];
        end
        if r == 0 || mod(r, 13) == 0
            fprintf('  exp21 wind %2g MW C = %s r=%2d wind %5.1f MWh  valid %s| net(k) %s| renewable share %s%% (%.0f min)\n', p, ...
                mat2str(Cr), r, wE, sprintf('%d ', q(:, 1)), sprintf('%5.0f ', q(:, 2)), sprintf('%4.1f ', q(:, 3)), toc(t0) / 60);
        end
    end
    write_csv(fullfile(root, 'results', sprintf('exp21_wind%s.csv', tag)), [{'wind_MW', 'realisation', 'strategy'}, ch, {'wind_MWh_day'}, cc, hdr], rows);
end
write_csv(fullfile(root, 'results', 'exp21_strategies.csv'), {'index'}, (1:size(Sc, 1))', Sc(:, 3));
out.rows = rows; out.hdr = hdr;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
