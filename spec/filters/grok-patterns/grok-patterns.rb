# encoding: utf-8
require "test_utils"

# Test suite for the grok patterns defined in patterns/java
# For each pattern:
#  - a sample is considered valid i.e. "should match"  where message == result
#  - a sample is considered invalid i.e. "should NOT match"  where message != result
#
describe "base grok patterns" do
  extend LogStash::RSpec

  describe "PROG" do
    config <<-CONFIG
      filter {
        grok {
          match => { "message" => "^%{PROG:prog}$" }
        }
      }
    CONFIG

    context "should match" do
      [
        "run-parts(/some/path)"
      ].each do |message|
        sample message do 
          insist { subject["prog"] } == message
        end
      end
    end
  end

  describe "SYSLOGLINE" do
    config <<-CONFIG
      filter {
        grok {
          match => { "message" => "^%{SYSLOGLINE}$" }
        }
      }
    CONFIG

    context "should match" do
      {
        "<77>Aug 28 15:01:01 lb-tds-gs0001 run-parts(/etc/cron.hourly)[8136]: starting mcelog.cron" => {
          "program" => "run-parts(/etc/cron.hourly)"
        }
      ].each do |message, fields|
        sample message do 
          fields.each do |name, value|
            insist { subject[name] } == value
          end
        end
      end
    end
  end
end
