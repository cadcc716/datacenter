here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); ctx = setup_case(par);
root = fullfile(tempdir, 'dcdr_test14'); mkdir(root); mkdir(fullfile(root, 'results'));
out = exp14_timing(ctx, root, struct('Hs', [24 72], 'Ss', [1 5], 'reps', 1));
