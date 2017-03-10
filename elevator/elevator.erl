-module(elevator).
-export([simple_drive/0]).
-compile(export_all).
-define(SENSOR_MONITOR_PID, smpid).
-define(DRIVER_MANAGER_PID, dmpid).

%THE ELEVATOR IS ASSUMED TO START ON BOTTOM FLOOR!
simple_drive() ->
	register(?SENSOR_MONITOR_PID, spawn(fun() -> sensor_monitor() end)), 
	register(?DRIVER_MANAGER_PID, spawn(fun() -> simple_driver_manager1() end)).

sensor_monitor() -> 
	receive
		{new_floor_reached,Floor} ->
			io:fwrite("New floor reached ~w ~n ", [Floor]), %DEBUG
			?DRIVER_MANAGER_PID ! {new_floor_reached,Floor};

		{button_pressed, ButtonType, Floor} ->
			io:fwrite("Button pressed ~w ~w ~n ", [ButtonType,Floor]) %DEBUG
			%WHEN DEBUGGING; CHECK WHAT NUMBERS BUTTONTYPE ARE; MAYBE CONVERT IN DRIVER?
	end,
	sensor_monitor().

simple_driver_manager1() ->
	driver:start(?SENSOR_MONITOR_PID),
	driver:set_motor_direction(up),
	receive
		{new_floor_reached,Floor} ->
			io:fwrite("New floor reached in function that stops ~w ~n ", [Floor]), %DEBUG
			driver:set_floor_indicator(Floor),
			case Floor of
				0 ->
					driver:set_motor_direction(up);
				3 ->
					driver:set_motor_direction(down)
			end,
		simple_driver_manager2()
	end.

simple_driver_manager2() ->
	receive
		{new_floor_reached,Floor} ->
			io:fwrite("New floor reached in function that stops ~w ~n ", [Floor]), %DEBUG
			driver:set_floor_indicator(Floor),
			case Floor of
				0 ->
					driver:set_motor_direction(up);
				1 ->
					ok;
				2 ->
					ok;
				3 ->
					driver:set_motor_direction(down)
			end,
		simple_driver_manager2()
	end.