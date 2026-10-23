here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); ctx = setup_case(par);
root = fullfile(tempdir, 'dcdr_test15'); mkdir(root); mkdir(fullfile(root, 'results'));
% the l1-ball DRO with delta = 0 must reproduce the stochastic programme, delta = 2 the worst scenario
cda = ctx;
D0 = dayahead_commit(cda, 'coupled', 'scenario', []);
D1 = dayahead_commit(cda, 'coupled', 'scenario', struct('type', 'dro', 'delta', 0));
D2 = dayahead_commit(cda, 'coupled', 'scenario', struct('type', 'dro', 'delta', 2));
D3 = dayahead_commit(cda, 'coupled', 'scenario', struct('type', 'cvar', 'beta', 0.8, 'w', 1));
fprintf('SP     C=%s obj=%.1f mean fs=%.1f\n', mat2str(D0.C', 4), D0.obj, mean(D0.fs));
fprintf('DRO-0  C=%s obj=%.1f (should equal SP)\n', mat2str(D1.C', 4), D1.obj);
fprintf('RO     C=%s obj=%.1f max fs=%.1f\n', mat2str(D2.C', 4), D2.obj, max(D2.fs));
fprintf('CVaR80 C=%s obj=%.1f max fs=%.1f (S=5: CVaR_0.8 = worst scenario)\n', mat2str(D3.C', 4), D3.obj, max(D3.fs));
assert(abs(D0.obj - D1.obj) < 1e-3 * abs(D0.obj) + 1);
assert(abs(D2.obj - (max(D2.fs) - par.dr.eps_commit * sum(D2.C))) < 1e-3 * abs(D2.obj) + 1);
out = exp15_risk(ctx, root, struct('Sda', 5, 'N', 2, 'deltas', [0.4 2], 'cvars', [0.8 1.0]));
disp(out.C);
