function out = exp3_sensitivity(ctx, root, opts, tag)
%EXP3_SENSITIVITY  Event duration, interval, connection margin, commitment level; tau x gamma map.
%   Perfect-information (open-loop) plans, so that only the recovery coordination differs:
%   IR-R (rules, closed loop), IR-O (static split 0.41), IR-O* (best static split chosen with
%   hindsight on each case), IR-P (IT side priced by the perfect-information channel price), JR.
if nargin < 3, opts = struct(); end
if nargin < 4, tag = ''; end
C0 = getf(opts, 'C', 6);
strat = bench_list('open');
hdr0 = {'x', 'strategy'};
% (a) duration
rows = [];
for D = getf(opts, 'durations', [0.5 1 1.5 2])
    c = set_events(ctx, [17, 17 + D + 1, 17 + 2 * (D + 1)], D, C0);
    [r, hdr] = run_set(c, strat, D, 'dur'); rows = [rows; r]; %#ok<AGROW>
end
write_csv(fullfile(root, 'results', sprintf('exp3_duration%s.csv', tag)), [hdr0, hdr], rows); out.duration = rows;
% (b) interval
rows = [];
for tau = getf(opts, 'intervals', [0.25 0.5 1 1.5 2 3])
    c = set_events(ctx, [17, 18 + tau, 19 + 2 * tau], 1, C0);
    rows = [rows; run_set(c, strat, tau, 'tau')]; %#ok<AGROW>
end
write_csv(fullfile(root, 'results', sprintf('exp3_interval%s.csv', tag)), [hdr0, hdr], rows); out.interval = rows;
% (c) connection margin
rows = [];
for g = getf(opts, 'gammas', [1.0 1.05 1.1 1.15 1.2 1.3])
    c = ctx_with_gamma(ctx, g); c = apply_commit(c, C0 * [1 1 1]);
    rows = [rows; run_set(c, strat, g, 'gamma')]; %#ok<AGROW>
end
write_csv(fullfile(root, 'results', sprintf('exp3_gamma%s.csv', tag)), [hdr0, hdr], rows); out.gamma = rows;
% (d) commitment level
rows = [];
for C = getf(opts, 'Cs', [3 4 5 6 7 8 9])
    c = apply_commit(ctx, C * [1 1 1]);
    rows = [rows; run_set(c, strat, C, 'C')]; %#ok<AGROW>
end
write_csv(fullfile(root, 'results', sprintf('exp3_commitment%s.csv', tag)), [hdr0, hdr], rows); out.commit = rows;
% (e) tau x gamma map
rows = [];
for g = getf(opts, 'map_gammas', [1.0 1.05 1.1 1.2 1.3])
    cg = ctx_with_gamma(ctx, g);
    for tau = getf(opts, 'map_taus', [0.25 0.5 1 1.5 2 3])
        c = set_events(cg, [17, 18 + tau, 19 + 2 * tau], 1, C0);
        r = run_set(c, strat, tau, sprintf('g%.2f tau', g));
        rows = [rows; repmat(g, size(r, 1), 1), r]; %#ok<AGROW>
    end
end
write_csv(fullfile(root, 'results', sprintf('exp3_map%s.csv', tag)), [{'gamma'}, hdr0, hdr], rows); out.map = rows;
end

function [rows, hdr] = run_set(c, strat, x, nm)
[r, hdr] = run_list_quiet(c, strat);
rows = [repmat(x, size(r, 1), 1), (1:size(r, 1))', r];
jn = find(strcmp(hdr, 'net_cost_adj')); jr = find(strcmp(hdr, 'max_rebound_MW'));
fprintf('  exp3 %s=%-5g fulfil %s = %s  maxRb %s  net_adj(k) %s\n', nm, x, strjoin(strat(:, 3)', '/'), ...
    sprintf('%5.1f ', r(:, 1)), sprintf('%4.2f ', r(:, jr)), sprintf('%5.0f ', r(:, jn) / 1000));
end

function [rows, hdr] = run_list_quiet(c, S)
rows = []; hdr = {};
for i = 1:size(S, 1)
    ci = c;
    if strcmp(S{i, 1}, 'IR-O*'), ci.alpha_star = alpha_hindsight(ci); end
    if strcmp(S{i, 1}, 'IR-P'), ci.lambda_hr_da = dayahead_prices(ci, 'oracle'); end
    R = run_strategy(ci, S{i, 1}, S{i, 2});
    [row, hdr] = metrics_row(R.M); rows = [rows; row]; %#ok<AGROW>
end
end

function v = getf(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end
