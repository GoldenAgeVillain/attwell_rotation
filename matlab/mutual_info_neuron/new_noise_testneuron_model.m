function [data, data_AP, APfreq, iInj_plot, iInj_plot_inhib, gTotal, wholecell_Na_current] = new_noise_testneuron_model(switchPlot,noise_scaler,gsyn_scaler);

global tstart dt DT

dt = 0.5; % ms
how_many_seconds = 10; % [seconds]
EAMPA = 0;      % mV
EL = -70;       % mV
s0 = EL;        % mV

Vthresh = -50;  % mV
Vspike = 10;    % mV
Rm = 90;        % MOhms
tauM = 30;      % ms

DT = how_many_seconds * 1000; % ms

 rng('shuffle'); % restores rand generator for random syn noise
[spiketrain, gsyn] = rand_spike_train(how_many_seconds); % 10 seconds

gsyn = gsyn*gsyn_scaler; 
gsyn= gsyn';

Excit_synapses = 160;
Inhib_synapses = 0;

[totalcond,Inhib_cond] = BackgroundNoise(Excit_synapses,Inhib_synapses);
totalcond =  totalcond(1:length(gsyn));
DT = how_many_seconds * 1000; % ms

Inhib_cond =  Inhib_cond(1:length(gsyn));

gTotal = totalcond  + gsyn;

%% calculate sodium conductance at the synapse
ENa = 90; %mV from neuron paper Harris et al. 2015
EK = -105; % mV

gNa_synapse = gsyn / (1 - (ENa/EK));
gNa_wholecell = gTotal / (1 - (ENa/EK));

options = odeset('MaxStep',dt,'RelTol',1e-03,'OutputFcn',@myfun,'Event',@myEvent);
tspan1   = 0:dt:DT;% to get full length of array
tstart  = clock;
data = zeros(size(tspan1));

%% loop setting parameters
tlast = 0; starthere = 0; AP = -1;% set to -1 because AP = AP + 1 is called when the while loop breaks naturally 

%% integrating loop
while tlast < DT    % loops until target time reached
    tspan = tlast:dt:DT;
    [time, S] = ode15s(@fxn,tspan,s0,options);% options specify pause and reset if solution > Vthresh
    data((starthere+1):(length(S)+starthere))=S;% concatenates data array over loop
    tlast =  2*dt + round((max(time)-0.24999)/0.5)*0.5;% grabs stoptime, to feed into next loop as starttime
    starthere = starthere+length(S);
    AP = AP +1;% counts spikes
end

if AP > 0
    APfreq = AP /(DT/1000);% in Hz
else
    APfreq = 0;% threshold not reached
end

%% stop event
function [value,isterminal,direction] = myEvent(~,s)
    r          = double((s) > Vthresh);
    value      = r;
    isterminal = r;
    direction  = 0;
end

%% main nested subfunction
    function ds = fxn(t,s)
        V = s(1);
        
        synapse_iNa    = -gNa_synapse(floor(t/dt)+1)*(V-ENa); % nS * mV = [pA]
        Wholecell_iNa = -gNa_wholecell(floor(t/dt)+1)*(V-ENa); % nS * mV = [pA]
                
        %% injected current Excitatory and Inhibitory
        iInj    = -gTotal(floor(t/dt)+1)*(V-EAMPA); % nS * mV = [pA]
        iInj = iInj / 1000; % [nA]
        
        Inbitory_current = Inhib_cond(floor(t/dt)+1)*(V-(-75));
        Inbitory_current = Inbitory_current / 1000; % [nA]

        iInj_plot(floor(t/dt)+1)=iInj; % creates vector for plotting current inject over time
        iInj_plot_inhib(floor(t/dt)+1)=Inbitory_current; % creates vector for plotting current inject over time
                

        Synaptic_Na_current(floor(t/dt)+1)= synapse_iNa / 1000; % nA
        wholecell_Na_current(floor(t/dt)+1)= Wholecell_iNa / 1000; % nA
              
        ds(1) = (EL - V + (Rm * (iInj-Inbitory_current)))/tauM;        % solves for V      
        ds     = ds';                               % transpose the vector of derivatives
        ds(isnan(ds)) = 0;                          % avoids NaN in the vector of derivatives
        ds(isinf(ds)) = 0;                          % avoids Inf in the vector of derivatives           
    end

%% add spikes into data
data = data'; % flip it

if length(data) > (DT/dt)+1
    data((DT/dt)+2:end)=[];
end
ind = zeros(length(data),1); % create index for threshold
ind(data >= Vthresh) = 1; 
data_AP = data;
data_AP(ind==1)= Vspike; % apply index

%% figure
if switchPlot == 1
    
    subplot(4,1,1)
    plot(spiketrain)
    title('Input stimulus')
    xlim([0 length(totalcond)])   
    ylabel('Action potential');

    subplot(4,1,2)
    plot(gTotal)
    xlim([0 length(totalcond)])
    title('total postsynaptic conductance (synaptic + noise)')
    ylabel('Conductance [nS]');
        
    subplot(4,1,3)
    plot(iInj_plot)
    xlim([0 length(totalcond)])
    title('postsynaptic current (EPSC)')
    ylabel('Current [nA]');
 
    subplot(4,1,4)   
    lblY     = {'Voltage [mV]'};
    lblX     = {'Time [ms]'};    
    plot(data_AP)     
    xlim([0 length(totalcond)])
    title('post-synaptic membrane response')

    ylabel(lblY(1));
    xlabel(lblX(1));
end

end

% subfunction for output
function status = myfun(t,s,flag)
global tstart DT;
eta = (clock-tstart)*[0 0 24*60*60 60*60 60 1]';
fprintf([...
    't = ' num2str(t,'%0.2f') ' ms || ' num2str(100*t/DT,'%0.2f')...
    '%% completed || ETA = ' num2str(eta*(DT-t)./(t*60),'%03.2f') ' min\n']);
status = 0;
end
