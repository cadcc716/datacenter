function out = exp25_region(ctx, root, opts)
%EXP25_REGION  Cross-event deliverable capability region (review, innovation direction 1).
%   For the K = 3 events of a day, the set of commitment vectors C = (C1, C2, C3) that can be delivered
%   in full (mean reduction >= C_k in every event, all deadlines met, connection limit hard, perfect
%   information; REGION_CHECK) under joint recovery (JR: a convex polytope, Proposition 4) and under the
%   sequential independent benchmarks IR-O (static share ctx.alpha), IR-O* (best static share of
%   par.bench.alpha_grid for each ray, i.e. tuned with hindsight) and the price-coordinated IR-P, whose
%   IT response to the channel price is not unique: IR-P = the solver's own optimal response, IR-P+ =
%   the most favourable optimal response (REGION_CHECK).
%   (a) cases opts.cases = [gamma tau] (default [1.1 1; 1.0 0.5]: base case; short intervals and no
%       connection margin): virtual-battery template of the JR region (REGION_TEMPLATE) with its vertex
%       certificate, multi-event energy bound (REGION_BOUND), radial function on a simplex grid of
%       directions (opts.n, default 12 -> 91 rays) for JR, IR-O*, IR-O, IR-P, IR-P+; volumes
%       -> results/exp25_case.csv, exp25_radial.csv, exp25_vertices.csv
%   (b) slices C3 = const (opts.c3, default [0 6 G3]) in the (C1, C2) plane: largest C2 for opts.nc1
%       (default 17) values of C1 in [0, G1], JR and IR-O* -> results/exp25_slices.csv
%   (c) interval tau (opts.taus) x connection margin gamma (opts.gammas): single-event capabilities,
%       largest total commitment h(1,1,1), energy bound, uniform capability of JR / IR-O* / IR-O /
%       IR-P / IR-P+ -> results/exp25_sweep.csv
%   (d) Monte-Carlo days (opts.N, default all; base events): same metrics -> results/exp25_mc.csv
%   (e) IR-P summary per case: share of the rays on which IR-P+ reaches the JR boundary, ratio of the
%       solver's response to JR -> results/exp25_irp.csv
%   (f) optimistic IR-P with near-optimal IT responses (IT objective within opts.irp_tol_f, default 0.1 %,
%       of its optimum) on the rays of the cases, the centre rays of the sweep and the Monte-Carlo days
%       -> results/exp25_irp_eps.csv
%   opts.parts: subset of 'abcdf' to run (default 'abcdf'; (e) belongs to (a)).
if nargin < 3, opts = struct(); end
parts = getf(opts, 'parts', 'abcdf');
cases  = getf(opts, 'cases', [1.1 1; 1.0 0.5]);
n      = getf(opts, 'n', 12);
taus   = getf(opts, 'taus', [0 0.25 0.5 0.75 1 1.5 2 3]);
gammas = getf(opts, 'gammas', [1.0 1.05 1.1]);
N      = min(getf(opts, 'N', ctx.inp.mc.N), ctx.inp.mc.N);
c3     = getf(opts, 'c3', [0 6 NaN]);
nc1    = getf(opts, 'nc1', 17);
g0 = ctx.par.cap.gamma; t0 = tic;
dc = [1; 1; 1] / 3;
%% (a)-(b) cases
[Dg, tri] = simplex_grid(n);
Rcase = []; Rrad = []; Rvert = []; Rsl = []; Rp = [];
for ci = 1:size(cases, 1)
    c = mkcase(ctx, cases(ci, 1), cases(ci, 2), g0);
    if any(parts == 'a')
    tp = region_template(c);
    [bd, Tb] = region_bound(c, {1:3});
    tr = zeros(size(Dg, 1), 6);
    for q = 1:size(Dg, 1)
        d = Dg(q, :)';
        tj = region_radius(c, d, 'JR'); o = struct('tmax', tj);
        [ts, is] = region_radius(c, d, 'IR-O*', o);
        o.alpha = c.alpha; to = region_radius(c, d, 'IR-O', o);
        tp_ = region_radius(c, d, 'IR-P', o); tq = region_radius(c, d, 'IR-P+', o);
        tr(q, :) = [tj, ts, is.alpha, to, tp_, tq];
    end
    Rrad = [Rrad; repmat(ci, size(Dg, 1), 1), Dg, tr]; %#ok<AGROW>
    vol = zeros(1, 5);
    for j = 1:5, vol(j) = tri_volume(Dg, tr(:, j + (j > 2)), tri); end   % JR, IR-O*, IR-O, IR-P, IR-P+
    qc = find(all(abs(Dg - dc') < 1e-9, 2));        % centre ray (n divisible by 3)
    hs = max(tr(:, 2)); ho = max(tr(:, 4));          % largest total commitment on the IR boundaries
    Rcase = [Rcase; ci, cases(ci, :), tp.G', tp.hS', bd, Tb, tp.exact, tp.theta, size(tp.V, 1), tp.vol, ...
             prod(tp.G), vol, tr(qc, [1 2 4 5 6]) / 3, tr(qc, 3), hs, ho, c.alpha]; %#ok<AGROW>
    Rvert = [Rvert; repmat(ci, size(tp.V, 1), 1), tp.V, tp.ok]; %#ok<AGROW>
    ok = tr(:, 1) > 1e-6;
    Rp = [Rp; ci, sum(ok), mean(abs(tr(ok, 6) - tr(ok, 1)) <= 0.02), min(tr(ok, 5) ./ tr(ok, 1)), ...
          mean(tr(ok, 5) ./ tr(ok, 1)), vol(4) / vol(1), vol(5) / vol(1)]; %#ok<AGROW>
    fprintf(['  exp25 case gamma %.2f tau %.2f: G %s, h123 %.2f (bound %.2f), template exact %d (theta %.4f),\n', ...
             '      u JR %.2f IR-O* %.2f IR-O %.2f IR-P %.2f IR-P+ %.2f, vol / JR: IR-O* %.3f IR-O %.3f IR-P %.3f IR-P+ %.3f (%.0f min)\n'], ...
        cases(ci, :), mat2str(tp.G', 4), tp.hS(end), bd, tp.exact, tp.theta, tr(qc, [1 2 4 5 6]) / 3, vol(2:5) / vol(1), toc(t0) / 60);
    end
    if any(parts == 'b')                            % slices C3 = const: largest C2 for a grid of C1
        e3 = [0; 0; 1]; G3 = region_radius(c, e3, 'JR'); G1 = region_radius(c, [1; 0; 0], 'JR');
        for lev = c3
            C3 = lev; if isnan(C3), C3 = G3; end
            for c1 = linspace(0, G1, nc1)
                o = struct('C0', [c1; 0; C3] * (1 - 1e-4));
                tj = region_radius(c, [0; 1; 0], 'JR', o); o.tmax = tj;
                [ts, is] = region_radius(c, [0; 1; 0], 'IR-O*', o);
                Rsl = [Rsl; ci, C3, c1, tj, ts, is.alpha]; %#ok<AGROW>
            end
        end
        fprintf('  exp25 slices case %d done (%.0f min)\n', ci, toc(t0) / 60);
    end
end
if any(parts == 'a')
    hc = {'case', 'gamma', 'tau_h', 'G1', 'G2', 'G3', 'h12', 'h13', 'h23', 'h123', 'bound123', 'Xbar', 'Es', ...
          'H', 'gD', 'Delta', 'exact', 'theta', 'n_vertices', 'vol_template', 'vol_box', 'vol_JR', 'vol_IROs', ...
          'vol_IRO', 'vol_IRP', 'vol_IRPp', 'u_JR', 'u_IROs', 'u_IRO', 'u_IRP', 'u_IRPp', 'alpha_u_IROs', ...
          'tmax_IROs', 'tmax_IRO', 'alpha_static'};
    write_csv(fullfile(root, 'results', 'exp25_case.csv'), hc, Rcase);
    write_csv(fullfile(root, 'results', 'exp25_radial.csv'), {'case', 'd1', 'd2', 'd3', 't_JR', 't_IROs', 'alpha_IROs', 't_IRO', 't_IRP', 't_IRPp'}, Rrad);
    write_csv(fullfile(root, 'results', 'exp25_irp.csv'), {'case', 'n_rays', 'share_IRPp_eq_JR', 'min_ratio_IRP', 'mean_ratio_IRP', 'vol_ratio_IRP', 'vol_ratio_IRPp'}, Rp);
    write_csv(fullfile(root, 'results', 'exp25_vertices.csv'), {'case', 'C1', 'C2', 'C3', 'deliverable'}, Rvert);
end
if any(parts == 'b')
    write_csv(fullfile(root, 'results', 'exp25_slices.csv'), {'case', 'C3', 'C1', 'C2_JR', 'C2_IROs', 'alpha_IROs'}, Rsl);
end
%% (c) tau x gamma
Rsw = [];
hm = {'G1', 'G2', 'G3', 'h123', 'bound123', 'u_JR', 'u_IROs', 'alpha_IROs', 'u_IRO', 'u_IRP', 'u_IRPp'};
if any(parts == 'c')
    for g = gammas
        for tau = taus
            c = mkcase(ctx, g, tau, g0);
            Rsw = [Rsw; g, tau, metrics(c)]; %#ok<AGROW>
        end
        fprintf('  exp25 sweep gamma %.2f done (%.0f min)\n', g, toc(t0) / 60);
    end
    write_csv(fullfile(root, 'results', 'exp25_sweep.csv'), [{'gamma', 'tau_h'}, hm], Rsw);
end
%% (d) Monte-Carlo days
Rmc = [];
if any(parts == 'd')
    c0 = mkcase(ctx, g0, 1, g0);
    for r = 1:N
        c = use_realization(c0, r);
        Rmc = [Rmc; r, metrics(c)]; %#ok<AGROW>
        if mod(r, 13) == 0, fprintf('  exp25 MC %d/%d (%.0f min)\n', r, N, toc(t0) / 60); end
    end
    write_csv(fullfile(root, 'results', 'exp25_mc.csv'), [{'realisation'}, hm], Rmc);
end
%% (f) near-optimal IT responses under the channel price
Rf = [];
if any(parts == 'f')
    oe = struct('irp_tol', getf(opts, 'irp_tol_f', 1e-3));
    for ci = 1:size(cases, 1)
        c = mkcase(ctx, cases(ci, 1), cases(ci, 2), g0);
        for q = 1:size(Dg, 1)
            d = Dg(q, :)'; tj = region_radius(c, d, 'JR'); o = oe; o.tmax = tj;
            Rf = [Rf; 1, ci, cases(ci, :), Dg(q, :), tj, region_radius(c, d, 'IR-P+', o)]; %#ok<AGROW>
        end
    end
    for g = gammas
        for tau = taus
            c = mkcase(ctx, g, tau, g0); tj = region_radius(c, dc, 'JR'); o = oe; o.tmax = tj;
            Rf = [Rf; 2, 0, g, tau, dc', tj, region_radius(c, dc, 'IR-P+', o)]; %#ok<AGROW>
        end
    end
    c0 = mkcase(ctx, g0, 1, g0);
    for r = 1:N
        c = use_realization(c0, r); tj = region_radius(c, dc, 'JR'); o = oe; o.tmax = tj;
        Rf = [Rf; 3, r, g0, 1, dc', tj, region_radius(c, dc, 'IR-P+', o)]; %#ok<AGROW>
    end
    write_csv(fullfile(root, 'results', 'exp25_irp_eps.csv'), {'part', 'id', 'gamma', 'tau_h', 'd1', 'd2', 'd3', 't_JR', 't_IRPe'}, Rf);
    fprintf('  exp25 near-optimal IR-P+ done (%.0f min)\n', toc(t0) / 60);
end
out.case = Rcase; out.radial = Rrad; out.sweep = Rsw; out.mc = Rmc; out.irp = Rp; out.irp_eps = Rf;
fprintf('  exp25 done (%.1f min)\n', toc(t0) / 60);
end

function row = metrics(c)
% single-event capabilities, largest total commitment, energy bound, uniform capabilities
G = zeros(1, 3);
for k = 1:3, e = zeros(3, 1); e(k) = 1; G(k) = region_radius(c, e, 'JR'); end
[~, h] = region_support(c, [1; 1; 1]);
bd = region_bound(c, {1:3});
dc = [1; 1; 1] / 3;
tj = region_radius(c, dc, 'JR'); o = struct('tmax', tj);
[ts, is] = region_radius(c, dc, 'IR-O*', o);
o.alpha = c.alpha; to = region_radius(c, dc, 'IR-O', o);
tp = region_radius(c, dc, 'IR-P', o); tq = region_radius(c, dc, 'IR-P+', o);
row = [G, h, bd, [tj, ts] / 3, is.alpha, [to, tp, tq] / 3];
end

function c = mkcase(ctx, g, tau, g0)
% events E1 17:00, E2 18:00 + tau, E3 19:00 + 2 tau (1 h each); connection margin g
c = ctx; if abs(g - g0) > 1e-9, c = ctx_with_gamma(ctx, g); end
c = set_events(c, [17, 18 + tau, 19 + 2 * tau], 1, 6);
% static IT share of IR-O for these windows (ratio of single-event capabilities, as SETUP_CASE)
par = c.par; d = c.d; gc = 0; gs = 0;
for k = 1:numel(c.ev)
    tt = c.ev(k).s:c.ev(k).e;
    phi = 1 + par.fac.a_aux + par.fac.theta ./ c.inp.real.cop(tt);
    gc = gc + mean(phi .* d.pdyn .* sum(c.inp.fc.flex(tt, :), 2));
    gs = gs + par.bess.Pmax + mean(par.tes.Qmax ./ c.inp.real.cop(tt));
end
c.alpha = gc / (gc + gs);
end

function [D, tri] = simplex_grid(n)
% rays d = (i, j, n-i-j)/n and the triangles of the grid on the simplex
D = []; id = zeros(n + 1);
for i = 0:n
    for j = 0:n - i
        D = [D; i, j, n - i - j]; id(i + 1, j + 1) = size(D, 1); %#ok<AGROW>
    end
end
D = D / n; tri = [];
for i = 0:n - 1
    for j = 0:n - 1 - i
        tri = [tri; id(i + 1, j + 1), id(i + 2, j + 1), id(i + 1, j + 2)]; %#ok<AGROW>
        if i + j <= n - 2, tri = [tri; id(i + 2, j + 1), id(i + 1, j + 2), id(i + 2, j + 2)]; end %#ok<AGROW>
    end
end
end

function v = tri_volume(D, t, tri)
% volume of the star-shaped polyhedron with boundary points t_q d_q over the simplex triangulation
t(isnan(t)) = 0; P = D .* t(:); v = 0;
for i = 1:size(tri, 1)
    v = v + abs(det(P(tri(i, :), :))) / 6;
end
end

function v = getf(s, f, dflt)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = dflt; end
end
