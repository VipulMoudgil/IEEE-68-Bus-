%% S1_Scenario_DC42.m
%  Attack schedule for the data center at bus 42 (area-5).
%  Run BEFORE sim(). Creates PQ_data_DC42 in the base workspace.
%
%  MODEL WIRING
%    From Workspace  ->  Three-Phase Dynamic Load PQ port
%      Data                              : PQ_data_DC42
%      Sample time                       : Ts
%      Interpolate data                  : OFF
%      Form output after final data value: Holding final value

% Baseline values - must match the Dynamic Load block's Po and Qo EXACTLY
P_DC42 = 1150e6;      % 1150 MW active power
Q_DC42 =  250e6;      %  250 MVAr (inductive)

scenario_name = 'DC42 disconnection at 5 s';

% ============================================================
% SCHEDULE FOR DATA CENTER AT BUS 42
%   columns:  t_start   t_end   multiplier
% ============================================================
schedule_DC42 = [
     0     5     1.00;
     5    20     0.01;
];

% Build from the schedule
PQ_data_DC42 = build_schedule(P_DC42, Q_DC42, schedule_DC42);

% Report
fprintf('\n=== Attack schedule loaded: %s ===\n', scenario_name);
fprintf('Baseline DC42: %.0f MW  ->  Final DC42: %.1f MW   (%d steps)\n', ...
    P_DC42/1e6, PQ_data_DC42(end,2)/1e6, size(schedule_DC42,1)-1);
fprintf('Reactive     : %.0f MVAr ->  %.1f MVAr\n', ...
    Q_DC42/1e6, PQ_data_DC42(end,3)/1e6);
fprintf('Load removed : %.0f MW at t = %g s\n', ...
    (P_DC42 - PQ_data_DC42(end,2))/1e6, schedule_DC42(2,1));
fprintf('\n%8s %14s %14s\n','t (s)','P (MW)','Q (MVAr)');
for i = 1:size(PQ_data_DC42,1)
    fprintf('%8.3f %14.1f %14.1f\n', PQ_data_DC42(i,1), ...
        PQ_data_DC42(i,2)/1e6, PQ_data_DC42(i,3)/1e6);
end
fprintf('\n');

% ---------------------------------------------------------------------
% Helper: converts a segment table into the [t P Q] format that
% From Workspace expects. Two rows per segment (start and end time)
% make each segment flat; the jump between segments arises because
% consecutive segments share a time boundary with different values.
% ---------------------------------------------------------------------
function PQ = build_schedule(P0, Q0, sched)
    PQ = [];
    for k = 1:size(sched,1)
        t_start = sched(k,1);
        t_end   = sched(k,2);
        mult    = sched(k,3);
        PQ = [PQ;
              t_start  mult*P0  mult*Q0;
              t_end    mult*P0  mult*Q0];
    end
end