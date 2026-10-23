% Smoke test of the tariff-shape, policy and climate experiments (tiny settings).
here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); par.bench.alpha_grid = [0.6 1.0]; ctx = setup_case(par);
root = fullfile(tempdir, 'dcdr_test16'); mkdir(root); mkdir(fullfile(root, 'results'));
exp16_tariff(ctx, root, struct('shapes', {{'flat', 'duck'}}, 'Cs', 6, 'N', 1));
exp17_policy(ctx, root, struct('Cs', 6, 'greens', 0.8, 'pues', 1.25, 'N', 1));
exp18_climate(ctx, root, struct('cases', {{'suzhou_winter', 'guian_summer'}}, 'Cs', 6, 'N', 1));
