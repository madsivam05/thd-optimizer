% collect_thd_data.m
% Sweeps m, mf, R (1 to 100 ohm) and L (1 to 100 mH).
% Skips combinations with L/R above 20 ms (too slow to settle).
% Saves thd_simulation_data.csv and thd_lookup.csv.
clear; clc;

mdl   = 'EV_ML_THD_SPWM';
Vdc   = 200;
f0    = 50;
Tstop = 0.3;                        % steady-state window = last 5 cycles (0.2 to 0.3 s)

load_system(mdl);

m_list  = 0.4:0.1:1.0;
mf_list = 51:50:201;
R_list  = [1 2 5 10 20 50 100];     % ohm
L_list  = [1 2 5 10 20 50 100];     % mH

pairs = [];
for R = R_list
    for L = L_list
        if (L/1000)/R <= 0.02
            pairs(end+1, :) = [R L]; %#ok<SAGROW>
        end
    end
end
nPairs = size(pairs, 1);
total  = nPairs * numel(m_list) * numel(mf_list);
fprintf('Load combinations: %d, total runs: %d\n', nPairs, total);

rows = zeros(total, 9);
k = 0;
tic;
for mf = mf_list
    fsw = mf * f0;
    Ts  = 1 / (fsw * 200);
    set_param([mdl '/Carrier'], 'rep_seq_t', sprintf('[0 0.5 1]/%g', fsw));
    set_param(mdl, 'FixedStep', num2str(Ts), 'StopTime', num2str(Tstop));
    set_param([mdl '/Vdc_Gain'], 'Gain', num2str(Vdc));

    for p = 1:nPairs
        R = pairs(p, 1);
        L = pairs(p, 2);
        set_param([mdl '/Load_RL'], 'Denominator', sprintf('[%g %g]', L/1000, R));

        for m = m_list
            k = k + 1;
            set_param([mdl '/Reference'], 'Amplitude', num2str(m));

            simOut = sim(mdl, 'ReturnWorkspaceOutputs', 'on');
            [thdV, V1] = compute_thd(simOut.vout, Ts, f0);
            [thdI, ~]  = compute_thd(simOut.iout, Ts, f0);

            rows(k, :) = [m, mf, fsw, Vdc, R, L, V1, thdV, thdI];
            fprintf('[%5d/%d] m=%.1f mf=%3d R=%3d L=%3dmH V1=%6.1f THD_I=%7.4f%%\n', ...
                    k, total, m, mf, R, L, V1, thdI);
        end
    end
end
fprintf('Finished %d runs in %.1f min\n', total, toc/60);

T = array2table(rows, 'VariableNames', ...
    {'m', 'mf', 'switching_freq_Hz', 'Vdc_V', 'R_ohm', 'L_mH', ...
     'fund_V', 'THD_V', 'THD_I'});
writetable(T, 'thd_simulation_data.csv');
writetable(T(:, {'m', 'mf', 'R_ohm', 'L_mH', 'THD_I'}), 'thd_lookup.csv');
disp('Saved thd_simulation_data.csv and thd_lookup.csv');

% ---------- Local function: THD over the last 5 fundamental cycles ----------
function [thd, V1] = compute_thd(sig, Ts, f0)
    v = sig.signals.values;
    N = round((5 / f0) / Ts);
    v = v(end - N + 1:end);
    Vf = abs(fft(v)) / N * 2;
    V1 = Vf(6);
    hsq = 0;
    for h = 2:50
        hsq = hsq + Vf(5*h + 1)^2;
    end
    thd = 100 * sqrt(hsq) / V1;
end