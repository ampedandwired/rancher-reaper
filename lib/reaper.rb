#!/usr/bin/env ruby

require "set"
require "logger"
require "aws-sdk"
require_relative "rancher_api"

class RancherAwsHostReaper
  DEFAULT_INTERVAL_SECS = 30
  DEFAULT_HOSTS_PER_PAGE = 100

  def initialize(
      interval_secs: DEFAULT_INTERVAL_SECS,
      hosts_per_page: DEFAULT_HOSTS_PER_PAGE,
      dry_run: false,
      instance_id_label_name: "aws.instance_id",
      availability_zone_label_name: "aws.availability_zone")

    @interval_secs = interval_secs
    @hosts_per_page = hosts_per_page
    @dry_run = dry_run
    @instance_id_label_name = instance_id_label_name
    @availability_zone_label_name = availability_zone_label_name
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
      if @interval_secs >= 0
        sleep @interval_secs
      else
        break
      end
    end
    @logger.info("Rancher AWS host reaper exited")
  end


  private

  def reap_hosts
    @logger.info("Reaping terminated AWS hosts...")
    @logger.warn("*** Dry run - no changes will be applied") if @dry_run

    reconnecting_hosts.each do |host|
      delete_rancher_host(host) if host_terminated?(host)
    end
    disconnected_hosts.each do |host|
      delete_rancher_host(host) if host_terminated?(host)
    end

  end

  def delete_rancher_host(host)
    @logger.info("Deleting rancher host #{host["hostname"]}")
    if !@dry_run
      if host["state"] == "active"
        @logger.info("Deactivating Rancher host #{host["hostname"]}")
        host = @rancher_api.perform_action(host, "deactivate")
      end
      if host["state"] == "inactive"
        @logger.info("Removing Rancher host #{host["hostname"]}")
        host = @rancher_api.perform_action(host, "remove")
      end
      if host["state"] == "removed"
        @logger.info("Purging Rancher host #{host["hostname"]}")
        host = @rancher_api.perform_action(host, "purge")
      end
    end
    @logger.info("Deleted rancher host #{host["hostname"]}")
    host
  end

  def host_terminated?(host)
    is_terminated = false
    if has_aws_tags?(host)
      begin
        ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region(host)))
        instance = ec2.instance(instance_id(host))
        is_terminated = !instance.exists? || instance.state.name == "terminated"
        if !is_terminated
          @logger.info("Host #{host["hostname"]} is reconnecting but not terminated in AWS - skipping")
        end
      rescue Aws::EC2::Errors::InvalidInstanceIDMalformed
        @logger.info("Host #{host["hostname"]} has a malformed AWS instance id label - skipping")
      end
    else
      # We could possibly do a "best effort" search for the instance based on Rancher hostname here.
      # For now err on the side of safety and skip it.
      @logger.info("Host #{host["hostname"]} is not labelled correctly with AWS instance ID and region - skipping")
    end
    is_terminated
  end

  def reconnecting_hosts
    @rancher_api.get_all("/hosts?limit=#{@hosts_per_page}&agentState=reconnecting")
  end

  def disconnected_hosts
    @rancher_api.get_all("/hosts?limit=#{@hosts_per_page}&agentState=disconnected")
  end

  def has_aws_tags?(host)
    instance_id(host) && region(host)
  end

  def instance_id(host)
    host["labels"][@instance_id_label_name]
  end

  def region(host)
    region = nil
    availability_zone = host["labels"][@availability_zone_label_name]
    if availability_zone
      region = availability_zone[0..-2]
      if !valid_region?(region)
        region = nil
        @logger.warn("Host #{host["hostname"]} is labelled with an invalid availability zone: #{availability_zone}")
      end
    end
    region
  end

  def valid_region?(region)
    @_regions ||= begin
      Aws::EC2::Client.new(region: region).describe_regions.regions.map { |r| r.region_name } rescue nil
    end
    @_regions ? @_regions.include?(region) : false
  end

end
