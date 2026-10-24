function R = run_strategy(ctx, name, fmode)
%RUN_STRATEGY  Run one scheduling strategy on the DR day and evaluate it.
%   name : 'NoDR' | 'IR-R' | 'IR-O' | 'IR-O*' | 'IR-P' | 'JR' | 'JR-M'
%     IR-R  independent recovery, rule based
%     IR-O  independent recovery, sequential optimisation, static split ctx.alpha
%     IR-O* as IR-O with the split tuned day-ahead (ctx.alpha_star, see prepare_benchmarks)
%     IR-P  independent recovery coordinated only by a day-ahead shadow price (ctx.lambda_hr_da)
%     JR    joint recovery (proposed); JR-M joint but event-by-event (no cross-event foresight)
%   fmode: 'open'     - perfect-information plan solved once over the whole day, replayed open loop
%          'oracle'   - rolling horizon with perfect forecasts
%          'expected' - rolling horizon, deterministic (historical-mean) forecasts
%          'scenario' - rolling horizon, scenario-based MPC
par = ctx.par; inp = ctx.inp;
if nargin < 3, fmode = 'open'; end
ctx.fmode = fmode;
if ~isfield(ctx, 'lambda_hr'), ctx.lambda_hr = []; end
switch name
    case 'NoDR'
        if isfield(ctx, 'ref_eval'), o = ctx.ref_eval; else, o = ctx.ref; end
    case 'IR-R'
        o = run_closed_loop(par, inp.real, ctx.base, ctx.ev, @planner_irr, ctx);
    case {'IR-O', 'IR-O*', 'IR-P'}
        ctx.lambda_hr = [];
        if strcmp(name, 'IR-O*'), ctx.alpha = ctx.alpha_star; end
        if strcmp(name, 'IR-P'), ctx.lambda_hr = ctx.lambda_hr_da; end
        if strcmp(fmode, 'open')
            ctx.plan = open_plan_iro(ctx);
            o = run_closed_loop(par, inp.real, ctx.base, ctx.ev, @planner_plan, ctx);
        else
            o = run_closed_loop(par, inp.real, ctx.base, ctx.ev, @planner_iro, ctx);
        end
    case {'JR', 'JR-M'}
        if strcmp(name, 'JR-M')
            ctx.myopic = true; ctx.Eterm = []; ctx.Sterm = [];
            if strcmp(fmode, 'open'), ctx.fmode = 'oracle'; fmode = 'oracle'; end
        end
        if strcmp(fmode, 'open')
            ctx.plan = open_plan_jr(ctx);
            o = run_closed_loop(par, inp.real, ctx.base, ctx.ev, @planner_plan, ctx);
        else
            o = run_closed_loop(par, inp.real, ctx.base, ctx.ev, @planner_jr, ctx);
        end
    otherwise
        error('run_strategy:name', 'unknown strategy %s', name);
end
R.name = name; R.fmode = fmode; R.log = o.log;
refL = []; if isfield(ctx, 'ref_eval'), refL = ctx.ref_eval.log; end
R.M = evaluate_run(o.log, ctx.ev, ctx.base, par, inp, refL);
end

function plan = open_plan_jr(ctx)
par = ctx.par; st = state_init(par, numel(ctx.ev));
st = add_arrivals(st, ctx.inp.real.flex(1, :), par);
c = ctx; c.fmode = 'oracle';
sc = make_scen(ctx.inp, par, ctx.base, 1, par.Tsim, c);
act = event_activity(ctx, 1, 1, 'oracle');
opt = struct('milp', ctx.milp, 'visible', any(act, 2), 'active', act, 'terminal', true, ...
             'Eref_end', ctx.Eref(end), 'Sref_end', ctx.Sref(end), 'Href_end', href_end(ctx));
[P, ix] = build_model(par, st, sc, ctx.ev, opt);
sol = solve_milp(P, ctx.solver);
if ~sol.ok, error('run_strategy:jr', 'JR open-loop plan infeasible'); end
plan = extract_plan(sol.x, ix);
end

function plan = open_plan_iro(ctx)
par = ctx.par; st = state_init(par, numel(ctx.ev));
st = add_arrivals(st, ctx.inp.real.flex(1, :), par);
c = ctx; c.fmode = 'oracle';
sc = make_scen(ctx.inp, par, ctx.base, 1, par.Tsim, c);
act = event_activity(ctx, 1, 1, 'oracle'); vis = act(:, 1);
o1 = struct('alpha', ctx.alpha, 'visible', vis, 'pgt_nom', ctx.pgt_nom, 'ynom_now', sum(ctx.inp.real.flex(1,:)));
if ~isempty(ctx.lambda_hr), o1.lambda = ctx.lambda_hr; o1.use_share = false; end
[P1, ix1] = build_compute_model(par, st, sc, ctx.ev, o1);
s1 = solve_milp(P1, ctx.solver);
if ~s1.ok, error('run_strategy:iro1', 'IR-O stage 1 infeasible'); end
yfix = [s1.x(ix1.Y{1}), s1.x(ix1.Y{2}), s1.x(ix1.Y{3})];
zfix = []; if ~isempty(ix1.Zc), zfix = [s1.x(ix1.Zc{1}), s1.x(ix1.Zc{2}), s1.x(ix1.Zc{3})]; end
o2 = struct('milp', ctx.milp, 'fix_y', yfix, 'fix_z', zfix, 'visible', vis, 'active', act, 'terminal', true, ...
            'Eref_end', ctx.Eref(end), 'Sref_end', ctx.Sref(end), 'Href_end', href_end(ctx));
[P2, ix2] = build_model(par, st, sc, ctx.ev, o2);
s2 = solve_milp(P2, ctx.solver);
if ~s2.ok, error('run_strategy:iro2', 'IR-O stage 2 infeasible'); end
plan = extract_plan(s2.x, ix2);
plan.y = yfix; if ~isempty(zfix), plan.z = zfix; end
end

function h = href_end(ctx)
h = 0; if isfield(ctx, 'Href') && ~isempty(ctx.Href), h = ctx.Href(end); end
end
