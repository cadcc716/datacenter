function out = exp16_tariff(ctx, root, opts)
%EXP16_TARIFF  Robustness to the shape of the time-of-use tariff (same daily mean price):
%   'jiangsu' (base, peak 14-22 h), 'flat', 'two_tier' (peak 8-22 h), 'critical' (+ critical peak 19-21 h),
%   'duck' (midday valley 10-15 h, evening peak 17-23 h). For every shape the baseline, references and
%   benchmarks are rebuilt; (a) perfect-information comparison at uniform commitments Cs; (b) closed
%   loop (IR-O*, IR-P, JR-D) on the first N Monte-Carlo days at C = 6 MW.
if nargin < 3, opts = struct(); end
shapes = getf(opts, 'shapes', {'jiangsu', 'flat', 'two_tier', 'critical', 'duck'});
Cs = getf(opts, 'Cs', [6 8]); N = min(getf(opts, 'N', 20), ctx.inp.mc.N);
S = {'IR-O*', 'IR-P', 'JR'}; Smc = {'IR-O*', 'expected', 'IR-O*'; 'IR-P', 'expected', 'IR-P'; 'JR', 'expected', 'JR-D'};
rows = []; mrows = []; hdr = {}; t0 = tic;
for j = 1:numel(shapes)
    par = ctx.par; par.price.shape = shapes{j};
    cfg = setup_case(par);
    for C = Cs
        c = apply_commit(cfg, C * [1 1 1]);
        for i = 1:numel(S)
            ci = c;
            if strcmp(S{i}, 'IR-O*'), ci.alpha_star = alpha_hindsight(ci); end
            if strcmp(S{i}, 'IR-P'), ci.lambda_hr_da = dayahead_prices(ci, 'oracle'); end
            R = run_strategy(ci, S{i}, 'open');
            [row, hdr] = metrics_row(R.M); rows = [rows; j, C, i, row]; %#ok<AGROW>
        end
        q = rows(rows(:, 1) == j & rows(:, 2) == C, :); jn = 3 + find(strcmp(hdr, 'net_cost_adj'));
        fprintf('  exp16 %-9s C=%g open: net_adj(k) IR-O* %.0f  IR-P %.0f  JR %.0f  (%.0f min)\n', shapes{j}, C, q(:, jn) / 1000, toc(t0) / 60);
    end
    if N > 0
        c0 = prepare_benchmarks(apply_commit(cfg, [6 6 6]), struct('verbose', false));
        for r = 1:N
            c = use_realization(c0, r);
            for i = 1:size(Smc, 1)
                R = run_strategy(c, Smc{i, 1}, Smc{i, 2});
                [row, hdr] = metrics_row(R.M); mrows = [mrows; j, r, i, row]; %#ok<AGROW>
            end
        end
        q = mrows(mrows(:, 1) == j, :); jn = 3 + find(strcmp(hdr, 'net_cost_adj'));
        fprintf('  exp16 %-9s MC(%d): mean net_adj(k) IR-O* %.0f  IR-P %.0f  JR-D %.0f  (%.0f min)\n', shapes{j}, N, ...
            mean(q(q(:, 3) == 1, jn)) / 1000, mean(q(q(:, 3) == 2, jn)) / 1000, mean(q(q(:, 3) == 3, jn)) / 1000, toc(t0) / 60);
    end
end
write_csv(fullfile(root, 'results', 'exp16_tariff.csv'), [{'shape', 'C', 'strategy'}, hdr], rows);
if ~isempty(mrows), write_csv(fullfile(root, 'results', 'exp16_tariff_mc.csv'), [{'shape', 'realisation', 'strategy'}, hdr], mrows); end
write_csv(fullfile(root, 'results', 'exp16_shapes.csv'), {'index'}, (1:numel(shapes))', shapes(:));
out.rows = rows; out.mrows = mrows; out.hdr = hdr;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
