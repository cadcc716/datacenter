function [par, st, sc, ev, opt, slv] = region_setup(ctx, C, dvar, opts)
%REGION_SETUP  Common data of the capability-region LPs (REGION_CHECK, REGION_RADIUS, REGION_SUPPORT):
%   whole-day perfect-information scenario from the initial state, events of ctx with
%     - commitment held at C_k ('hardm', or 'hard' for opts.basis = 'step') for called events not in dvar,
%     - commitment as a decision variable ('maxm' / 'max') for called events in dvar (K x 1 logical),
%     - 'none' for events that are not called (opts.called, default all called);
%   no lateness allowed, free terminal state; glpk's infeasibility verdict is trusted (no re-solve).
par = ctx.par; K = numel(ctx.ev);
called = true(K, 1); if isfield(opts, 'called') && ~isempty(opts.called), called = logical(opts.called(:)); end
if isempty(dvar), dvar = false(K, 1); end
step = isfield(opts, 'basis') && strcmp(opts.basis, 'step');
hm = 'hardm'; mm = 'maxm'; if step, hm = 'hard'; mm = 'max'; end
ev = ctx.ev; C = C(:);
for k = 1:K
    ev(k).C = C(k);
    if ~called(k), ev(k).mode = 'none';
    elseif dvar(k), ev(k).mode = mm;
    else, ev(k).mode = hm; end
end
st = state_init(par, K); st = add_arrivals(st, ctx.inp.real.flex(1, :), par);
c = ctx; c.fmode = 'oracle';
sc = make_scen(ctx.inp, par, ctx.base, 1, par.Tsim, c);
opt = struct('milp', false, 'visible', called, 'no_late', true, 'terminal', false);
slv = ctx.solver; slv.retry_infeas = false;
end
