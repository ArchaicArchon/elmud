defmodule ChatServer do

## Version 0.0.1 of ElMUD : The MUD written in Elixir!###
## Now with a kv store for users!
## Going to add rooms!

def debug do true end

defp douts(string) do
  if debug do IO.puts(string) end
end

defp dpass(string) do
  if debug do IO.puts("#{inspect string}") end
  string
end

def fst({item,_}) do item end

def snd({_,item}) do item end

def start(port) do
  {:ok,socket} = :gen_tcp.listen(port,
    [:binary,
       packet: :line, active: false,
       reuseaddr: true])
  socketsAndPids = %{}
  keys_and_values = %{}
  statePid = spawn(fn -> state socketsAndPids end) 
  spawn(fn -> sweeper statePid end)
  broadcastPid = spawn(fn -> broadcast(statePid) end)
  key_value_store_pid = spawn(fn -> key_value_store(keys_and_values) end)
  IO.puts "Accepting connections on port #{inspect port}"
  loop_acceptor(socket,statePid,broadcastPid,key_value_store_pid)
end

defp key_value_store(keys_and_values) do
  receive do 
    {:get,caller,key} ->
      send(caller,{:key,keys_and_values[key]})
    {:set,{k,v}} ->
      key_value_store(Map.put(keys_and_values,k,v))
  end
  key_value_store(keys_and_values)
end

defp state(socketsAndPids) do
  receive do
    {:get,caller} ->
      send(caller,{:state,socketsAndPids})
    {:get_extra,caller,msg,socket} ->
      send(caller,
        {:state_with_msg_and_name,socketsAndPids,msg,
            (socketsAndPids[socket] |> snd)})
    {:insert,{k,v}} ->
      state(Map.put(socketsAndPids,k,v))
    {:remove,socket} ->
      state(Map.delete(socketsAndPids,socket))
  end
  state(socketsAndPids)
end

defp sweeper(statePid) do
  send(statePid,{:get,self()})
  receive do
    {:state,socketsAndPids} ->
      Map.keys(socketsAndPids) |>
      Enum.map(fn socket -> if !Process.alive?(fst(socketsAndPids[socket])) do
        send(statePid,{:remove,socket})
        end end)
  end
  sweeper(statePid)
end

defp broadcast(statePid) do
  receive do
    {:broadcast,msg,socket} ->
      douts("got a msg: #{inspect msg} from: #{inspect socket}")
      send(statePid,{:get_extra,self(),msg,socket})
    {:state_with_msg_and_name,socketsAndPids,msg,name} ->
      douts("oh here is my state in broadcast: #{inspect socketsAndPids}")
      Map.keys(socketsAndPids) |> 
      dpass |>
      Enum.map(fn socket -> 
        douts("here is my msg and socket and name: #{inspect msg} : #{inspect socket} : #{inspect name}")
        spawn(fn -> write_line((to_char_list(String.rstrip(name)) 
            ++ ': ' ++ to_char_list(msg)),
            socket) end) end)
  end
  broadcast(statePid)
end

defp loop_acceptor(socket,statePid,broadcastPid,key_value_store_pid) do
  {:ok,client_socket} = :gen_tcp.accept(socket) ### could error here!
  spawn(fn -> 
    start_loop(client_socket,statePid,broadcastPid,key_value_store_pid) end)
  loop_acceptor(socket,statePid,broadcastPid,key_value_store_pid)
end

defp start_loop(socket,statePid,broadcastPid,key_value_store_pid) do
  write_line("Welcome to Elixir Chat!\n",socket)
  write_line("Enter your User name:\n",socket)
  name = login(socket)
  send(statePid,{:insert,{socket,{self(),name}}})
  loop_server(socket,broadcastPid,key_value_store_pid)
end

defp login(socket) do
  line = read_line(socket)
  write_line("Welcome #{line}",socket)
  line
end

defp loop_server(socket,broadcastPid,key_value_store_pid) do
  line = String.to_char_list(read_line socket)
  case line do
    [?c,?h,?a,?t,?\ |chat_message] ->
      send(broadcastPid,{:broadcast,chat_message,socket})
    [?g,?e,?t,?\ |key_with_white_space] ->
      key = String.rstrip(String.lstrip(to_string(key_with_white_space)))
      send(key_value_store_pid,{:get,self(),key})
      receive do
        {:key,value} -> 
          write_line("#{inspect value}\n",socket)
       end
    [?s,?e,?t,?\ |key_and_value] ->
      [key,value|_] = String.split(to_string(key_and_value))
      send(key_value_store_pid,{:set,{key,value}})
    _ -> write_line("I do not understand: #{line}",socket)
  end
  loop_server(socket,broadcastPid,key_value_store_pid)
end

defp read_line(socket) do
  {:ok, data} = :gen_tcp.recv(socket,0)
  douts "Read in data: #{inspect data} : from #{inspect socket}"
  data
end

defp write_line(line,socket) do
  douts("trying to write: #{line} to #{inspect socket}")
  :gen_tcp.send(socket,line)
end

end

port = 4000

spawn(fn -> ChatServer.start port end)
