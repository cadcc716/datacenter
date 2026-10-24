function u = planner_nominal(st, par, data, price_t)
%PLANNER_NOMINAL  No-DR "business as usual" operation (used for baseline days and references):
%   compute runs as submitted (ASAP), BESS/TES follow the TOU schedule, gas engine runs in peak.
dt = par.dt;
r = rule_common(st, par, data, price_t);
u.y = edf_alloc(st, par, min(sum(r.avail), r.gfree));
u.pgt = r.pgt; u.hac = r.hac;
[u.pch, u.pdis] = bess_tou(st, par, r);
[u.qtc, u.qtd] = tes_tou(st, par, r);
u.php = hp_rule(st, par, data, r);
end

function [pch, pdis] = bess_tou(st, par, r)
dt = par.dt; b = par.bess; pch = 0; pdis = 0;
if r.is_valley && r.valley_left > 0
    pch = min(b.Pmax, max(b.Emax - st.E, 0) / (b.eta_c * r.valley_left));
elseif r.is_peak
    pdis = min(b.Pmax, max(st.E - b.Emin, 0) * b.eta_d / r.peak_left);
end
end

function [qtc, qtd] = tes_tou(st, par, r)
s = par.tes; qtc = 0; qtd = 0;
if r.is_valley && r.valley_left > 0
    qtc = min(s.Qmax, max(s.Smax - st.S, 0) / (s.eta_c * r.valley_left));
elseif r.is_peak
    qtd = min(s.Qmax, max(st.S - s.Smin, 0) * s.eta_d / r.peak_left);
end
end
