defmodule Amqp do

	# Define record types for sending messages etc
	defrecord :amqp_params_network, Record.extract( :amqp_params_network, from_lib: "amqp_client/include/amqp_client.hrl")
	defrecord :"basic.publish", Record.extract( :"basic.publish", from_lib: "rabbit_common/include/rabbit_framing.hrl") 
	defrecord :"P_basic", Record.extract( :"P_basic", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :amqp_msg, props: :"P_basic".new, payload: ""
	defrecord :"exchange.declare", Record.extract( :"exchange.declare", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"exchange.declare_ok", Record.extract( :"exchange.declare_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"queue.declare", Record.extract( :"queue.declare", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"queue.bind", Record.extract( :"queue.bind", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"queue.unbind", Record.extract( :"queue.unbind", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"basic.get", Record.extract( :"basic.get", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"basic.get_ok", Record.extract( :"basic.get_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"basic.get_empty", Record.extract( :"basic.get_empty", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"basic.consume", Record.extract( :"basic.consume", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"basic.consume_ok", Record.extract( :"basic.consume_ok", from_lib: "rabbit_common/include/rabbit_framing.hrl")
	defrecord :"basic.ack", Record.extract( :"basic.ack", from_lib: "rabbit_common/include/rabbit_framing.hrl" )

	# Connect to an AMQP server via URL
	defrecord Server, uri: nil, connection: nil, channel: nil, ctag: "" do
		
		# connect to the server in question
		def connect(uri, server) when is_list(uri) do
			server.connect(String.from_char_list!(uri))
		end
		def connect(uri, server) when is_binary(uri) do
			server = server.uri(Amqp.Uri.new.parse(uri))
			{ :ok, params } = :amqp_uri.parse(String.to_char_list!(server.uri.connstr))
			{ :ok, connection } = :amqp_connection.start params
			server = server.connection(connection)
			{ :ok, channel } = :amqp_connection.open_channel connection
			server.channel(channel)
		end
	
		# Send a message to an exchange, exchange, key, and message are binaries ""
		def send(exchange,key,message,opts \\ [persistent: false], server) do
			publish = :'basic.publish'.new exchange: exchange, routing_key: key, persistent: opts[:persistent]
			msg = :amqp_msg.new payload: message
			:amqp_channel.cast server.channel, publish, msg
		end

		def receive(exchange,key,queue,server) do
      server.receive(exchange, key, queue, type: "topic")
    end

		# Binds a exchange key and queue together setting up a subscription
		def receive(exchange,key,queue,opts \\ [persitent: false], server) do
      type = opts[:type]
			:amqp_channel.call server.channel, :"exchange.declare".
      new exchange: exchange, type: type, auto_delete: true, persistent: opts[:persistent]
			:amqp_channel.call server.channel, :"queue.declare".new queue: queue, auto_delete: true
			:amqp_channel.call server.channel, :"queue.bind".new queue: queue, exchange: exchange, routing_key: key
			{ :"basic.consume_ok", ctag } = :amqp_channel.call server.channel, :"basic.consume".new queue: queue
			server.ctag(ctag)	
		end

		def wait(callback,server) do
			receive do
				{ :"basic.consume_ok", _ctag } -> 
					server.wait(callback)
				{ { :"basic.deliver", _ctag, tag, _redelivered, exchange, key }, 
				  {:amqp_msg, {:P_basic, content_type, _content_encoding, 
						_headers, _delivery_mode, _priority, 
						_correlation_id, _reply_to, _expiration, 
						_message_id, _timestamp, _type, _user_id, 
						_app_id, _cluster_id }, payload } } ->
					:amqp_channel.cast server.channel, :"basic.ack".new delivery_tag: tag
					try do
						callback.(payload,  content_type: content_type, routing_key: key, exchange: exchange )
					after
						server.wait(callback)
					end
				any ->
					IO.puts "Unknown message #{any}"
					server.wait(callback)
			end		
		end
	end
	defrecord Uri, connstr: "amqp://guest:guest@localhost:5672/", user: "guest", password: "guest", host: "localhost", port: 5672, 
			vhost: "/", exchange: "test-in", key: "#", queue: "test-in", destination: "test-out", route: "test" do
		def parse(uri, self) when is_list(uri) do self.parse( :binary.list_to_bin ) end
		def parse(uri, self) when is_binary(uri) do
      case :lists.nthtail(1, Regex.run(~r{(amqp://([^:]+):([^@]+)@([^:]+):(\d+)/([^/]*))(/([^/]+)/([^/]+)/*([^/]*)/*([^/]*)/*([^/]*)/)*}, URI.decode(uri))) do
			                                    [ connstr, user, password, host, port, vhost, exchange, key, queue, destination, route ] -> 
			                                      self.connstr(connstr).user(user).password(password).host(host).port(port).vhost(vhost).exchange(exchange).key(key).queue(queue).destination(destination).route(route)	
			                                    [ connstr, user, password , host, port, vhost , _ , exchange,  key , queue, _, _ |  _] -> 
                                            IO.puts "#{exchange}, #{key}, #{queue}"
			                                      self.connstr(connstr).user(user).password(password).host(host).port(port).vhost(vhost).exchange(exchange).key(key).queue(queue)
			                                    [ connstr, user, password, host, port, vhost ] -> 
			                                      self.connstr(connstr).user(user).password(password).host(host).port(port).vhost(vhost)
                                        end
		end
	end
end
