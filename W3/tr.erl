-module(tr).
-export([master/2, init_node/1, init_node/2, receive_output/2]).

master(N, M) ->
  % 1. spawn N processes
  {FirstNode, LastNode} = init_node_ring(N-1), % 0-based
  % 2. send M tokens
  send_counters(FirstNode, LastNode, M-1), % 0-based
  % 3. receive responses
  receive_output(N, []).

send_counters(FirstNode, LastNode, M) when M == 0 ->
  send_counter(last, FirstNode, LastNode, M+1);
send_counters(FirstNode, LastNode, M) ->
  send_counter(FirstNode, LastNode, M*10),
  send_counters(FirstNode, LastNode, M-1).

receive_output(MsgCount, ListOut) when MsgCount == 0 ->
  io:format("MASTER (~p): All Counters received, terminating!~n", [self()]),
  io:format("Output:~n~p", [ListOut]);
receive_output(MsgCount, ListOut) ->
  receive
    {Pid, Pid_Succ, Counter} ->
      io:format("MASTER (~p): received: {~p, ~p, ~p}~n", [self(), Pid, Pid_Succ, Counter]),
      receive_output(MsgCount-1, ListOut ++ [{Pid, Pid_Succ, Counter}])
  end.

send_counter(FirstNode, LastNode, Counter) ->
  FirstNode ! {counter, LastNode, Counter},
  io:format("MASTER (~p): Sent FIRST (~p) ! {counter, ~p, ~p}~n", [self(), FirstNode, LastNode, Counter]).
send_counter(last, FirstNode, LastNode, Counter) ->
  FirstNode ! {last, counter, LastNode, Counter},
  io:format("MASTER (~p): Sent FIRST (~p) ! {last, ~p, ~p, ~p}~n", [self(), FirstNode, FirstNode, LastNode, Counter]).

init_node_ring(0) -> false; % error condition
init_node_ring(1) -> false; % error condition
init_node_ring(N) ->
  FirstNode = spawn(tr, init_node, [self()]),
  LastNode = init_nodes(N-1, FirstNode),
  {FirstNode, LastNode}. % return {FirstNode, LastNode} for reuse

init_nodes(N, Successor) when N > 0 ->
  Node = spawn(tr, init_node, [self(), Successor]),
  init_nodes(N-1, Node);
init_nodes(_, Successor) ->
  spawn(tr, init_node, [self(), Successor]). % return the last created node

write_to_file(Pid, Pid_Succ, Counter) ->
  io:format("Pid: ~p~nPid_Succ: ~p~nCounter: ~p~n", [Pid, Pid_Succ, Counter]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% NODE CODE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_node(RootPid) ->
  receive_counters(RootPid).

init_node(RootPid, Successor) ->
  receive_counters(RootPid, Successor).

% FirstNode msg handling
receive_counters(RootPid) ->
  receive
    % FIRST node receives msg from its predecessor after msg has cycled ring
    {counter, Counter} ->
      io:format("FIRST (~p): Counter ~p has cycled ring completely, do nothing and wait for next counter from MASTER~n", [self(), Counter]),
      receive_counters(RootPid);
    % FIRST node receives last msg from its predecessor after last msg has cycled ring
    % Only in this case can we terminate the FIRST node
    {last, counter, Counter} ->
      io:format("FIRST (~p): last counter received, TERMINATE!~n", [self()]);
    % FIRST node receives msg from MASTER
    {counter, Successor, Counter} ->
      io:format("FIRST (~p)|~p: Initial {counter, ~p, ~p} received, sending {counter, ~p, ~p} to ~p~n", [self(), Counter, Successor, Counter, Successor, Counter, Successor]),
      Successor ! {counter, Counter+1},
      receive_counters(RootPid);
    % FIRST node receives last msg from MASTER
    {last, counter, Successor, Counter} ->
      io:format("FIRST(~p)|~p: {last, counter, ~p, ~p} received, sending {last, counter, ~p, ~p} to ~p~n", [self(), Counter, Successor, Counter, Successor, Counter, Successor]),
      Successor ! {last, counter, Counter+1},
      RootPid ! {self(), Successor, Counter},
      io:format("FIRST (~p): sent MASTER (~p) ! {~p, ~p, ~p}~n", [self(), RootPid, self(), Successor, Counter]),
      receive_counters(RootPid)
  end.

% OtherNodes msg handling
receive_counters(RootPid, Successor) ->
  receive
    {counter, Counter} ->
      io:format("(~p)|~p: {counter, ~p} received, sending counter+1 to ~p~n", [self(), Counter, Counter, Successor]),
      Successor ! {counter, Counter+1},
      receive_counters(RootPid, Successor);
    {last, counter, Counter} ->
      Successor ! {last, counter, (Counter + 1)},
      RootPid ! {self(), Successor, Counter},
      io:format("(~p): sent MASTER (~p) ! {~p, ~p, ~p}~n", [self(), RootPid, self(), Successor, Counter])
      io:format("(~p): last msg sent, TERMINATE!")
  end.
