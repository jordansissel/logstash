# encoding: utf-8
require "logstash/namespace"
require "logstash/outputs/http"

# This output allows you to write events to [HipChat](https://www.hipchat.com/).
#
class LogStash::Outputs::HipChat < LogStash::Outputs::Base

  config_name "hipchat"
  milestone 1

  # The HipChat authentication token.
  config :token, :validate => :string, :required => true

  # The ID or name of the room.
  config :room_id, :validate => :string, :required => true

  # The name the message will appear be sent from.
  config :from, :validate => :string, :default => "logstash"

  # Whether or not this message should trigger a notification for people in the room.
  config :trigger_notify, :validate => :boolean, :default => false

  # Background color for message.
  # HipChat currently supports one of "yellow", "red", "green", "purple",
  # "gray", or "random". (default: yellow)
  config :color, :validate => :string, :default => "yellow"

  # Message format to send, event tokens are usable here.
  config :format, :validate => :string, :default => "%{message}"

  public
  def register
    require "ftw"
    require "uri"

    @agent = FTW::Agent.new
    l = Cabin::Channel.get
    l.subscribe(STDOUT)
    l.level = :debug
  end # def register

  public
  def receive(event)
    return unless output?(event)

    hipchat_data = Hash.new
    #hipchat_data['from']    = @from
    hipchat_data['color']   = @color
    hipchat_data['notify']  = @trigger_notify
    hipchat_data['message'] = event.sprintf(@format)
    hipchat_data['message_format'] = "html"

    @logger.debug("HipChat data", :hipchat_data => hipchat_data, :url => @url)

    url = "https://api.hipchat.com/v2/room/#{CGI.escape(@room_id).gsub("+", "%20")}/notification?auth_token=#{@token}"
    begin
      # hack for now because ruby 2.1 changed the meaning of 'public/private' ?
      request = @agent.request("POST", url, {})
      request["Content-Type"] = "application/json"
      request.body = hipchat_data.to_json
      response = @agent.execute(request)

      # Consume body to let this connection be reused
      rbody = ""
      response.read_body { |c| rbody << c }
      #puts rbody
    rescue Exception => e
      @logger.warn("Unhandled exception", :request => request, :response => response, :exception => e, :stacktrace => e.backtrace)
    end
  end # def receive

  # shamelessly lifted this from the LogStash::Outputs::Http, I'd rather put this
  # in a common place for both to use, but unsure where that place is or should be
  def encode(hash)
    return hash.collect do |key, value|
      CGI.escape(key) + "=" + CGI.escape(value)
    end.join("&")
  end # def encode

end # class LogStash::Outputs::HipChat
