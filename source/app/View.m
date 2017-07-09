classdef View < handle
%LIFT - class for visualization of model, instance of View is created in
% CONTROLLER class
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Up&Down
% Author - Michal Semelka, <m.semelka@gmail.com>, 2017
% https://github.com/michalsemelka/UpEtDown
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    properties (Access = {?Simulation, ?Controller})
        model                   % Instance of Simulation.m
        
        % handles for GUI objects
        wG;
        bG;
        lG;
        liftShaftsG;
        liftShaftsDeniedG;
        liftGraphic;
        hG;
        parametersG;
        oG;
        
        humansWaitingCount;
        humansFinishedCount;
        
       
        images;                 % Structure of loaded images
    end
    
    methods (Access = {?Simulation, ?Controller})
        
        function [this] = View(model)
            this.model = model;
            
            this.wG = [];
            this.bG = [];
            this.lG = [];
            this.liftShaftsG = [];
            this.liftShaftsDeniedG = [];
            this.liftGraphic = [];
            this.hG = [];
            this.parametersG = [];
            this.oG = [];
            this.humansWaitingCount = [];
            this.humansFinishedCount = [];
            
        end
        
        %------------------------------------------------------------------
        %   GUI based
        function plan = getPlanForGUI(this)
            % Creates matrix of lifts for visualization. 
            % Lifts are added to a free column or a new one is created
            
            numOfFloors = this.model.b.getNumOfFloors();
            plan = zeros(numOfFloors,1);
            numOfLifts = this.model.b.getNumOfLifts;
            lifts = this.model.b.getLifts;
            
            for i=1:numOfLifts
                max = lifts(i).getFinalFloor;
                min = lifts(i).getBaseFloor;
                ID = lifts(i).getID;
                planSize = size(plan,2);
                
                for k=1:planSize
                    free = false;
                    if (sum(plan(min:max,k)) == 0)
                        free = true;
                    end
                    
                    if (free == true)
                        plan(min:max,k) = ID;
                        break;
                    end
                end
                if (free == false)
                    plan = [plan zeros(numOfFloors,1)];
                    plan(min:max,end) = ID;
                end
            end
            plan = flipud(plan);
        end
        
        function num = getLiftsPerFloorAverage(this)
            % return number of lifts (shafts) per floor
            
            plan = this.getPlanForGUI;
            num = [];
            
            for i=1:size(plan,1)
                tmp = plan(i,:);
                num(i) = size(tmp(tmp ~= 0),2);
            end
            
            num = mean(num);
            
        end
        
        function setGraphicsForCabin(this, width, height)
            % load and resize images for lift
            
            oneCabin = uipanel('Parent',this.bG(1)','position',[0 0 width height],'fontweight','bold','BorderType', 'none', 'Visible', 'Off');
            
            position = getpixelposition(oneCabin);
            
            if (~isdeployed)
                this.images.lift_up_f = imresize(imread('assets/g_lift_up_f.jpg'), [position(3) position(4)]);
                this.images.lift_up_e = imresize(imread('assets/g_lift_up_e.jpg'), [position(3) position(4)]);
                this.images.lift_down_f = imresize(imread('assets/g_lift_down_f.jpg'), [position(3) position(4)]);
                this.images.lift_down_e = imresize(imread('assets/g_lift_down_e.jpg'), [position(3) position(4)]);
                this.images.lift_idle = imresize(imread('assets/g_lift.jpg'), [position(3) position(4)]);
            else
                this.images.lift_up_f = imresize(imread('g_lift_up_f.jpg'), [position(3) position(4)]);
                this.images.lift_up_e = imresize(imread('g_lift_up_e.jpg'), [position(3) position(4)]);
                this.images.lift_down_f = imresize(imread('g_lift_down_f.jpg'), [position(3) position(4)]);
                this.images.lift_down_e = imresize(imread('g_lift_down_e.jpg'), [position(3) position(4)]);
                this.images.lift_idle = imresize(imread('g_lift.jpg'), [position(3) position(4)]);
            end
            
                
        end

        function createGUIWindow(this, forSimulation)
            % Create main window for visualization
            % forSimulation = true when creating window for simulation (with
            % lift car, progress bar, ...).

            % resolution calculation
            resolution = get(0,'screensize');
            
            correction = 0;
            correction30 = 0;
            if (resolution(4) < 800)
                correction = 50;
                correction30 = 30;
            end
            
            positionx = (resolution(3) - 1000)/2;
            positiony = (resolution(4) - 700-correction)/2;
            
            % window
            this.wG = figure('units','pixels',...
                'position',[positionx-25 positiony+correction30 300 700-correction],...
                'color',[0.6 0.6 0.6],...
                'menubar','none',...
                'numbertitle','off',...
                'name','Up&Down - Model visualization',...
                'resize','off');
            % building panel
            this.bG = uipanel('Parent',this.wG',...
                'units','pixels',...
                'FontSize',12,...
                'BackgroundColor',[1 1 1],...
                'Position',[25 25 250 650-correction],...
                'BorderType', 'none');
            % axes for lines
            this.bG(2) = axes('Parent',this.bG',...
                'FontSize',12,...
                'Position',[0 0 1 1],...
                'xtick',[],'ytick',[],...
                'xcolor','w','ycolor','w',...
                'Color', 'none',...
                'box', 'off');
            
            
                uicontrol('Parent',this.wG','style','text','units','pixels','position',[0 675 300 20],'backgroundcolor',[0.6 0.6 0.6],'fontweight','bold','FontSize',12, 'String', 'Building');
                if (forSimulation)
                    set(this.wG, 'name', 'Up&Down - Simulation ongoing ...');
                end
            
            % Some calc
            plan = flipud(this.getPlanForGUI());
            numOfRows = size(plan,2);
            numOfFloors = this.model.b.getNumOfFloors();
            numOfLifts = this.model.b.getNumOfLifts;
            lifts = this.model.b.getLifts;
            
            border = 0.15;
            spaceBetween = 0.01;
            totalSpaceBetween = (numOfRows - 1) * spaceBetween;
            spaceForLift = 1 - (border*2) - totalSpaceBetween;
            
            oneLiftWidth = spaceForLift/numOfRows;
            oneFloorHeight = 1/numOfFloors;
            
            if (forSimulation)
                % resize lift images based on actual size
                this.setGraphicsForCabin(oneLiftWidth, oneFloorHeight)
            end
            
            % Set GUI Paremeters
            % -------------------------------------------------------------
            % | border | spaceBetween | totalSpaceBetween | oneLiftWidth |
            % oneFloorHeight |
            % -------------------------------------------------------------
            this.parametersG(1) = border;
            this.parametersG(2) = spaceBetween;
            this.parametersG(3) = totalSpaceBetween;
            this.parametersG(4) = oneLiftWidth;
            this.parametersG(5) = oneFloorHeight;
            
            % Create lines as floors for building
            linesX = [0 1; zeros(numOfFloors,1), ones(numOfFloors,1)];
            linesY = [0 oneFloorHeight:oneFloorHeight:1; 0 oneFloorHeight:oneFloorHeight:1];
            linesY = linesY';
            
            %openGL check
            d = opengl('data');
            oGL = false;
            if (isfield(d, 'SupportsGraphicsSmoothing'))
                oGL = true;
            end
            for k=1:numOfFloors+1
                this.bG(k+2) = line(linesX(k,:), linesY(k,:),'Color',[.8 .8 .8],'LineWidth',1, 'Parent', this.bG(2));
                if (oGL && d.SupportsAlignVertexCenters)
                    set(this.bG(k+2), 'AlignVertexCenters', 'On')                   
                end
            end
            
            % create count boxes for simulation
            if (forSimulation)
                for k=1:numOfFloors
                    this.humansWaitingCount(k) =  uicontrol('parent', this.bG(1),'style','text','units','normalized','position',[0.01 linesY(k)+0.01 this.parametersG(1)-0.015 this.parametersG(5)/2],'backgroundcolor',[1 1 1],'fontweight','bold', 'Visible', 'Off');
                    this.humansFinishedCount(k) =  uicontrol('parent', this.bG(1),'style','text','units','normalized','position',[1-this.parametersG(1)+0.01 linesY(k)+0.01 this.parametersG(1)-0.02 this.parametersG(5)/2],'backgroundcolor',[1 1 1],'fontweight','bold', 'Visible', 'Off');
                end
            end
            
            % Create shafts for lifts
            this.liftShaftsG = zeros(1,numOfLifts);
            pos = border;
            
            colorRange = linspace(0.2,0.8,numOfLifts);
            colorRangeDenied = linspace(0.25,0.75,numOfLifts);
            
            for i=1:numOfLifts
                [y, x] = find(plan==lifts(i).getID);
                liftNumOfFloors = size(x,1);
                
                posY = (oneFloorHeight * min(y)) - oneFloorHeight;
                
                if (x(1) == 1)
                    posX = x(1) * pos;
                else
                    posX =  ((x(1)-1) * (oneLiftWidth + spaceBetween)) + pos;
                end
                this.liftShaftsG(i) = uipanel('Parent',this.bG(1)','position',[posX posY oneLiftWidth liftNumOfFloors*oneFloorHeight],'backgroundcolor',[colorRange(i) colorRange(i) colorRange(i)],'fontweight','bold','BorderType', 'none');
                
                % Visulate floors, in which lift cant stop
                liftHeight = 1 / liftNumOfFloors;
                deniedFloors = lifts(i).getDeniedFloors();
                if (deniedFloors ~= 0)
                    for k=1:size(deniedFloors,2)
                        this.liftShaftsDeniedG(k) = uipanel('Parent',this.liftShaftsG(i)','position',[0 ((liftHeight * find(y == deniedFloors(k))) - liftHeight) 1 liftHeight],'backgroundcolor',[colorRangeDenied(i) colorRangeDenied(i) colorRangeDenied(i)],'fontweight','bold','BorderType', 'none');
                        bG(k) = axes('Parent',this.liftShaftsDeniedG(k)','Position',[0 0 1 1],'xtick',[],'ytick',[],'xcolor',[colorRangeDenied(i) colorRangeDenied(i) colorRangeDenied(i)],'ycolor',[colorRangeDenied(i) colorRangeDenied(i) colorRangeDenied(i)],'box', 'off','Color', 'none');
                        line([0 1], [0 1],'Color',[colorRange(i)+0.125 colorRange(i)+0.125 colorRange(i)+0.125],'LineWidth',1, 'Parent', bG(k))
                        line([0 1], [1 0],'Color',[colorRange(i)+0.125 colorRange(i)+0.125 colorRange(i)+0.125],'LineWidth',1, 'Parent', bG(k))
                    end
                end
                
                if (forSimulation)
                    % Visulate lifts cabin
                    this.lG(i) = uipanel('Parent',this.liftShaftsG(i)','position',[0 0 1 liftHeight],'backgroundcolor',[0 0 0],'fontweight','bold','BorderType', 'none');
                    test(i) = axes('Parent',this.lG(i)','Position',[0 0 1 1],'xtick',[],'ytick',[],'xcolor',[colorRangeDenied(i) colorRangeDenied(i) colorRangeDenied(i)],'ycolor',[colorRangeDenied(i) colorRangeDenied(i) colorRangeDenied(i)],'box', 'off','Color', 'none');
                    this.liftGraphic(i) = imshow(this.images.lift_idle, 'Parent', test(i));
                    set(test(i), 'DataAspectRatioMode', 'auto');
                end
            end
            
            % Progress bar
            if (forSimulation)
                this.oG = javax.swing.JProgressBar(0, this.model.getHumansLeft);
                this.oG.setStringPainted(true);
                this.oG.setIndeterminate(false);
                
                [jhandle, hhandle] = javacomponent(this.oG, [0 0 1 0.02], this.wG);
                set(hhandle, 'parent', this.wG, 'Units', 'norm', 'Position', [0 0 1 0.02]);
            end
            pause(0.5);
        end
        
        function moveLiftsInGUI(this)
            % change graphics of lifts and update their position
            
            numOfLifts=this.model.b.getNumOfLifts;
            lifts = this.model.b.getLifts;
            
            % change graphics
            for i=1:numOfLifts
                if (lifts(i).getNumOfHumansInLift > 0 )
                    load = true;
                else
                    load = false;
                end
                
                direction = lifts(i).getDirection;
                if (direction.eq(States.up))
                    
                    if (load)
                        set(this.liftGraphic(i),'CData',this.images.lift_up_f);
                    else
                        set(this.liftGraphic(i),'CData',this.images.lift_up_e);
                    end
                    
                elseif (direction.eq(States.down))
                    
                    if (load)
                        set(this.liftGraphic(i),'CData',this.images.lift_down_f);
                    else
                        set(this.liftGraphic(i),'CData',this.images.lift_down_e);
                    end
                else                    
                    set(this.liftGraphic(i),'CData',this.images.lift_idle);
                end
            end
            
            % change position
            for i=1:numOfLifts
                position = get(this.lG(i), 'Position');
                position4 = position(4);
                floor = lifts(i).getActualFloor;
                if (lifts(i).getBaseFloor > 1)
                    floor = floor - ((lifts(i).getBaseFloor) - 1);
                end
                newPosition = ((floor*position4)/1) - position4;
                if (floor == 1)
                    newPosition = 0;
                end
                position(2) = newPosition;
                set(this.lG(i), 'Position',position);
            end
            drawnow;
        end
        
        function showHumansWaitingInGUI(this)
            % load both waitingList and floorList and update
            % number of humans on floors in humansWaitingCount panels
            
            floors = [];
            waitingList = this.model.waitingList;
            floorList = this.model.floorList;
            
            if (~isempty(waitingList) || ~isempty(floorList))
                
                if (~isempty(waitingList))
                    floors = [floors waitingList{:,1}];
                end
                if (~isempty(floorList))
                    floors = [floors floorList{:,1}];
                end
                
                floors = unique(floors);
                
                num = this.model.b.getNumOfFloors;
                for i=1:num
                    if (~isempty(find(floors==i)))
                        tmpHumansWait = size(this.model.findHumansOnFloorWaiting(i,true),2);
                        tmpHumansFloor =  size(this.model.findHumansOnFloorWaiting(i,false),2);
                        set(this.humansWaitingCount(i), 'Visible', 'On', 'String', (tmpHumansWait + tmpHumansFloor));
                    else
                        set(this.humansWaitingCount(i), 'Visible', 'Off', 'String', 0);
                    end
                end
            else
                set(this.humansWaitingCount(:), 'Visible', 'Off', 'String', 0);
            end
            
        end
        
        function showHumansFinishedInGUI(this, floor)
            % refresh number of finished humans on specific floor
            % floor = floor where human finished
            
            num = str2num(get(this.humansFinishedCount(floor), 'String'));
            if (isempty(num))
                num = 0;
            end
            newNum = num + 1;
            set(this.humansFinishedCount(floor), 'Visible', 'On', 'String', newNum);
            
        end
        
        function updateProgressBar(this)
            
            javaMethodEDT('setValue', this.oG, get(this.oG, 'Maximum') - this.model.getHumansLeft);
            
        end
        
        function showFinalStats(this)
            % create report, saves it and show it to the
            % user
            this.moveLiftsInGUI();
            
            procesMsg = msgbox('Simulation was finished, please wait for report!');
            
            filePath = 'output/';
            
            behavior = this.model.getSystemBehavior;
            switch behavior
                case States.random
                    fileSuffix = 'Random';
                case States.dijkstra_e
                    fileSuffix = 'Scheduler';
            end
            fileName = 'simResult_';
            fileDate = Simulation.getTime();
            fileExt = '.html';
            fileString = strcat(filePath,fileName,fileSuffix,'-',fileDate,fileExt);
            
            % little hack, output is displayed in CLI and saved as diary
            clc;
            if (exist(fileString, 'file'))
                delete(fileString);
            end
            
            if (isdeployed && ismac)
                % special care for deployed app on macOS
                [fileMacDiary,pathMacDiary] = uiputfile(strcat(fileName,fileSuffix,'-',fileDate,fileExt),'Save simulation report.');
                fileString = strcat(pathMacDiary,fileMacDiary);
                diary(strcat(pathMacDiary,fileMacDiary))
            else
                diary(fileString)
            end
            
            diary on;
            
            this.model.getFinalStats();

            diary off;
            clc;
                        
            if (exist(fileString, 'file'))
                close(procesMsg);
                web(fileString);
            end
            
        end
        
    end
    
    methods (Static)
        function timechar = getTime()
            % Test if datetime function is available and return
            % time string
            testFunction = exist('datetime', 'file');
            
            if (testFunction == 0)
                timechar = datestr(now, 'HH-MM-yyyy-dd-mm-ss');
            else
                timechar=char(datetime('now','Format','HH-mm-ss''-''yyyy-dd-MM'));
            end
        end
    end
    
end

