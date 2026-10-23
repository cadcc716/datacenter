% Smoke test of the optional thermal-inertia state and the PUE / green-share constraints (all off by default).
here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); ctx = setup_case(par);
c = apply_commit(ctx, [6 6 6]);
R0 = run_strategy(c, 'JR', 'open');
fprintf('base      : net_adj %.0f  pue %.3f  pv share %.3f  th_max %.2f K\n', R0.M.net_cost_adj, R0.M.pue, R0.M.green_share_pv, R0.M.th_max_K);
% thermal inertia on
p1 = par; p1.th.on = true; c1 = c; c1.par = p1;
R1 = run_strategy(c1, 'JR', 'open');
fprintf('inertia   : net_adj %.0f  th_max %.2f K  TH_end %.2f  fulfil %.1f%%\n', R1.M.net_cost_adj, R1.M.th_max_K, R1.M.th_end, 100 * R1.M.fulfil_rate);
assert(R1.M.net_cost_adj <= R0.M.net_cost_adj + 1);      % an extra resource cannot hurt the perfect-information plan
R1d = run_strategy(c1, 'JR', 'expected');
fprintf('inertia MPC: net_adj %.0f  th_max %.2f K\n', R1d.M.net_cost_adj, R1d.M.th_max_K);
% PUE cap and green share
p2 = par; p2.pol.pue_max = 1.25; p2.pol.green_min = 0.8; c2 = c; c2.par = p2;
R2 = run_strategy(c2, 'JR', 'open');
fprintf('policy    : net_adj %.0f  pue %.3f (excess %.2f MWh)  green bought %.1f MWh cost %.0f\n', R2.M.net_cost_adj, R2.M.pue, R2.M.pue_excess, R2.M.green_buy, R2.M.cost_green);
R3 = run_strategy(c2, 'IR-O', 'expected');
fprintf('policy IR : net_adj %.0f  pue %.3f\n', R3.M.net_cost_adj, R3.M.pue);
