require "net/http"
require "uri"

class RancherApi
  def initialize
    @api_url = ENV['CATTLE_URL']
    @access_key = ENV["CATTLE_ACCESS_KEY"]
    @secret_key = ENV["CATTLE_SECRET_KEY"]
  end

  def get(url)
    uri = resolve_uri(url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth(@access_key, @secret_key)
    response = http.request(request)
    JSON.parse(response.body)
  end

  def get_all(url, &block)
    Enumerator.new do |enum|
      loop do
        response = get(url)
        items = response["data"]
        items.each { |item| enum.yield item }
        break unless response["pagination"] && response["pagination"]["next"]
        url = response["pagination"]["next"]
      end
    end
  end

  def post(url)
    uri = resolve_uri(url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.request_uri)
    request.basic_auth(@access_key, @secret_key)
    response = http.request(request)
    JSON.parse(response.body)
  end

  def perform_action(item, action)
    action_url = item["links"][action]
    if action_url
      item = post(action_url)["data"]
      wait_for_transition_complete(item)
    end
  end

  def wait_for_transition_complete(item, timeout_secs = 30, poll_interval_secs = 3)
    start_time = Time.now
    elapsed_secs = 0
    while item["transitioning"] == "yes" && elapsed_secs < timeout_secs
      sleep(poll_interval_secs)
      item = get(item["links"]["self"])
      elapsed_secs = Time.now - start_time
    end

    item["transitioning"] == "yes" ? nil : item
  end


  private

  def resolve_uri(url)
    uri = URI.parse(url)
    if !uri.host
      uri = URI.parse("#{@api_url}#{url}")
    end
    uri
  end

end
