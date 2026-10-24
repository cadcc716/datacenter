function ctx = use_realization(ctx, r)
%USE_REALIZATION  Replace the realised DR-day data by Monte-Carlo realisation r (forecasts, baseline,
%   scenarios and commitments are kept: they were fixed before the day; with wind, the PV + wind forecast
%   and the scenario pool are the day's own day-ahead forecast, see LOAD_INPUTS). The no-DR reference on the
%   realised data is recomputed (for the true-reduction / payback metrics), and events that are only
%   called with probability prob < 1 are drawn with a deterministic low-discrepancy sequence, so that
%   a fraction ~prob of the realisations calls them (reproducible without a random generator).
mc = ctx.inp.mc;
ctx.inp.real.flex = mc.flex(:, :, r); ctx.inp.real.fix = mc.fix(:, r); ctx.inp.real.inf = mc.inf(:, r);
ctx.inp.real.pv = mc.pv(:, r); ctx.inp.real.cop = mc.cop(:, r);
ctx.inp.fc.cop = mc.cop(:, r);
if isfield(mc, 'fcpv')                  % wind: the day's own day-ahead forecast and scenario pool
    ctx.inp.fc.pv = mc.fcpv(:, r); ctx.inp.pool.pv = mc.poolpv(:, :, r); ctx.inp.real.wind = mc.wind(:, r);
    sx = scenario_index(ctx.par, ctx.inp); ctx.sidx.pv = sx.pv;
end
for k = 1:numel(ctx.ev)
    p = ctx.ev(k).prob;
    if p >= 1, ctx.ev(k).called = true; continue; end
    u = mod((r - 0.5) * 0.6180339887498949 + 0.37 * (k - 1), 1);
    ctx.ev(k).called = u < p;
end
ctx.ref_eval = run_nodr(ctx.par, ctx.inp, ctx.base);
end
