function basicChoiceWorldLMN(t, events, p, visStim, inputs, outputs, audio)
% basicChoiceworld(t, events, parameters, visStim, inputs, outputs, audio)
% 2017-03 - AP created
% 2018-01 - MW updated: automatic reward reduction, L-R performance
%
% Choice world that adapts with behavior
%
% Task structure: 
% Start trial
% Resetting pre-stim quiescent period
% Stimulus onset
% Fixed cue interactive delay
% Infinite time for response, fix stim azimuth on response
% Short ITI on reward, long ITI on punish, then turn stim off
% End trial


%% Fixed parameters
% ---- Parameters used for trialData init -----
% Stimulus/target
% (which contrasts to use)
contrasts = [1,0.5,0.25,0.125,0.06,0];
% (which conrasts to use at the beginning of training)
startingContrasts = [true,true,false,false,false,false];
% (which contrasts to repeat on miss)
repeatOnMiss = [true,true,false,false,false,false];
% (number of trials to judge rolling performance)
trialsToBuffer = 50;
% (number of trials after introducing 12.5% contrast to introduce 0%)
trialsToZeroContrast = 500;

% Trial choice parameters
% Staircase trial choice
% (how often staircase trials appear - every staircaseTrials trials)
staircaseTrials = p.staircaseTrials.skipRepeats; 
% (how many hits to move forward on the staircase)
staircaseHit = p.staircaseHit.skipRepeats;
% (how many misses to move backward on the staircase)
staircaseMiss = p.staircaseMiss.skipRepeats;

% Starting reward size
rewardSize = p.rewardSize.skipRepeats;
wheelGain = p.wheelGain.skipRepeats;



sigma = [p.sigma,p.sigma];
spatialFreq = p.spatialFreq;
% stimFlickerFrequency = 5; % DISABLED BELOW
startingAzimuth = p.startingAzimuth;
responseDisplacement = p.responseDisplacement;

% Timing
prestimQuiescentTime = p.prestimQuiescentTime;
cueInteractiveDelay = p.cueInteractiveDelay;
itiHit = p.itiHit;
itiMiss = p.itiMiss;

% Sounds
audioSampleRate = 44100;

onsetToneAmplitude = 0.2;
onsetToneFreq = 6000;
onsetToneDuration = 0.1;
onsetToneRampDuration = 0.01;
audioChannels = 2;
toneSamples = onsetToneAmplitude*events.expStart.map(@(x) ...
    aud.pureTone(onsetToneFreq,onsetToneDuration,audioSampleRate, ...
    onsetToneRampDuration,audioChannels));

missNoiseDuration = 0.5;
missNoiseAmplitude = 0.02;
missNoiseSamples = missNoiseAmplitude*events.expStart.map(@(x) ...
    randn(2, audioSampleRate*missNoiseDuration));

% Wheel parameters
quiescThreshold = 1;
encoderRes = 1024; % Resolution of the rotary encoder
millimetersFactor = events.newTrial.map2(31*2*pi/(encoderRes*4), @times); % convert the wheel gain to a value in mm/deg

%% Initialize trial data

trialDataInit = events.expStart.mapn( ...
    contrasts,startingContrasts,repeatOnMiss, ...
    trialsToBuffer,trialsToZeroContrast,staircaseTrials,...
    staircaseHit,staircaseMiss,rewardSize, wheelGain,...
    @initializeTrialData).subscriptable;

%% Set up wheel 

wheel = inputs.wheel.skipRepeats();

%% Trial event times
% (this is set up to be independent of trial conditon, that way the trial
% condition can be chosen in a performance-dependent manner)

% Resetting pre-stim quiescent period
prestimQuiescentPeriod = at(prestimQuiescentTime,events.newTrial.delay(0)); 
preStimQuiescence = sig.quiescenceWatch(prestimQuiescentPeriod, t, wheel, quiescThreshold); 

% Stimulus onset
%stimOn = sig.quiescenceWatch(preStimQuiescPeriod, t, wheel, quiescThreshold); 
stimOn = at(true,preStimQuiescence); 

% Fixed cue interactive delay
interactiveOn = stimOn.delay(cueInteractiveDelay); 

% Play tone at interactive onset
audio.onsetTone = toneSamples.at(interactiveOn);

% Response
% (wheel displacement zeroed at interactiveOn)
stimDisplacement = wheelGain*millimetersFactor*(wheel - wheel.at(interactiveOn));

threshold = interactiveOn.setTrigger(abs(stimDisplacement) ...
    >= responseDisplacement);
response = at(-sign(stimDisplacement), threshold);

% A rolling buffer of trial response times
dt = t.scan(@(a,b)diff([a,b]),0).at(response);
avgResponseTime = dt.bufferUpTo(100).map(@median);

%% Update performance at response

responseData = vertcat(stimDisplacement, avgResponseTime, events.trialNum);
% Update performance
trialData = responseData.at(response).scan(@updateTrialData,trialDataInit).subscriptable;
% stimDisplacement = stimDisplacement*trialData.wheelGain;
% Set trial contrast (chosen when updating performance)
trialContrast = trialData.trialContrast;

%% Give feedback and end trial

% Give reward on hit
% NOTE: there is a 10ms delay for water output, because otherwise water and
% stim output compete and stim is delayed
water = at(trialDataInit.rewardSize,trialData.hit.delay(0.01));  
outputs.reward = water;

% Play noise on miss
audio.missNoise = missNoiseSamples.at(trialData.miss.delay(0.01));

% ITI defined by outcome
iti = iff(trialData.hit==1, itiHit, itiMiss);
% iti = iff(eq(trialData.miss, true), abs(response)*itiHit, abs(response)*itiMiss).at(response);

% Stim stays on until the end of the ITI
stimOff = threshold.delay(iti);

%% Visual stimulus

% Azimuth control
% 1) stim fixed in place until interactive on
% 2) wheel-conditional during interactive  
% 3) fixed at response displacement azimuth after response
azimuth = cond( ...
    events.newTrial.to(interactiveOn), startingAzimuth*trialData.trialSide, ...
    interactiveOn.to(response), startingAzimuth*trialData.trialSide + stimDisplacement, ...
    response.to(events.newTrial), ...
    startingAzimuth*trialData.trialSide.at(interactiveOn) + sign(stimDisplacement.at(response))*responseDisplacement);

% Stim flicker
% stimFlicker = sin((t - t.at(stimOn))*stimFlickerFrequency*2*pi) > 0;

stim = vis.grating(t, 'square', 'gaussian');
stim.sigma = sigma;
stim.spatialFreq = spatialFreq;
stim.phase = 2*pi*events.newTrial.map(@(v)rand);
stim.azimuth = azimuth;
%stim.contrast = trialContrast.at(stimOn)*stimFlicker;
stim.contrast = trialContrast.at(events.newTrial);
stim.show = stimOn.to(stimOff);

visStim.stim = stim;

%% Display and save

% Wheel and stim
events.azimuth = azimuth;

% Trial times
events.stimOn = stimOn;
events.stimOff = stimOff;
events.interactiveOn = interactiveOn;
events.response = response;
events.endTrial = at(~trialData.repeatTrial, stimOff);

% Performance
events.contrasts = trialData.contrasts;
events.repeatOnMiss = trialData.repeatOnMiss;
events.trialContrast = trialData.trialContrast;
events.trialSide = trialData.trialSide;
events.hit = trialData.hit.at(response);
events.staircase = trialData.staircase;
events.useContrasts = trialData.useContrasts;
events.trialsToZeroContrast = trialData.trialsToZeroContrast;
events.hitBuffer = trialData.hitBuffer;
events.sessionPerformance = trialData.sessionPerformance;
events.totalWater = water.scan(@plus, 0).map(fun.partial(@sprintf, '%.1f�l'));

% Default parameters
try
% Trial choice parameters
% Staircase trial choice
% (how often staircase trials appear - every staircaseTrials trials)
p.staircaseTrials = 2; 
% (how many hits to move forward on the staircase)
p.staircaseHit = 3;
% (how many misses to move backward on the staircase)
p.staircaseMiss = 1;

% Stimulus/target
% (which contrasts to use)
p.contrasts = [1,0.5,0.25,0.125,0.06,0];
% (which conrasts to use at the beginning of training)
p.startingContrasts = [true,true,false,false,false,false];
% (which contrasts to repeat on miss)
p.repeatOnMiss = [true,true,false,false,false,false];
% (number of trials to judge rolling performance)
p.trialsToBuffer = 50;
% (number of trials after introducing 12.5% contrast to introduce 0%)
p.trialsToZeroContrast = 500;
p.sigma = 7;
p.spatialFreq = 1/15;
% stimFlickerFrequency = 5; % DISABLED BELOW
p.startingAzimuth = 35;
p.responseDisplacement = 35;
% Starting reward size
p.rewardSize = 2;


% Timing
p.prestimQuiescentTime = 3;
p.cueInteractiveDelay = 0.5;
p.itiHit = 1;
p.itiMiss = 2;

% Sounds
p.onsetToneAmplitude = 0.2;
p.onsetToneFreq = 6000;
p.onsetToneDuration = 0.1;
p.onsetToneRampDuration = 0.01;
p.missNoiseDuration = 0.5;
p.missNoiseAmplitude = 0.02;


% Wheel parameters
p.quiescThreshold = 1;
p.wheelGain = 5;
catch
end
end

function trialDataInit = initializeTrialData(expRef, ...
    contrasts,startingContrasts,repeatOnMiss,trialsToBuffer, ...
    trialsToZeroContrast,staircaseTrials,staircaseHit,...
    staircaseMiss,rewardSize,wheelGain)

%%%% Get the subject
% (from events.expStart - derive subject from expRef)
subject = dat.parseExpRef(expRef);

%%%% Initialize all of the session-independent performance values
trialDataInit = struct;

% Store the contrasts which are used
trialDataInit.contrasts = contrasts;
% Store which trials are repeated on miss
trialDataInit.repeatOnMiss = repeatOnMiss;
% Set the first contrast to 1
trialDataInit.trialContrast = 1;
% Set the first trial side randomly
trialDataInit.trialSide = randsample([-1,1],1);
% Set up the flag for repeating incorrect
trialDataInit.repeatTrial = false;
% Initialize hit/miss
trialDataInit.hit = false;
trialDataInit.miss = false;
% Initialize the staircase: 
% [current contrast, hits, misses, staircase trial counter, 
% staircase every n trials, hit requirement, miss requirement]
trialDataInit.staircase = ...
    [contrasts(1),0,0,0, ...
    staircaseTrials,staircaseHit,staircaseMiss];
trialDataInit.staircase(2,:) = trialDataInit.staircase; % Two rows, one for each side
% Initialize the day's performance to plot
% [conditions, number of trials, number of move left choices]
trialDataInit.sessionPerformance = ...
    [sort(unique([-contrasts,contrasts])); ...
    zeros(size(unique([-contrasts,contrasts]))); ...
    zeros(size(unique([-contrasts,contrasts])))];

%%%% Load the last experiment for the subject if it exists
% (note: MC creates folder on initilization, so start search at 1-back)
expRef = dat.listExps(subject);
useOldParams = false;
expRef = [];
if length(expRef) > 1
    % Loop through blocks from latest to oldest, if any have the relevant
    % parameters then carry them over
    for check_expt = length(expRef)-1:-1:1
        previousBlockFilename = dat.expFilePath(expRef{check_expt}, 'block', 'master');
        if exist(previousBlockFilename,'file')
            previousBlock = load(previousBlockFilename);
            if ~isfield(previousBlock.block, 'outputs')||isempty(previousBlock.block.outputs.rewardValues)
                lastRewardSize = rewardSize;
            else
                lastRewardSize = previousBlock.block.outputs.rewardValues(end);
            end
            
            if isfield(previousBlock.block,'events')
                previousBlock = previousBlock.block.events;
            else
                previousBlock = [];
            end
        end
        % Check if the relevant fields exist
        if exist('previousBlock','var') && all(isfield(previousBlock, ...
                {'useContrastsValues','hitBufferValues','trialsToZeroContrastValues'})) &&...
                length(previousBlock.newTrialValues) > 5 
            % Break the loop and use these parameters
            useOldParams = true;
            break
        end       
    end        
end

if useOldParams
    % If the last experiment file has the relevant fields, set up performance
    
    % Which contrasts are currently in use
    trialDataInit.useContrasts = previousBlock.useContrastsValues(end-length(contrasts)+1:end);
    
    % The buffer to judge recent performance for adding contrasts
    trialDataInit.hitBuffer = ...
        previousBlock.hitBufferValues(:,end-length(contrasts)+1:end,:);
    
    % The countdown to adding 0% contrast
    trialDataInit.trialsToZeroContrast = previousBlock.trialsToZeroContrastValues(end);
    
    % If the subject did over 200 trials last session, reduce the reward by
    % 0.1, unless it is 2ml
    if length(previousBlock.newTrialValues) > 200 && lastRewardSize > 2
        trialDataInit.rewardSize = lastRewardSize-0.1;
    else
        trialDataInit.rewardSize = lastRewardSize;
    end
    
    % What wheel gain should we use?
%     trialDataInit.wheelGain = previousBlock.wheelGainValues(end);
    
else
    % If this animal has no previous experiments, initialize performance
    trialDataInit.useContrasts = startingContrasts;
    trialDataInit.hitBuffer = nan(trialsToBuffer, length(contrasts), 2); % two tables, one for each side
    trialDataInit.trialsToZeroContrast = trialsToZeroContrast;  
    % Initialize water reward size & wheel gain
    trialDataInit.rewardSize = rewardSize;
    trialDataInit.wheelGain = wheelGain;
end
end

function trialData = updateTrialData(trialData,responseData)
% Update the performance and pick the next contrast

stimDisplacement = responseData(1);
avgResponseTime = responseData(2);
trialNum = responseData(3);

if trialNum > 50 && avgResponseTime < 60
    trialData.wheelGain = 3;
end

%%%% Get index of current trial contrast
currentContrastIdx = trialData.trialContrast == trialData.contrasts;

%%%% Define response type based on trial condition
trialData.hit = stimDisplacement*trialData.trialSide < 0;
trialData.miss = stimDisplacement*trialData.trialSide > 0;

% Index for whether contrast was on the left or the right as performance is
% calculated for both sides.  If the contrast was on the left, the index is
% 1, otherwise 2
trialSideIdx = iff(trialData.trialSide<0, 1, 2); 
    

%%%% Update buffers and counters if not a repeat trial
if ~trialData.repeatTrial
    
    %%%% Contrast-adding performance buffer
    % Update hit buffer for running performance
    trialData.hitBuffer(:,currentContrastIdx,trialSideIdx) = ...
        [trialData.hit;trialData.hitBuffer(1:end-1,currentContrastIdx,trialSideIdx)];
    
    %%%% Staircase
    % Update staircase trial counter
    trialData.staircase(trialSideIdx,4) = trialData.staircase(trialSideIdx,4) + 1;
    if trialData.staircase(trialSideIdx,4) >= trialData.staircase(trialSideIdx,5)
        trialData.staircase(trialSideIdx,4) = 0;
    end
    
    % Update hit/miss counter
    trialData.staircase(trialSideIdx,2) = trialData.staircase(trialSideIdx,2) + trialData.hit;
    trialData.staircase(trialSideIdx,3) = trialData.staircase(trialSideIdx,3) + trialData.miss;
        
    % Move staircase on hit/miss counter threshold 
    if all(trialData.staircase(:,2) >= trialData.staircase(:,6))
        % On hit threshold, move the staircase forward and reset hit/miss
        newStaircaseContrast = trialData.contrasts(...
            min(find(trialData.staircase(1,1) == trialData.contrasts)+1, ...
            sum(trialData.useContrasts)));
        trialData.staircase(:,1) = newStaircaseContrast;
        trialData.staircase(:,2:3) = 0;
    elseif any(trialData.staircase(:,3) >= trialData.staircase(:,7))
        % On miss threshold, move staircase backward and reset hit/miss
        newStaircaseContrast = trialData.contrasts(...
            max(find(trialData.staircase(1,1) == trialData.contrasts)-1,1));
        trialData.staircase(:,1) = newStaircaseContrast;
        trialData.staircase(:,2:3) = 0;
    end
    
    %%% Session performance for plotting
    currCondition = trialData.trialContrast*trialData.trialSide;
    currConditionIdx = trialData.sessionPerformance(1,:) == currCondition;
    disp('Before update:')
    disp(trialData.sessionPerformance)
    trialData.sessionPerformance(2,currConditionIdx) = ...
        trialData.sessionPerformance(2,currConditionIdx) + 1;
    trialData.sessionPerformance(3,currConditionIdx) = ...
        trialData.sessionPerformance(3,currConditionIdx) + (stimDisplacement < 0);
    disp('After update:')
    disp(trialData.sessionPerformance)
end

%%%% Add new contrasts as necessary given performance
% This is based on the last trialsToBuffer trials for rolling performance
% (these parameters are hard-coded because too specific)
% (these are side-dependent)
current_min_contrast = min(trialData.contrasts(trialData.useContrasts & trialData.contrasts ~= 0));
trialsToBuffer = size(trialData.hitBuffer,1);
switch current_min_contrast
    
    case 0.5
        % Lower from 0.5 contrast after > 70% correct
        min_hit_percentage = 0.70;
        
        contrast_buffer_idx = ismember(trialData.contrasts,[0.5,1]);
        contrast_total_trials = sum(~isnan(trialData.hitBuffer(:,contrast_buffer_idx,:)));
        % If there have been enough buffer trials, check performance
        if sum(contrast_total_trials) >= size(trialData.hitBuffer,1)
            % Sample as evenly as possible across pooled contrasts.  Here
            % we pool the columns representing the 50% and 100% contrasts
            % for each side (dim 3) individually, then shift the dimentions
            % so that pooled_hits(1,:) = all 50% and 100% trials on the
            % left, and pooled_hits(2,:) = all 50% and 100% trials on the
            % right.
            pooled_hits = shiftdim(...
                reshape(trialData.hitBuffer(:,contrast_buffer_idx,:),[],1,2), 2);
            use_hits(1) = sum(pooled_hits(1,(find(~isnan(pooled_hits(1,:)),trialsToBuffer/2))));
            use_hits(2) = sum(pooled_hits(2,(find(~isnan(pooled_hits(2,:)),trialsToBuffer/2))));
            min_hits = find(1 - binocdf(1:trialsToBuffer/2,trialsToBuffer/2,min_hit_percentage) < 0.05,1);
            if all(use_hits >= min_hits)
                trialData.useContrasts(find(~trialData.useContrasts,1)) = true;
            end
        end

    case 0.25
        % Lower from 0.25 contrast after > 50% correct
        min_hit_percentage = 0.5;
        
        contrast_buffer_idx = ismember(trialData.contrasts,current_min_contrast);
        contrast_total_trials = sum(~isnan(trialData.hitBuffer(:,contrast_buffer_idx,:)));
        % If there have been enough buffer trials, check performance
        if sum(contrast_total_trials) >= size(trialData.hitBuffer,1)
            % Sample as evenly as possible across pooled contrasts
            pooled_hits = shiftdim(...
                reshape(trialData.hitBuffer(:,contrast_buffer_idx,:),[],1,2), 2);
            use_hits(1) = sum(pooled_hits(1,(find(~isnan(pooled_hits(1,:)),trialsToBuffer/2))));
            use_hits(2) = sum(pooled_hits(2,(find(~isnan(pooled_hits(2,:)),trialsToBuffer/2))));
            min_hits = find(1 - binocdf(1:trialsToBuffer/2,trialsToBuffer/2,min_hit_percentage) < 0.05,1);
            if all(use_hits >= min_hits)
                trialData.useContrasts(find(~trialData.useContrasts,1)) = true;
            end
        end
        
    case 0.125
        % Lower from 0.25 contrast after > 50% correct
        min_hit_percentage = 0.5;
        
        contrast_buffer_idx = ismember(trialData.contrasts,current_min_contrast);
        contrast_total_trials = sum(~isnan(trialData.hitBuffer(:,contrast_buffer_idx,:)));
        % If there have been enough buffer trials, check performance
        if sum(contrast_total_trials) >= size(trialData.hitBuffer,1)
            % Sample as evenly as possible across pooled contrasts
            pooled_hits = shiftdim(...
                reshape(trialData.hitBuffer(:,contrast_buffer_idx,:),[],1,2), 2);
            use_hits(1) = sum(pooled_hits(1,(find(~isnan(pooled_hits(1,:)),trialsToBuffer/2))));
            use_hits(2) = sum(pooled_hits(2,(find(~isnan(pooled_hits(2,:)),trialsToBuffer/2))));
            min_hits = find(1 - binocdf(1:trialsToBuffer/2,trialsToBuffer/2,min_hit_percentage) < 0.05,1);
            if all(use_hits >= min_hits)
                trialData.useContrasts(find(~trialData.useContrasts,1)) = true;
            end
        end          
        
end

% Add 0 contrast after trialsToZeroContrast trials with 0.125 contrast
if min(trialData.contrasts(trialData.useContrasts)) <= 0.125 && ...
        trialData.trialsToZeroContrast > 0
    % Subtract one from the countdown
    trialData.trialsToZeroContrast = trialData.trialsToZeroContrast-1;
    % If at zero, add 0 contrast
    if trialData.trialsToZeroContrast == 0
        trialData.useContrasts(trialData.contrasts == 0) = true;
    end    
end

%%%% Set flag to repeat - skip trial choice if so
if trialData.miss && ...
        ismember(trialData.trialContrast,trialData.contrasts(trialData.repeatOnMiss))
    trialData.repeatTrial = true;
    return
else
    trialData.repeatTrial = false;
end

%%%% Pick next contrast

% Define whether this is a staircase trial
staircaseTrial = trialData.staircase(trialSideIdx,4) == 0;

if ~staircaseTrial
    % Next contrast is random from current contrast set
    trialData.trialContrast = randsample(trialData.contrasts(trialData.useContrasts),1);    
elseif staircaseTrial  
    % Next contrast is defined by the staircase
    trialData.trialContrast = trialData.staircase(trialSideIdx,1);    
end

%%%% Pick next side (this is done at random)
trialData.trialSide = randsample([-1,1],1);

end