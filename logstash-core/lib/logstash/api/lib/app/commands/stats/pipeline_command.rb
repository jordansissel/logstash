# encoding: utf-8
require "app/command"

class LogStash::Api::PipelineStatsCommand < LogStash::Api::Command

  def run
    #return whatever is comming out of the snapshot event, this obvoiusly
    #need to be tailored to the right metrics for this command.
    stats =  LogStash::Json.load(service.get(:pipelines_stats))
    stats["stats"]["pipelines"]
  end

end
