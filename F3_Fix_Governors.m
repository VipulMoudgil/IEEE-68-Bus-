%% F3_Fix_Governors.m
%  Diagnose and repair governor initial conditions, then verify.
%  Safe to re-run. Backs up before changing anything.
%
%  BACKGROUND
%  Each machine's turbine-governor (STG) block stores its initial gate
%  position as mask parameter 'ini1', in per-unit of the machine's own
%  rating. It must lie between 0 and 1.
%
%  powergui rewrites these when you press Apply in the Load Flow tool.
%  If the machine ratings were ever wrong, the values it writes are wrong
%  too, and restoring the ratings does not undo them.
%
%  This script recomputes ini1 = Pref / machine_rating for every machine.
%
%  All lookups are by block PROPERTY, not by path, so it works regardless
%  of what the enclosing subsystems are named.

mdl = 'IEEE_68_Bus_baseline_v2';      % <-- model to repair

if ~bdIsLoaded(mdl), load_system(mdl); end

fprintf('\n=================================================================\n');
fprintf(' GOVERNOR INITIAL CONDITION REPAIR\n');
fprintf(' Model: %s        %s\n', mdl, datestr(now));
fprintf('=================================================================\n');

%% ---------- 1. map every STG block to its machine -----------------
stg = find_system(mdl,'LookUnderMasks','all','FollowLinks','on', ...
                  'RegExp','on','Name','^STG');
fprintf('\nFound %d STG blocks\n', numel(stg));

rec = struct('stg',{},'gen',{},'name',{},'idx',{},'old',{},'new',{}, ...
             'Pref',{},'Pn',{});

for i = 1:numel(stg)
    % the machine lives in the same G__ subsystem, two levels up
    gpar = fileparts(fileparts(stg{i}));
    cand = find_system(gpar,'LookUnderMasks','all','FollowLinks','on', ...
                       'BlockType','SubSystem');
    gen = '';
    for c = 1:numel(cand)
        if localIsMachine(cand{c}), gen = cand{c}; break; end
    end
    if isempty(gen)
        fprintf('  %-8s : no machine found under %s -- SKIPPED\n', ...
                get_param(stg{i},'Name'), gpar);
        continue
    end

    mvar = get_param(stg{i},'MaskVariables');
    tok  = regexp(mvar,'ini1=@(\d+)','tokens','once');
    if isempty(tok)
        fprintf('  %-8s : no ini1 parameter -- SKIPPED\n', get_param(stg{i},'Name'));
        continue
    end
    j  = str2double(tok{1});
    mv = get_param(stg{i},'MaskValues');

    Pn   = eval(get_param(gen,'NominalParameters'));   % [VA V Hz]
    Pref = eval(get_param(gen,'Pref'));                % W
    gnew = Pref / Pn(1);                               % pu on machine base

    k = numel(rec)+1;
    rec(k).stg  = stg{i};
    rec(k).gen  = gen;
    rec(k).name = get_param(stg{i},'Name');
    rec(k).idx  = j;
    rec(k).old  = mv{j};
    rec(k).new  = sprintf('%.6g', gnew);
    rec(k).Pref = Pref/1e6;
    rec(k).Pn   = Pn(1)/1e6;
end

%% ---------- 2. report before changing anything --------------------
fprintf('\n--- PROPOSED CHANGES ---\n');
fprintf('%-8s %-10s %-10s %-10s %-12s %-12s %s\n', ...
        'STG','MACHINE','Pref(MW)','Pn(MVA)','ini1 NOW','ini1 NEW','status');
nbad = 0;
for i = 1:numel(rec)
    v = str2double(rec(i).new);
    if v < 0 || v > 1
        st = '*** OUT OF RANGE';
    elseif strcmp(strtrim(rec(i).old), rec(i).new)
        st = 'already ok';
    else
        st = 'will change';  nbad = nbad + 1;
    end
    fprintf('%-8s %-10s %-10g %-10g %-12s %-12s %s\n', ...
            rec(i).name, get_param(rec(i).gen,'Name'), rec(i).Pref, ...
            rec(i).Pn, rec(i).old, rec(i).new, st);
end

if nbad == 0
    fprintf('\nNothing to change. Governors already correct.\n');
else
    bakname = sprintf('gov_backup_%s.mat', datestr(now,'yyyymmdd_HHMMSS'));
    govStg = {rec.stg};  govIdx = [rec.idx];  govOld = {rec.old};
    save(bakname,'govStg','govIdx','govOld');
    fprintf('\nBackup written: %s\n', bakname);

    for i = 1:numel(rec)
        mv = get_param(rec(i).stg,'MaskValues');
        mv{rec(i).idx} = rec(i).new;
        set_param(rec(i).stg,'MaskValues',mv);
    end
    fprintf('Applied changes to %d governors.\n', numel(rec));
end

%% ---------- 3. verify by reading back -----------------------------
fprintf('\n--- VERIFY (read back from model) ---\n');
allok = true;
for i = 1:numel(rec)
    mv = get_param(rec(i).stg,'MaskValues');
    v  = str2double(mv{rec(i).idx});
    ok = (v >= 0 && v <= 1);
    allok = allok && ok;
    if ok, tag = 'OK'; else, tag = '*** STILL INVALID'; end
    fprintf('  %-8s ini1 = %-12s %s\n', rec(i).name, mv{rec(i).idx}, tag);
end

%% ---------- 4. machine invariant re-check -------------------------
fprintf('\n--- MACHINE STORED ENERGY (invariant check) ---\n');
subs = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','SubSystem');
tot = 0; ngen = 0;
for i = 1:numel(subs)
    if localIsMachine(subs{i})
        M  = eval(get_param(subs{i},'Mechanical'));
        Pn = eval(get_param(subs{i},'NominalParameters'));
        tot = tot + M(1)*Pn(1)/1e6;
        ngen = ngen + 1;
    end
end
if abs(tot-198010) < 1, tag = 'PASS'; else, tag = '*** FAIL'; end
fprintf('  %d machines, total = %.0f MJ (target 198010)  %s\n', ngen, tot, tag);

%% ---------- 5. dynamic load check ---------------------------------
fprintf('\n--- DYNAMIC LOAD SETTINGS ---\n');
allb = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','Type','Block');
nm   = get_param(allb,'Name');  if ischar(nm), nm = {nm}; end
dlIdx = find(contains(nm,'Dynamic') & ~contains(nm,'3-Phase'));
if isempty(dlIdx)
    fprintf('  none found\n');
else
    for q = dlIdx'
        try
            fprintf('  %s\n', getfullname(allb{q}));
            for f = {'ActiveReactivePowers','PositiveSequence','ExternalControl', ...
                     'NpNq','Tfilter','MinimumVoltage'}
                fprintf('     %-22s = %s\n', f{1}, get_param(allb{q},f{1}));
            end
        catch
        end
    end
end

%% ---------- 6. From Workspace check -------------------------------
fprintf('\n--- FROM WORKSPACE BLOCKS ---\n');
fw = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','FromWorkspace');
if isempty(fw)
    fprintf('  none found\n');
else
    for q = 1:numel(fw)
        fprintf('  %s\n', getfullname(fw{q}));
        for f = {'VariableName','SampleTime','Interpolate','OutputAfterFinalValue'}
            try
                fprintf('     %-22s = %s\n', f{1}, get_param(fw{q},f{1}));
            catch
            end
        end
    end
end

%% ---------- 7. next step ------------------------------------------
fprintf('\n=================================================================\n');
if allok && abs(tot-198010) < 1
    fprintf(' READY.  Next: powergui -> Load Flow -> Compute -> Apply\n');
    fprintf(' Then:   S1_Scenario_DC42\n');
    fprintf('         set_param(''%s'',''StopTime'',''20''); out = sim(''%s'');\n', mdl, mdl);
else
    fprintf(' PROBLEMS REMAIN -- paste this whole output back.\n');
end
fprintf('=================================================================\n\n');


%% ---------- local function ----------------------------------------
function tf = localIsMachine(b)
tf = false;
try
    dp = get_param(b,'DialogParameters');
    if isempty(dp), return; end
    tf = isfield(dp,'NominalParameters') && isfield(dp,'Reactances1') ...
         && isfield(dp,'Mechanical');
catch
end
end