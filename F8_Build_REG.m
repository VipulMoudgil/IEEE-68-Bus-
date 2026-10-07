%% F13_Fix_REG13.m
%  Repairs the renewable proxy at bus 13 and reports what is left to do.
%
%  WHAT THE DUMP SHOWED
%    REG13 was copied from gen13 and kept four things it should not have:
%      H            still [mac_con(13,16) 0 4], the host's inertia
%      BusType      PV, so it would fight the host for voltage control
%      Pref         a load-flow Pref of 1288.2e6 while set to PV
%      governor     a Pref constant of 0.5985 inherited from the host
%    The host's own load-flow Pref was also left at 3591e6 after its
%    rating had been reduced to 3848 MVA.
%
%  WHAT THIS DOES
%    Writes H = 1 s as a literal, sets the proxy to PQ at its own output,
%    corrects the host's Pref, and then lists every Pref constant in area 4
%    with what it feeds, so the governor question can be settled by eye.
%
%  Back up first:  copyfile('IEEE_BUS_68_AGC.slx','PRE_REGFIX.slx');

mdl    = 'IEEE_BUS_68_AGC';
AREA   = 'area-4';
REG    = 'REG13';
HOST   = 'gen13';
H_REG  = 1.0;
REG_MW = 1288.2;        % proxy output
REG_MVA= 1442.78;       % proxy rating
HOST_MW= 2303;          % host output after displacement

if ~bdIsLoaded(mdl), load_system(mdl); end
F = {'Variants','AllVariants'};

fprintf('\n===============================================================\n');
fprintf(' REPAIR %s   %s\n', REG, datestr(now));
fprintf('===============================================================\n');

R = sprintf('%s/%s/%s', mdl, AREA, REG);
G = sprintf('%s/%s/G13/%s', mdl, AREA, HOST);
for p = {R, G}
    parts = strsplit(p{1},'/');
    if isempty(find_system(mdl,'LookUnderMasks','all','FollowLinks','on',F{:}, ...
                           'Name', parts{end}))
        fprintf('\n  %s not found. Stopping.\n\n', p{1}); return
    end
end

%% ---------- before ---------------------------------------------------
fprintf('\n--- BEFORE ---\n');
show = @(tag,pth) fprintf('  %-7s H=%-26s type=%-4s P=%-14s S=%s\n', tag, ...
    get_param(pth,'Mechanical'), get_param(pth,'BusType'), ...
    get_param(pth,'Pref'), get_param(pth,'NominalParameters'));
show(REG, R);  show(HOST, G);

%% ---------- 1. inertia ----------------------------------------------
fprintf('\n--- INERTIA ---\n');
mech = get_param(R,'Mechanical');
try
    mv = evalin('base', mech);
    fprintf('  host expression %s\n  evaluates to H = %.4f s\n', mech, mv(1));
    mv(1) = H_REG;
    set_param(R,'Mechanical', ['[ ' sprintf('%g ', mv) ']']);
    fprintf('  %s H written as a literal: %s\n', REG, get_param(R,'Mechanical'));
catch ME
    fprintf('  could not evaluate %s (%s)\n', mech, ME.message);
    fprintf('  set the Mechanical tab of %s by hand: first entry = %.1f\n', REG, H_REG);
end

%% ---------- 2. load flow role ---------------------------------------
fprintf('\n--- LOAD FLOW ---\n');
set_param(R,'BusType','PQ');
set_param(R,'Pref', sprintf('%ge6', REG_MW));
set_param(R,'Qref','0');
fprintf('  %s  -> PQ at %.1f MW, 0 MVAr  (no AVR, so it follows the bus)\n', REG, REG_MW);
set_param(G,'Pref', sprintf('%ge6', HOST_MW));
fprintf('  %s  -> Pref %.0f MW\n', HOST, HOST_MW);

%% ---------- 3. stored energy ----------------------------------------
fprintf('\n--- STORED ENERGY, AREA 4 ---\n');
tot = 0; names = {'gen10','gen11','gen12',HOST,REG};
for i = 1:numel(names)
    b = find_system(mdl,'LookUnderMasks','all','FollowLinks','on',F{:},'Name',names{i});
    if isempty(b), fprintf('  %-8s not found\n', names{i}); continue; end
    try
        S = evalin('base', get_param(b{1},'NominalParameters'));
        Hv= evalin('base', get_param(b{1},'Mechanical'));
        E = Hv(1)*S(1)/1e6;  tot = tot + E;
        fprintf('  %-8s H=%6.3f s   S=%8.1f MVA   HxS=%9.0f MJ\n', names{i}, Hv(1), S(1)/1e6, E);
    catch
        fprintf('  %-8s could not evaluate\n', names{i});
    end
end
fprintf('  %-8s %42s %9.0f MJ\n','TOTAL','', tot);
fprintf('  baseline was 64750 MJ  ->  %.1f%% reduction\n', 100*(64750-tot)/64750);

%% ---------- 4. every Pref constant in the area, and what it feeds ----
fprintf('\n--- Pref CONSTANTS IN %s ---\n', AREA);
c = find_system([mdl '/' AREA],'LookUnderMasks','all','FollowLinks','on',F{:}, ...
                'BlockType','Constant');
for i = 1:numel(c)
    nm = get_param(c{i},'Name');
    if ~startsWith(lower(nm),'pref'), continue; end
    dest = '';
    try
        pc = get_param(c{i},'PortConnectivity');
        for k = 1:numel(pc)
            if pc(k).DstBlock > 0
                dest = [dest ' -> ' get_param(pc(k).DstBlock,'Name')]; %#ok<AGROW>
            end
        end
    catch
    end
    fprintf('  %-8s = %-10s  %s%s\n', nm, get_param(c{i},'Value'), ...
            strrep(getfullname(c{i}), [mdl '/'], ''), dest);
end

%% ---------- 5. after -------------------------------------------------
fprintf('\n--- AFTER ---\n');
show(REG, R);  show(HOST, G);
save_system(mdl);

%% ---------- 6. what is left ------------------------------------------
fprintf('\n---------------------------------------------------------------\n');
fprintf(' LEFT TO DO BY HAND\n\n');
fprintf('  1. %s has no governor and no exciter in the real machine it\n', REG);
fprintf('     represents. From the list above, find the Pref constant that\n');
fprintf('     feeds %s and set it to %.4f, or disconnect the governor and\n', REG, REG_MW/REG_MVA);
fprintf('     feed Pm from a plain Constant of that value.\n\n');
fprintf('  2. Disconnect %s''s exciter. Feed Vf from a Constant, 1.0 for now.\n\n', REG);
fprintf('  3. Confirm %s is NOT wired into the area 4 AGC. It should not\n', REG);
fprintf('     take part in secondary control.\n\n');
fprintf('  4. Wire %s''s A, B, C to the same node as %s if not already done.\n\n', REG, HOST);
fprintf('  5. Remove breakers, Compute, then read the field voltage:\n\n');
fprintf('        ic = str2num(get_param(''%s'',''InitialConditions''));\n', R);
fprintf('        fprintf(''Vf = %%.4f pu\\n'', ic(9));\n\n');
fprintf('     Put that in the Vf constant, Compute again, Apply.\n\n');
fprintf('  6. Save the scenario:\n');
fprintf('        save_system(''%s'',''SWEEP_REG20.slx'');\n', mdl);
fprintf('---------------------------------------------------------------\n\n');