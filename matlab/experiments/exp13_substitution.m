function out = exp13_substitution(ctx, root, opts)
%EXP13_SUBSTITUTION  Virtual-physical substitution: how much battery energy and connection capacity the
%   joint recovery is worth. Perfect-information plans (open loop) so that only the recovery
%   coordination differs. Two sweeps around the base case:
%     'bess'  : battery energy capacity E (MWh, power fixed at par.bess.Pmax); baseline and references are
%               recomputed for the equipped facility, the absolute connection limit is kept;
%     'gamma' : connection margin gamma (connection limit gamma x typical peak).
%   For every configuration and uniform commitment C: IR-O* (best static split in hindsight on a coarse
%   grid), IR-P (perfect-information channel price) and JR. The backlog carried into each event is
%   recorded as the "virtual storage" used by the joint recovery.
if nargin < 3, opts = struct(); end
Es = getf(opts, 'Es', [3 6 9 12 15 18 24]);
gammas = getf(opts, 'gammas', [1.0 1.05 1.1 1.15 1.2 1.3]);
Cs = getf(opts, 'Cs', 5:0.5:9.5);
agrid = getf(opts, 'alpha_grid', [0.6 0.8 1.0]);
S = {'IR-O*', 'IR-P', 'JR'};
rows = []; hdr = {}; t0 = tic;
for sw = 1:2
    if sw == 1, vals = Es; else, vals = gammas; end
    for v = vals
        if sw == 1
            par = ctx.par; par.bess.Ecap = v; par.bess.Emax = 0.95 * v; par.bess.Emin = 0.10 * v; par.bess.E0 = 0.5 * v;
            par.cap.Pcap_fixed = ctx.d.Pcap;
            cfg = setup_case(par, ctx.inp);
        else
            cfg = ctx_with_gamma(ctx, v);
        end
        for C = Cs
            c = apply_commit(cfg, C * [1 1 1]);
            for i = 1:numel(S)
                ci = c;
                if strcmp(S{i}, 'IR-O*'), ci.alpha_star = alpha_hindsight(ci, agrid); end
                if strcmp(S{i}, 'IR-P'), ci.lambda_hr_da = dayahead_prices(ci, 'oracle'); end
                R = run_strategy(ci, S{i}, 'open');
                [row, hdr] = metrics_row(R.M);
                epsr = ci.d.eps_ref;                                  % MWh per GPU-h
                vs = epsr * [sum(R.log.backlog(ci.ev(2).s - 1, :)), sum(R.log.backlog(ci.ev(3).s - 1, :))];
                rows = [rows; sw, v, C, i, vs, row]; %#ok<AGROW>
            end
        end
        q = rows(rows(:, 1) == sw & rows(:, 2) == v, :);
        fprintf('  exp13 %s=%-5g reliable C (>=99%%): IR-O* %.1f  IR-P %.1f  JR %.1f   (%.0f min)\n', ...
            ifelse(sw == 1, 'E', 'gamma'), v, rel_cap(q, 1, Cs), rel_cap(q, 2, Cs), rel_cap(q, 3, Cs), toc(t0) / 60);
    end
end
write_csv(fullfile(root, 'results', 'exp13_substitution.csv'), [{'sweep', 'value', 'C', 'strategy', 'virtual_E2_MWh', 'virtual_E3_MWh'}, hdr], rows);
write_csv(fullfile(root, 'results', 'exp13_strategies.csv'), {'index'}, (1:numel(S))', S);
out.rows = rows; out.hdr = hdr;
end

function c = rel_cap(q, i, Cs)
% largest commitment delivered at >= 99 % with all events valid (column 7 = fulfil %, 8 = n_valid)
c = NaN;
for C = Cs
    r = q(q(:, 3) == C & q(:, 4) == i, :);
    if ~isempty(r) && r(1, 7) >= 99 - 1e-6 && r(1, 8) == 3, c = C; end
end
end

function v = ifelse(cnd, a, b)
if cnd, v = a; else, v = b; end
end

function v = getf(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end
