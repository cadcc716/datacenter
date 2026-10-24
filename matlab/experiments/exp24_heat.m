function out = exp24_heat(par0, root, opts)
%EXP24_HEAT  Winter case with waste-heat recovery for heating (optional par.hp module).
%   Winter peak day 2025-01-10 (Suzhou, daily mean 0.4 C) with the five prior workdays as reference days and the
%   26 coldest days of the winter as Monte-Carlo days (par.case.mc_weather = 'coldest'). A nearby heat network
%   draws q_t = k * max(18 - T_t, 0) (k = opts.k, default par.hp.k). Settings:
%     boiler       the heat demand is met by a gas boiler alone (reference for the value of heat recovery)
%     hp           heat pump (par.hp.Pmax) on the chilled-water return, no tank: backup boiler
%     hp+tank20    heat pump and a 20 MWh_th hot-water tank (fourth recovery state)
%     hp+tank40    heat pump and a 40 MWh_th tank
%   The grid connection limit is kept at the winter value without heat supply. Uniform commitments opts.C;
%   benchmarks tuned again for every setting; case day with bench_list('mc') and opts.N (default 26)
%   Monte-Carlo days with bench_list('core').
%   Writes results/exp24_heat<tag>.csv (rewritten after every setting), exp24_settings.csv, exp24_strategies.csv,
%   and the case-day time series ts_heat_<setting>_<strategy>.csv of IR-O*, IR-P and JR-D for the tank settings.
%   opts.ts_only = true: only the case-day time series (no Monte-Carlo days, no result table).
if nargin < 3, opts = struct(); end
N = getf(opts, 'N', 26); C = getf(opts, 'C', [6 6 6]); tag = getf(opts, 'tag', '');
tso = getf(opts, 'ts_only', false); if tso, N = 0; end
pw = par0;
pw.case.weather_file = 'weather_suzhou_2024winter.csv'; pw.case.weather_date = '2025-01-10';
pw.case.base_dates = {'2025-01-03', '2025-01-06', '2025-01-07', '2025-01-08', '2025-01-09'};
pw.case.mc_weather = 'coldest';
c00 = setup_case(pw);
cfg = {'boiler', 0, 0; 'hp', par0.hp.Pmax, 0; 'hp+tank20', par0.hp.Pmax, 20; 'hp+tank40', par0.hp.Pmax, 40};
sel = getf(opts, 'settings', 1:size(cfg, 1));
Sc = bench_list('mc'); Sm = bench_list('core');
K = numel(C); ch = arrayfun(@(k) sprintf('called_E%d', k), 1:K, 'UniformOutput', false);
rows = []; hdr = {}; t0 = tic;
for k = sel
    par = pw; par.cap.Pcap_fixed = c00.d.Pcap;
    par.hp.on = true; par.hp.Pmax = cfg{k, 2}; par.hp.E = cfg{k, 3}; par.hp.k = getf(opts, 'k', par0.hp.k);
    ctx = setup_case(par);
    c0 = apply_commit(ctx, C);
    c0 = prepare_benchmarks(c0);
    Nv = min(N, ctx.inp.mc.N);
    for r = 0:Nv
        if r == 0, c = c0; S = Sc; else, c = use_realization(c0, r); S = Sm; end
        hd = sum(c.inp.real.qdh(1:par.Tday)) * par.dt;
        q = zeros(size(S, 1), 3);
        for i = 1:size(S, 1)
            R = run_strategy(c, S{i, 1}, S{i, 2});
            [row, hdr] = metrics_row(R.M);
            si = find(strcmp(Sc(:, 3), S{i, 3}));
            ev_php = mean(arrayfun(@(j) mean(R.log.php(c.ev(j).s:c.ev(j).e)), 1:numel(c.ev)));
            Hs = R.log.H([c.ev.s] - 1)';
            rows = [rows; k, r, si, double([c.ev.called]), hd, ev_php, Hs, row]; %#ok<AGROW>
            q(i, :) = [R.M.n_valid, R.M.net_cost_adj / 1000, R.M.boiler_MWh];
            if r == 0 && cfg{k, 3} > 0 && any(strcmp(S{i, 3}, {'IR-O*', 'IR-P', 'JR-D'}))
                L = R.log; T = par.Tsim;
                write_csv(fullfile(root, 'results', sprintf('ts_heat_%s_%s.csv', strrep(cfg{k, 1}, '+', '_'), ...
                    strrep(strrep(S{i, 3}, '*', 's'), '-', ''))), {'hour', 'base', 'pg', 'php', 'qb', 'H', 'qdh', 'E', 'y', 'flex'}, ...
                    [(0:T - 1)' * par.dt, c.base(1:T), L.pg, L.php, L.qb, L.H, L.qdh, L.E, sum(L.y, 2), sum(c.inp.real.flex(1:T, :), 2)]);
            end
        end
        if r == 0 || mod(r, 13) == 0
            fprintf('  exp24 %-10s r=%2d heat %5.1f MWh_th valid %s| net(k) %s| boiler %s MWh_th (%.0f min)\n', cfg{k, 1}, r, hd, ...
                sprintf('%d ', q(:, 1)), sprintf('%5.0f ', q(:, 2)), sprintf('%4.1f ', q(:, 3)), toc(t0) / 60);
        end
    end
    if tso, continue; end
    hh = arrayfun(@(j) sprintf('H_start_E%d', j), 1:K, 'UniformOutput', false);
    write_csv(fullfile(root, 'results', sprintf('exp24_heat%s.csv', tag)), ...
        [{'setting', 'realisation', 'strategy'}, ch, {'heat_demand_MWh', 'php_events_MW'}, hh, hdr], rows);
end
write_csv(fullfile(root, 'results', 'exp24_settings.csv'), {'index'}, (1:size(cfg, 1))', cfg(:, 1));
write_csv(fullfile(root, 'results', 'exp24_strategies.csv'), {'index'}, (1:size(Sc, 1))', Sc(:, 3));
out.rows = rows; out.hdr = hdr;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
