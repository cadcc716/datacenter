%MAIN_RUN_ALL  Reproduce all experiments of the paper
%   "Coordinated scheduling for consecutive demand response in AI data-center integrated energy
%    systems considering cross-event computing-storage recovery" (revised version).
%
%   Runs in MATLAB (Optimization Toolbox, or Gurobi if on the path) or GNU Octave (glpk).
%   Results are written to matlab/results/*.csv, figures by tools/plot_results.py.
%   Options (set before calling):  QUICK = true  -> smoke run (tiny samples / grids)
%                                  RUN = [...]   -> subset of experiments (default 1:15; Exp14 timing runs last)
%                                  NMC = n       -> Monte-Carlo realisations (default: all, 52)
%                                  MC_PART = 'certain' | 'uncertain' | 'all' (parts of Exp4; default 'all')
%   Base case: Jiangsu settlement rules + gap-rebound assessment c_rb = 3 CNY/kW per event (a policy
%   parameter); every main experiment is repeated with c_rb = 0 (Jiangsu rules alone, tag '_crb0').
clc;
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'src')); addpath(fullfile(root, 'config')); addpath(fullfile(root, 'experiments'));
dcdr_setup_paths();
if ~exist('QUICK', 'var'), QUICK = false; end
if ~exist('RUN', 'var'), RUN = 1:15; end
if ~exist('NMC', 'var'), NMC = []; end
if ~exist('MC_PART', 'var'), MC_PART = 'all'; end
if ~exist('LOGTAG', 'var'), LOGTAG = ''; end
diary(fullfile(root, 'results', sprintf('run_log%s.txt', LOGTAG)));
t_all = tic;
par = dcdr_params();
if QUICK, par.bench.alpha_grid = [0.6 1.0]; end
ctx = setup_case(par);
ctx0 = ctx; ctx0.par.dr.c_rb = 0;             % Jiangsu rules alone (no gap-rebound assessment)
fprintf('== case: Pcap = %.2f MW (gamma %.2f x typical peak %.2f MW), static split alpha = %.2f, MC realisations = %d\n', ...
    ctx.d.Pcap, par.cap.gamma, ctx.par.cap.Pbase_peak, ctx.alpha, ctx.inp.mc.N);
if any(RUN == 1), write_case_summary(ctx, root); end

%% day-ahead commitments: coupled (proposed) and single-event (conventional), with / without c_rb
if any(ismember(RUN, [2 6]))
    DA = dayahead_commit(ctx, 'coupled');  SE = dayahead_commit(ctx, 'single');
    DA0 = dayahead_commit(ctx0, 'coupled'); SE0 = dayahead_commit(ctx0, 'single');
    fprintf('== day-ahead commitments (c_rb = %g)  coupled: %s   single-event: %s\n', par.dr.c_rb, ...
        mat2str(round(DA.C' * 100) / 100), mat2str(round(SE.C' * 100) / 100));
    fprintf('== day-ahead commitments (c_rb = 0)     coupled: %s   single-event: %s\n', ...
        mat2str(round(DA0.C' * 100) / 100), mat2str(round(SE0.C' * 100) / 100));
    save(fullfile(root, 'results', 'dayahead.mat'), 'DA', 'SE', 'DA0', 'SE0');
end

if any(RUN == 1)
    fprintf('== Exp1: mechanism (two events)\n');
    if QUICK, o1 = struct('gammas', [1.05 1.2], 'taus', [0.25 1 2]); else, o1 = struct(); end
    o1.CA = 6; o1.DA_h = 2; E1a = exp1_mechanism(ctx, root, o1);
    movefile(fullfile(root, 'results', 'exp1_mechanism.csv'), fullfile(root, 'results', 'exp1_mechanism_CA6_DA2.csv'));
    o1.CA = 6; o1.DA_h = 1; o1.DB_h = 2; E1b = exp1_mechanism(ctx, root, o1);
    movefile(fullfile(root, 'results', 'exp1_mechanism.csv'), fullfile(root, 'results', 'exp1_mechanism_CA6_DA1_DB2.csv'));
end
if any(RUN == 2)
    fprintf('== Exp2: main comparison (c_rb = %g)\n', par.dr.c_rb); E2 = exp2_main(ctx, root, DA);
    fprintf('== Exp2: main comparison (c_rb = 0)\n'); E2b = exp2_main(ctx0, root, DA0, '_crb0');
end
if any(RUN == 3)
    if QUICK, o3 = struct('durations', [1 2], 'intervals', [0.5 1], 'gammas', [1.05 1.2], 'Cs', [6 8], 'map_gammas', [1.05], 'map_taus', [0.5 2]); else, o3 = struct(); end
    fprintf('== Exp3: sensitivity (perfect information, c_rb = %g)\n', par.dr.c_rb); E3 = exp3_sensitivity(ctx, root, o3);
    fprintf('== Exp3: sensitivity (perfect information, c_rb = 0)\n'); E3b = exp3_sensitivity(ctx0, root, o3, '_crb0');
end
if any(RUN == 4)
    if QUICK, N = 2; elseif isempty(NMC), N = ctx.inp.mc.N; else, N = NMC; end
    if any(strcmp(MC_PART, {'all', 'certain'}))
        fprintf('== Exp4a: Monte-Carlo, all events certain (c_rb = %g), N = %d\n', par.dr.c_rb, N);
        E4a = exp4_montecarlo(ctx, root, [6 6 6], N, '_certain', bench_list('mc'));
        fprintf('== Exp4b: Monte-Carlo, all events certain (c_rb = 0), N = %d\n', N);
        E4b = exp4_montecarlo(ctx0, root, [6 6 6], N, '_certain_crb0', bench_list('mc'));
    end
    if any(strcmp(MC_PART, {'all', 'uncertain'}))
        % E3 pre-announced day-ahead as possible (call probability 0.6), confirmed or cancelled 1 h before
        % its start (Jiangsu speed coefficient 1.6 for 0.5-2 h notice)
        cu = set_events(ctx, [17 19 21], 1, 6, [24 24 1], [1 1 0.6]);
        fprintf('== Exp4c: Monte-Carlo with event-call uncertainty (E3 p = 0.6, notice 1 h), N = %d\n', N);
        E4c = exp4_montecarlo(cu, root, [6 6 6], N, '_e3uncertain', bench_list('mc_unc'));
    end
end
if any(RUN == 5)
    fprintf('== Exp5: shadow prices and Proposition 2 check\n');
    E5 = exp5_shadow(ctx, root, [6 6 6]);
    E5b = exp5_shadow(ctx0, root, [6 6 6], '_crb0');
    E5c = exp5_shadow(ctx_with_gamma(ctx, 1.0), root, [6 6 6], '_gamma100');
    E5d = exp5_shadow(ctx_with_gamma(ctx0, 1.0), root, [6 6 6], '_gamma100_crb0');
end
if any(RUN == 6)
    if QUICK, N6 = 2; th6 = [0.8 1.0]; else, N6 = 20; th6 = []; end
    fprintf('== Exp6: commitment-operation pairing (c_rb = %g)\n', par.dr.c_rb); E6 = exp6_commitment(ctx, root, DA, SE, N6, '', th6);
    fprintf('== Exp6: commitment-operation pairing (c_rb = 0)\n'); E6b = exp6_commitment(ctx0, root, DA0, SE0, N6, '_crb0', th6);
end
if any(RUN == 7), fprintf('== Exp7: ablation\n'); E7 = exp7_ablation(ctx, root, [6 6 6]); end
if any(RUN == 8)
    fprintf('== Exp8: rebound assessment as a policy parameter\n');
    if QUICK, E8 = exp8_rebound(ctx, root, [6 6 6], [0 3000]); else, E8 = exp8_rebound(ctx, root, [6 6 6]); end
end
if any(RUN == 9)
    fprintf('== Exp9: DR price and shortfall coefficient\n');
    if QUICK, E9 = exp9_price(ctx, root, [6 6 6], 3000, 1); else, E9 = exp9_price(ctx, root, [6 6 6]); end
end
if any(RUN == 10), fprintf('== Exp10: realism (liquid cooling, IT ramp limits, load-up charge)\n'); E10 = exp10_realism(ctx, root, [6 6 6]); end
if any(RUN == 11), fprintf('== Exp11: stylised theorem check\n'); E11 = exp11_stylized(root); end
if any(RUN == 12)
    fprintf('== Exp12: reliably deliverable capacity (c_rb = 0, Monte-Carlo commitment sweep)\n');
    if QUICK, E12 = exp12_capacity(ctx0, root, [6 8], 2, '_crb0'); else, E12 = exp12_capacity(ctx0, root, [4 5 6 7 8 9], 20, '_crb0'); end
end
if any(RUN == 13)
    fprintf('== Exp13: virtual-physical substitution (battery energy, connection margin; c_rb = 0)\n');
    if QUICK, E13 = exp13_substitution(ctx0, root, struct('Es', [6 12], 'gammas', 1.1, 'Cs', [7 8])); else, E13 = exp13_substitution(ctx0, root); end
end
if any(RUN == 15)
    fprintf('== Exp15: risk-averse day-ahead commitment (SP / DRO / RO / CVaR), out of sample with JR-D\n');
    if QUICK, E15 = exp15_risk(ctx, root, struct('Sda', 5, 'N', 2, 'deltas', [0.4 2], 'cvars', [0.8 1.0]));
    else, E15 = exp15_risk(ctx, root); end
end
if any(RUN == 14)
    fprintf('== Exp14: computational performance (run on an idle machine)\n');
    if QUICK, E14 = exp14_timing(ctx, root, struct('Hs', 24, 'Ss', 1, 'reps', 1)); else, E14 = exp14_timing(ctx, root); end
end
fprintf('== all done in %.1f min\n', toc(t_all) / 60);
diary off;
