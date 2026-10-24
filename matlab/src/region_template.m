function out = region_template(ctx, opts)
%REGION_TEMPLATE  Virtual-battery description of the joint-recovery capability region (Proposition 4)
%   and its exactness certificate. With D_k the event durations (h),
%       T = { C >= 0 : C_k <= G_k,  sum_{k in S} D_k C_k <= h_S  for every subset S, |S| >= 2 },
%   G_k = single-event capability (JR radius along e_k, the other events called at 0) and
%   h_S = support function of the region in the direction D .* 1_S (REGION_SUPPORT). Each constraint
%   is valid for the region, so T contains it. Every vertex of T is then checked (REGION_CHECK 'JR',
%   scaled by 1 - opts.shrink, default 1e-4, against rounding on the boundary): if all are
%   deliverable, T equals the region (it is convex); otherwise theta = the smallest JR radius along a
%   failing vertex (relative to the vertex) and theta * T is a certified inner approximation.
%   out: G (K x 1), S (cell of subsets), hS, V (vertices), ok (per vertex), exact, theta, vol (of T),
%        n_lp.
if nargin < 2, opts = struct(); end
K = numel(ctx.ev); shrink = 1e-4; if isfield(opts, 'shrink'), shrink = opts.shrink; end
Dk = arrayfun(@(e) (e.e - e.s + 1) * ctx.par.dt, ctx.ev(:));
G = zeros(K, 1);
for k = 1:K
    e = zeros(K, 1); e(k) = 1; G(k) = region_radius(ctx, e, 'JR', opts);
end
S = {};
for m = 1:2^K - 1
    s = find(bitget(m, 1:K));
    if numel(s) >= 2, S{end+1} = s; end %#ok<AGROW>
end
hS = zeros(numel(S), 1);
for q = 1:numel(S)
    w = zeros(K, 1); w(S{q}) = Dk(S{q});
    [~, hS(q)] = region_support(ctx, w, opts);
end
% half-space description A C <= b
A = [-eye(K); eye(K)]; b = [zeros(K, 1); G];
for q = 1:numel(S)
    a = zeros(1, K); a(S{q}) = Dk(S{q})'; A = [A; a]; b = [b; hS(q)]; %#ok<AGROW>
end
V = poly_vertices(A, b);
ok = false(size(V, 1), 1); theta = 1; nlp = K + numel(S);
for i = 1:size(V, 1)
    ok(i) = region_check(ctx, (1 - shrink) * V(i, :)', 'JR', opts); nlp = nlp + 1;
    if ~ok(i) && any(V(i, :) > 0)
        nv = sum(V(i, :)); tv = region_radius(ctx, V(i, :)' / nv, 'JR', opts); nlp = nlp + 1;
        theta = min(theta, tv / nv);
    end
end
out.G = G; out.S = S; out.hS = hS; out.V = V; out.ok = ok; out.exact = all(ok); out.theta = theta;
out.n_lp = nlp; out.vol = 0;
if size(V, 1) > K, [~, out.vol] = convhulln(V); end
end

function V = poly_vertices(A, b)
% vertices of {x : A x <= b} in R^K by enumeration of K-subsets of the constraints (small K)
[m, K] = size(A); V = [];
cmb = nchoosek(1:m, K);
for i = 1:size(cmb, 1)
    Ai = A(cmb(i, :), :);
    if abs(det(Ai)) < 1e-10, continue; end
    x = Ai \ b(cmb(i, :));
    if all(A * x <= b + 1e-7), V = [V; x']; end %#ok<AGROW>
end
V = unique(round(V * 1e6) / 1e6, 'rows');
end
