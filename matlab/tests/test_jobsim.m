% Smoke test of the review-6f / P2 additions (all optional, off by default): job-level simulator,
% rigid-job recovery bound, pause / resume overhead, several capping levels, K-means scenarios, wind.
here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); ctx = setup_case(par);
c = apply_commit(ctx, [6 6 6]);
% 1 job population follows the profile; replaying the no-DR operation at job level is exact
J = job_gen(c.inp.real.flex, load_job_dist('pai'), struct('warm', 6));
[L0, S0] = job_replay(c.ref_eval.log, c, J, struct());
fprintf('jobs %d, no-DR replay: rmse %.2e MW, pauses %d\n', S0.n_jobs, S0.rmse_pg, S0.n_pause);
assert(S0.rmse_pg < 1e-9 && S0.n_pause == 0);
% 2 the rigid-job bound makes the fluid plan executable at job level
R1 = run_strategy(c, 'JR', 'open'); [M1, ~, ~, S1] = job_settle(R1, c, J, struct(), L0);
cb = c; cb.par.it.rec_tau = trace_rec_tau('pai'); R2 = run_strategy(cb, 'JR', 'open');
[M2, ~, ~, S2] = job_settle(R2, cb, J, struct(), L0);
fprintf('fluid plan : valid %d -> job %d, rmse %.2f MW, catch-up not executed %.0f GPU-h\n', R1.M.n_valid, M1.n_valid, S1.rmse_pg, S1.rec_short);
fprintf('rigid plan : valid %d -> job %d, rmse %.2f MW, catch-up not executed %.0f GPU-h\n', R2.M.n_valid, M2.n_valid, S2.rmse_pg, S2.rec_short);
assert(S2.rec_short < S1.rec_short && S2.rmse_pg < S1.rmse_pg && M2.n_valid == 3);
% 3 pause overhead adds work; more capping levels cannot hurt the perfect-information plan
co = c; co.par.it.pause_ovh_h = 0.1 * [1 1 1]; R3 = run_strategy(co, 'JR', 'open');
c1 = c; c1.par.it.cap_on = true; R4 = run_strategy(c1, 'JR', 'open');
c3 = c1; c3.par.it.cap_rho = [0.15 0.30 0.45]; c3.par.it.cap_loss = [0.03 0.12 0.30]; R5 = run_strategy(c3, 'JR', 'open');
fprintf('JR open: base %.0f, pause overhead %.0f (%.0f GPU-h), one capping level %.0f, three levels %.0f\n', ...
        R1.M.net_cost_adj, R3.M.net_cost_adj, R3.M.pause_ovh, R4.M.net_cost_adj, R5.M.net_cost_adj);
assert(R3.M.pause_ovh > 0 && R3.M.net_cost_adj > R1.M.net_cost_adj);
assert(R4.M.net_cost_adj <= R1.M.net_cost_adj + 1 && R5.M.net_cost_adj <= R4.M.net_cost_adj + 1);
% 4 K-means scenarios: non-uniform probabilities that sum to one
s5 = kmeans_scen(ctx.inp, par, 5);
fprintf('K-means 5 of %d candidates: probabilities %s\n', s5.size, mat2str(round(s5.prob' * 100) / 100));
assert(abs(sum(s5.prob) - 1) < 1e-12 && numel(s5.flex) == 5);
% 5 wind behind the meter is added to the renewable supply
pw = par; pw.wind.Prated = 20; inp = load_inputs(pw);
assert(all(inp.real.wind >= 0) && max(inp.real.wind) <= 20 * pw.wind.eta + 1e-9);
assert(max(abs(inp.real.pv - inp.real.wind - ctx.inp.real.pv)) < 1e-9);
fprintf('wind 20 MW: %.1f MWh on the DR day\n', sum(inp.real.wind(1:96)) * par.dt);
disp('test_jobsim passed');
