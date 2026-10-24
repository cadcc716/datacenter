function sidx = scenario_index(par, inp)
%SCENARIO_INDEX  Day-ahead scenario selection from the forecast pools (used by SETUP_CASE and, for a
%   Monte-Carlo day with its own wind forecast ensemble, by USE_REALIZATION).
% deterministic (RNG-free) scenario selection: quantiles of daily level, fixed pairing
S = par.mpc.S;
q = linspace(0.1, 0.9, S); if S == 1, q = 0.5; end
lv = squeeze(mean(sum(inp.pool.flex(1:par.Tday, :, :), 2), 1));
[~, o] = sort(lv); sidx.flex = o(max(1, round(q * numel(o))))';
ninf = size(inp.pool.inf, 2); pinf = [3 1 4 5 2 6 7 8 9 10];
sidx.inf = pinf(1:S); sidx.inf = mod(sidx.inf - 1, ninf) + 1;
lp = sum(inp.pool.pv(1:par.Tday, :), 1);
[~, o] = sort(lp); pv = o(max(1, round(q * numel(o))));
if S == 5, sidx.pv = pv([2 5 1 4 3]); else, sidx.pv = pv; end   % fixed pairing for the base case
end
