defmodule Elmud do

## Version 0.0.1 of ElMUD : The MUD written in Elixir!###
## Now with a kv store for users!
## Going to add rooms!
## Now with user accounts with passwords and creation
## Going to add crash quick semantics to all receives and case

def debug do true end

defmodule Object do

defstruct name: "Noname", title: "Notitle", description: "This object does not have a description", identifier: {:item, 0}, location: {:room, 0}, inventory: [], equipment: %{}, internal_verbs: [], external_verbs: [], internal_inventory_verbs: [], external_inventory_verbs: [], internal_equipment_verbs: [], external_equipment_verbs: []

end

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
  password_filename = ".passwords"
  password_map = read_passwords_file password_filename
  douts "Password file succesfully read!"
  password_server_id = spawn(fn -> password_server(password_map,password_filename) end)
  douts "Password_server successfully started!"
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
  loop_acceptor(socket,password_server_id,statePid,broadcastPid,key_value_store_pid)
end

defp key_value_store(keys_and_values) do
  receive do 
    {:get,caller,key} ->
      send(caller,{:key,keys_and_values[key]})
    {:set,{k,v}} ->
      key_value_store(Map.put(keys_and_values,k,v))
    anything_else -> 
      raise "Improper message passed to key_value_store: #{inspect anything_else}"
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
    anything_else ->
      raise "improper message passed to state: #{inspect anything_else}"
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
    anything_else ->
      raise "Improper message passed to sweeper: #{inspect anything_else}"
  end
  :timer.sleep(1000) ## sleep the sweeper for 1 second, is this too long?, to cut down on cpu cycles
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
    anything_else ->
      raise "Improper message passed to broadcast: #{inspect anything_else}"
  end
  broadcast(statePid)
end

defp password_server(password_map,password_filename) do
  receive do
    {:create_username,username,password} ->
      douts "password_server is adding Username: #{inspect username} Password: #{inspect password}\n"
      {:ok,file_handle} = File.open(password_filename,[:append])
      IO.binwrite(file_handle,"#{username}:#{password}\n")
      File.close(file_handle)
      password_server(Map.put(password_map,username,password),password_filename)
    {:check_username,{caller,username}} ->
      douts("password_server checking username: #{inspect username}#")
      send(caller,{:username_is,(password_map[username] != nil)})
    {:check_username_password,{caller,username,password}} ->
      douts("password_server received a :check from: #{inspect caller} username: #{inspect username} password: #{inspect password}")
      douts("looking up password....")
      douts("our password map: #{inspect password_map}")
      looked_up_password = password_map[username]
      douts("the looked up pasword is: #{inspect looked_up_password}")
      return_value = password == password_map[username]
      douts("PASSWORD SERVER IS STILL ALIVE!!!!!")
      douts("Passwords match: #{inspect return_value}")
      send(caller,{:password_is,return_value})
      douts("password_server sent data back to caller!")
    anything_else ->
      douts("password_server received: #{inspect anything_else}")
  end
  password_server(password_map,password_filename)
end

defp loop_acceptor(socket,password_server_id,statePid,broadcastPid,key_value_store_pid) do
  {:ok,client_socket} = :gen_tcp.accept(socket) ### could error here!
  spawn(fn -> 
    start_loop(client_socket,password_server_id,statePid,broadcastPid,key_value_store_pid) end)
  loop_acceptor(socket,password_server_id,statePid,broadcastPid,key_value_store_pid)
end

defp start_loop(socket,password_server_id,statePid,broadcastPid,key_value_store_pid) do
  write_line("Welcome to Elixir Chat\n",socket)
  name = login(socket,password_server_id)
  send(statePid,{:insert,{socket,{self(),name}}})
  loop_server(socket,broadcastPid,key_value_store_pid)
end

## Login function is kinda big and a bit messy, should break it up
defp login(socket,password_server_id) do
  write_line("Enter your User name: ",socket)
  username = String.rstrip(read_line(socket))
  case check_username(username) do
    true ->
      case check_username_exists(username,password_server_id) do
        true ->
          write_line("Password: ",socket)
          password = String.rstrip(read_line(socket))
          douts("Sending username: #{inspect username} and password: #{inspect password}   to password server...\n")
          send(password_server_id,{:check_username_password,{self(),username,password}})
          douts("password sent to password server... Now waiting for a response\n")
          receive do
            {:password_is,true} -> 
              write_line("::WELCOME #{username}::\n",socket)
              username
            {:password_is,false} ->
              write_line("Invalid Password!\nDisconnected......\n",socket)
              File.close(socket)
              Process.exit(self(),{:kill,"Invalid Password"})
            anything_else ->
              raise "Improper messaged passed to login: #{inspect anything_else}"
          end
        false ->
          ## write_line("Need to add functionality for adding new users\n",socket)
          write_line("Did I get that right #{inspect username}(y/n) ? ",socket)
          yes_or_no = String.rstrip(read_line(socket))
          case (yes_or_no == "y") or (yes_or_no == "Y") do
            true -> 
              write_line("Password: ",socket)
              password_first = String.rstrip(read_line(socket))
              write_line("Enter Password Again: ",socket)
              password_second = String.rstrip(read_line(socket))
              case password_first == password_second do
                true ->
                  write_line("Passwords Match! Creating Account #{inspect username}\n",socket)
                  send(password_server_id,{:create_username,username,password_first})
                  username
                false -> 
                  write_line("Passwords DO NOT MATCH!\n",socket)
                  login(socket,password_server_id)
              end
            false ->
              write_line("Ok...\nEnter the name you want to login as\n",socket)
              login(socket,password_server_id)
          end
      end
    false ->
      write_line("Invalid Username!\n",socket)
      login(socket,password_server_id)
  end
end

defp check_username(name) do
  Regex.match?(~r/^[a-zA-Z]+$/,name)
end

defp check_username_exists(username,password_server_id) do
  send(password_server_id,{:check_username,{self(),username}})
  receive do
    {:username_is,true} -> true
    {:username_is,false} -> false
    anything_else ->
      raise "Improper message passed to check_user_name_exists: #{inspect anything_else}"
  end
end

def read_passwords_file(file_name) do
  file_contents_by_lines = String.split((String.rstrip(File.read!(file_name))),"\n")
  douts("Passwords file contents: #{inspect file_contents_by_lines}")
  password_map = contents_of_lines_to_map(file_contents_by_lines,%{})
  douts "Our Passowrd Map is: #{inspect password_map}"
  password_map
end

defp contents_of_lines_to_map([],map) do map end

defp contents_of_lines_to_map([line|more_lines],map) do
   douts("ok our current line being parsed is: #{inspect line}")
   {k,v} = password_line_parse line
   douts("ok our key value pair is: #{inspect {k,v}}")
   contents_of_lines_to_map(more_lines,Map.put(map,k,v))
end

def password_line_parse(line) do
  [k,v] = String.split(line,":")
  {k,v}
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
      key_and_value_split = String.split(to_string(key_and_value))
      case length(key_and_value_split) == 2 do
        true -> 
          [key,value] = key_and_value_split
          send(key_value_store_pid,{:set,{key,value}})
        false -> write_line("Invalid Key Value Pair\n",socket)
      end
    [?e,?v,?a,?l,?\ |code_string] -> ## THIS IS EXTREMELY DANGEROUS AND INSECURE!!!!! :D
      value = Code.eval_string code_string, [] ## DANGER
      write_line("#{inspect value}\n",socket)     ## DANGER
    [?p,?i,?n,?g | junk] -> write_line("PONG!\n",socket)
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

def main(args) do
  Elmud.start 4000
end

end

## port = 4000

## spawn(fn -> Elmud.start port end) ## uncomment this to make it autoboot
