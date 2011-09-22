-module(irc).

-export([start/0, stop/0, lists/0, connect/2, disconnect/0, join/1, leave/1]).

start() -> 
    register(irc, spawn(fun irc_server/0)).

stop() ->
    unregister(irc).

connect(Hostname, Nickname) ->
    {ok, connected} = rpc({connect, Hostname, Nickname}).

disconnect() ->
    {ok, disconnected} = rpc(disconnect).

lists() ->
    ok = rpc(lists).

join(Channel) ->
    ok = rpc({join, Channel}).

leave(Channel) ->
    ok = rpc({leave, Channel}).

rpc(Request) ->
    irc ! {self(), Request},
    receive 
	{irc, Response} ->
	    Response
    end.

irc_server() ->
    receive
	{From, {connect, Hostname, Nickname}} ->
	    {ok, Socket} = gen_tcp:connect(Hostname, 6667,[binary, {packet, 0}]),
	    Pid = spawn(fun() -> irc_server_loop(Socket, [], dict:new()) end),
	    true = register(irc_server, Pid),
	    ok = gen_tcp:controlling_process(Socket, Pid),
	    send_data(["NICK", " ", Nickname, "\r\n"]),
 	    send_data(["USER pling plang plong :ding dong\r\n"]),
	    From ! {irc, {ok, connected}},
	    irc_server();
	{From, disconnect} ->
 	    send_data(["QUIT :ding dong\r\n"]),
	    From ! {irc, {ok, disconnected}},
	    true = unregister(irc_server),
	    irc_server();
	{From, lists} ->
 	    send_data(["LIST\r\n"]),
	    From ! {irc, ok},
	    irc_server();
	{From, {join, Channel}} ->
 	    send_data(["JOIN", " ", Channel, "\r\n"]),
	    send_join_channel(Channel),
	    From ! {irc, ok},
	    irc_server();
	{From, {leave, Channel}} ->
 	    send_data(["PART", " ", Channel, "\r\n"]),
	    From ! {irc, ok},
	    irc_server();
	Any ->
	    io:format("Received unhandle [~p]~n", [Any]),
	    irc_server()
    end.

irc_server_loop(Socket, Leftover, Dict) ->
    % io:format("Leftover: ~p~n", [Leftover]),
    receive
	{tcp, Socket, Bin} ->
	    L = Leftover ++ binary_to_list(Bin),
	    % io:format("L: ~s", [L]),
	    LastCrLfPos = string:rstr(L, "\r\n"),
	    LinesWithCrLf = 
		case LastCrLfPos of 
		    0 ->
			[];
		    _ ->
			string:substr(L, 1, LastCrLfPos+1)
		end,
	    Leftoversize = string:len(L)-string:len(LinesWithCrLf),
	    NewLeftover = 
		if
		    Leftoversize == 0 -> [];
		    Leftoversize > 0  -> string:substr(L, LastCrLfPos+2, Leftoversize)
		end,
	    % io:format("NewLeftover: ~p~n", [NewLeftover]),
	    T = string:tokens(LinesWithCrLf, "\r\n"),
	    Dict1 = handle_server_message(T, Socket, Dict),
	    irc_server_loop(Socket, NewLeftover, Dict1);
	{tcp_closed, Socket} ->
	    io:format("Connection closed~n"),
	    irc_server_loop(Socket, Leftover, Dict);
	{error, closed}  ->
	    io:format("Connection closed by peer~n"),
	    irc_server_loop(Socket, Leftover, Dict);
	{irc_client_request, Payload} ->
	    ok = gen_tcp:send(Socket, list_to_binary(Payload)),
	    irc_server_loop(Socket, Leftover, Dict);
	{irc_client_request_join_channel, Channel} ->
	    ChannelPid = spawn(fun() -> channel_handler(Channel) end),
	    % io:format("Spawned new process ~p for handling channel ~s~n", [ChannelPid, Channel]),
	    NewDict = dict:store(Channel, ChannelPid, Dict),
	    irc_server_loop(Socket, Leftover, NewDict)
    end.

send_data(Payload) ->
    irc_server ! {irc_client_request, Payload}.

send_join_channel(Channel) ->
    irc_server ! {irc_client_request_join_channel, Channel}.

handle_server_message([H|T], Socket, Dict)->
    %io:format("H: ~s~n", [H]),
    Message = string:tokens(H, " "),
    %io:format("Message: ~s~n", [Message]),
    First = lists:nth(1, Message),
    case string:str(First, ":") of
	0 ->
	    case string:str(First, "PING") of
		1 ->
		    send_data(["PONG\r\n"]);
		_ ->
		    io:format("Unhandled command ~s~n", [H])
	    end;
	_ ->
	    Second = lists:nth(2, Message),
	    case Second of 
		"PRIVMSG" ->
		    Third = lists:nth(3, Message),
		    % io:format("Third: ~p~n", [Third]),
		    {ok, ChannelPID } = dict:find(Third, Dict),
		    io:format("ChannelPID: ~p  Message: ~p ~n", [ChannelPID,H]),
		    ChannelPID ! {channel_message, H};
		% RPL_LIST (322)
		"322" ->
		    Channel = lists:nth(4, Message),
		    send_join_channel(Channel);
		    % io:format("Sent message to ~s channel handler~n", [Channel]);
		_ ->
		    Dict
	    end,
	    Dict
    end,
    handle_server_message(T, Socket, Dict);

handle_server_message([], _Socket, Dict) ->
    Dict.


channel_handler(Channel) ->
    % io:format("~p Channel handler for ~s~n", [self(), Channel]),
    receive
	{channel_message, Message} ->
	    io:format("~p ~s ~s~n", [calendar:local_time(),Channel, Message]),
	    channel_handler(Channel);
	    
	Any ->
	    io:format("Received unhandle [~p]~n", [Any]),
	    channel_handler(Channel)
    end.


