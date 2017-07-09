
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Up&Down
% Author - Michal Semelka, <m.semelka@gmail.com>, 2017
% https://github.com/michalsemelka/UpEtDown
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



% load folders
[rootPath, ~, ~] = fileparts(which('index.m'));

addpath(genpath(rootPath));
cd(rootPath);
addpath(genpath('app'));
addpath(genpath('app/assets'));
addpath(genpath('output'));

% start program
GUI();