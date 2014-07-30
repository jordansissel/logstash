# encoding: utf-8
require "logstash/inputs/base"
require "logstash/inputs/threadable"
require "logstash/namespace"

# This input will read events from a Redis instance; it supports both Redis channels and lists.
# The list command (BLPOP) used by Logstash is supported in Redis v1.3.1+, and
# the channel commands used by Logstash are found in Redis v1.3.8+. 
# While you may be able to make these Redis versions work, the best performance
# and stability will be found in more recent stable versions.  Versions 2.6.0+
# are recommended.
#
# For more information about Redis, see <http://redis.io/>
#
# Redis 2.6.0 or newer required.
class LogStash::Inputs::Redis < LogStash::Inputs::Threadable
  config_name "redis"
  milestone 2

  default :codec, "json"

  # The `name` configuration is used for logging in case there are multiple instances.
  # This feature has no real function and will be removed in future versions.
  config :name, :validate => :string, :default => "default", :deprecated => true

  # The hostname of your Redis server.
  config :host, :validate => :string, :default => "127.0.0.1"

  # The port to connect on.
  config :port, :validate => :number, :default => 6379

  # The Redis database number.
  config :db, :validate => :number, :default => 0

  # Initial connection timeout in seconds.
  config :timeout, :validate => :number, :default => 5

  # Password to authenticate with. There is no authentication by default.
  config :password, :validate => :password

  # This setting is invalid and deprecated.
  config :queue, :validate => :string, :deprecated => true

  # The name of a Redis list or channel.
  config :key, :validate => :string, :required => true

  # Specify either list or channel.  If `data\_type` is `list`, then we will BLPOP the
  # key.  If `data\_type` is `channel`, then we will SUBSCRIBE to the key.
  # If `data\_type` is `pattern_channel`, then we will PSUBSCRIBE to the key.
  # TODO: change required to true
  config :data_type, :validate => [ "list", "channel", "pattern_channel" ], :default => "list"

  # When `data_type` is `list`, we will fetch items in bulk from Redis. This
  # setting configures how many events to fetch. The goal is to ammortize the 
  # network round-trip cost of querying Redis. Bulk fetching is done using a
  # custom Lua script that attempts `batch_count` `RPOP` calls on Redis.
  #
  # To disable bulk fetching, set `batch_count` to `.
  config :batch_count, :validate => :number, :default => 100

  public
  def register
    require 'redis'
    @redis = nil

    # TODO remove after setting key and data_type to true
    if @queue
      @logger.warn("redis input: The `queue` setting is deprecated. Please use the `key` setting.")
      @key = @queue
    end

    @logger.info("Registering Redis", :data_type => @data_type, :key => @key, :host => @host)
  end # def register


  private
  def connect
    redis = Redis.new(
      :host => @host,
      :port => @port,
      :timeout => @timeout,
      :db => @db,
      :password => @password.nil? ? nil : @password.value
    )
    load_batch_script(redis) if @data_type == 'list' && (@batch_count > 1)
    return redis
  end # def connect

  private
  def load_batch_script(redis)
    #A Redis Lua EVAL script to fetch a count of keys
    #in case count is bigger than current items in queue whole queue will be returned without extra nil values
    redis_script = <<EOF
          local i = tonumber(ARGV[1])
          local res = {}
          local length = redis.call('llen',KEYS[1])
          if length < i then i = length end
          while (i > 0) do
            local item = redis.call("lpop", KEYS[1])
            if (not item) then
              break
            end
            table.insert(res, item)
            i = i-1
          end
          return res
EOF
    @redis_script_sha = redis.script(:load, redis_script)
  end

  private
  def queue_event(msg, output_queue)
    begin
      @codec.decode(msg) do |event|
        decorate(event)
        output_queue << event
      end
    rescue => e # parse or event creation error
      @logger.error("Failed to create event", :message => msg, :exception => e,
                    :backtrace => e.backtrace);
    end
  end

  private
  def list_listener(redis, output_queue)

    # blpop returns the 'key' read from as well as the item result
    # we only care about the result (2nd item in the list).
    item = redis.blpop(@key, 0)[1]

    # blpop failed or .. something?
    # TODO(sissel): handle the error
    return if item.nil?
    queue_event(item, output_queue)

    # If @batch_count is 1, there's no need to continue.
    return if @batch_count == 1

    begin
      redis.evalsha(@redis_script_sha, [@key], [@batch_count-1]).each do |item|
        queue_event(item, output_queue)
      end

      # Below is a commented-out implementation of 'batch fetch'
      # using pipelined LPOP calls. This in practice has been observed to
      # perform exactly the same in terms of event throughput as
      # the evalsha method. Given that the EVALSHA implementation uses
      # one call to Redis instead of N (where N == @batch_count) calls,
      # I decided to go with the 'evalsha' method of fetching N items
      # from Redis in bulk.
      #redis.pipelined do
        #error, item = redis.lpop(@key)
        #(@batch_count-1).times { redis.lpop(@key) }
      #end.each do |item|
        #queue_event(item, output_queue) if item
      #end
      # --- End commented out implementation of 'batch fetch'
    rescue Redis::CommandError => e
      if e.to_s =~ /NOSCRIPT/ then
        @logger.warn("Redis may have been restarted, reloading Redis batch EVAL script", :exception => e);
        load_batch_script(redis)
        retry
      else
        raise e
      end
    end
  end

  private
  def channel_listener(redis, output_queue)
    redis.subscribe @key do |on|
      on.subscribe do |channel, count|
        @logger.info("Subscribed", :channel => channel, :count => count)
      end

      on.message do |channel, message|
        queue_event message, output_queue
      end

      on.unsubscribe do |channel, count|
        @logger.info("Unsubscribed", :channel => channel, :count => count)
      end
    end
  end

  private
  def pattern_channel_listener(redis, output_queue)
    redis.psubscribe @key do |on|
      on.psubscribe do |channel, count|
        @logger.info("Subscribed", :channel => channel, :count => count)
      end

      on.pmessage do |ch, event, message|
        queue_event message, output_queue
      end

      on.punsubscribe do |channel, count|
        @logger.info("Unsubscribed", :channel => channel, :count => count)
      end
    end
  end

  # Since both listeners have the same basic loop, we've abstracted the outer
  # loop.
  private
  def listener_loop(listener, output_queue)
    while !finished?
      begin
        @redis ||= connect
        self.send listener, @redis, output_queue
      rescue Redis::CannotConnectError => e
        @logger.warn("Redis connection problem", :exception => e)
        sleep 1
        @redis = connect
      rescue Redis::CommandError => e
        if e.to_s =~ /ERR unknown command 'script'/
          @logger.error("Your redis server is too old and does not support the `script` command which is required for bulk reads. Please upgrade your redis server to at least redis version 2.6.")
          return nil
        else
          raise e
        end
      rescue => e # Redis error
        @logger.warn("Failed to get event from Redis", :name => @name,
                     :exception => e, :backtrace => e.backtrace)
        raise e
      end
    end # while !finished?
  end # listener_loop

  public
  def run(output_queue)
    if @data_type == 'list'
      listener_loop :list_listener, output_queue
    elsif @data_type == 'channel'
      listener_loop :channel_listener, output_queue
    else
      listener_loop :pattern_channel_listener, output_queue
    end
  end # def run

  public
  def teardown
    if @data_type == 'channel' and @redis
      @redis.unsubscribe
      @redis.quit
      @redis = nil
    end
    if @data_type == 'pattern_channel' and @redis
      @redis.punsubscribe
      @redis.quit
      @redis = nil
    end
  end
end # class LogStash::Inputs::Redis
