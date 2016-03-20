% This code is used to select ground motions with response spectra 
% representative of a target scenario earthquake, as predicted by a ground 
% motion model. Spectra can be selected to be consistent with the full
% distribution of response spectra, or conditional on a spectral amplitude
% at a given period (i.e., using the conditional spectrum approach). 
% Single-component or two-component motions can be selected, and several
% ground motion databases are provided to search in. Further details are
% provided in the following documents:
%
%   Lee, C. and Baker, J.W. (2016). An Improved Algorithm for Selecting 
%   Ground Motions to Match a Conditional Spectrum, Earthquake Spectra, 
%   (in review).
%
% created by Nirmal Jayaram, Ting Lin and Jack Baker, Official release 7 June, 2010 
% modified by Cynthia Lee and Jack Baker, last updated, 14 March, 2016
%
%
%% OUTPUT VARIABLES
%
% finalRecords      : Record numbers of selected records
% finalScaleFactors : Corresponding scale factors
%
% (these variables are also output to a text file specified by the outputFile variable)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Variable definitions and user inputs
%
% Variable definitions for loading data:
%
% databaseFile : filename of the target database. This file should exist 
%                in the 'Databases' subfolder. Further documentation of 
%                these databases can be found at 
%                'Databases/WorkspaceDocumentation***.txt'.
% cond         : 0 to run unconditional selection
%                1 to run conditional
% arb          : 1 for single-component selection and arbitrary component sigma
%                2 for two-component selection and average component sigma
% RotD         : 50 to use SaRotD50 data
%              : 100 to use SaRotD100 data
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Certain variables are stored in data structures which are later used in
% the optimization function. Required user input values are indicated for
% the user. Some variables defined here are calculated within this script
% or other functions. The data structures are as follows:
%
% optInputs: input values needed to run the optimization function
%            isScaled   : The user will input 1 to allow records to be 
%                         scaled, and input 0 otherwise 
%            maxScale   : The maximum allowable scale factor
%            tol        : User input percent error tolerance to determine
%                         whether or not optimization can be skipped (only
%                         used for SSE optimization)
%            optType    : For greedy optimization, the user will input a 0
%                         to use the sum of squared errors approach to 
%                         optimize the selected spectra, or a 1 to use 
%                         D-statistic calculations from the KS-test
%            penalty    : If a penalty needs to be applied to avoid selecting
%                         spectra that have spectral acceleration values 
%                         beyond 3 sigma at any of the periods, set a value
%                         here. Use 0 otherwise.
%            weights    : [Weights for error in mean, standard deviation 
%                         and skewness] e.g., [1.0,2.0 0.3] 
%            nLoop      : Number of loops of optimization to perform.
%                         Default value = 2
%            nBig       : The number of spectra that will be searched
%            indT1      : This is the index of T1, the conditioning period
%            recID      : This is a vector of index values for chosen
%                         spectra
% 
% rup     :  A structure with parameters that specify the rupture scenario
%            for the purpose of evaluating a GMPE
%
% Tgts    :  The target values (means and covariances) being matched
%            meanReq    : Estimated target response spectrum means (vector of
%                         logarithmic spectral values, one at each period)
%            covReq     : Matrix of response spectrum covariances
%            stdevs     : A vector of standard deviations at each period
% 
% IMs     :  The intensity measure values (from SaKnown) chosen and the 
%            values available
%            sampleSmall: matrix of selected logarithmic response spectra 
%            sampleBig  : The matrix of logarithmic spectra that will be 
%                          searched
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% User inputs begin here
% Ground motion database and type of selection 
databaseFile         = 'NGA_W2_meta_data'; 
optInputs.cond       = 1;
arb                  = 2; 
RotD                 = 50; 

% Number of ground motions and spectral periods of interest
optInputs.nGM        = 30;      % number of ground motions to be selected 
optInputs.T1         = 0.5;     % Period at which spectra should be scaled and matched 
Tmin                 = 0.1;     % smallest spectral period of interest
Tmax                 = 10;      % largest spectral period of interest
optInputs.TgtPer     = logspace(log10(Tmin),log10(Tmax),30); % Periods at which the target spectrum needs to be computed (logarithmically spaced)

% other parameters to scale motions and evaluate selections 
optInputs.isScaled   = 1;       
optInputs.maxScale   = 4;       
optInputs.tol        = 0; 
optInputs.optType    = 1; 
optInputs.penalty    = 0;
optInputs.weights    = [1.0 2.0 0.3];
optInputs.nLoop      = 2;
useVar               = 1;   % =1 to use conditional spectrum variance, =0 to use a target variance of 0

% User inputs to specify the target earthquake rupture scenario
rup.M_bar       = 6.5;      % earthquake magnitude
rup.R_bar       = 11;       % distance corresponding to the target scenario earthquake
rup.Rjb         = R_bar;    % closest distance to surface projection of the fault rupture (km)
rup.eps_bar     = 1.9;      % epsilon value (used only for conditional selection)
                            % BackCalcEpsilon is a supplementary script that
                            % will back-calculate epsilon values based on M, R,
                            % and Sa inputs from USGS deaggregations
rup.Vs30        = 259;      % average shear wave velocity in the top 30m of the soil (m/s)
rup.z1          = 999;      % basin depth (km); depth from ground surface to the 1km/s shear-wave horizon,
                            % =999 if unknown
rup.region      = 1;        % =0 for global (incl. Taiwan)
                            % =1 for California
                            % =2 for Japan
                            % =3 for China or Turkey
                            % =4 for Italy
rup.Fault_Type  = 1;        % =0 for unspecified fault
                            % =1 for strike-slip fault
                            % =2 for normal fault
                            % =3 for reverse fault
                        
% Ground motion properties to require when selecting from the database. 
allowedVs30 = [-Inf Inf];     % upper and lower bound of allowable Vs30 values 
allowedMag  = [6.3 6.7];        % upper and lower bound of allowable magnitude values
allowedD    = [-Inf Inf];     % upper and lower bound of allowable distance values

% Miscellaneous other inputs
showPlots   = 1;        % =1 to plot results, =0 to suppress plots
seedValue   = 1;        % =0 for random seed in when simulating 
                        % response spectra for initial matching, 
                        % otherwise the specifed seedValue is used.
nTrials     = 20;       % number of iterations of the initial spectral 
                        % simulation step to perform
outputFile  = 'Output_File.dat'; % File name of the output file

% User inputs end here
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Load the specified ground motion database and screen for suitable motions
[SaKnown, optInputs, indPer, knownPer, Filename, dirLocation, getTimeSeries, allowedIndex] = screen_database(optInputs, databaseFile, arb, RotD, allowedVs30, allowedMag, allowedD );

% Process available spectra
SaKnown = SaKnown(allowedIndex,:);       % allowed spectra defined at all periods
IMs.sampleBig = log(SaKnown(:,indPer));  % logarithmic spectral accelerations at target periods
optInputs.nBig = size(IMs.sampleBig,1);  % number of allowed spectra

fprintf('Number of allowed ground motions = %i \n \n', optInputs.nBig)
assert(optInputs.nBig >= optInputs.nGM, 'Warning: there are not enough allowable ground motions');


%% Compute target means and covariances of spectral values 

% Compute the mean response spectrum and target covariance matrix at all
% available periods of the database
Tgts = get_target_spectrum(RotD, arb, knownPer, useVar, eps_bar, optInputs, indPer, rup);
                                                                           
% Define the spectral accleration at T1 that all ground motions will be scaled to
optInputs.lnSa1 = Tgts.meanReq(optInputs.indT1); 

%% Simulate response spectra matching the computed targets
simulatedSpectra = simulate_spectra( seedValue, nTrials, Tgts, optInputs );

%% Find best matches to the simulated spectra from ground-motion database
IMs = find_ground_motions( optInputs, simulatedSpectra, IMs );

% Compute means and standard deviations of the originally selected ground motions 
IMs.stageOneScaleFac =  IMs.scaleFac;
IMs.stageOneMeans = mean(log(SaKnown(IMs.recID,:).*repmat(stageOneScaleFac,1,size(SaKnown,2))));
IMs.stageOneStdevs= std(log(SaKnown(IMs.recID,:).*repmat(stageOneScaleFac,1,size(SaKnown,2))));

% Compute maximum percent error of selection relative to target means and
% standard deviations (do not compute standard deviation error at T1 for
% conditional selection)
meanErr = max(abs(exp(stageOneMeans(indPer))-exp(Tgts.meanReq))./exp(Tgts.meanReq))*100;
stdErr = max(abs(stageOneStdevs(indPer ~= indPer(optInputs.indT1))-Tgts.stdevs(1:end ~= optInputs.indT1))./Tgts.stdevs(1:end ~= optInputs.indT1))*100;

% Display the original maximum error between the selected gm and the target
fprintf('End of simulation stage \n')
fprintf('Max (across periods) error in median = %3.1f percent \n', meanErr); 
fprintf('Max (across periods) error in standard deviation = %3.1f percent \n \n', stdErr); 

%% Further optimize the ground motion selection, if desired

if meanErr > optInputs.tol || stdErr > optInputs.tol 
    IMs = optimize_ground_motions(optInputs, Tgts, IMs);  
    % IMs = optimize_ground_motions_par(optInputs, Tgts, IMs); % a version of the optimization function that uses parallel processing
else % otherwise, skip greedy optimization
    display('Greedy optimization was skipped based on user input tolerance.');
end

%% Plot results, if desired
if showPlots
    plot_results( optInputs, Tgts, IMs, simulatedSpectra, SaKnown, knownPer, knownCovReq )
end
 
%% Output results to a text file 
rec = allowedIndex(IMs.recID); % selected motions, as indixed in the original database

write_output( rec, finalScaleFac, outputFile, getTimeSeries, Filename, dirLocation)
