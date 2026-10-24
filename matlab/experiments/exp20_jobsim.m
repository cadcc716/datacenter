function out = exp20_jobsim(par0, root, opts)
%EXP20_JOBSIM  Job-level validation of the fluid model on the case day (review issue 6f): how the
%   execution with discrete rigid gang jobs depends on the job mix (gang sizes and run times of PAI,
%   Acme Seren, Acme Kalos; enlarged gangs) and on the pause overheads (none; base = asynchronous
%   checkpoint 1 min + restart 5 min + minimum pause 15 min; slow = synchronous checkpoint 10 min +
%   restart 15 min + minimum pause 30 min; periodic = no checkpoint at the pause, the progress since the
%   last 30-min checkpoint is lost).
%   Workloads: PAI 2020 (case day 27) and Acme Seren 2023 (2023-05-23); recovery models: fluid (base)
%   and rigid-job bound (par.it.rec_tau from the workload's trace). Every closed-loop run of
%   bench_list('mc') under uniform commitments opts.C is replayed once per job setting.
%   Writes results/exp20_jobsim.csv (one row per workload, model, strategy and job setting; setting 0 =
%   the fluid evaluation itself) and exp20_settings.csv.
if nargin < 3, opts = struct(); end
C = getf(opts, 'C', [6 6 6]);
wls = getf(opts, 'workloads', [1 2]); models = getf(opts, 'models', [0 1]); ssel = getf(opts, 'settings', []);
base = struct('t_save', 1, 't_rs', 5, 't_minp', 15);
none = struct('t_save', 0, 't_rs', 0, 't_minp', 0);
slow = struct('t_save', 10, 't_rs', 15, 't_minp', 30);
peri = struct('t_save', 0, 't_rs', 5, 't_minp', 15, 'ck_mode', 'periodic', 't_ck', 30);
% job settings per workload: {label, job source, gang multiplier, overheads}
JS{1} = {'pai-base', 'pai', 1, base; 'pai-none', 'pai', 1, none; 'pai-slow', 'pai', 1, slow; ...
         'pai-periodic', 'pai', 1, peri; 'seren-base', 'seren', 1, base; 'kalos-base', 'kalos', 1, base; ...
         'pai-x4-base', 'pai', 4, base};
JS{2} = {'seren-base', 'seren', 1, base; 'seren-none', 'seren', 1, none; 'seren-slow', 'seren', 1, slow; ...
         'seren-periodic', 'seren', 1, peri; 'kalos-base', 'kalos', 1, base; 'seren-x2-base', 'seren', 2, base; ...
         'pai-base', 'pai', 1, base};
WL = {'pai', 'pai'; 'acme', 'seren'};
S = bench_list('mc');
rows = []; hdr = {}; t0 = tic;
for w = wls
    for model = models
        par = par0;
        if w == 2, par.case.workload_file = 'acme_seren_gpu_occupancy_15min.csv'; par.case.pai_day = 83; end
        if model == 1, par.it.rec_tau = trace_rec_tau(WL{w, 2}); end
        ctx = setup_case(par);
        c = apply_commit(ctx, C);
        c = prepare_benchmarks(c);
        js = JS{w}; if ~isempty(ssel), js = js(ssel, :); end
        nj = size(js, 1);
        Jp = cell(nj, 1); L0 = cell(nj, 1);
        for q = 1:nj
            Jp{q} = job_gen(c.inp.real.flex, load_job_dist(js{q, 2}), struct('warm', 12, 'gscale', js{q, 3}, 'seed', 1));
            L0{q} = job_replay(c.ref_eval.log, c, Jp{q}, js{q, 4});
        end
        for i = 1:size(S, 1)
            R = run_strategy(c, S{i, 1}, S{i, 2});
            [frow, fhdr] = metrics_row(R.M);
            jh = {}; nan_j = [];
            for q = 1:nj
                [Mj, jrow, jh, ~, L1] = job_settle(R, c, Jp{q}, js{q, 4}, L0{q});
                if q == 1 && any(strcmp(S{i, 3}, {'JR-D', 'IR-P', 'IR-O*'}))     % time series of the base job setting
                    T = par.Tsim; hh = (0:T - 1)' * par.dt;
                    write_csv(fullfile(root, 'results', sprintf('ts_job_%s_m%d_%s.csv', WL{w, 1}, model, strrep(strrep(S{i, 3}, '*', 's'), '-', ''))), ...
                        {'hour', 'base', 'pg_fluid', 'pg_job', 'y_fluid', 'y_job', 'flex', 'B_fluid', 'B_job', 'E'}, ...
                        [hh, c.base, R.log.pg, L1.pg, sum(R.log.y, 2), sum(L1.y, 2), sum(c.inp.real.flex(1:T, :), 2), ...
                         sum(R.log.backlog, 2), sum(L1.backlog, 2), R.log.E]);
                end
                if isempty(nan_j), nan_j = NaN(1, numel(jrow)); rows = [rows; w, model, i, 0, frow, nan_j]; end %#ok<AGROW>
                rows = [rows; w, model, i, q, metrics_row(Mj), jrow]; %#ok<AGROW>
                fprintf('  exp20 %s model %d %-6s %-14s valid %d -> %d  net %6.0f -> %6.0f  rmse %.2f MW  lag %s (%.0f min)\n', ...
                    WL{w, 1}, model, S{i, 3}, js{q, 1}, R.M.n_valid, Mj.n_valid, R.M.net_cost_adj, Mj.net_cost_adj, ...
                    jrow(1), mat2str(round(jrow(end-10:end-8) * 100) / 100), toc(t0) / 60);
            end
            hdr = [fhdr, jh];
        end
    end
end
write_csv(fullfile(root, 'results', 'exp20_jobsim.csv'), [{'workload', 'model', 'strategy', 'setting'}, hdr], rows);
lab = [JS{1}(:, 1); JS{2}(:, 1)];
write_csv(fullfile(root, 'results', 'exp20_settings.csv'), {'workload', 'index'}, ...
          [[ones(size(JS{1}, 1), 1); 2 * ones(size(JS{2}, 1), 1)], [(1:size(JS{1}, 1))'; (1:size(JS{2}, 1))']], lab);
write_csv(fullfile(root, 'results', 'exp20_strategies.csv'), {'index'}, (1:size(S, 1))', S(:, 3));
out.rows = rows; out.hdr = hdr;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
