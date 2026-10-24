function [t, info] = region_radius(ctx, d, strat, opts)
%REGION_RADIUS  Largest t >= 0 such that the commitment vector C = C0 + t d is deliverable
%   (REGION_CHECK); C0 = opts.C0 (default 0) and the direction d >= 0 have disjoint supports.
%   'JR'  : one LP, the events with d_k > 0 in 'maxm' mode ('max' for opts.basis = 'step') with
%           C_k = d_k t, the other called events held at C0_k.
%   'IR-O', 'IR-P', 'IR-P+', 'IR-O*': bisection on [opts.tlo, opts.tmax] (default [0, JR radius]: every IR
%           plan is a feasible operation of the joint model, so the IR regions lie inside the JR region)
%           to opts.tol (default 0.01 in t). IR-O uses opts.alpha; IR-O* the best static share of the
%           grid opts.alphas (default par.bench.alpha_grid) for this ray (hindsight), assuming, as the
%           bisection does, that the deliverable part of a ray is an interval starting at C0.
%   info.n_check = number of REGION_CHECK calls (2-3 LPs each), info.alpha = share used (IR-O, IR-O*).
if nargin < 4, opts = struct(); end
d = d(:); K = numel(ctx.ev);
C0 = getf(opts, 'C0', zeros(K, 1)); C0 = C0(:);
info = struct('alpha', NaN, 'n_check', 0, 'time', 0);
t0 = tic;
switch strat
    case 'JR'
        t = jr_radius(ctx, d, C0, opts);
    case {'IR-O', 'IR-P', 'IR-P+', 'IR-O*'}
        tmax = getf(opts, 'tmax', []);
        if isempty(tmax), tmax = jr_radius(ctx, d, C0, opts); end
        tol = getf(opts, 'tol', 0.01);
        if isnan(tmax), t = NaN; info.time = toc(t0); return; end
        if strcmp(strat, 'IR-O*')
            al = getf(opts, 'alphas', ctx.par.bench.alpha_grid); t = -Inf;
            for a = al(:)'
                o = opts; o.alpha = a;
                if t >= 0                                   % this share must beat the best one so far
                    if t + tol > tmax, break; end
                    info.n_check = info.n_check + 1;
                    if ~region_check(ctx, C0 + (t + tol) * d, 'IR-O', o), continue; end
                    o.tlo = t + tol;
                end
                o.tmax = tmax;
                [ta, ia] = region_radius(ctx, d, 'IR-O', o); info.n_check = info.n_check + ia.n_check;
                if ta > t, t = ta; info.alpha = a; end
            end
            if isinf(t), t = NaN; end                       % C0 not deliverable with any share
        else
            lo = getf(opts, 'tlo', 0); hi = tmax;
            if lo == 0                                      % is C0 itself deliverable?
                info.n_check = info.n_check + 1;
                if ~region_check(ctx, C0, strat, opts), t = NaN; info.time = toc(t0); return; end
            end
            info.n_check = info.n_check + 1;
            if region_check(ctx, C0 + hi * d, strat, opts)
                t = hi;
            else
                while hi - lo > tol
                    mid = (lo + hi) / 2;
                    if region_check(ctx, C0 + mid * d, strat, opts), lo = mid; else, hi = mid; end
                    info.n_check = info.n_check + 1;
                end
                t = lo;
            end
            if strcmp(strat, 'IR-O'), info.alpha = opts.alpha; end
        end
    otherwise
        error('region_radius:strat', 'unknown strategy %s', strat);
end
info.time = toc(t0);
end

function t = jr_radius(ctx, d, C0, opts)
on = find(d > 1e-12);
[par, st, sc, ev, opt, slv] = region_setup(ctx, C0, d > 1e-12, opts);
[P, ix] = build_model(par, st, sc, ev, opt);
P.ub(ix.POV(:)) = 0;
k1 = on(1); n = numel(P.f);
for k = on(2:end)'
    row = sparse(1, [ix.ev(k).C, ix.ev(k1).C], [d(k1), -d(k)], 1, n);
    P.Aeq = [P.Aeq; row]; P.beq = [P.beq; 0];
end
sol = solve_milp(P, slv);
t = NaN;
if sol.ok, t = sol.x(ix.ev(k1).C) / d(k1); end
end

function v = getf(s, f, dflt)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = dflt; end
end
