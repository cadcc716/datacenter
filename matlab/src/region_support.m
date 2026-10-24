function [C, h, info] = region_support(ctx, w, opts)
%REGION_SUPPORT  Support point of the joint-recovery capability region in the direction w >= 0:
%   C = argmax { w'C : C deliverable (REGION_CHECK, 'JR') } and h = w'C (the support function), one LP
%   with the commitments of all called events as decision variables. Events with w_k = 0 are weighted
%   opts.eps_w (default 1e-3) so that the support point is a maximal (Pareto) point of the region.
%   info.sol: LP solution; info.mu: duals of the event rows (d objective / d rhs, CNY-weighted).
if nargin < 3, opts = struct(); end
K = numel(ctx.ev); w = w(:); epsw = 1e-3; if isfield(opts, 'eps_w'), epsw = opts.eps_w; end
called = true(K, 1); if isfield(opts, 'called') && ~isempty(opts.called), called = logical(opts.called(:)); end
[par, st, sc, ev, opt, slv] = region_setup(ctx, zeros(K, 1), called, opts);
opt.w_max = 1e7;
[P, ix] = build_model(par, st, sc, ev, opt);
P.ub(ix.POV(:)) = 0;
for k = find(called)'
    P.f(ix.ev(k).C) = -opt.w_max * max(w(k), epsw);
end
sol = solve_milp(P, slv);
C = NaN(K, 1); h = NaN; info.sol = sol;
if sol.ok
    C = zeros(K, 1);
    for k = find(called)', C(k) = sol.x(ix.ev(k).C); end
    h = w' * C;
end
end
