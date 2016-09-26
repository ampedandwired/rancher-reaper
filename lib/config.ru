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

mandatory_variables = ["CATTLE_URL", "CATTLE_ACCESS_KEY", "CATTLE_SECRET_KEY", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"]
mandatory_variables.each { |v| verify_environment_variable_set(v) }

interval_secs = (ENV['REAPER_INTERVAL_SECS'] || 30).to_i
dry_run = ENV["REAPER_DRY_RUN"] == "true"

Thread.start do
  begin
    RancherAwsHostReaper.new(interval_secs: interval_secs, dry_run: dry_run).run
  rescue => error
    logger.error(error)
  end
end

run ->(env) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
