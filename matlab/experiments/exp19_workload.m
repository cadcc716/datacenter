function out = exp19_workload(par0, root, opts)
%EXP19_WORKLOAD  LLM-era workload and rigid-job recovery, with every run also executed at job level
%   (review issue 6f).
%   Variants (opts.variants, default all four):
%     pai_fluid   PAI 2020 workload, fluid recovery (the base model; Monte-Carlo days as in Exp4)
%     pai_rigid   PAI 2020 workload, rigid-job recovery bound par.it.rec_tau from the PAI trace
%     acme_fluid  Acme Seren 2023 LLM-development workload (case day 2023-05-23), fluid recovery
%     acme_rigid  Acme workload, rigid-job recovery bound from the Acme trace
%   Each variant: uniform commitments opts.C, benchmarks tuned day-ahead, the case day (realisation 0,
%   strategies bench_list('main')) and opts.N Monte-Carlo realisations (bench_list('mc')). Every run is
%   replayed with discrete gang jobs drawn from the trace of the variant's workload (JOB_REPLAY, base
%   overheads opts.jo) and settled again.
%   Writes results/exp19_workload<tag>.csv (one row per variant, realisation and strategy: fluid
%   metrics, job-level metrics prefixed job_, job-level statistics), exp19_strategies.csv and
%   exp19_variants.csv.
if nargin < 3, opts = struct(); end
C = getf(opts, 'C', [6 6 6]);
N = getf(opts, 'N', 52);
jo = getf(opts, 'jo', struct('t_save', 1, 't_rs', 5, 't_minp', 15));
tag = getf(opts, 'tag', '');
V = {'pai_fluid', 'pai', 'pai', false; 'pai_rigid', 'pai', 'pai', true; ...
     'acme_fluid', 'acme', 'seren', false; 'acme_rigid', 'acme', 'seren', true};
vsel = getf(opts, 'variants', V(:, 1)');
Sm = bench_list('main'); Smc = bench_list('mc');
rows = []; hdr = {};
for v = find(ismember(V(:, 1)', vsel))
    t0 = tic;
    par = par0;
    if strcmp(V{v, 2}, 'acme')
        par.case.workload_file = 'acme_seren_gpu_occupancy_15min.csv'; par.case.pai_day = 83;
    end
    if V{v, 4}, par.it.rec_tau = trace_rec_tau(V{v, 3}); end
    ctx = setup_case(par);
    c0 = apply_commit(ctx, C);
    c0 = prepare_benchmarks(c0);
    dist = load_job_dist(V{v, 3});
    Nv = min(N, ctx.inp.mc.N);
    for r = 0:Nv
        if r == 0, c = c0; S = Sm; else, c = use_realization(c0, r); S = Smc; end
        J = job_gen(c.inp.real.flex, dist, struct('warm', 12, 'seed', r + 1));
        L0 = job_replay(c.ref_eval.log, c, J, jo);
        called = double([c.ev.called]);
        q = zeros(size(S, 1), 4);
        for i = 1:size(S, 1)
            R = run_strategy(c, S{i, 1}, S{i, 2});
            [Mj, jrow, jhdr] = job_settle(R, c, J, jo, L0);
            [frow, fhdr] = metrics_row(R.M); mrow = metrics_row(Mj);
            rows = [rows; v, r, i, called, frow, mrow, jrow]; %#ok<AGROW>
            hdr = [fhdr, strcat('job_', fhdr), jhdr];
            q(i, :) = [R.M.n_valid, Mj.n_valid, R.M.net_cost_adj / 1000, Mj.net_cost_adj / 1000];
        end
        fprintf('  exp19 %-10s r=%2d valid fluid/job %s| net(k) fluid %s| job %s (%.0f min)\n', V{v, 1}, r, ...
            sprintf('%d/%d ', q(:, 1:2)'), sprintf('%4.0f ', q(:, 3)), sprintf('%4.0f ', q(:, 4)), toc(t0) / 60);
    end
end
K = numel(C);
ch = arrayfun(@(k) sprintf('called_E%d', k), 1:K, 'UniformOutput', false);
write_csv(fullfile(root, 'results', sprintf('exp19_workload%s.csv', tag)), [{'variant', 'realisation', 'strategy'}, ch, hdr], rows);
write_csv(fullfile(root, 'results', 'exp19_strategies.csv'), {'index'}, (1:size(Sm, 1))', Sm(:, 3));
write_csv(fullfile(root, 'results', 'exp19_variants.csv'), {'index'}, (1:size(V, 1))', V(:, 1));
out.rows = rows; out.hdr = hdr;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
