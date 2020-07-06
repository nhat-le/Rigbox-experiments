function continuousReward(t, evts, p, vs, in, out, audio)
%% Adapted from advancedChoiceWorld
% Script for presenting rewards continuously
% Burgess 2AUFC task with contrast discrimination and baited equal contrast
% trial conditions.  
% 2017-03-25 Added contrast discrimination MW
% 2017-08    Added baited trials (thanks PZH)
% 2017-09-26 Added manual reward key presses
% 2017-10-26 p.wheelGain now in mm/deg units

rewardKey = p.rewardKey.at(evts.expStart);
rewardKeyPressed = in.keyboard.strcmp(rewardKey); % true each time the reward key is pressed

endReward = evts.newTrial.delay(p.interval); %only update when feedback changes to greater than 0, or reward key is pressed


reward = merge(rewardKeyPressed, endReward > 0);

out.reward = p.rewardSize.at(reward); % output this signal to the reward controller
evts.endTrial = reward.delay(0.1);
evts.totalReward = out.reward.scan(@plus, 0).map(fun.partial(@sprintf, '%.1fµl'));
evts.rewardKeyPressed = rewardKeyPressed;

% evts.expStop = evts.trialNum >= 10;


%% Parameter defaults
try
p.rewardSize = 3;
p.rewardKey = 'r';
p.interval = 3; %seconds
% p.numTrials = 10;

catch
end
end