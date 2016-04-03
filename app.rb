require 'slack-ruby-client'

Slack.configure do |conf|
  conf.token = File.open('slack_token').read.chomp
end

client = Slack::RealTime::Client.new

client.on :hello do
  puts 'connected.'
end

client.on :message do |data|
  puts data.to_json
end

client.start!
