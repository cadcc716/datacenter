function out = exp18_climate(ctx, root, opts)
%EXP18_CLIMATE  Generalisation across season and climate (same AI workload traces, Jiangsu rules and tariff;
%   weather from the Open-Meteo ERA5 archive, see data_prep/fetch_weather.py):
%     suzhou_summer  base case (hot weekday 2024-08-05, Tmax 38.3 C)
%     suzhou_winter  cold weekday 2025-01-10 (Tmin -3.0 C): chiller COP at its maximum, little PV
%     guian_summer   Gui'an (Guizhou) national hub node, hottest weekday 2024-07-26 (Tmax 31.7 C)
%   The connection limit is gamma x the local typical-day peak in every case. For each climate:
%   (a) perfect-information commitment sweep (reliable capacity) and (b) closed loop at C = 6 MW on the
%   first N Monte-Carlo days of that climate (IR-O*, IR-P, JR-D).
if nargin < 3, opts = struct(); end
Cs = getf(opts, 'Cs', 4:1:10); N = getf(opts, 'N', 20);
cases = getf(opts, 'cases', {'suzhou_summer', 'suzhou_winter', 'guian_summer'});
S = {'IR-O*', 'IR-P', 'JR'}; Smc = {'IR-O*', 'expected'; 'IR-P', 'expected'; 'JR', 'expected'};
rows = []; mrows = []; info = []; hdr = {}; t0 = tic;
for j = 1:numel(cases)
    par = ctx.par;
    switch cases{j}
        case 'suzhou_summer'
        case 'suzhou_winter'
            par.case.weather_file = 'weather_suzhou_2024winter.csv'; par.case.weather_date = '2025-01-10';
            par.case.base_dates = {'2025-01-03', '2025-01-06', '2025-01-07', '2025-01-08', '2025-01-09'};
        case 'guian_summer'
            par.case.weather_file = 'weather_guian_2024summer.csv'; par.case.weather_date = '2024-07-26';
            par.case.base_dates = {'2024-07-19', '2024-07-22', '2024-07-23', '2024-07-24', '2024-07-25'};
            par.case.lat = 26.38; par.case.lon = 106.45;
        otherwise
            error('exp18:case', 'unknown case %s', cases{j});
    end
    cfg = setup_case(par);
    info = [info; j, cfg.d.Pcap, cfg.par.cap.Pbase_peak, mean(cfg.inp.real.cop(1:96)), sum(cfg.inp.real.pv(1:96)) * par.dt, cfg.alpha]; %#ok<AGROW>
    for C = Cs
        c = apply_commit(cfg, C * [1 1 1]);
        for i = 1:numel(S)
            ci = c;
            if strcmp(S{i}, 'IR-O*'), ci.alpha_star = alpha_hindsight(ci); end
            if strcmp(S{i}, 'IR-P'), ci.lambda_hr_da = dayahead_prices(ci, 'oracle'); end
            R = run_strategy(ci, S{i}, 'open');
            [row, hdr] = metrics_row(R.M); rows = [rows; j, C, i, row]; %#ok<AGROW>
        end
    end
    fprintf('  exp18 %-14s Pcap %.2f MW, mean COP %.2f, PV %.1f MWh/day, reliable C (>=99%%): IR-O* %g  IR-P %g  JR %g  (%.0f min)\n', ...
        cases{j}, cfg.d.Pcap, info(end, 4), info(end, 5), rel_cap(rows, hdr, j, 1), rel_cap(rows, hdr, j, 2), rel_cap(rows, hdr, j, 3), toc(t0) / 60);
    n = min(N, cfg.inp.mc.N);
    if n > 0
        c0 = prepare_benchmarks(apply_commit(cfg, [6 6 6]), struct('verbose', false));
        for r = 1:n
            c = use_realization(c0, r);
            for i = 1:3
                R = run_strategy(c, Smc{i, 1}, Smc{i, 2});
                [row, hdr] = metrics_row(R.M); mrows = [mrows; j, r, i, row]; %#ok<AGROW>
            end
        end
        q = mrows(mrows(:, 1) == j, :); jn = 3 + find(strcmp(hdr, 'net_cost_adj')); jf = 3 + find(strcmp(hdr, 'fulfil_rate_pct'));
        fprintf('  exp18 %-14s MC(%d): fulfil IR-O* %.1f IR-P %.1f JR-D %.1f | net_adj(k) %.0f %.0f %.0f  (%.0f min)\n', cases{j}, n, ...
            mean(q(q(:, 3) == 1, jf)), mean(q(q(:, 3) == 2, jf)), mean(q(q(:, 3) == 3, jf)), ...
            mean(q(q(:, 3) == 1, jn)) / 1000, mean(q(q(:, 3) == 2, jn)) / 1000, mean(q(q(:, 3) == 3, jn)) / 1000, toc(t0) / 60);
    end
end
write_csv(fullfile(root, 'results', 'exp18_climate.csv'), [{'case', 'C', 'strategy'}, hdr], rows);
if ~isempty(mrows), write_csv(fullfile(root, 'results', 'exp18_climate_mc.csv'), [{'case', 'realisation', 'strategy'}, hdr], mrows); end
write_csv(fullfile(root, 'results', 'exp18_cases.csv'), {'Pcap_MW', 'Pbase_peak_MW', 'mean_cop', 'pv_MWh_day', 'alpha'}, info(:, 2:end), cases(:));
out.rows = rows; out.mrows = mrows; out.hdr = hdr; out.info = info;
end

function c = rel_cap(rows, hdr, j, i)
jf = 3 + find(strcmp(hdr, 'fulfil_rate_pct')); jv = 3 + find(strcmp(hdr, 'n_valid'));
q = rows(rows(:, 1) == j & rows(:, 3) == i & rows(:, jf) >= 99 - 1e-6 & rows(:, jv) == 3, :);
c = NaN; if ~isempty(q), c = max(q(:, 2)); end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
