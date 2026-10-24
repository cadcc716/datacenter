function J = job_gen(prof, dist, opt)
%JOB_GEN  Synthetic gang-job population whose undisturbed occupancy follows a 15-min load profile.
%   prof : T x 3 busy GPUs per runtime class (nominal deferrable load, e.g. ctx.inp.real.flex)
%   dist : 1x3 struct from LOAD_JOB_DIST (gang sizes g, run times d in min, job counts w per class)
%   opt  : warm   - warm-up before 00:00 of day 1 (h, default 12; the profile of day 1 is repeated)
%          gscale - gang-size multiplier (default 1; e.g. 4 for frontier-scale jobs, same run times)
%          seed   - generator seed (default 1)
%   The population at the start of the warm-up is the stationary mix of each class (job types drawn
%   in proportion to count x run time, ages uniform over the run time). Later jobs are drawn one by
%   one from the job-count distribution and each starts as soon as the occupancy of its class is at
%   least half its gang below the profile (half the profile for gangs larger than the profile) and
%   the accumulated deficit allows it, so the occupancy follows the profile within about half a gang
%   and on average also for classes whose largest gangs exceed their load.
%   Jobs are rigid: they run on their whole gang for their whole run time.
%   J.cls, J.g, J.s (nominal start), J.d (run time), J.e (nominal end): column vectors, minutes from
%   00:00 of day 1, one row per job that overlaps [0, 15 T) min.
if nargin < 3, opt = struct(); end
W = getf(opt, 'warm', 12); gk = getf(opt, 'gscale', 1); seed = getf(opt, 'seed', 1);
x = mod(round(seed) * 7919 + 12345, 2147483646) + 1;          % generator state in [1, 2^31 - 2]
T = size(prof, 1); tmin = -round(W * 60); tmax = 15 * T; nm = tmax - tmin;
tq = (tmin:tmax - 1)';
stp = floor(tq / 15);
stp(tq >= 0) = stp(tq >= 0) + 1;
stp(tq < 0) = mod(stp(tq < 0), 96) + 1;                        % warm-up repeats day 1
cap = 4096; cls = zeros(cap, 1); gg = cls; ss = cls; dd = cls; nj = 0;
for c = 1:3
    g = dist(c).g(:) * gk; d = max(1, round(dist(c).d(:))); w = dist(c).w(:);
    f = prof(stp, c);
    cw = cumsum(w) / sum(w); cl = cumsum(w .* d) / sum(w .* d);
    ends = zeros(nm + 1, 1);
    % stationary population at the start of the warm-up
    N = 0;
    while N < f(1)
        [u, x] = lcg_rand(x, 2);
        i = pick(cl, u(1)); age = floor(u(2) * d(i));
        [cls, gg, ss, dd, nj] = push(cls, gg, ss, dd, nj, c, g(i), tmin - age, d(i));
        N = N + g(i);
        q = d(i) - age + 1; if q <= nm, ends(q) = ends(q) + g(i); end
    end
    % arrivals: job types drawn in batches, consumed in order. A job starts when the class is at
    % least half its gang (or half the profile, for gangs larger than the profile) below the profile
    % and the accumulated deficit D is not more negative than half its first-hour GPU-minutes, so
    % that bursts of jobs larger than the class load are paid back and the mean occupancy matches.
    nb = 2048; [u, x] = lcg_rand(x, nb); typ = pick(cw, u); p = 1; D = 0;
    for q = 1:nm
        N = N - ends(q);
        i = typ(p);
        while f(q) - N > 0 && f(q) - N >= min(g(i), f(q)) / 2 && D >= -g(i) * min(d(i), 60) / 2
            [cls, gg, ss, dd, nj] = push(cls, gg, ss, dd, nj, c, g(i), tq(q), d(i));
            N = N + g(i);
            if q + d(i) <= nm, ends(q + d(i)) = ends(q + d(i)) + g(i); end
            p = p + 1;
            if p > nb, [u, x] = lcg_rand(x, nb); typ = pick(cw, u); p = 1; end
            i = typ(p);
        end
        D = D + f(q) - N;
    end
end
cls = cls(1:nj); gg = gg(1:nj); ss = ss(1:nj); dd = dd(1:nj); ee = ss + dd;
k = ee > 0 & ss < tmax;
J.cls = cls(k); J.g = gg(k); J.s = ss(k); J.d = dd(k); J.e = ee(k);
end

function i = pick(cw, u)
% inverse-CDF draw from cumulative weights cw for uniforms u
[~, i] = histc(u(:), [0; cw(:)]);
i = min(max(i, 1), numel(cw));
end

function [cls, gg, ss, dd, nj] = push(cls, gg, ss, dd, nj, c, g, s, d)
if nj == numel(cls)
    cls = [cls; zeros(nj, 1)]; gg = [gg; zeros(nj, 1)]; ss = [ss; zeros(nj, 1)]; dd = [dd; zeros(nj, 1)];
end
nj = nj + 1; cls(nj) = c; gg(nj) = g; ss(nj) = s; dd(nj) = d;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
