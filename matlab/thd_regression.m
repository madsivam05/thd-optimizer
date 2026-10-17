% thd_regression.m
% Predicts current THD (THD_I) from modulation index, carrier ratio,
% load resistance and load inductance.
% Input : thd_simulation_data.csv (252 runs from collect_thd_data.m)
% Output: thd_best_model.mat, thd_model_comparison.csv, thd_optimization_results.csv
clear; clc; close all;

%% 1. Load data
T = readtable('thd_simulation_data.csv');
T = rmmissing(T(:, {'m', 'mf', 'R_ohm', 'L_mH', 'THD_I'}));
fprintf('Rows loaded: %d\n', height(T));

%% 2. Split: train on R = 5 and 10 ohm, test on unseen R = 20 ohm
trainT = T(T.R_ohm <= 10, :);
testT  = T(T.R_ohm == 20, :);
fprintf('Train rows: %d (R = 5 and 10 ohm)\n', height(trainT));
fprintf('Test rows : %d (R = 20 ohm, unseen load)\n', height(testT));

features = {'m', 'mf', 'R_ohm', 'L_mH'};
Xtrain = trainT{:, features};  yTrain = trainT.THD_I;
Xtest  = testT{:, features};   yTest  = testT.THD_I;

%% 3. Candidate models
% 'interactions' = linear terms plus pairwise products, no squared terms.
% Squared terms are avoided because R has only two levels in training.
modelNames = {'Linear Regression', 'Interaction Regression', ...
              'Random Forest', 'Gradient Boosting'};
fitters = {
    @(X,y) fitlm(X, y)
    @(X,y) fitlm(X, y, 'interactions')
    @(X,y) fitrensemble(X, y, 'Method', 'Bag',    'NumLearningCycles', 200)
    @(X,y) fitrensemble(X, y, 'Method', 'LSBoost', 'NumLearningCycles', 200, 'LearnRate', 0.1)
};
nM = numel(modelNames);

%% 4. Leave-one-carrier-out CV on training data, then test on unseen load
cvp = cvpartition(trainT.mf, 'LeaveOut');
cvRMSE   = zeros(nM, 1);
testRMSE = zeros(nM, 1);
testMAE  = zeros(nM, 1);
testR2   = zeros(nM, 1);
models   = cell(nM, 1);

for j = 1:nM
    errs = zeros(cvp.NumTestSets, 1);
    for k = 1:cvp.NumTestSets
        tr = training(cvp, k);
        te = test(cvp, k);
        mdlK = fitters{j}(Xtrain(tr,:), yTrain(tr));
        pK   = predict(mdlK, Xtrain(te,:));
        errs(k) = mean((yTrain(te) - pK).^2);
    end
    cvRMSE(j) = sqrt(mean(errs));

    models{j} = fitters{j}(Xtrain, yTrain);
    pred = predict(models{j}, Xtest);
    err  = yTest - pred;
    testRMSE(j) = sqrt(mean(err.^2));
    testMAE(j)  = mean(abs(err));
    testR2(j)   = 1 - sum(err.^2) / sum((yTest - mean(yTest)).^2);
end

results = table(modelNames', cvRMSE, testMAE, testRMSE, testR2, ...
    'VariableNames', {'Model', 'CV_RMSE_train', 'Test_MAE', 'Test_RMSE', 'Test_R2'});
results = sortrows(results, 'CV_RMSE_train');
disp(results);
writetable(results, 'thd_model_comparison.csv');

%% 5. Choose best model by CV (not by test score)
[~, order] = sort(cvRMSE);
bestIdx  = order(1);
bestName = modelNames{bestIdx};
best     = models{bestIdx};
fprintf('\nBest model (by CV RMSE): %s\n', bestName);

%% 6. Diagnostic: predicted vs simulated on the unseen load
pred = predict(best, Xtest);
figure;
scatter(yTest, pred, 30, 'filled', 'MarkerFaceAlpha', 0.6); hold on;
lims = [min([yTest; pred]), max([yTest; pred])];
plot(lims, lims, 'r--', 'LineWidth', 1.2);
xlabel('Simulated THD_I (%)'); ylabel('Predicted THD_I (%)');
title([bestName ': unseen load R = 20 ohm']);
legend('Test points', 'Perfect prediction', 'Location', 'best'); grid on;

%% 7. Optimize carrier ratio over simulated values (mf 51 to 201)
LAMBDA  = 0.0001;                 % switching penalty; THD_I values are small
MF_GRID = [51; 101; 151; 201];    % the simulated carrier ratios
Rdemo   = 10;                     % load used for the demonstration (ohm)
Ldemo   = 10;                     % load used for the demonstration (mH)
mList   = [0.6 0.7 0.8 0.9];

rowsOut = zeros(numel(mList), 9);
for i = 1:numel(mList)
    m = mList(i);
    Xg = [repmat(m, 4, 1), MF_GRID, repmat(Rdemo, 4, 1), repmat(Ldemo, 4, 1)];
    pg = predict(best, Xg);
    [~, idx] = min(pg + LAMBDA * MF_GRID);
    mfOpt = MF_GRID(idx);

    S = T(abs(T.m - m) < 1e-9 & T.R_ohm == Rdemo & abs(T.L_mH - Ldemo) < 1e-9, :);
    base   = S.THD_I(S.mf == 51);
    simOpt = S.THD_I(S.mf == mfOpt);
    [bestSim, bi] = min(S.THD_I);

    rowsOut(i, :) = [m, Rdemo, Ldemo, firstOrNaN(base), mfOpt, pg(idx), ...
                     firstOrNaN(simOpt), S.mf(bi), bestSim];
end
optResults = array2table(rowsOut, 'VariableNames', ...
    {'m', 'R_ohm', 'L_mH', 'THD_I_at_mf51_sim', 'optimized_mf', ...
     'predicted_THD_I', 'simulated_THD_I_at_opt', 'simulated_best_mf', 'simulated_best_THD_I'});
disp('Optimization results:');
disp(optResults);
writetable(optResults, 'thd_optimization_results.csv');

%% 8. Save the best model and its input order
save('thd_best_model.mat', 'best', 'bestName', 'features', 'MF_GRID', 'LAMBDA');
fprintf('Saved thd_best_model.mat and CSV results.\n');

%% Local helper
function v = firstOrNaN(x)
    if isempty(x), v = NaN; else, v = x(1); end
end