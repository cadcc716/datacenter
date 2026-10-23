function par = dcdr_params()
%DCDR_PARAMS  All model parameters of the AI data-center integrated energy system (AIDC-IES).
%   Every value is tagged:  [S] = taken from a cited source,  [D] = derived from public data,
%   [A] = modelling assumption (documented in docs/ and varied in the sensitivity study).
%   Units: power MW, energy MWh, price CNY/MWh, time step 0.25 h.

par.dt   = 0.25;                 % [A] time step (h)
par.Tday = 96;                   % steps per day
par.Tsim = 120;                  % simulate 00:00 (day D) .. 06:00 (day D+1)

%% ---------------- GPU cluster (IT) ----------------
par.it.Ngpu      = 16000;        % [A] H100-class GPUs (2,000 eight-GPU HGX nodes)
par.it.p_peak    = 8.4/8/1000;   % [S] 8.4 kW measured max per 8xH100 node (Latif et al., arXiv:2412.08602) -> MW/GPU
par.it.p_idle    = 0.25*par.it.p_peak;  % [A] idle node power = 25% of measured max
par.it.k_inf     = 0.65;         % [A] dynamic-power factor of inference GPUs (inference seldom reaches TDP; Patel et al., ASPLOS'24)
par.it.P_other   = 0.6;          % [A] storage / network IT power (MW, constant)
par.it.u_max     = 0.95;         % [A] max schedulable GPU fraction (fragmentation)
par.it.phi_flex  = 0.40;         % [A] mean share of GPUs busy with training/batch work (PAI trace shape)
par.it.flex_share = 0.75;        % [A] part of that work enrolled in Flex 1-3 tiers (rest = Flex 0, not deferrable)
par.it.phi_inf   = 0.25;         % [A] mean share of GPUs busy with online inference (non-deferrable)
% deferrable classes from PAI runtime bins (<=1 h, 1-12 h, >12 h) [D]; lag-bounded SLA
par.it.lag_h     = [0.5 1.5 3];  % [A] max lag L_c (h): Emerald AI Flex1-3 (10/25/50 % throughput loss over 6 h)
% GPU power capping as an additional DR-only lever (Acun et al., ACM e-Energy 2026): a capped GPU draws
% (1-rho) of its dynamic power and loses beta*rho of its throughput, i.e. it leaves a recovery debt of
% beta per unit of power reduction instead of 1 for pausing. Off in the base case (exp10 sensitivity).
par.it.cap_on    = false;        % [A] power capping available during DR events
par.it.cap_rho   = 0.30;         % [A] dynamic-power reduction of a capped GPU
par.it.cap_beta  = 0.40;         % [A] throughput loss per unit power reduction (30 % less power -> 12 % slower)
par.it.class_name = {'C1 short batch (<=1h)', 'C2 medium (1-12h)', 'C3 long training (>12h)'};
par.it.ramp_max  = Inf;          % [A] max change of deferrable IT power per step (MW/15 min); Inf = no limit
par.it.c_ramp    = 5e4;          % [A] penalty on ramping beyond ramp_max (CNY per MW and step; soft so GPUs may idle)

%% ---------------- facility & cooling ----------------
par.fac.a_aux    = 0.05;         % [A] UPS / distribution losses + air handlers (fraction of IT power)
par.fac.P_aux0   = 0.3;          % [A] lighting / offices (MW)
par.fac.theta    = 1.0;          % [A] IT power -> heat to be removed (MW_th per MW)
par.fac.Q0       = 0.3;          % [A] envelope / other cooling load (MW_th)
par.fac.cop_ref  = 6.0;          % [A] chiller-plant COP at 25 C wet/dry reference
par.fac.cop_k    = 0.12;         % [A] COP drop per deg C above reference
par.fac.T_ref    = 25;           % deg C
par.fac.cop_min  = 3.0; par.fac.cop_max = 7.0;
par.fac.Qec_max  = 30;           % electric chiller capacity (MW_th)

%% ---------------- gas engine CCHP + absorption chiller ----------------
par.gt.Pmax      = 3.0;          % [A] gas engine (MW_e)
par.gt.eta_e     = 0.38;         % [A] electrical efficiency (typical gas engine)
par.gt.eta_h     = 0.45;         % [A] recoverable heat efficiency
par.gt.ramp      = 1.5;          % [A] MW per step
par.ac.cop       = 0.75;         % [A] single-effect absorption chiller COP
par.ac.Qmax      = 2.7;          % [A] MW_th
par.price.gas    = 3.6/9.89*1000;% [A] 3.6 CNY/Nm3, LHV 9.89 kWh/Nm3 -> CNY per MWh fuel

%% ---------------- storage ----------------
par.bess.Pmax    = 6;            % [A] MW
par.bess.Emax    = 12*0.95;      % [A] 12 MWh, SOC 10..95 %
par.bess.Emin    = 12*0.10;
par.bess.Ecap    = 12;
par.bess.E0      = 12*0.5;       % initial SOC 50 %
par.bess.eta_c   = 0.95; par.bess.eta_d = 0.95;   % [A] RTE ~0.90
par.bess.c_deg   = 60;           % [A] CNY/MWh throughput (0.6 CNY/Wh system, 6000 cycles @80% DoD)
par.tes.Smax     = 10; par.tes.Smin = 1.0; par.tes.S0 = 5;   % [A] chilled-water tank (MWh_th)
par.tes.Qmax     = 4;            % [A] MW_th
par.tes.eta_c    = 0.98; par.tes.eta_d = 0.98; par.tes.loss = 0.005;  % per hour

%% ---------------- PV ----------------
par.pv.Prated    = 8;            % [A] MWp (rooftop + carport + adjacent "green direct supply")
par.pv.gamma     = -0.0037;      % [S] temperature coefficient (PVWatts v5 default, Dobos 2014)
par.pv.noct      = 45;           % [A] deg C
par.pv.eta_sys   = 0.86;         % [S] system derate (PVWatts v5 default losses 14 %)

%% ---------------- grid & tariff (Jiangsu, summer, from June 2025) ----------------
% periods (consultation draft, Apr 2025): peak 14-22, valley 0-6 & 11-13, flat otherwise
% peak = flat-part x 1.8, valley = x 0.35 on the purchase price (two-part users) [S]
par.price.purchase = 422;        % [D] CNY/MWh, implied by the 0.612 CNY/kWh peak-valley spread (May 2025)
par.price.nonfloat = 250;        % [A] T&D + losses + funds (not floated)
par.cap.gamma     = 1.10;        % [A] connection limit / typical-day peak import (flexible interconnection)
par.cap.Pcap_abs  = [];          % set by setup_case from the baseline peak (MW)
par.cap.Pmin      = 1.5;         % [A] minimum grid import kept for anti-reverse-power protection / supply security (MW)
par.cap.ramp_max  = Inf;         % [A] optional tie-line ramp limit on grid import (MW per 15 min); Inf = off
par.cap.c_ramp    = 5e4;         % [A] CNY per MW and step above the tie-line ramp limit (soft)

%% ---------------- demand response (Jiangsu rules 2024) ----------------
par.dr.price_da   = 3000;        % [S] day-ahead peak-shaving cap 3 CNY/kWh (speed coefficient 1.0)
par.dr.coef_2to4h = 1.4;         % [S] intraday notice 2-4 h
par.dr.coef_05to2h= 1.6;         % [S] intraday notice 0.5-2 h
par.dr.valid_lo   = 0.80;        % [S] effective response if avg reduction >= 80 % of confirmed value
par.dr.valid_margin = 0.1;       % [A] planning margin above the 80 % threshold (MW), against metering / forecast error
par.dr.pay_hi     = 1.20;        % [S] payment capped at 120 %
par.dr.kappa_dev = 1.0;          % [A] shortfall assessed at kappa x the event's DR unit price (symmetric)
par.dr.c_rb       = 3000;        % [A] rebound assessment (CNY/MW per event) = 3 CNY/kW, i.e. the pay of a 1-h event
par.dr.rb_win_h   = 2;           % [A] post-event window in which load must stay <= baseline
par.dr.c_maxload  = 1e5;         % rule (1): load in event <= baseline max (soft, CNY/MW)
par.dr.eps_commit = 100;         % [A] tie-breaker value of committed capacity in the day-ahead model (CNY/MW)
par.dr.pre_win_h  = 3;           % window before the first event used for the load-up metric (h)
par.dr.c_pre      = 0;           % [A] optional pre-event load-up assessment (CNY/MWh above baseline); 0 = none (Jiangsu rules have none)
par.dr.payback_h  = 6;           % horizon of the window-independent payback-energy metric after the last event (h)

%% ---------------- QoS / misc ----------------
par.qos.c_late   = 1000;         % [A] CNY per GPU-h per hour late (acts as a hard SLA)
par.qos.c_jct    = 0.5;          % [A] small preference for early completion (CNY per GPU-h per h)
par.cap.c_over   = 1e5;          % CNY/MWh above the grid limit (soft, should be 0)
par.term.c_E     = 500;          % [A] CNY/MWh value of terminal BESS shortfall, just above the refill cost (valley price + c_deg) / eta_c = 482
par.term.c_S     = 100;          % [A] CNY/MWh_th value of terminal TES shortfall, just above the refill cost valley price / (eta_c * COP) = 77
% leftover backlog at the end of the evaluation window is valued at its energy cost at the flat price
% (set in sys_derived as d.c_B_end, CNY per GPU-h)

%% ---------------- server-room thermal inertia (optional third recovery state; off in the base case) ----------------
% Stored heat TH (MWh_th) of the data hall + chilled-water loop above the supply set-point: cooling may run
% below the heat load during an event (the hall warms up within the allowed band) and must remove that heat
% afterwards, competing for the same recovery channel as catch-up computing and storage recharge.
par.th.on     = false;           % [A] enable the thermal-inertia state
par.th.C      = 2.0;             % [A] effective thermal capacitance, MWh_th per K (chilled-water loop ~1.2 + air/IT/structure)
par.th.dT_up  = 3;               % [A] allowed rise above the set-point, K (e.g. 22 -> 25 C supply, ASHRAE A1 recommended 18-27 C)
par.th.dT_dn  = 2;               % [A] allowed pre-cooling below the set-point, K
par.th.loss   = 0;               % [A] per-hour relaxation of the stored heat (envelope exchange; negligible for a data hall)

%% ---------------- policy constraints (optional; off in the base case) ----------------
% cumulative over the simulated window; the MPC enforces them on accrued + planned quantities (soft)
par.pol.pue_max   = Inf;         % [S] electric PUE cap: new large DCs <= 1.25, national hub nodes <= 1.2 (NDRC et al.,
                                 %     data-centre green and low-carbon action plan, 2024); Inf = off
par.pol.c_pue     = 2000;        % [A] CNY per MWh of facility electricity above the PUE cap (soft)
par.pol.green_min = 0;           % [S] minimum green-electricity share (action plan: > 80 % for new hub-node DCs); 0 = off
par.pol.c_green   = 30;          % [A] environmental premium of purchased green electricity (CNY/MWh)
par.pol.c_green_short = 1000;    % [A] CNY/MWh short of the green-share target (soft)

%% ---------------- carbon accounting ----------------
par.co2.ef_grid  = 0.5617;       % [S] tCO2/MWh, East China grid 2022 average (MEE & NBS notice, 2024-12-20)
par.co2.ef_gas   = 56.1 * 3.6 / 1000;  % [S] tCO2/MWh_fuel, IPCC 2006 default for natural gas (56.1 t/TJ)

%% ---------------- benchmarks ----------------
par.bench.alpha_grid = 0.2:0.1:1.0;   % static compute share searched day-ahead for IR-O* (1.0 = IT side alone)
par.bench.it_gas = 'available';     % IT power budget of the independent benchmarks counts the gas engine's
                                     % ramp-feasible output ('nominal' = its no-DR schedule, earlier weaker variant)

%% ---------------- case selection ----------------
par.case.weather_date = '2024-08-05';          % hot weekday (Tmax 38.3 C, Suzhou-Wujiang)
par.case.base_dates   = {'2024-07-29','2024-07-30','2024-07-31','2024-08-01','2024-08-02'}; % 5 prior workdays
par.case.pai_day      = 27;                    % PAI trace weekday used as DR day
par.case.azure_date   = '2024-05-14';          % Azure LLM weekday used as DR day
par.case.lat = 31.16; par.case.lon = 120.64;

%% ---------------- DR events (base case) ----------------
% start/end in hours of day D, notice (h before start), commitment (MW)
par.ev = struct('t0', {17, 19, 21}, 't1', {18, 20, 22}, 'notice', {24, 24, 3}, 'C', {6, 6, 6}, 'prob', {1, 1, 1});
% prob = probability that a pre-announced event is actually called (confirmed at its notice time)

%% ---------------- MPC ----------------
par.mpc.H        = 72;           % prediction horizon (steps)
par.mpc.S        = 5;            % scenarios
par.mpc.decay    = 0.9;          % persistence of observed forecast error per step
par.mpc.seed     = 2024;
par.mpc.ce_threshold = 0.5;     % deterministic planners treat an unconfirmed event as called if prob >= this
end
