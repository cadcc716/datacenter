%TEST_HEAT  Smoke test of the waste-heat recovery option (par.hp): off by default (base case unchanged), tank and
%   heat balances of the plant hold, the heat pump stays within its capacity and the waste heat of the loop, and
%   every strategy runs on the winter case.
par = dcdr_params();
assert(~par.hp.on, 'heat recovery must be off by default');
ctx = setup_case(par); c0 = apply_commit(ctx, [6 6 6]);
R = run_strategy(c0, 'JR', 'expected');
assert(abs(R.M.net_cost_adj - 228416.891907) < 1e-3, 'base case changed: %.6f', R.M.net_cost_adj);
pw = par; pw.case.weather_file = 'weather_suzhou_2024winter.csv'; pw.case.weather_date = '2025-01-10';
pw.case.base_dates = {'2025-01-03', '2025-01-06', '2025-01-07', '2025-01-08', '2025-01-09'};
pw.case.mc_weather = 'coldest'; pw.hp.on = true;
ctx = setup_case(pw); c0 = apply_commit(ctx, [6 6 6]); c0.alpha_star = 0.6; c0.lambda_hr_da = dayahead_prices(c0);
dt = pw.dt; hp = pw.hp; keep = 1 - hp.loss * dt;
for st = {'IR-R', 'rule'; 'IR-P', 'expected'; 'JR', 'expected'}'
    R = run_strategy(c0, st{1}, st{2}); L = R.log;
    Hp = [hp.E0 * hp.E; L.H(1:end-1)];
    res = L.H - (keep * Hp + (hp.cop * L.php + L.qb - L.qdh) * dt);   % <= 0 (surplus heat to the cooling tower)
    assert(all(res <= 1e-9), '%s: tank balance violated (%.3g)', st{1}, max(res));
    assert(all(L.H >= -1e-9 & L.H <= hp.E + 1e-9) && all(L.qb >= 0), '%s: tank or boiler out of range', st{1});
    assert(all(L.php <= hp.Pmax + 1e-9) && all(L.php >= 0), '%s: heat pump out of range', st{1});
    assert(all(L.qec >= -1e-9), '%s: heat pump took more heat than the loop carries', st{1});
    printf('%-5s net %.0f valid %d | heat pump %.1f MWh_el, boiler %.1f MWh_th, recovered share %.2f\n', st{1}, ...
        R.M.net_cost_adj, R.M.n_valid, R.M.hp_MWh, R.M.boiler_MWh, R.M.heat_rec_share);
end
printf('test_heat passed\n');
