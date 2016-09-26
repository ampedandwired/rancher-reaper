#!/usr/bin/env ruby

require "set"
require "logger"
require "aws-sdk"
require_relative "rancher_api"

class RancherAwsHostReaper
  def initialize(interval_secs: 30, hosts_per_page: 100, dry_run: false)
    @interval_secs = interval_secs
    @hosts_per_page = hosts_per_page
    @dry_run = dry_run
    @logger = Logger.new(STDOUT)
    @rancher_api = RancherApi.new
  end

  def run
    @logger.info("Rancher AWS host reaper started")
    while true
      begin
        reap_hosts
      rescue => error
        @logger.error(error)
      end
      sleep @interval_secs
    end
    @logger.info("Rancher AWS host reaper exited")
  end


  private

  def reap_hosts
    @logger.info("Reaping terminated AWS hosts...")
    @logger.warn("*** Dry run - no changes will be applied") if @dry_run
    #terminated_hosts.each { |host| delete_rancher_host(host) }
    reconnecting_hosts.each do |host|
      delete_rancher_host(host) if host_terminated?(host)
    end
  end

  def delete_rancher_host(host)
    @logger.info("Deleting rancher host #{host["hostname"]}")
    if !@dry_run
      if host["state"] == "active"
        @rancher_api.perform_action(host, "deactivate")
      end
      if host["state"] == "inactive"
        @rancher_api.perform_action(host, "remove")
      end
    end
    host
  end

  def host_terminated?(host)
    is_terminated = false
    if has_aws_tags?(host)
      is_terminated = terminated_in_aws?(host)
      if !is_terminated
        @logger.info("Host #{host["hostname"]} is reconnecting but not terminated in AWS - skipping")
      end
    else
      # We could possibly do a "best effort" search for the instance based on Rancher hostname here.
      # For now err on the side of safety and skip it.
      @logger.info("Host #{host["hostname"]} is not labelled with AWS info - skipping")
    end
    is_terminated
  end

  def terminated_in_aws?(host)
    is_terminated = false
    ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region(host)))
    begin
      instance = ec2.instance(instance_id(host))
      is_terminated = instance.state.name == "terminated"
    rescue Aws::EC2::Errors::InvalidInstanceIDNotFound
      # We could possibly allow an option to also delete hosts that are not found.
      # For now err on the side of safety and skip it.
      @logger.info("Host #{host["hostname"]} not found in AWS - skipping")
    end
    is_terminated
  end

  def reconnecting_hosts
    @rancher_api.get_all("/hosts?limit=#{@hosts_per_page}&agentState=reconnecting")
  end

  def has_aws_tags?(host)
    instance_id(host) && region(host)
  end

  def instance_id(host)
    host["labels"]["aws.instance_id"]
  end

  def region(host)
    availability_zone = host["labels"]["aws.availability_zone"]
    availability_zone ? availability_zone[0..-2] : nil
  end

end
