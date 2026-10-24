function sidx = kmeans_scen(inp, par, K, opt)
%KMEANS_SCEN  Joint day-ahead scenarios by K-means reduction of the historical candidates (A3).
%   Candidates: every pairing of a compute-pool day i (deferrable and fixed load) with a weather-pool
%   day j (on-site renewable power, and the COP if opt.cop), the inference day cycling with j.
%   Feature vector of a candidate: hourly means over opt.hours (default 12-24 h) of the deferrable
%   GPUs, the inference GPUs, the renewable power (and the COP), each block standardised over the
%   candidates. K-means (Lloyd) from a deterministic farthest-point start; every cluster is
%   represented by its medoid with probability = cluster size / number of candidates.
%   sidx: flex, inf, pv (pool indices), cop (if opt.cop), prob (K x 1, sums to 1), size.
if nargin < 4, opt = struct(); end
hours = getf(opt, 'hours', 12:23); usecop = getf(opt, 'cop', false);
np = size(inp.pool.flex, 3); nw = size(inp.pool.pv, 2); ninf = size(inp.pool.inf, 2);
[I, Jw] = ndgrid(1:np, 1:nw); I = I(:); Jw = Jw(:); n = numel(I);
Jinf = mod(Jw - 1, ninf) + 1;
hr = @(x) squeeze(mean(reshape(x(1:par.Tday, :), 4, 24, []), 1));     % 96 x m -> 24 x m hourly means
fl = hr(squeeze(sum(inp.pool.flex, 2))); inf = hr(inp.pool.inf); pv = hr(inp.pool.pv); cop = hr(inp.pool.cop);
blocks = {fl(hours + 1, I), inf(hours + 1, Jinf), pv(hours + 1, Jw)};
if usecop, blocks{end + 1} = cop(hours + 1, Jw); end
X = [];
for b = 1:numel(blocks)
    v = blocks{b}';                                  % n x nh
    sdv = std(v(:)); if sdv < 1e-9, sdv = 1; end
    X = [X, (v - mean(v(:))) / sdv]; %#ok<AGROW>
end
K = min(K, n);
% farthest-point initialisation from the candidate closest to the mean
d0 = sum((X - mean(X, 1)).^2, 2); [~, c1] = min(d0);
cen = X(c1, :); dmin = sum((X - cen).^2, 2);
for k = 2:K
    [~, j] = max(dmin); cen(k, :) = X(j, :);
    dmin = min(dmin, sum((X - X(j, :)).^2, 2));
end
lab = zeros(n, 1);
for it = 1:200
    D = zeros(n, K);
    for k = 1:K, D(:, k) = sum((X - cen(k, :)).^2, 2); end
    [~, nl] = min(D, [], 2);
    if all(nl == lab), break; end
    lab = nl;
    for k = 1:K
        if any(lab == k), cen(k, :) = mean(X(lab == k, :), 1); end
    end
end
sidx.flex = zeros(1, K); sidx.inf = zeros(1, K); sidx.pv = zeros(1, K); sidx.cop = zeros(1, K); sidx.prob = zeros(K, 1);
for k = 1:K
    m = find(lab == k);
    if isempty(m), m = 1; end
    [~, j] = min(sum((X(m, :) - cen(k, :)).^2, 2)); j = m(j);
    sidx.flex(k) = I(j); sidx.inf(k) = Jinf(j); sidx.pv(k) = Jw(j); sidx.cop(k) = Jw(j);
    sidx.prob(k) = sum(lab == k) / n;
end
sidx.prob = sidx.prob / sum(sidx.prob);
if ~usecop, sidx = rmfield(sidx, 'cop'); end
sidx.size = n;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
