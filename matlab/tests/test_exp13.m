here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src')); addpath(fullfile(here, '..', 'config')); addpath(fullfile(here, '..', 'experiments'));
dcdr_setup_paths(); par = dcdr_params(); par.dr.c_rb = 0; ctx = setup_case(par);
root = '/tmp/claude-0/-home-user-datacenter/04fe6aee-8cb8-5143-920f-6b65f51ec8f1/scratchpad/t13'; mkdir(root); mkdir(fullfile(root, 'results'));
out = exp13_substitution(ctx, root, struct('Es', [6 12], 'gammas', [1.1], 'Cs', [7 8], 'alpha_grid', [0.8 1.0]));
disp(out.rows(:, 1:9));
