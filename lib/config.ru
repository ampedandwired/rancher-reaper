require 'logger'
require 'rack'
require 'thin'
require_relative 'reaper'

Thin::Logging.silent = true
logger = Logger.new(STDOUT)

def verify_environment_variable_set(var_name)
  if !ENV[var_name]
    puts "Environment variable #{var_name} not set - exiting"
    exit 1
  end
end

mandatory_variables = ["CATTLE_URL", "CATTLE_ACCESS_KEY", "CATTLE_SECRET_KEY"]
mandatory_variables.each { |v| verify_environment_variable_set(v) }

interval_secs = Integer(ENV['REAPER_INTERVAL_SECS']) rescue 30
dry_run = ENV["REAPER_DRY_RUN"] == "true"
instance_id_label_name = ENV["REAPER_INSTANCE_ID_LABEL_NAME"] || "aws.instance_id"
availability_zone_label_name = ENV["REAPER_AVAILABILITY_ZONE_LABEL_NAME"] || "aws.availability_zone"

Thread.start do
  begin
    RancherAwsHostReaper.new(
      interval_secs: interval_secs,
      dry_run: dry_run,
      instance_id_label_name: instance_id_label_name,
      availability_zone_label_name: availability_zone_label_name).run
  rescue => error
    logger.error(error)
    exit 1
  end
  exit
end

run ->(env) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
