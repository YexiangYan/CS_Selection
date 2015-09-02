% This code is used to select conditional and unconditional ground motions.
% Conditional selection chooses structure- and site- specific
% ground motions. The target means and covariances are obtained
% corresponding to a pre-defined target scenario earthquake, and are
% obtained based on the CMS method. For unconditional selection, the target 
% means and covariances are still corresponding to a pre-defined target 
% scenario earthquake, but are not conditioned at a specified period of 
% interest. The target means and variances can be
% modified by the user. The ground motion selection algorithm used here can 
% be based on a single arbitrary ground motion component or two-component
% ground motions based on a flag set by the user. The single arbitrary 
% ground motion component is used for two-dimensional structural models and
% two-component ground motions are used for three-dimensional structural 
% models, as described in Jayaram et al. (2010). Therefore, this code may 
% be used for two-dimensional and three-dimensional structural models. 
%
% Nirmal Jayaram, Ting Lin, Jack W. Baker
% Department of Civil and Environmental Engineering
% Stanford University
% Last Updated: 7 June 2010 
% Modified 4/23/2015
% Modified 7/7/2015 (Spring & Summer 2015)
%
% Referenced manuscripts:
%
% N. Jayaram, T. Lin and and Baker, J. W. (2010). A computationally
% efficient ground-motion selection algorithm for matching a target
% response spectrum mean and variance, Earthquake Spectra, (in press).
%
% N. Jayaram and Baker, J. W. (2010). Ground-motion selection for PEER
% Transportation Systems Research Program, 7th CUEE and 5th ICEE Joint
% Conference, Tokyo, Japan.
%
% J. W. Baker and Jayaram, N. (2008). Correlation of spectral acceleration
% values from NGA ground motion models, Earthquake Spectra, 24 (1), 299-317
%
% Baker, J.W. (2010). The Conditional Mean Spectrum: A tool for ground
% motion selection, ASCE Journal of Structural Engineering, (in press).
%

%% OUTPUT VARIABLES
%
% finalRecords      : Record numbers of selected records
% finalScaleFactors : Scale factors
%
% The final cell in this m file shows how to plot the selected spectra
% using this information.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Load workspace containing ground-motion information. 
% Based on a user flag, either NGA or NGA W2 database is used. 
% Documentation of either database workspace ('rec_selection_meta_data.mat'
% or 'NGA_W2_meta_data.mat') can be found at 'WorkspaceDocumentation.m'.
% For an alternate database, the minimum information to be provided
% includes the pseudo-acceleration spectra of the available, ground
% motions, periods at which the spectra are defined, and other information
% required to compute means and variances using ground-motion models.
% This cell can be modified by the user if desired.
%
% Variable definitions for loading data:
% data      : 0 to load rec_selection_meta_data
%             1 to run NGA_W2_meta_data
% cond      : 0 to run unconditional selection
%             1 to run conditional
% arb       : 1 for single-component selection and arbitrary component sigma
%             2 for two-component selection and average component sigma
% RotD      : 50 to use SaRotD50 data
%           : 100 to use SaRotD100 data
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Certain variables are stored as parts of data structures which will later
% be incorporated in the optimization portion of the code. Required user
% input values are indicated for the user. Some of these are labelled as
% advanced user inputs and are set to default values which the user may
% choose to change. Other variables described below are calculated within
% this script or other functions. These structures are as follows:
%
% optInputs - input values needed to run the optimization function:
%            nGM        : Number of ground motions to be selected 
%            T1         : Period at which spectra should be scaled and 
%                         matched (for conditional selection only; for 
%                         unconditional selection, set T1 to 100)
%            isScaled   : Should spectra be scaled before matching (1 -YES,
%                         0-NO). 
%            maxScale   : Maximum allowable scale factor. 
%            weights    : [Weight for error in mean, Weight for error 
%                         in standard deviation] e.g., [1.0,1.0] - equal 
%                         weight for both errors.
%            nLoop      : This is a meta-variable of the algorithm. The 
%                         greedy improvement technique does several passes 
%                         over the available data set and tries to improve 
%                         the selected records. This variable denotes the 
%                         number of passes. Recommended value: 2.
%            penalty    : If a penalty needs to be applied to avoid selecting
%                         spectra that have spectral acceleration values 
%                         beyond 3 sigma at any of the periods, set a value
%                         here. Use 0 otherwise.
%            PerTgt     : Periods at which the target spectrum needs to be
%                         computed (logarithmically spaced)
%            tol        : User input percent error tolerance to determine
%                         whether or not optimization can be skipped
%            optType    : For greedy optimization, the user will input a 0
%                         to use the sum of squared errors approach to 
%                         optimize the selected spectra, or a 1 to use 
%                         D-statistic calculations
%            nBig       : The number of allowed spectra
%            recID      : This is a vector of index values for chosen
%                         spectra
% 
% Tgts      - The target values (means and covariances) being matched
%            meanReq : Estimated target response spectrum means (vector of
%                      spectral values, one at each period)
%            covReq  : Matrix of response spectrum covariances
%            means   : The meanReq vector re-formatted to be equal to
%                      exp(meanReq) in order to plot the means 
%                      properly on a log scale
%            sigs    : A vector of standard deviations at each period
% 
% IMs       - The intensity measure values (from SaKnown) chosen and the 
%             values available:
%            sampleSmall : The matrix of spectra chosen at any point; this
%                          matrix will be redefined after optimization so 
%                          that it will no longer be a part of the "IMs" 
%                          data structure
%            sampleBig   : The matrix of allowed spectra 
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Variable definitions for more user inputs: 
% SaKnown   : (N*P matrix)
%             This is a matrix of Sa values at different periods (P) for
%             available ground-motion time histories (N).
%             Usually, the structure's fundamental period.
% Tmin      : Represents the shortest period at which the target spectrum 
%             needs to be computed, where the shortest period will be
%             10^(Tmin)
% Tmax      : As above, the longest period will be 10^(Tmax)
% numPer    : Number of periods for which the target spectrum needs to be
%             computed between Tmin and Tmax
% checkCorr : If 1, this runs a code that compares the correlation
%             structure of the selected ground motions to the correlations
%             published by Baker and Jayaram (2008).
% seedValue : For repeatability. For a particular seedValue not equal to
%             zero, the code will output the same set of ground motions.
%             The set will change when the seedValue changes. If set to
%             zero, the code randomizes the algorithm and different sets of
%             ground motions (satisfying the target mean and variance) are
%             generated each time.
% showPlots : 0 to suppress plots, 1 to show plots
% outputFile: File name of the output file
% perKnown  : The set of P periods.
% allowedIndex: Only records that meet a certain criteria for Vs30,
%               magnitude, and closest distance values will be searched 
%               for the ground motion selection
%
% If a database other than the NGA database is used, also define the
% following variables:
% 
% soil_Vs30        : Soil Vs30 values corresponding to all the records
% magnitude        : Magnitude of all the records
% closest_D        : Closest distance for all the records
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% User inputs begin here
% Choose data set and type of selection the user should note that the
% original NGA database does not contain RotD100 values for two-component
% selection
data                 = 1;
optInputs.cond       = 0;
arb                  = 2; 
RotD                 = 100; 

% Choose number of ground motions and set requirements for periods
optInputs.nGM        = 20;
optInputs.T1         = 100; % for unconditional selection, T1 = 100
Tmin                 = 0.1;
Tmax                 = 10;

% Choose to show or suppress plots
showPlots            = 1;

% MORE user input in the next cell
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Determination of target mean and covariances

% The Campbell and Bozorgnia (2008) ground-motion model is used in this
% code. The input variables defined below are the inputs required for this
% model. The user can change the ground-motion model as long as any
% additional information that may be required by the new model is provided.

% Please refer to Baker (2010) for details on the conditional mean spectrum
% method which is used for obtaining the target means and covariances in
% this example. Alternately, the details are summarized in Jayaram et al.
% (2010). ***Edit: add documentation for unconditional selection***

% The code provides the user an option to not match the target variance.
% This is done by setting the target variance to zero so that each selected
% response spectrum matches the target mean response spectrum.

% Variable definitions

% M_bar     : Magnitude of the target scenario earthquake
% R_bar     : Distance corresponding to the target scenario earthquake
% eps_bar   : Epsilon value for the target scenario (for conditional
%             selection; for unconditional selection, leave as any value or
%             set equal to 0)
% Vs30      : Average shear wave velocity in the top 30m of the soil, used
%             to model local site effects (m/s)
% Ztor      : Depth to the top of coseismic rupture (km)
% delta     : Average dip of the rupture place (degree)
% lambda    : Rake angle (degree)
% Zvs       : Depth to the 2.5 km/s shear-wave velocity horizon (km)
% useVar    : 0 to set target variance to zero, 1 to compute target
%             variance using ground-motion model
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% User inputs begin here

M_bar       = 7;
R_bar       = 10; 
eps_bar     = 2; % for conditional selection
Vs30        = 400;
Ztor        = 0;
delta       = 90;
lambda      = 180;
Zvs         = 2;
useVar      = 1;

Rrup        = R_bar; % Can be modified by the user
Rjb         = R_bar; % Can be modified by the user

% User inputs end here

%% Advanced user inputs (optional) 
% The script will run with these default values, but the user has the
% option to change them.
optInputs.isScaled   = 1;
optInputs.maxScale   = 4;
optInputs.weights    = [1.0 2.0];
optInputs.nLoop      = 2;
optInputs.penalty    = 0;
checkCorr            = 1;
outputFile           = 'Output_File.dat';
optInputs.tol        = 15; 
optInputs.PerTgt     = logspace(log10(Tmin),log10(Tmax),30);
nTrials              = 20;
optInputs.optType    = 0; % 0 for SSE, 1 for KS-test
seedValue            = 1; % default will be set to 0

% PerTgt can be edited for a custom set of periods 
% Advanced user inputs end here
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Load the user-chosen database and format according to type of selection
% SaKnown can be modified as a user input
if data == 0
    load rec_selection_meta_data 
elseif data == 1
    load NGA_W2_meta_data
end

% Format appropriate variables according to single or two-component
% selection
if arb == 1
    Filename    = [Filename_1; Filename_2];
    SaKnown     = [Sa_1; Sa_2]; 
    soil_Vs30   = [soil_Vs30; soil_Vs30]; 
    magnitude   = [magnitude; magnitude]; 
    closest_D   = [closest_D; closest_D]; 
elseif arb == 2 && RotD == 50
    SaKnown     = Sa_RotD50; 
    Filename    = Filename_1;
elseif arb == 2 && RotD == 100 && data == 1 % for the NGA-W2 database only
    SaKnown     = Sa_RotD100;
    Filename    = Filename_1;
end

% Create variable for known periods
perKnown = Periods;

% More fields available in databases that can also be used in screening 
% (e.g. the ones shown below)

% mechanism = [mechanism; mechanism];
% lowest_usable_freq = [lowest_usable_freq; lowest_usable_freq];
% distance_jb = [distance_jb; distance_jb];
% distance_hyp = [distance_hyp; distance_hyp];
% distance_epi = [distance_epi; distance_epi];
% distance_campbell = [distance_campbell; distance_campbell];

%% Arrange available spectra in usable format and check for invalid values

% Modify perTgt to include T1 if running a conditional selection
if optInputs.cond == 1 && ~any(optInputs.PerTgt == optInputs.T1)
    optInputs.PerTgt = [optInputs.PerTgt(optInputs.PerTgt<optInputs.T1)...
        optInputs.T1 optInputs.PerTgt(optInputs.PerTgt>optInputs.T1)];
end

% Match periods (known periods and periods for error computations)
recPer = zeros(length(optInputs.PerTgt),1);
for i=1:length(optInputs.PerTgt)
    [~ , recPer(i)] = min(abs(perKnown - optInputs.PerTgt(i)));
end

% remove any repeated values from PerTgt (occurs with conditional
% selection)
recPer = unique(recPer);
optInputs.PerTgt = perKnown(recPer);
numPer = length(recPer);

% Screen the records to be considered
recValidSa = ~all(SaKnown == -999,2); % remove invalid inputs
recValidSoil = (soil_Vs30 > 200 | soil_Vs30 < 500); % Site condition limits 
recValidMag = magnitude > 5.5; % magnitude limits 
recValidDist = closest_D < 30; % distance limits

% only these records will be searched
allowedIndex = find(recValidSoil & recValidMag & recValidDist & recValidSa); 
nAllowed = length(allowedIndex);

% round to lowest 100 for number of records to be searched
if ~isinteger(nAllowed/100)
    allowedIndex = allowedIndex(1:100*floor(nAllowed/100));
    nAllowed = length(allowedIndex);
end

SaKnown = SaKnown(allowedIndex,:);
IMs.sampleBig = SaKnown(:,recPer);

% Processing available spectra
IMs.sampleBig = log(IMs.sampleBig);
optInputs.nBig = size(IMs.sampleBig,1);

fprintf('Number of allowed ground motions = %i \n \n', nAllowed)


%% Determine target spectra using ground-motion model 
%(replace ground-motion model code if desired)
sa = zeros(1,numPer);
sigma = zeros(1,numPer);
for i = 1:numPer
    [sa(1,i), sigma(1,i)] = CB_2008_nga (M_bar, optInputs.PerTgt(i), Rrup,...
                            Rjb, Ztor, delta, lambda, Vs30, Zvs, arb);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Estimate target means and covariances

% (Log) Response Spectrum Mean: meanReq
% for conditional selection, include epsilons
if optInputs.cond == 1 
    rho = zeros(1,numPer);  
    for i = 1:numPer
        rho(i) = baker_jayaram_correlation(optInputs.PerTgt(i), optInputs.T1);
    end
    Tgts.meanReq = log(sa) + sigma.*eps_bar.*rho;
    optInputs.lnSa1 = Tgts.meanReq(optInputs.PerTgt == optInputs.T1);
elseif optInputs.cond == 0 
    Tgts.meanReq = log(sa);
end

% (Log) Response Spectrum Covariance: covReq
Tgts.covReq = zeros(numPer);
for i=1:numPer
    for j=1:numPer
        % Periods
        Ti = optInputs.PerTgt(i);
        Tj = optInputs.PerTgt(j);

        % Means and variances
        rec1 = find(optInputs.PerTgt == Ti);
        rec2 = find(optInputs.PerTgt == Tj);
        var1 = sigma(rec1)^2;
        var2 = sigma(rec2)^2;

        if optInputs.cond == 1 % variance will be zero at specified T1
            rec = find(optInputs.PerTgt == optInputs.T1);
            varT = sigma(rec)^2;

            sigma11 = [var1 baker_jayaram_correlation(Ti, Tj)*sqrt(var1*var2);baker_jayaram_correlation(Ti, Tj)*sqrt(var1*var2) var2];
            sigma22 = varT;
            sigma12 = [baker_jayaram_correlation(Ti, optInputs.T1)*sqrt(var1*varT);baker_jayaram_correlation(optInputs.T1, Tj)*sqrt(var2*varT)];

            sigmaCond = sigma11 - sigma12*inv(sigma22)*(sigma12)';
            % Covariances
            Tgts.covReq(i,j) = sigmaCond(1,2);
        
        elseif optInputs.cond == 0 
            % Covariances
            Tgts.covReq(i,j) = baker_jayaram_correlation(Ti, Tj)*sqrt(var1*var2);            
        end
       
        if useVar == 0 % do not match the target variance
           Tgts.covReq(i,j) = 0.0;
        end

    end
end

%% Simulate response spectra using Monte Carlo Simulation/Latin Hypercube Sampling
% 20 sets of response spectra are simulated and the best set (in terms of
% matching means, variances and skewness is chosen as the seed). The script
% is set up to simulate the spectra using Latin Hypercube Sampling, but the
% user has the option to use a Monte Carlo simulation by changing "lhsnorm"
% at line 411 to "mvnrnd".The user can also optionally rerun this segment
% multiple times before deciding to proceed with the rest of the algorithm.
% It is to be noted, however, that the greedy improvement technique
% significantly improves the match between the means and the variances
% subsequently.

% Setting initial seed for simulation
if seedValue ~= 0
    rng(seedValue);
else
    rng('shuffle');
end

devTotalSim = zeros(nTrials,1);
for j=1:nTrials
    gmCell{j} = zeros(optInputs.nGM,numPer);
    gmCell{j}(:,:) = exp(lhsnorm(Tgts.meanReq,Tgts.covReq,optInputs.nGM)); % can replace 'lhsnorm' with 'mvnrnd'
    devMeanSim = mean(log(gmCell{j})) - Tgts.meanReq;
    devSkewSim = skewness(log(gmCell{j}),1);
    devSigSim = std(log(gmCell{j})) - sqrt(diag(Tgts.covReq))';
    devTotalSim(j) = optInputs.weights(1) * sum(devMeanSim.^2) + ...
                     optInputs.weights(2) * sum(devSigSim.^2)+ 0.1 * ...
                     (optInputs.weights(1)+optInputs.weights(2)) * sum(devSkewSim.^2);
end

[tmp recUse] = min(abs(devTotalSim));
gm = gmCell{recUse};

%% Find best matches to the simulated spectra from ground-motion database

% initialize vectors
optInputs.recID = zeros(optInputs.nGM,1);
IMs.sampleSmall = [];
finalScaleFac = ones(optInputs.nGM,1);

for i = 1:optInputs.nGM
    err = zeros(optInputs.nBig,1);
    scaleFac = ones(optInputs.nBig,1);
    
    for j=1:optInputs.nBig
        
        if (any(optInputs.recID == j)) % check for repeated spectra selection, set error to 1000000 if repeated, otherwise calculate error
            err(j) = 1000000;
        
        elseif optInputs.isScaled == 1
            if optInputs.cond == 1
                scaleFac(j) = exp(optInputs.lnSa1)/exp(IMs.sampleBig(j,optInputs.PerTgt == optInputs.T1));
            elseif optInputs.cond == 0
                scaleFac(j) = sum(exp(IMs.sampleBig(j,:)).*gm(i,:))/sum(exp(IMs.sampleBig(j,:)).^2);
            end  
            if (scaleFac(j) > optInputs.maxScale)
                err(j) = 1000000;
            else
                err(j) = sum((log(exp(IMs.sampleBig(j,:))*scaleFac(j)) - log(gm(i,:))).^2);
            end
        else
            err(j) = sum((IMs.sampleBig(j,:) - log(gm(i,:))).^2);
            if err(j) == inf                
               err(j) = 1000000;
            end
        end
        
      
    end
    [tmp, optInputs.recID(i)] = min(err);
    if tmp >= 1000000
       display('Warning: Possible problem with simulated spectrum. No good matches found');
       display(optInputs.recID(i));
    end
    if (optInputs.isScaled == 1)
       finalScaleFac(i) = scaleFac(optInputs.recID(i));
    else
       finalScaleFac(i) = 1;
    end
    IMs.sampleSmall = [IMs.sampleSmall;log(exp(IMs.sampleBig(optInputs.recID(i),:))*scaleFac(optInputs.recID(i)))];

end

%  display correlations before optimization 
% 
% if (checkCorr)
%     if optInputs.cond == 1
%         conditionalCovariance
%     elseif optInputs.cond == 0
%         unconditionalCovariance
%     end
% end
%% Skip greedy optimization if the user-defined tolerance for maximum 
% percent error between the target and sample means and standard deviations
% have been attained

% Format the target means and standard deviations and the means and
% standard deviations of the originally selected ground motions so that they are
% easily comparable. (stored for later comparison)
Tgts.means = exp(Tgts.meanReq);
Tgts.sigs = sqrt(diag(Tgts.covReq))';
origMeans = exp(mean(IMs.sampleSmall));
origSigs = std(IMs.sampleSmall);

% Compute maximum percent error from target
% Remove the period (index) all spectra are scaled to for conditional selection
notT1 = find(optInputs.PerTgt ~= optInputs.T1);

meanErr = max(abs(origMeans-Tgts.means)./Tgts.means)*100;
sigErr = max(abs(origSigs(notT1)-Tgts.sigs(notT1))./Tgts.sigs(notT1))*100;

% Display the original maximum error between the selected gm and the target
display(meanErr);
display(sigErr);

%% Greedy subset modification procedure
% Call the optimization function if the user defined tolerance has not been
% reached. Each nLoop, the error is recalculated and the loop will break if
% the error has been reached

if meanErr > optInputs.tol || sigErr > optInputs.tol 
    [sampleSmall, finalRecords, finalScaleFactors] = GreedyOpt(optInputs, Tgts, IMs);
%     finalRecords1 = allowedIndex(finalRecords);
    IMs.sampleSmall = sampleSmall;
    
else % otherwise, skip greedy optimization
    display('Greedy optimization was skipped based on user input tolerance.');
    finalRecords = optInputs.recID;
%     finalRecords1 = allowedIndex(optInputs.recID);
    finalScaleFactors = finalScaleFac;
end

%% Spectra Plots

    % Variables used here
    
    % SaKnown    : As before, it contains the response spectra of all the
    %              available ground motions (N*P matrix) - N ground motions,
    %              P periods
    % gm         : gm is a matrix of simulated response spectra defined
    %              only at PerTgt
    % sampleBig  : Same as SaKnown, but is only defined at PerTgt, the
    %              periods at which the target response spectrum properties
    %              are computed
    % sampleSmall: The response spectra of the selected ground motions,
    %              defined at PerTgt
    % meanReq    : Target mean for the (log) response spectrum
    % covReq     : Target covariance for the (log) response spectrum

if (showPlots)
    
    % Plot simulated response spectra -- move with the rest of the figures 
    figure
    loglog(optInputs.PerTgt, exp(Tgts.meanReq), '-r', 'linewidth', 3)
    hold on
    loglog(optInputs.PerTgt, exp(Tgts.meanReq + 1.96*sqrt(diag(Tgts.covReq))'), '--r', 'linewidth', 3)
    loglog(optInputs.PerTgt,gm,'k');
    loglog(optInputs.PerTgt, exp(Tgts.meanReq - 1.96*sqrt(diag(Tgts.covReq))'), '--r', 'linewidth', 3)
    axis([min(optInputs.PerTgt) max(optInputs.PerTgt) 1e-2 5])
    xlabel('T (s)')
    ylabel('S_a (g)')
    legend('Median response spectrum','2.5 and 97.5 percentile response spectra','Response spectra of simulated ground motions')
    title('Response spectra of simulated ground motions')
    set(findall(gcf,'-property','FontSize'),'FontSize',18)
    
    % Plot target and simulated means
    figure
    loglog(optInputs.PerTgt,exp(Tgts.meanReq))
    hold on
    loglog(optInputs.PerTgt,exp(mean(log(gm))),'--')
    axis([min(optInputs.PerTgt) max(optInputs.PerTgt) 1e-2 5])
    xlabel('T (s)')
    ylabel('Median S_a (g)')
    legend('exp(Target mean lnS_a)','exp(Mean of simulated lnS_a)')
    title('Target and simulated exponential logarithmic means (i.e., medians)')
    set(findall(gcf,'-property','FontSize'),'FontSize',18)

    % Plot target and simulated standard deviations
    figure
    semilogx(optInputs.PerTgt,sqrt(diag(Tgts.covReq))')
    hold on
    semilogx(optInputs.PerTgt,std(log(gm)),'--')
    axis([min(optInputs.PerTgt) max(optInputs.PerTgt) 0 1])
    xlabel('T (s)')
    ylabel('Standard deviation of lnS_a')
    legend('Target standard deviation of lnS_a','Standard deviation of simulated lnS_a')
    title('Target and simulated logarithmic standard deviations')
    set(findall(gcf,'-property','FontSize'),'FontSize',18)
    
    % Plot at all periods
    figure
    loglog(optInputs.PerTgt, exp(Tgts.meanReq), 'b', 'linewidth', 3)
    hold on
    loglog(optInputs.PerTgt, exp(Tgts.meanReq + 1.96*sqrt(diag(Tgts.covReq))'), '--b', 'linewidth', 3)
    loglog(perKnown,SaKnown(finalRecords,:).*repmat(finalScaleFactors,1,size(SaKnown,2)),'k');
    loglog(optInputs.PerTgt, exp(Tgts.meanReq - 1.96*sqrt(diag(Tgts.covReq))'), '--b', 'linewidth', 3)
    axis([min(optInputs.PerTgt) max(optInputs.PerTgt) 1e-2 5])
%     hx = xlabel('T (s)');
%     hy = ylabel('S_a (g)');
%     legh = legend('Median response spectrum','2.5 and 97.5 percentile response spectra','Response spectra of selected ground motions');
    title ('Response spectra of selected ground motions');
    set(findall(gcf,'-property','FontSize'),'FontSize',18)

    % Plot spectra only at periods where error is minimized
    figure
    loglog(optInputs.PerTgt, exp(Tgts.meanReq), 'b', 'linewidth', 3)
    hold on
    loglog(optInputs.PerTgt, exp(Tgts.meanReq + 1.96*sqrt(diag(Tgts.covReq))'), '--b', 'linewidth', 3)
    loglog(optInputs.PerTgt,exp(IMs.sampleBig(finalRecords,:)).*repmat(finalScaleFactors,1,numPer),'color',[0.5 0.5 0.5],'linewidth',1)
    loglog(optInputs.PerTgt, exp(Tgts.meanReq - 1.96*sqrt(diag(Tgts.covReq))'), '--b', 'linewidth', 3)
    axis([min(optInputs.PerTgt) max(optInputs.PerTgt) 1e-2 5])
%     hx = xlabel('T (s)');
%     hy = ylabel('S_a (g)');
%     legh = legend('Median response spectrum','2.5 and 97.5 percentile response spectra','Response spectra of selected ground motions');
    title ('Response spectra of selected ground motions at periods where error is minimized');
    set(findall(gcf,'-property','FontSize'),'FontSize',18)

    % Sample, original sample, and target means
    figure
    loglog(optInputs.PerTgt,Tgts.means,'k','linewidth',1)
    hold on
    loglog(optInputs.PerTgt, origMeans,'r*', 'linewidth',2)
    loglog(optInputs.PerTgt,exp(mean(IMs.sampleSmall)),'b--','linewidth',1)
    axis([min(optInputs.PerTgt) max(optInputs.PerTgt) 1e-2 5])
%     hx = xlabel('T (s)');
%     hy = ylabel('Median S_a (g)');
%     legh = legend('exp(Target mean lnS_a)','exp(Mean of originally selected lnS_a', 'exp(Mean of selected lnS_a)');
    title('Target and sample exponential logarithmic means (i.e., medians)')
    set(findall(gcf,'-property','FontSize'),'FontSize',18)
    
    % Sample, original sample, and target standard deviations
    figure
    semilogx(optInputs.PerTgt,Tgts.sigs,'k','linewidth',1)
    hold on
    semilogx(optInputs.PerTgt, origSigs,'r*','linewidth',2)
    semilogx(optInputs.PerTgt,std(IMs.sampleSmall),'b--','linewidth',1)
    axis([min(optInputs.PerTgt) max(optInputs.PerTgt) 0 1])
%     hx = xlabel('T (s)');
%     hy = ylabel('Standard deviation of lnS_a');
%     legh = legend('Target standard deviation of lnS_a','Standard deviation of originally selected lnS_a','Standard deviation of selected lnS_a');
    title('Target and sample logarithmic standard deviations')
    set(findall(gcf,'-property','FontSize'),'FontSize',18)

end

if (checkCorr)
    if optInputs.cond == 1
        conditionalCovariance
    elseif optInputs.cond == 0
        unconditionalCovariance
    end
end

%% Output data to file (best viewed with textpad)
% output http://ngawest2.berkeley.edu/ for NGA-W2 -- check that tool works
% for input record numbers 

fin = fopen(outputFile,'w');
if arb == 1
    fprintf(fin,'%s \t %s \t %s \t %s \n','Record Number','Scale Factor','File Name','URL');
elseif arb == 2
    fprintf(fin,'%s \t %s \t %s \t %s \t %s \t %s \t %s \n','Record Number','NGA Record Sequence Number','Scale Factor','File Name Dir. 1','File Name Dir. 2','URL Dir 1','URL Dir 2');
end

for i = 1 : length(finalRecords)
    rec = allowedIndex(finalRecords(i));
    if data == 0 && arb == 1
        url = ['http://peer.berkeley.edu/nga_files/ath/' Filename{rec}(1:end-3) 'AT2']; % URL of selected record
        fprintf(fin,'%d \t %6.2f \t %s \t %s \n',i,finalScaleFactors(i),Filename{rec},url); % Print relevant outputs
    elseif data == 0 && arb == 2
        url1 = ['http://peer.berkeley.edu/nga_files/ath/' Filename_1{rec}(1:end-3) 'AT2'];
        url2 = ['http://peer.berkeley.edu/nga_files/ath/' Filename_2{rec}(1:end-3) 'AT2'];
        fprintf(fin,'%d \t %d \t %6.2f \t %s \t %s \t %s \t %s \n',i,rec,finalScaleFactors(i),Filename_1{rec},Filename_2{rec},url1,url2);
    elseif data == 1 && arb == 1
        fprintf(fin,'%d , %d , %6.2f , %s , %s \n',i,rec,finalScaleFactors(i),Filename_1{rec});
    elseif data == 1 && arb == 2
        fprintf(fin,'%d , %d , %6.2f , %s , %s \n',i,rec,finalScaleFactors(i),Filename_1{rec},Filename_2{rec});
    end
end

fclose(fin);