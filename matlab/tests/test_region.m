% Quick test of the capability-region tools and Exp25 (small grid, 2 Monte-Carlo days).
here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); dcdr_setup_paths();
par = dcdr_params(); ctx = setup_case(par);
root = fullfile(tempdir, 'dcdr_test25'); mkdir(root); mkdir(fullfile(root, 'results'));
out = exp25_region(ctx, root, struct('n', 3, 'taus', [0 1], 'gammas', 1.1, 'N', 2, 'c3', [0 NaN], 'nc1', 3));
R = read_csv_table(fullfile(root, 'results', 'exp25_radial.csv'));
assert(all(R.t_IROs <= R.t_JR + 1e-6) && all(R.t_IRO <= R.t_JR + 1e-6), 'IR region outside the JR region');
C = read_csv_table(fullfile(root, 'results', 'exp25_case.csv'));
assert(all(C.bound123 >= C.h123 - 1e-6), 'energy bound violated');
assert(C.exact(1) == 1, 'base-case template not exact');
assert(all(R.t_IRP <= R.t_IRPp + 1e-6) && all(R.t_IRPp <= R.t_JR + 1e-6), 'IR-P bracket out of order');
P = read_csv_table(fullfile(root, 'results', 'exp25_irp.csv'));
fprintf('IR-P+ reaches the JR boundary on %.0f%% / %.0f%% of the rays\n', 100 * P.share_IRPp_eq_JR);
S = read_csv_table(fullfile(root, 'results', 'exp25_sweep.csv'));
assert(all(S.bound123 >= S.h123 - 1e-6), 'energy bound violated in the sweep');
fprintf('test_region passed: base case u_JR %.2f, u_IR-O* %.2f, h123 %.2f <= bound %.2f\n', C.u_JR(1), C.u_IROs(1), C.h123(1), C.bound123(1));
