% Smoke test of the optional tie-line ramp limit (off by default).
here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); ctx = setup_case(par);
c = apply_commit(ctx, [6 6 6]);
R0 = run_strategy(c, 'JR', 'open');
fprintf('base  : net_adj %.0f  ramp up/down max %.2f / %.2f MW\n', R0.M.net_cost_adj, R0.M.ramp_up_max, R0.M.ramp_dn_max);
assert(abs(R0.M.net_cost_adj - 228021) < 2);          % unchanged base result
p1 = par; p1.cap.ramp_max = 2; c1 = c; c1.par = p1;
R1 = run_strategy(c1, 'JR', 'open');
fprintf('ramp 2: net_adj %.0f  ramp up/down max %.2f / %.2f MW  fulfil %.1f%%\n', R1.M.net_cost_adj, R1.M.ramp_up_max, R1.M.ramp_dn_max, 100 * R1.M.fulfil_rate);
R2 = run_strategy(c1, 'JR', 'expected');
fprintf('ramp 2 MPC: net_adj %.0f  ramp up/down max %.2f / %.2f MW\n', R2.M.net_cost_adj, R2.M.ramp_up_max, R2.M.ramp_dn_max);
