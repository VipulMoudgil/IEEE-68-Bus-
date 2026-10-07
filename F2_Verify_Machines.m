%% verify_machines.m
%  Run AFTER applying the mac_con scaling.
%  Paste into the Command Window, or save with this exact filename.
%
%  Checks:
%    1. Machine expressions actually took
%    2. Stored energy invariant  (must be 198,010 MJ)
%    3. Per-unit values are physically plausible
%    4. Transformers still on 100 MVA base
%    5. Outstanding known defects
%    6. Solver configuration
%    7. Workspace data present

mdl = 'IEEE_68_Bus';
if ~bdIsLoaded(mdl), load_system(mdl); end

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' MODEL VERIFICATION  --  %s\n', datestr(now));
fprintf('===============================================================\n');

%% --- 0. workspace data present -----------------------------------
fprintf('\n--- 0. REQUIRED WORKSPACE DATA ---\n');
need = {'mac_con','line','AVR_Data','Bus','Ts'};
ok0 = true;
for i = 1:numel(need)
    if evalin('base', sprintf('exist(''%s'',''var'')', need{i}))
        fprintf('  %-10s present\n', need{i});
    else
        fprintf('  %-10s *** MISSING ***\n', need{i});  ok0 = false;
    end
end

%% --- 1. locate machines -------------------------------------------
subs = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','SubSystem');
gens = {};
for i = 1:numel(subs)
    p = get_param(subs{i},'DialogParameters');
    if ~isempty(p) && isfield(p,'NominalParameters') && isfield(p,'Reactances1')
        gens{end+1} = subs{i};
    end
end
fprintf('\n--- 1. MACHINES FOUND: %d (expect 16) ---\n', numel(gens));

%% --- 2. per-machine detail + stored energy ------------------------
fprintf('\n--- 2. MACHINE PARAMETERS ---\n');
fprintf('%-8s %-5s %-6s %-8s %-8s %-8s %-8s %-9s %-10s\n', ...
        'NAME','row','k','Pn(MVA)','H(s)','xd(pu)','xd''(pu)','Ra(pu)','E(MJ)');
tot = 0; bad = {};
for i = 1:numel(gens)
    nm = get_param(gens{i},'Name');
    rx = get_param(gens{i},'Reactances1');
    r  = str2double(regexp(rx,'mac_con\((\d+)','tokens','once'));
    kt = regexp(rx,'\]\s*\*\s*([\d.eE+-]+)','tokens','once');
    if isempty(kt)
        k = NaN; bad{end+1} = [nm ' : no scale factor in Reactances1'];
    else
        k = str2double(kt{1});
    end
    try
        Pn = eval(get_param(gens{i},'NominalParameters'));
        X  = eval(get_param(gens{i},'Reactances1'));
        M  = eval(get_param(gens{i},'Mechanical'));
        Ra = eval(get_param(gens{i},'StatorResistance'));
        E  = M(1)*Pn(1)/1e6;
        tot = tot + E;
        fprintf('%-8s %-5d %-6g %-8g %-8.3f %-8.3f %-8.4f %-9.6f %-10.0f\n', ...
                nm, r, k, Pn(1)/1e6, M(1), X(1), X(2), Ra, E);
        kexp = (Pn(1)/1e6)/mac_con(r,3);
        if abs(k-kexp) > 1e-6
            bad{end+1} = sprintf('%s : k=%g but Pn/base=%g', nm, k, kexp);
        end
    catch ME
        fprintf('%-8s  *** EVAL FAILED: %s\n', nm, ME.message);
        bad{end+1} = [nm ' : ' ME.message];
    end
end
fprintf('\n  TOTAL STORED ENERGY = %.0f MJ   (target 198010)\n', tot);
if abs(tot-198010) < 1
    fprintf('  >>> PASS\n');
else
    fprintf('  >>> FAIL  (off by %.0f MJ)\n', tot-198010);
end

%% --- 3. plausibility ---------------------------------------------
fprintf('\n--- 3. PLAUSIBILITY FLAGS ---\n');
fprintf('  (typical: H 2-10 s,  xd 1.5-2.5 pu,  xd'' 0.2-0.4 pu)\n');
nflag = 0;
for i = 1:numel(gens)
    nm = get_param(gens{i},'Name');
    try
        X = eval(get_param(gens{i},'Reactances1'));
        M = eval(get_param(gens{i},'Mechanical'));
        msg = {};
        if M(1) < 1.5 || M(1) > 12,  msg{end+1} = sprintf('H=%.2f s', M(1)); end
        if X(1) < 0.8 || X(1) > 3.5, msg{end+1} = sprintf('xd=%.2f pu', X(1)); end
        if ~isempty(msg)
            fprintf('  %-8s %s\n', nm, strjoin(msg,', '));  nflag = nflag+1;
        end
    catch
    end
end
if nflag==0, fprintf('  none\n'); end

%% --- 4. transformers ----------------------------------------------
fprintf('\n--- 4. TRANSFORMER BASES ---\n');
ntf = 0; nwrong = 0;
for i = 1:numel(subs)
    p = get_param(subs{i},'DialogParameters');
    if ~isempty(p) && isfield(p,'NominalPower') && isfield(p,'Winding1')
        ntf = ntf + 1;
        v = get_param(subs{i},'NominalPower');
        if isempty(strfind(v,'100e6'))
            fprintf('  %-10s %s   <-- NOT 100e6\n', get_param(subs{i},'Name'), v);
            nwrong = nwrong + 1;
        end
    end
end
fprintf('  %d transformers, %d not on 100e6\n', ntf, nwrong);

%% --- 5. known outstanding defects ---------------------------------
fprintf('\n--- 5. KNOWN DEFECT CHECK ---\n');
chk = {'T63-64','Winding2','0.152'; 'T65-64','Winding2','0.152'; ...
       'T12-36','Winding2','0.002'};
for i = 1:size(chk,1)
    b = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','Name',chk{i,1});
    if isempty(b)
        fprintf('  %-8s not found (commented?)\n', chk{i,1});
    else
        v = get_param(b{1},chk{i,2});
        if ~isempty(strfind(v,chk{i,3}))
            fprintf('  %-8s STILL BAD : %s = %s\n', chk{i,1}, chk{i,2}, v);
        else
            fprintf('  %-8s ok        : %s = %s\n', chk{i,1}, chk{i,2}, v);
        end
    end
end

%% --- 6. governor initial conditions -------------------------------
fprintf('\n--- 6. GOVERNOR INITIAL CONDITIONS (ini1) ---\n');
stg = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','^STG');
for i = 1:numel(stg)
    try
        mv = get_param(stg{i},'MaskValues');
        mvar = get_param(stg{i},'MaskVariables');
        idx = regexp(mvar,'ini1=@(\d+)','tokens','once');
        if ~isempty(idx)
            j = str2double(idx{1});
            fprintf('  %-30s ini1 = %s\n', get_param(stg{i},'Name'), mv{j});
        end
    catch
    end
end

%% --- 7. solver -----------------------------------------------------
fprintf('\n--- 7. SOLVER ---\n');
for f = {'SolverType','Solver','FixedStep','StopTime'}
    fprintf('  %-12s = %s\n', f{1}, get_param(mdl,f{1}));
end

%% --- summary -------------------------------------------------------
fprintf('\n===============================================================\n');
if isempty(bad) && abs(tot-198010) < 1 && ok0
    fprintf(' RESULT: machine rebase VERIFIED\n');
else
    fprintf(' RESULT: ISSUES FOUND\n');
    for i = 1:numel(bad), fprintf('   - %s\n', bad{i}); end
end
fprintf('===============================================================\n\n');