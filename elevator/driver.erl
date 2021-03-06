-module(driver).
-export([start/2, stop/0]).
-export([set_motor_direction/1, set_button_lamp/3, set_floor_indicator/1, set_door_open_lamp/1, create_buttons/2]). %Consider if init and turn all off is necessary

-record(button,{floor,type,state = 0}).

-define(NUM_FLOORS, 4).
-define(NUM_BUTTONS, 3).
-define(BUTTON_TYPES, [up,inner,down]).

start(Init_listener, Sensor_monitor_pid) -> 
	spawn(fun() -> init_port("../driver/elev_port") end),
    timer:sleep(100),

    %Initialize elevator, is void in c, so no return:
    init(),
    Floor = go_to_defined_floor(),

    %Start sensor monitor that can send to process with PID SENSOR_MONITOR_PID in supermodule:
    Buttons = create_buttons([],0),
    spawn(fun() -> sensor_poller(Sensor_monitor_pid, Floor, Buttons) end),
    Init_listener ! {driver_init_complete, Floor}.
 
go_to_defined_floor() ->
	set_motor_direction(down),
	case Floor = get_floor_sensor_signal() of 
		255 -> go_to_defined_floor();
		_ -> 
			set_motor_direction(stop),
			set_floor_indicator(Floor),
			Floor
	end.
	
sensor_poller(Sensor_monitor_pid, Last_floor, Buttons) -> 
	New_floor = get_floor_sensor_signal(),
	floor_sensor_reaction(New_floor == Last_floor, New_floor, Sensor_monitor_pid),

	Updated_buttons = button_sensor_poller(Sensor_monitor_pid, Buttons,[]),
	timer:sleep(50),
	sensor_poller(Sensor_monitor_pid, New_floor, Updated_buttons).

floor_sensor_reaction(true, _New_floor, _PID) ->
	false;
floor_sensor_reaction(false, 255, _PID) ->
	false;
floor_sensor_reaction(false, New_floor, Sensor_monitor_pid) ->
	Sensor_monitor_pid ! {new_floor_reached, New_floor}.

button_sensor_poller(_Sensor_monitor_pid, [], Updated_buttons) -> Updated_buttons; % No more buttons
button_sensor_poller(Sensor_monitor_pid, Buttons, Updated_buttons) ->
	[Button | Rest] = Buttons,
	button_sensor_poller(Sensor_monitor_pid, Button, Rest, Updated_buttons).

button_sensor_poller(Sensor_monitor_pid, Button, Rest, Updated_buttons) -> % Still have more buttons to check
	Floor = Button#button.floor,
	Button_type = Button#button.type,
	State = Button#button.state,
	New_state = get_button_signal(Button_type,Floor),
	react_to_button_press((New_state /= State) and (New_state == 1), Sensor_monitor_pid, Floor, Button_type),
	New_buttons = Updated_buttons ++ [#button{floor=Floor,type = Button_type,state = New_state}],
	button_sensor_poller(Sensor_monitor_pid, Rest, New_buttons).

react_to_button_press(true, Sensor_monitor_pid, Floor, Button_type) ->
	Sensor_monitor_pid ! {button_pressed, Floor, Button_type};
react_to_button_press(false, _SENSOR_MONITOR_PID, _Floor, _Button_type) ->
	false.

%%%%%%% ERL VERSIONS OF C FUNCTIONS %%%%%%%%
init() -> call_port(elev_init).
set_motor_direction(Direction) -> call_port({elev_set_motor_direction, Direction}).
set_button_lamp(Button_type,Floor,Value) -> call_port({elev_set_button_lamp,Button_type,Floor, Value}).
set_floor_indicator(Floor) -> call_port({elev_set_floor_indicator,Floor}).
set_door_open_lamp(Value) -> call_port({elev_set_door_open_lamp, Value}).
get_button_signal(Button_type,Floor) -> call_port({elev_get_button_signal,Button_type,Floor}).
get_floor_sensor_signal() -> call_port({elev_get_floor_sensor_signal}).

%%%%%%% COMMUNICATION WITH C PORT %%%%%%%%
init_port(ExtPrg) ->
    register(driver, self()),
    process_flag(trap_exit, true),
    Port = open_port({spawn, ExtPrg}, [{packet, 2}]),
    loop(Port).

loop(Port) ->
    receive
	{call, Caller, Msg} ->
	    Port ! {self(), {command, encode(Msg)}},
	    receive
		{Port, {data, Data}} ->
		    Caller ! {driver, Data}
	    end,
	    loop(Port);

	stop ->
	    Port ! {self(), close},
	    receive
		{Port, closed} ->
		    exit(normal)
	    end;
	{'EXIT', _Port, _Reason} ->
	    exit(port_terminated)
    end.

call_port(Msg) ->
    driver ! {call, self(), Msg},
    receive
	{driver, [Result]} ->
	    Result
    end.

stop() ->
    driver ! stop.


%%%%%%% ENCODING MESSAGES FOR C PORT %%%%%%%%
encode(elev_init) -> [1];

encode({elev_set_motor_direction, up}) -> [2,1];
encode({elev_set_motor_direction, stop}) -> [2,0];
encode({elev_set_motor_direction, down}) -> [2,2];

encode({elev_set_button_lamp,up, Floor ,on}) -> [3,0,Floor,1];
encode({elev_set_button_lamp,inner, Floor,on}) -> [3,2,Floor,1];
encode({elev_set_button_lamp,down, Floor,on}) -> [3,1,Floor,1];

encode({elev_set_button_lamp,up, Floor , off}) -> [3,0,Floor,0];
encode({elev_set_button_lamp,inner, Floor, off}) -> [3,2,Floor,0];
encode({elev_set_button_lamp,down, Floor, off}) -> [3,1,Floor,0];

encode({elev_set_floor_indicator, Floor}) -> [4, Floor];

encode({elev_set_door_open_lamp, on}) -> [5, 1];
encode({elev_set_door_open_lamp, off}) -> [5, 0];

encode({elev_get_button_signal,up,Floor}) -> [6,0,Floor];
encode({elev_get_button_signal,inner,Floor}) -> [6,2,Floor];
encode({elev_get_button_signal,down,Floor}) -> [6,1,Floor];

encode({elev_get_floor_sensor_signal}) -> [7];

encode({elev_reset_order_lights,Floor}) -> [8,Floor];
encode({elev_turn_all_the_lights_off}) -> [9].


%%%%%% HELPER FUNCTIONS %%%%%%
create_buttons(Buttons,0) -> %At bottom floor
	New_buttons = Buttons ++ [#button{floor=0,type = inner}, #button{floor=0,type = up}],
	create_buttons(New_buttons,1);

create_buttons(Buttons,Floor) when (Floor>0) and (Floor < ?NUM_FLOORS-1)-> %At middle floor
	New_buttons = Buttons ++ [#button{floor=Floor,type = down}, #button{floor=Floor,type = inner},#button{floor=Floor,type = up}],
	create_buttons(New_buttons,Floor+1);
			
create_buttons(Buttons,?NUM_FLOORS-1) -> %At top floor
	Buttons ++ [#button{floor= ?NUM_FLOORS-1 ,type = down}, #button{floor=?NUM_FLOORS-1 ,type = inner}].

