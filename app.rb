require 'slack-ruby-client'
require 'logger'
require './db_slack_rsvp'
require './words'

log = Logger.new('slack_rsvp.log')

db = DBSlackRsvp.new

Slack.configure do |conf|
  conf.token = File.open('slack_token').read.chomp
end

client = Slack::RealTime::Client.new

client.on :hello do
  log.info(':hello')
  puts 'connected.'
end

client.on :message do |data|
  log.info(':message')
  log.info(data.to_json)
  if $words_rsvp.include?(data['text'])
    client.message channel: data['channel'], text:'未実装だよ。ちょっと待っててね。'
  else
    client.message channel: data['channel'], text:'？'
  end
end

client.start!

