function out = exp17_policy(ctx, root, opts)
%EXP17_POLICY  Multi-energy coupling and policy constraints (perfect information, case day):
%   sweep 1  thermal inertia of the data hall (third recovery state) off / on, uniform commitments Cs;
%   sweep 2  green-electricity share target g (purchased green power at par.pol.c_green), C = 6 MW;
%   sweep 3  electric PUE cap, C = 6 MW;
%   sweep 4  closed loop with thermal inertia on: IR-O*, IR-P, JR-D on the first N Monte-Carlo days (C = 6 MW)
%            (the same days without inertia are in exp4_certain);
%   sweep 5  tie-line ramp limit on grid import (MW per 15 min), C = 6 MW.
if nargin < 3, opts = struct(); end
Cs = getf(opts, 'Cs', [6 7 8 9]); gs = getf(opts, 'greens', [0 0.6 0.8 0.9]); pues = getf(opts, 'pues', [Inf 1.3 1.25 1.2]);
ramps = getf(opts, 'ramps', [Inf 4 2 1]);
N = min(getf(opts, 'N', 26), ctx.inp.mc.N);
S = {'IR-O*', 'IR-P', 'JR'};
rows = []; hdr = {}; t0 = tic;
for th = [0 1]
    for C = Cs
        par = ctx.par; par.th.on = logical(th);
        [rows, hdr] = run3(rows, ctx, par, C, S, [1, th, C]);
    end
    report(rows, hdr, 1, th, t0);
end
for g = gs
    par = ctx.par; par.pol.green_min = g;
    [rows, hdr] = run3(rows, ctx, par, 6, S, [2, g, 6]);
    report(rows, hdr, 2, g, t0);
end
for u = pues
    par = ctx.par; par.pol.pue_max = u;
    [rows, hdr] = run3(rows, ctx, par, 6, S, [3, u, 6]);
    report(rows, hdr, 3, u, t0);
end
for rg = ramps
    par = ctx.par; par.cap.ramp_max = rg;
    [rows, hdr] = run3(rows, ctx, par, 6, S, [5, rg, 6]);
    report(rows, hdr, 5, rg, t0);
end
if N > 0
    par = ctx.par; par.th.on = true; c0 = ctx; c0.par = par;
    c0 = prepare_benchmarks(apply_commit(c0, [6 6 6]), struct('verbose', false));
    Smc = {'IR-O*', 'expected'; 'IR-P', 'expected'; 'JR', 'expected'};
    for r = 1:N
        c = use_realization(c0, r);
        for i = 1:3
            R = run_strategy(c, Smc{i, 1}, Smc{i, 2});
            [row, hdr] = metrics_row(R.M); rows = [rows; 4, r, 6, i, row]; %#ok<AGROW>
        end
    end
    report(rows, hdr, 4, NaN, t0);
end
write_csv(fullfile(root, 'results', 'exp17_policy.csv'), [{'sweep', 'value', 'C', 'strategy'}, hdr], rows);
write_csv(fullfile(root, 'results', 'exp17_strategies.csv'), {'index'}, (1:3)', {'IR-O*'; 'IR-P'; 'JR'});
out.rows = rows; out.hdr = hdr;
end

function [rows, hdr] = run3(rows, ctx, par, C, S, key)
c = apply_commit(ctx, C * [1 1 1]); c.par = par;
for i = 1:numel(S)
    ci = c;
    if strcmp(S{i}, 'IR-O*'), ci.alpha_star = alpha_hindsight(ci); end
    if strcmp(S{i}, 'IR-P'), ci.lambda_hr_da = dayahead_prices(ci, 'oracle'); end
    R = run_strategy(ci, S{i}, 'open');
    [row, hdr] = metrics_row(R.M); rows = [rows; key, i, row]; %#ok<AGROW>
end
end

function report(rows, hdr, sw, v, t0)
q = rows(rows(:, 1) == sw & (isnan(v) | rows(:, 2) == v), :);
jn = 4 + find(strcmp(hdr, 'net_cost_adj')); jf = 4 + find(strcmp(hdr, 'fulfil_rate_pct')); jp = 4 + find(strcmp(hdr, 'pue'));
nm = {'IR-O*', 'IR-P', 'JR'};
for i = 1:3
    qi = q(q(:, 4) == i, :);
    fprintf('  exp17 sweep %d value %-5g %-6s fulfil %5.1f%%  net_adj(k) %6.1f  PUE %.3f\n', sw, v, ...
        nm{i}, mean(qi(:, jf)), mean(qi(:, jn)) / 1000, mean(qi(:, jp)));
end
fprintf('  (%.0f min)\n', toc(t0) / 60);
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
