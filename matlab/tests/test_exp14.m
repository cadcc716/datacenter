here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); ctx = setup_case(par);
root = '/tmp/claude-0/-home-user-datacenter/04fe6aee-8cb8-5143-920f-6b65f51ec8f1/scratchpad/t13';
out = exp14_timing(ctx, root, struct('Hs', [24 72], 'Ss', [1 5], 'reps', 1));
