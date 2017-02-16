require "hashie"
require "spec_helper.rb"

describe RancherAwsHostReaper do
  before do
    setup_aws_regions
  end

  it "deletes hosts in rancher that have been terminated in aws" do
    rancher_api = setup_hosts([
      create_host("0", rancher_state: "active", aws_instance_state: "terminated", availability_zone: "us-invalid-1"),
      create_host("0a", rancher_state: "active", aws_instance_state: "terminated", availability_zone: "us-invalid-1"),
      create_host("1", rancher_state: "active", aws_instance_state: "terminated"),
      create_host("2", rancher_state: "inactive", aws_instance_state: "terminated"),
      create_host("3", rancher_state: "removed", aws_instance_state: "terminated"),
      create_host("4", rancher_state: "purged", aws_instance_state: "terminated"),
      create_host("5", rancher_state: "active", aws_instance_state: "running"),
      create_host("6", rancher_state: "active", aws_instance_state: nil)
    ])

    expect_actions(rancher_api, "0", [])
    expect_actions(rancher_api, "0a", [])
    expect_actions(rancher_api, "1", ["deactivate", "remove", "purge"])
    expect_actions(rancher_api, "2", ["remove", "purge"])
    expect_actions(rancher_api, "3", ["purge"])
    expect_actions(rancher_api, "4", [])
    expect_actions(rancher_api, "5", [])
    expect_actions(rancher_api, "6", [])

    RancherAwsHostReaper.new(interval_secs: -1).run
  end

end


def create_host(hostname, instance_id: hostname, rancher_state: "active", availability_zone: "us-west-1a", aws_instance_state: "terminated")
  host = {
    rancher: {
      "hostname" => hostname,
      "state" => rancher_state,
      "labels" => {}
    }
  }

  host[:rancher]["labels"]["aws.instance_id"] = instance_id if instance_id
  host[:rancher]["labels"]["aws.availability_zone"] = availability_zone if availability_zone
  host[:aws] = aws_instance_state ? Hashie::Mash.new({ state: { name: aws_instance_state } }) : nil
  host
end


def setup_hosts(hosts)
  ENV['CATTLE_URL'] = "http://rancher_host"
  ENV["CATTLE_ACCESS_KEY"] = "key"
  ENV["CATTLE_SECRET_KEY"] = "secret"

  rancher_api = double(RancherApi)
  allow(RancherApi).to receive(:new).and_return(rancher_api)
  rancher_hosts = hosts.collect { |h| h[:rancher] }
  expect(rancher_api).to receive(:get_all).with("/hosts?limit=#{RancherAwsHostReaper::DEFAULT_HOSTS_PER_PAGE}&agentState=reconnecting").and_return(rancher_hosts)
expect(rancher_api).to receive(:get_all).with("/hosts?limit=#{RancherAwsHostReaper::DEFAULT_HOSTS_PER_PAGE}&agentState=disconnected").and_return([])

  ec2 = double(Aws::EC2::Resource)
  allow(Aws::EC2::Resource).to receive(:new).and_return(ec2)
  aws_instances = hosts.collect { |h| h[:aws] }
  allow(ec2).to receive(:instance) do |instance_id|
    host = hosts.find { |h| h[:rancher]["labels"]["aws.instance_id"] == instance_id }
    instance = host[:aws]
    instance ? instance : raise(Aws::EC2::Errors::InvalidInstanceIDNotFound.new("Instance #{instance_id} not found", ""))
  end

  rancher_api
end

def expect_actions(rancher_api, hostname, actions)
  expect_action(rancher_api, hostname, "deactivate", "inactive", should_not_receive: !actions.include?("deactivate"))
  expect_action(rancher_api, hostname, "remove", "removed", should_not_receive: !actions.include?("remove"))
  expect_action(rancher_api, hostname, "purge", "purged", should_not_receive: !actions.include?("purge"))
end

def expect_action(rancher_api, hostname, action, new_state, should_not_receive: false)
  receive_action = receive(:perform_action).with(hash_including({"hostname" => hostname}), action) do |host, _|
    host["state"] = new_state
    host
  end

  if should_not_receive
    expect(rancher_api).to_not receive_action
  else
    expect(rancher_api).to receive_action
  end
end

def setup_aws_regions
  valid_regions = ["ap-south-1", "eu-west-1", "ap-northeast-2", "ap-northeast-1", "sa-east-1", "ap-southeast-1", "ap-southeast-2", "eu-central-1", "us-east-1", "us-east-2", "us-west-1", "us-west-2"]

  ec2 = double(Aws::EC2::Client)
  allow(ec2).to receive(:describe_regions).and_return(Hashie::Mash.new(
    regions: valid_regions.map { |r| {region_name: r} }
  ))

  ec2_invalid = double(Aws::EC2::Client)
  allow(ec2_invalid).to receive(:describe_regions).and_raise("Invalid region")

  allow(Aws::EC2::Client).to receive(:new) do |params|
    valid_regions.include?(params[:region]) ? ec2 : ec2_invalid
  end
end
