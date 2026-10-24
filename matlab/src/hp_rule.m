function php = hp_rule(st, par, data, r, off)
%HP_RULE  Rule-based heat-pump dispatch (no-DR operation and the rule-based strategy IR-R): the hot-water tank
%   is filled in the valley hours, discharged evenly over the peak hours (time-of-use, like the battery), and in
%   flat hours the heat pump follows the heat demand and refills the tank to its initial level. off = true
%   switches the pump off (IR-R during a known event: the tank and the boiler supply the heat).
php = 0;
if ~(isfield(par, 'hp') && par.hp.on) || (nargin >= 5 && off), return; end
hp = par.hp;
need = data.qdh;                                          % MW_th
if r.is_valley && r.valley_left > 0
    q = need + max(hp.E - st.H, 0) / r.valley_left;
elseif r.is_peak && r.peak_left > 0
    q = max(need - st.H / r.peak_left, 0);
else
    q = need + max(hp.E0 * hp.E - st.H, 0) / 2;
end
php = min(hp.Pmax, q / hp.cop);
end
