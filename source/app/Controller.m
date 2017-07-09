classdef Controller < handle
%CONTROLLER - initialize app (model - Simulation.m, view - View.m)
% Instance of Controller.m
% |___ model		-> Instance of Simulation.m
% |   |___ b		-> Instance of Building.m
% |     |___ l      -> Instance of Lift.m
% |   |___ h		-> Instance of Human.m
% |   |___ ss       -> Instance of StateSpace.m
% |___ view         -> Instance of View.m
% and runs it via run() method
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Up&Down
% Author - Michal Semelka, <m.semelka@gmail.com>, 2017
% https://github.com/michalsemelka/UpEtDown
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    properties (Access = private)
        model;                  % instance of Simulation.m
        view;                   % instance of View.m
        
        isModelForSim = true;
               
        loop;                   
        
        % listeners
        e_endOfSim;
        e_humansLeftChanged;
        e_humansFinished;
    end
    
    methods
        
        function [this] = Controller(s)
            this.model = s;
            this.view = View(this.model);
            
            if (size(this.model.humansList,2) == 1 && this.model.humansList == -42)
               % model is not fully set, simulation is not possible
               this.isModelForSim = false;
            end
            
            this.loop = true;
            
            this.e_endOfSim = addlistener(this.model,'finished',@this.endOfSim);
            this.e_humansLeftChanged = addlistener(this.model,'humansLeft','PostSet',@this.updateProgressBar);
            this.e_humansFinished = addlistener(this.model,'humanFinished',@this.updateFinished);
        end
        
        function run(this)
            if (this.isModelForSim)
                
                % create visualization window
                this.view.createGUIWindow(true);
                
                while (this.loop)
                    % while there are some humans unfinished
                    
                    tic;
                    this.model.setTimeStamp();              % increase simulation step value
                    this.model.moveLifts();                 % move all lifts
                    this.model.checkHumansWaiting();        % simulate all waiting Humans
                    this.model.checkForNewHumanBatch();     % create instances of new Humans
                    this.model.selectLiftsNextFloor();      % handle calls for lifts
                    
                    % wait 0.1s before refreshing visualization
                    while (toc < 0.1)
                        pause(0.0001);
                    end
                    
                    this.view.showHumansWaitingInGUI();     % refresh Humans count in visualization
                    this.view.moveLiftsInGUI();             % move lifts in visualization
                    
                end
                
                % create report after end of simulation
                this.view.showFinalStats();
                
            else
                msgbox('Instance was created only for visualization, simulation is not possible!');
            end
        end
        
        function showGUIWindow(this)
            
            this.view.createGUIWindow(false);
            
        end
        
        function avg = getLiftsPerFloorAverage(this)
            
            avg = this.view.getLiftsPerFloorAverage();
            
        end
        
        function error = checkAllFloorsCovered(this)
            
            error = this.model.checkAllFloorsCovered();
            
        end
        
    end
    
    methods (Access = private)
        
        function endOfSim(this, src, evtdata)
            this.loop = false;
        end
        
        function updateProgressBar(this, src, evtdata)
            % every time new Human is in final floor, refresh progress bar
            % value
            this.view.updateProgressBar();
        end
        
        function updateFinished(this, src, evtdata)
            % every time new Human is in final floor, increase number of humans
            % finished for the corresponding floor
            this.view.showHumansFinishedInGUI(evtdata.newData)
        end
        
    end
    
end

