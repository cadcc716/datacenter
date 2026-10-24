function inp = load_inputs(par, datadir)
%LOAD_INPUTS  Build all time series of the case study from the derived public data.
%   inp.real   : realised profiles of the DR day (Tsim steps)
%   inp.base   : profiles of the 5 typical days used for the DR baseline (Jiangsu rule)
%   inp.pool   : pool of historical days used for forecasts / scenarios
if nargin < 2, datadir = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'data'); end
dt = par.dt; T = par.Tsim; Td = par.Tday;

%% --- deferrable GPU occupancy (busy GPUs per 15 min, 3 runtime classes; PAI 2020 or Acme 2023) ---
wlfile = 'pai_gpu_occupancy_15min.csv';
if isfield(par.case, 'workload_file') && ~isempty(par.case.workload_file), wlfile = par.case.workload_file; end
M = dlmread(fullfile(datadir, wlfile), ',', 1, 0);
days = unique(M(:,1));
nd = numel(days);
occ = zeros(Td, 3, nd); dow = zeros(nd,1);
for i = 1:nd
    r = M(M(:,1) == days(i), :);
    [~, o] = sort(r(:,3));
    occ(:,:,i) = r(o, 4:6);
    dow(i) = r(1,2);
end
wk = find(dow < 5);
scale_flex = par.it.phi_flex * par.it.Ngpu / mean(reshape(sum(occ(:,:,wk),2), [], 1));
occ = occ * scale_flex;
iD = find(days == par.case.pai_day);
if isempty(iD) || iD == nd || dow(iD) >= 5, error('load_inputs:paiday', 'pai_day must be a weekday with a following day'); end
prevwk = wk(wk < iD); prevwk = prevwk(end-4:end);            % 5 previous weekdays
poolwk = wk(wk < iD); poolwk = poolwk(max(1,end-19):end);    % 20 previous weekdays (scenario pool)

%% --- Azure LLM inference index (local time UTC-4, normalised per service) ---
[svc, dstr, slot, tok] = read_azure(fullfile(datadir, 'azure_llm_tokens_15min_local.csv'));
dates = unique(dstr);
idx = nan(Td, numel(dates));
for s = {'code', 'conv'}
    sel = strcmp(svc, s{1});
    mu = mean(tok(sel));
    for j = 1:numel(dates)
        q = sel & strcmp(dstr, dates{j});
        if sum(q) == Td
            v = zeros(Td,1); v(slot(q)+1) = tok(q) / mu;
            idx(:,j) = mean_nan2(idx(:,j), v);
        end
    end
end
azdow = zeros(numel(dates),1);
for j = 1:numel(dates), azdow(j) = weekday_of(dates{j}); end   % 0 = Monday
azwk = find(azdow < 5 & all(~isnan(idx),1)');
idx = idx / mean(reshape(idx(:,azwk),[],1));
ginf = par.it.phi_inf * par.it.Ngpu * idx;
jD = find(strcmp(dates, par.case.azure_date));
jN = find(strcmp(dates, next_date(par.case.azure_date)));
if isempty(jN), jN = jD; end
azpool = setdiff(azwk, jD);

%% --- weather -> PV and chiller COP ---
wfile = 'weather_suzhou_2024summer.csv';
if isfield(par.case, 'weather_file') && ~isempty(par.case.weather_file), wfile = par.case.weather_file; end
[wt, Tamb, ghi] = read_weather(fullfile(datadir, wfile));
wD = weather_day(wt, Tamb, ghi, par.case.weather_date);
wN = weather_day(wt, Tamb, ghi, next_date(par.case.weather_date));
wB = cell(1, numel(par.case.base_dates));
for i = 1:numel(wB), wB{i} = weather_day(wt, Tamb, ghi, par.case.base_dates{i}); end
wP = {}; dP = {};
d0 = par.case.weather_date;
for k = 1:20      % previous 20 days (scenario pool for PV)
    dk = add_days(d0, -k);
    w = weather_day(wt, Tamb, ghi, dk);
    if ~isempty(w), wP{end+1} = w; dP{end+1} = dk; end %#ok<AGROW>
end

%% --- assemble realised DR-day profiles (Tsim steps: day D + 6 h of D+1) ---
nxt = 1:(T - Td);
fs = par.it.flex_share;
inp.real.flex = fs * [occ(:,:,iD); occ(nxt,:,iD+1)];
inp.real.fix  = (1 - fs) * sum([occ(:,:,iD); occ(nxt,:,iD+1)], 2);
inp.real.inf  = [ginf(:,jD); ginf(nxt,jN)];
[pvD, copD, TD] = pv_cop(wD, par); [pvN, copN, TN] = pv_cop(wN, par);
inp.real.pv  = [pvD; pvN(nxt)];
inp.real.cop = [copD; copN(nxt)];
inp.real.T   = [TD; TN(nxt)];

%% --- baseline typical days (each 96 steps) ---
nb = numel(prevwk);
inp.base.flex = cell(1,nb); inp.base.fix = cell(1,nb); inp.base.inf = cell(1,nb); inp.base.pv = cell(1,nb); inp.base.cop = cell(1,nb);
azb = azpool(1:min(nb, numel(azpool)));
for i = 1:nb
    o3 = [occ(:,:,prevwk(i)); occ(nxt,:,prevwk(i)+1)];
    inp.base.flex{i} = fs * o3; inp.base.fix{i} = (1 - fs) * sum(o3, 2);
    a = azb(mod(i-1, numel(azb)) + 1);
    inp.base.inf{i} = [ginf(:,a); ginf(nxt,a)];
    [pb, cb] = pv_cop(wB{i}, par);
    inp.base.pv{i} = [pb; pb(nxt)]; inp.base.cop{i} = [cb; cb(nxt)];
end

%% --- forecast pools (historical days, used for expected forecasts and scenarios) ---
np = numel(poolwk);
inp.pool.flex = zeros(T, 3, np); inp.pool.fix = zeros(T, np);
for i = 1:np
    o3 = [occ(:,:,poolwk(i)); occ(nxt,:,poolwk(i)+1)];
    inp.pool.flex(:,:,i) = fs * o3; inp.pool.fix(:,i) = (1 - fs) * sum(o3, 2);
end
inp.pool.inf = zeros(T, numel(azpool));
for i = 1:numel(azpool), inp.pool.inf(:,i) = [ginf(:,azpool(i)); ginf(nxt,azpool(i))]; end
inp.pool.pv = zeros(T, numel(wP)); inp.pool.cop = zeros(T, numel(wP));
for i = 1:numel(wP)
    [p, c] = pv_cop(wP{i}, par);
    inp.pool.pv(:,i) = [p; p(nxt)]; inp.pool.cop(:,i) = [c; c(nxt)];
end
% expected forecasts: previous-5-weekday mean (compute), pool mean (inference),
% previous-3-day mean (PV, persistence-type), the day's own temperature (COP; temperature forecasts are accurate)
inp.fc.flex = mean(inp.pool.flex(:,:,end-4:end), 3);
inp.fc.fix  = mean(inp.pool.fix(:,end-4:end), 2);
inp.fc.inf  = mean(inp.pool.inf, 2);
inp.fc.pv   = mean(inp.pool.pv(:,1:3), 2);
inp.fc.cop  = inp.real.cop;

%% --- Monte-Carlo realisation library (other weekdays / other hot days) ---
cand = wk(wk > iD & wk < nd);                         % later PAI weekdays with a following day
Wd = all_days_weather(wt, Tamb, ghi); tmax = -Inf(numel(Wd), 1);
for q = 1:numel(Wd), if ~isempty(Wd{q}), tmax(q) = max(Wd{q}.T); end, end
[~, ordT] = sort(tmax, 'descend');
wdays = all_dates(wt);
wsel = {};
for q = ordT(:)'
    if numel(wsel) >= 30, break; end
    if ~strcmp(wdays{q}, par.case.weather_date) && ~any(strcmp(wdays{q}, par.case.base_dates))
        w1 = weather_day(wt, Tamb, ghi, wdays{q}); w2 = weather_day(wt, Tamb, ghi, next_date(wdays{q}));
        if ~isempty(w1) && ~isempty(w2), wsel{end+1} = {w1, w2, wdays{q}}; end %#ok<AGROW>
    end
end
% crossed design: each later PAI weekday is paired with two different hot days (weather) and two
% different Azure inference days -> up to 2 x numel(cand) distinct realisations
nc = min(numel(cand), numel(wsel)); azall = azwk(:)'; na = numel(azall); nw = numel(wsel);
Nmc = min(2 * nc, 60);
inp.mc.N = Nmc; inp.mc.flex = zeros(T, 3, Nmc); inp.mc.fix = zeros(T, Nmc); inp.mc.inf = zeros(T, Nmc);
inp.mc.pv = zeros(T, Nmc); inp.mc.cop = zeros(T, Nmc); inp.mc.label = cell(Nmc, 1);
for r = 1:Nmc
    ip = mod(r - 1, nc) + 1; pass = floor((r - 1) / nc);
    iw = mod(r - 1 + 11 * pass, nw) + 1; ia = mod(r - 1 + 5 * pass, na) + 1;
    o3 = [occ(:,:,cand(ip)); occ(nxt,:,cand(ip)+1)];
    inp.mc.flex(:,:,r) = fs * o3; inp.mc.fix(:,r) = (1 - fs) * sum(o3, 2);
    a1 = azall(ia); a2 = min(a1 + 1, size(ginf, 2));
    inp.mc.inf(:, r) = [ginf(:, a1); ginf(nxt, a2)];
    [p1, c1] = pv_cop(wsel{iw}{1}, par); [p2, c2] = pv_cop(wsel{iw}{2}, par);
    inp.mc.pv(:, r) = [p1; p2(nxt)]; inp.mc.cop(:, r) = [c1; c2(nxt)];
    inp.mc.label{r} = sprintf('pai%d_%s_%s', days(cand(ip)), dates{a1}, wsel{iw}{3});
end

%% --- optional green-power direct connection (offshore wind behind the meter, par.wind) ---
%  Wind power is added to the on-site renewable supply (curtailable like PV, no export) of the DR day,
%  the baseline days, the forecast pool and the Monte-Carlo days, for the same calendar dates as the weather.
inp.real.wind = zeros(T, 1);
if isfield(par, 'wind') && par.wind.Prated > 0
    [tw, vw] = read_wind(fullfile(datadir, par.wind.file));
    wd = @(dstr) wind_day(tw, vw, dstr, par);
    a = wd(par.case.weather_date); b = wd(next_date(par.case.weather_date));
    inp.real.wind = [a; b(nxt)]; inp.real.pv = inp.real.pv + inp.real.wind;
    for i = 1:nb, a = wd(par.case.base_dates{i}); inp.base.pv{i} = inp.base.pv{i} + [a; a(nxt)]; end
    for i = 1:numel(wP), a = wd(dP{i}); b = wd(next_date(dP{i})); inp.pool.pv(:, i) = inp.pool.pv(:, i) + [a; b(nxt)]; end
    inp.fc.pv = mean(inp.pool.pv(:, 1:3), 2);
    inp.mc.wind = zeros(T, inp.mc.N);
    for r = 1:inp.mc.N
        dw = inp.mc.label{r}(find(inp.mc.label{r} == '_', 1, 'last') + 1:end);
        a = wd(dw); b = wd(next_date(dw)); inp.mc.wind(:, r) = [a; b(nxt)];
        inp.mc.pv(:, r) = inp.mc.pv(:, r) + inp.mc.wind(:, r);
    end
end

%% --- admission control: nominal demand never exceeds the schedulable capacity ---
gmax = par.it.u_max * par.it.Ngpu;
[inp.real.flex, inp.real.fix] = clip_util(inp.real.flex, inp.real.fix, inp.real.inf, gmax);
for i = 1:nb, [inp.base.flex{i}, inp.base.fix{i}] = clip_util(inp.base.flex{i}, inp.base.fix{i}, inp.base.inf{mod(i-1,nb)+1}, gmax); end
for i = 1:np, [inp.pool.flex(:,:,i), inp.pool.fix(:,i)] = clip_util(inp.pool.flex(:,:,i), inp.pool.fix(:,i), max(inp.pool.inf, [], 2), gmax); end
for r = 1:inp.mc.N, [inp.mc.flex(:,:,r), inp.mc.fix(:,r)] = clip_util(inp.mc.flex(:,:,r), inp.mc.fix(:,r), inp.mc.inf(:,r), gmax); end
inp.fc.flex = mean(inp.pool.flex(:,:,end-4:end), 3);
inp.fc.fix  = mean(inp.pool.fix(:,end-4:end), 2);

%% --- tariff and events ---
inp.price = tou_price(par);
inp.ev = make_events(par);
inp.info.scale_flex = scale_flex; inp.info.workload_file = wlfile;
inp.info.pai_day = par.case.pai_day; inp.info.pai_prev = days(prevwk)'; inp.info.pai_pool = days(poolwk)';
inp.info.azure_date = par.case.azure_date; inp.info.azure_pool = dates(azpool);
end

%% ======================================================================
function [svc, dstr, slot, tok] = read_azure(f)
fid = fopen(f, 'r'); fgetl(fid);
C = textscan(fid, '%s %s %f %f %f %f', 'Delimiter', ',');
fclose(fid);
svc = C{1}; dstr = C{2}; slot = C{3}; tok = C{5} + C{6};
end

function [t, T, G] = read_weather(f)
fid = fopen(f, 'r'); fgetl(fid);
C = textscan(fid, '%s %f %f %f', 'Delimiter', ',');
fclose(fid);
t = C{1}; T = C{2}; G = C{3};
end

function w = weather_day(t, T, G, d)
% hourly -> 15 min. Temperature is instantaneous; GHI is the mean of the preceding hour.
w = [];
i0 = find(strncmp(t, d, 10), 1);
if isempty(i0) || i0 + 24 > numel(t), return; end
th = (0:24)';                      % hours 0..24 (needs next day 00:00)
Th = T(i0:i0+24);
Gm = G(i0+1:i0+24); tg = (0.5:1:23.5)';   % mean over (h, h+1] centred at h+0.5
tq = ((0:95)' + 0.5) * 0.25;
w.T = interp1(th, Th, tq, 'linear');
w.G = max(0, interp1([0; tg; 24], [0; Gm; 0], tq, 'linear'));
end

function [t, v] = read_wind(f)
fid = fopen(f, 'r');
if fid < 0, error('load_inputs:wind', 'wind file %s not found (data_prep/fetch_wind.py)', f); end
fgetl(fid);
C = textscan(fid, '%s %f', 'Delimiter', ',');
fclose(fid);
t = C{1}; v = C{2};
end

function p = wind_day(t, v, d, par)
% hourly 100-m wind speed (instantaneous) -> 15-min wind-farm power (MW): generic offshore power curve
% (cubic between cut-in and rated speed), farm efficiency par.wind.eta
i0 = find(strncmp(t, d, 10), 1);
if isempty(i0) || i0 + 24 > numel(t), error('load_inputs:windday', 'no wind data for %s', d); end
vq = interp1((0:24)', v(i0:i0+24), ((0:95)' + 0.5) * 0.25, 'linear');
w = par.wind;
cf = (vq.^3 - w.v_in^3) / (w.v_r^3 - w.v_in^3);
cf(vq < w.v_in | vq >= w.v_out) = 0; cf(vq >= w.v_r & vq < w.v_out) = 1;
p = w.Prated * w.eta * cf;
end

function [pv, cop, Tq] = pv_cop(w, par)
Tc = w.T + w.G / 800 * (par.pv.noct - 20);
pv = par.pv.Prated * w.G / 1000 .* (1 + par.pv.gamma * (Tc - 25)) * par.pv.eta_sys;
pv = max(pv, 0);
cop = par.fac.cop_ref - par.fac.cop_k * (w.T - par.fac.T_ref);
cop = min(max(cop, par.fac.cop_min), par.fac.cop_max);
Tq = w.T;
end

function p = tou_price(par)
% Jiangsu 2025 summer TOU on the purchase price; par.price.shape selects alternative shapes with the
% same daily mean (tariff-shape sensitivity, Exp16)
h = ((0:par.Tsim-1)' * par.dt);
hd = mod(h, 24);
f = jiangsu(hd);
shape = 'jiangsu'; if isfield(par.price, 'shape') && ~isempty(par.price.shape), shape = par.price.shape; end
switch shape
    case 'jiangsu'
    case 'flat'                    % no time-of-use signal
        f = ones(size(hd)) * mean(jiangsu((0:95)' / 4));
    case 'two_tier'                % peak 8-22 h / valley otherwise, peak-valley ratio 3
        f = 0.5 * ones(size(hd)); f(hd >= 8 & hd < 22) = 1.5;
    case 'critical'                % Jiangsu shape plus a critical peak 19-21 h (peak x 1.2)
        f(hd >= 19 & hd < 21) = 1.8 * 1.2;
    case 'duck'                    % solar-rich system: midday valley 10-15 h, evening peak 17-23 h
        f = ones(size(hd)); f(hd >= 10 & hd < 15) = 0.35; f(hd >= 17 & hd < 23) = 1.8; f(hd < 6) = 0.6;
    otherwise
        error('load_inputs:shape', 'unknown tariff shape %s', shape);
end
f = f * mean(jiangsu((0:95)' / 4)) / mean(f(1:96));   % same daily mean as the base tariff
p = par.price.nonfloat + par.price.purchase * f;
end

function f = jiangsu(hd)
f = ones(size(hd));
f(hd < 6 | (hd >= 11 & hd < 13)) = 0.35;
f(hd >= 14 & hd < 22) = 1.8;
end

function v = mean_nan2(a, b)
v = b; m = ~isnan(a); v(m) = (a(m) + b(m)) / 2;
end

function w = weekday_of(d)
y = str2double(d(1:4)); m = str2double(d(6:7)); dd = str2double(d(9:10));
w = mod(days_from_civil(y, m, dd) + 3, 7);  % 0 = Monday (1970-01-01 Thursday)
end

function n = days_from_civil(y, m, d)
% Howard Hinnant's algorithm: days since 1970-01-01
y = y - (m <= 2);
era = floor(y / 400);
yoe = y - era * 400;
mp = mod(m + 9, 12);
doy = floor((153 * mp + 2) / 5) + d - 1;
doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy;
n = era * 146097 + doe - 719468;
end

function s = add_days(d, k)
y = str2double(d(1:4)); m = str2double(d(6:7)); dd = str2double(d(9:10));
n = days_from_civil(y, m, dd) + k;
s = civil_from_days(n);
end

function s = next_date(d)
s = add_days(d, 1);
end

function s = civil_from_days(z)
z = z + 719468;
era = floor(z / 146097);
doe = z - era * 146097;
yoe = floor((doe - floor(doe/1460) + floor(doe/36524) - floor(doe/146096)) / 365);
y = yoe + era * 400;
doy = doe - (365*yoe + floor(yoe/4) - floor(yoe/100));
mp = floor((5*doy + 2)/153);
d = doy - floor((153*mp+2)/5) + 1;
m = mp + 3 - 12*(mp >= 10);
y = y + (m <= 2);
s = sprintf('%04d-%02d-%02d', y, m, d);
end

function W = all_days_weather(t, T, G)
D = all_dates(t); W = cell(size(D));
for i = 1:numel(D), W{i} = weather_day(t, T, G, D{i}); end
end

function D = all_dates(t)
D = unique(cellfun(@(x) x(1:10), t, 'UniformOutput', false));
end

function [flex, fix] = clip_util(flex, fix, inf, gmax)
% scale deferrable + Flex-0 training down where the nominal total would exceed the schedulable GPUs
tot = sum(flex, 2) + fix;
room = max(gmax - inf, 0);
f = ones(size(tot)); m = tot > room;
f(m) = room(m) ./ tot(m);
flex = flex .* f; fix = fix .* f;
end
