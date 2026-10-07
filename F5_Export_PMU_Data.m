%% F25_Extract_All.m
%  One extraction, one Excel file: bus voltages + trip logic (from F6)
%  PLUS all machine monitoring signals on their own sheets.
%
%  Run straight after a simulation:
%      out = sim('IEEE_BUS_68_AGC');
%      F25_Extract_All
%
%  SHEETS
%    V_area1..V_area5   bus voltages, time in column A
%    Summary            per-bus voltage statistics
%    TripLogic          crossing times, durations, trip verdict
%    Mach_w  Mach_Pe .. one sheet per machine signal, columns = machines
%    Freq_Hz            machine frequency, 60*w
%    Info               run metadata

outfile = sprintf('Results_%s.xlsx', datestr(now,'yyyymmdd_HHMM'));

% ---- voltage / trip settings (unchanged from F6) ----
V_THRESHOLD  = 1.10;
TRIP_DELAY   = 3.0;
RESET_ON_DIP = true;
GAIN_CORR    = 1;
VMIN = 0.95;  VMAX = 1.05;
DC_BUSES = [45 51 20 55];

% ---- machine signals to export ----
MSIGS = {'w','d_theta','Pe','Pa','Q','Vt','EFD','pss'};
NMACH = 16;

areas = struct( ...
 'name', {'area1','area2','area3','area4','area5'}, ...
 'buses',{[4 5 6 7 19 20 21 22 23 24 68], ...
          [2 3 37 52 55 56 57 58 59 60 62 63 64 65 66 67], ...
          [1 8 9 25 26 27 28 29 47 53 54], ...
          [10 11 12 13 17 30 31 32 33 34 35 36 38 39 43 44 45 46 49 50 51 61], ...
          [14 15 16 18 40 41 42 48]});
genBuses = 1:16;

fprintf('\n===============================================================\n');
fprintf(' EXTRACT ALL (voltages + machines)   %s\n', datestr(now));
fprintf('===============================================================\n');

%% ---------- unpack the sim output ------------------------------------
if evalin('base','exist(''out'',''var'')')
    try
        o = evalin('base','out');  nm = o.who;
        for i = 1:numel(nm), assignin('base', nm{i}, o.(nm{i})); end
        fprintf('\nUnpacked %d variables from ''out''\n', numel(nm));
    catch ME
        fprintf('\ncould not unpack ''out'': %s\n', ME.message);
    end
end

%% ================= PART 1: BUS VOLTAGES (F6) =========================
D = struct();  Tend = 0;  found = 0;
for a = 1:numel(areas)
    an = areas(a).name;  bl = areas(a).buses;  vn = ['V_' an];
    if ~evalin('base', sprintf('exist(''%s'',''var'')', vn))
        fprintf('  %-9s not in workspace -- skipped\n', vn);  continue
    end
    S = evalin('base', vn);
    t = S.time;  Y = S.signals.values;
    if size(Y,1) ~= numel(t), Y = Y'; end
    Y = Y / GAIN_CORR;
    nb  = numel(bl);  per = size(Y,2) / nb;
    if abs(per - round(per)) > 1e-9
        fprintf('  %-9s %d cols for %d buses -- skipped\n', vn, size(Y,2), nb);  continue
    end
    per = round(per);
    if per == 1, V = Y;
    else
        V = zeros(numel(t), nb);
        for k = 1:nb, V(:,k) = mean(Y(:,(k-1)*per+(1:per)),2); end
    end
    D.(an) = struct('t',t,'V',V,'buses',bl);
    Tend = max(Tend, t(end));  found = found + 1;
    fprintf('  %-9s %6d samples, 0 to %.1f s, %2d buses\n', vn, numel(t), t(end), nb);
end

EV = NaN;
if found > 0
    fn = fieldnames(D);
    tv = D.(fn{1}).t;
    agg = zeros(numel(tv)-1,1);
    for i = 1:numel(fn), agg = agg + sum(abs(diff(D.(fn{i}).V,1,1)),2); end
    mask = tv(1:end-1) >= 2;
    [~,ix] = max(agg .* mask);  EV = tv(ix+1);
    fprintf('\nDisturbance detected at t = %.3f s\n', EV);

    summary = {};  trip = {};
    for i = 1:numel(fn)
        an = fn{i};  t = D.(an).t;  V = D.(an).V;  bl = D.(an).buses;
        pre_k  = t >= 3 & t <= EV-0.1;
        post_k = t > EV;
        end_k  = t >= 0.85*t(end);
        for j = 1:numel(bl)
            b = bl(j);  v = V(:,j);
            pre = mean(v(pre_k));  post = v(post_k);  tp = t(post_k);
            pk = max(post);  dip = min(post);  fin = mean(v(end_k));
            isGen = ismember(b, genBuses);
            btype = 'LOAD'; if isGen, btype = 'GEN'; end
            flag = '';
            if ~isGen
                if pk  > VMAX, flag = 'HIGH'; end
                if dip < VMIN, flag = strtrim([flag ' LOW']); end
            end
            summary(end+1,:) = { b, an, btype, pre, pk, dip, fin, pk-dip, flag }; %#ok<SAGROW>

            runs = {};  st = [];  lastt = NaN;
            for k = 1:numel(tp)
                if post(k) > V_THRESHOLD
                    if isempty(st), st = tp(k); end
                    lastt = tp(k);
                else
                    if ~isempty(st), runs{end+1} = [st lastt]; st = []; end %#ok<SAGROW>
                end
            end
            if ~isempty(st), runs{end+1} = [st lastt]; end %#ok<SAGROW>
            if isempty(runs), first = NaN; longest = 0; total = 0;
            else
                R = cell2mat(runs(:));
                first = R(1,1); longest = max(R(:,2)-R(:,1)); total = sum(R(:,2)-R(:,1));
            end
            tt = NaN;
            if RESET_ON_DIP
                for q = 1:numel(runs)
                    if runs{q}(2)-runs{q}(1) >= TRIP_DELAY
                        tt = runs{q}(1) + TRIP_DELAY;  break
                    end
                end
            else
                if total >= TRIP_DELAY, tt = first + TRIP_DELAY; end
            end
            isDC = ismember(b, DC_BUSES);
            if isnan(tt), verdict = 'no';
            elseif isDC, verdict = 'TRIPS';
            else, verdict = 'crosses (no DC)'; end
            trip(end+1,:) = { b, an, pre, pk, 100*(pk/pre-1), first, longest, total, tt, verdict }; %#ok<SAGROW>
        end
    end

    for i = 1:numel(fn)
        an = fn{i};
        hdr = arrayfun(@(b) sprintf('Bus%02d',b), D.(an).buses,'UniformOutput',false);
        writetable(array2table([D.(an).t D.(an).V],'VariableNames',[{'Time_s'} hdr]), ...
                   outfile, 'Sheet', ['V_' an]);
    end
    Tsum = sortrows(cell2table(summary,'VariableNames', ...
       {'Bus','Area','Type','Vpre','Vpeak','Vdip','Vfinal','Vswing','Flag'}),'Bus');
    writetable(Tsum, outfile, 'Sheet','Summary');
    Ttrip = sortrows(cell2table(trip,'VariableNames', ...
       {'Bus','Area','Vpre','Vpeak','Rise_pct','FirstCross_s','LongestAbove_s', ...
        'TotalAbove_s','TripTime_s','Verdict'}),'Vpeak','descend');
    writetable(Ttrip, outfile, 'Sheet','TripLogic');

    tr = sortrows(Ttrip(strcmp(Ttrip.Verdict,'TRIPS'),:),'TripTime_s');
    fprintf('\n--- FACILITIES THAT TRIP ---\n');
    if isempty(tr), fprintf('  none\n');
    else
        for i=1:height(tr)
            fprintf('  bus %-3d %-7s trips at t = %.3f s\n', tr.Bus(i), tr.Area{i}, tr.TripTime_s(i));
        end
    end
end

%% ================= PART 2: MACHINE LOGS ==============================
fprintf('\n--- MACHINE SIGNALS ---\n');
Tref = [];
for s = 1:numel(MSIGS)
    for g = 1:NMACH
        [t,~] = local_getsig(sprintf('%s%d',MSIGS{s},g));
        if ~isempty(t), Tref = t(:); break; end
    end
    if ~isempty(Tref), break; end
end

if isempty(Tref)
    fprintf('  no machine variables in workspace -- machine sheets skipped\n');
else
    N = numel(Tref);
    for s = 1:numel(MSIGS)
        sig = MSIGS{s};  cols = {Tref};  hdr = {'Time_s'};  cnt = 0;
        for g = 1:NMACH
            [t,v] = local_getsig(sprintf('%s%d',sig,g));
            if isempty(v), continue; end
            if numel(v)~=N, try, v = interp1(t(:),v(:),Tref,'linear','extrap'); catch, continue; end; end
            cols{end+1} = v(:); hdr{end+1} = sprintf('%s%d',sig,g); %#ok<SAGROW>
            cnt = cnt + 1;
        end
        if cnt==0, fprintf('  %-8s none\n', sig); continue; end
        writecell([hdr; num2cell([cols{:}])], outfile, 'Sheet', ['Mach_' sig]);
        fprintf('  %-8s %2d machines -> Mach_%s\n', sig, cnt, sig);
    end
    % frequency in Hz from w
    fc = {Tref}; fh = {'Time_s'}; nf = 0;
    for g = 1:NMACH
        [t,v] = local_getsig(sprintf('w%d',g));
        if isempty(v), continue; end
        if numel(v)~=N, try, v = interp1(t(:),v(:),Tref,'linear','extrap'); catch, continue; end; end
        fc{end+1} = 60*v(:); fh{end+1} = sprintf('f%d_Hz',g); nf = nf+1; %#ok<SAGROW>
    end
    if nf>0
        writecell([fh; num2cell([fc{:}])], outfile, 'Sheet','Freq_Hz');
        fprintf('  %-8s %2d machines -> Freq_Hz (60*w)\n', 'freq', nf);
    end
end

%% ================= INFO ==============================================
dipStr = 'no'; if RESET_ON_DIP, dipStr = 'yes'; end
writecell({'Generated',datestr(now); 'RunLength_s',num2str(Tend); ...
           'EventTime_s',num2str(EV); 'Threshold_pu',num2str(V_THRESHOLD); ...
           'TripDelay_s',num2str(TRIP_DELAY); 'ResetOnDip',dipStr; ...
           'GainCorrection',num2str(GAIN_CORR); 'DC_Buses',mat2str(DC_BUSES)}, ...
           outfile, 'Sheet','Info');

fprintf('\n---------------------------------------------------------------\n');
fprintf(' Wrote %s\n', fullfile(pwd,outfile));
fprintf(' Voltages + trip logic + machine signals, all in one file.\n');
fprintf('---------------------------------------------------------------\n\n');


%% ================= helper (must be at end) ===========================
function [t,v] = local_getsig(name)
    t = []; v = [];
    if ~evalin('base', sprintf('exist(''%s'',''var'')', name)), return; end
    s = evalin('base', name);
    if isstruct(s) && isfield(s,'signals'), v = s.signals.values; t = s.time;
    elseif isstruct(s) && isfield(s,'Data'), v = s.Data; t = s.Time;
    elseif isa(s,'timeseries'), v = s.Data; t = s.Time;
    elseif isnumeric(s), v = s; t = (1:size(s,1))';
    end
    v = squeeze(v);
    if size(v,1)==1, v = v(:); end
end