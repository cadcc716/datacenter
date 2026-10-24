function ctx = setup_case(par, inp)
%SETUP_CASE  Prepare everything a strategy run needs (baseline, references, events, scenarios).
if nargin < 2, inp = load_inputs(par); end
par.cap.Pcap_abs = [];
[base, ~] = compute_baseline(par, inp);            % typical days, connection limit not binding
par.cap.Pbase_peak = max(base(1:par.Tday));
par.cap.Pcap_abs = par.cap.gamma * par.cap.Pbase_peak;
if isfield(par.cap, 'Pcap_fixed') && ~isempty(par.cap.Pcap_fixed)
    par.cap.Pcap_abs = par.cap.Pcap_fixed;          % absolute connection limit kept (equipment sweeps)
end
ref = run_nodr(par, inp, base);
d = sys_derived(par);
ev = inp.ev;
for k = 1:numel(ev)
    ev(k).Pbmax = max(base(ev(k).s:ev(k).e));
    ev(k).mode = 'settle';
end
% fixed compute/storage split used by the independent strategies: ratio of single-event capabilities
gc = 0; gs = 0;
for k = 1:numel(ev)
    tt = ev(k).s:ev(k).e;
    phi = 1 + par.fac.a_aux + par.fac.theta ./ inp.real.cop(tt);
    gc = gc + mean(phi .* d.pdyn .* sum(inp.fc.flex(tt, :), 2));
    gs = gs + par.bess.Pmax + mean(par.tes.Qmax ./ inp.real.cop(tt));
end
ctx.alpha = gc / (gc + gs);
ctx.cap_comp = gc / numel(ev); ctx.cap_stor = gs / numel(ev);
ctx.par = par; ctx.inp = inp; ctx.base = base; ctx.ref = ref; ctx.ref_eval = ref; ctx.ev = ev;
ctx.pgt_nom = ref.log.pgt; ctx.Eref = ref.log.E; ctx.Sref = ref.log.S;
ctx.H = par.mpc.H; ctx.milp = true; ctx.solver = struct(); ctx.fmode = 'oracle'; ctx.all_visible = false;
ctx.sidx = scenario_index(par, inp);
ctx.d = d;
end
