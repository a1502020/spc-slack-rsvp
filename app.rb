require 'slack-ruby-client'
require 'logger'
require './db-slack-rsvp'
require './words'

FileUtils.mkdir('log') unless FileTest.exist?('log')
log = Logger.new('log/slack-rsvp.log')

db = DBSlackRsvp.new

Slack.configure do |conf|
  conf.token = File.open('slack-token').read.chomp
end

client = Slack::RealTime::Client.new(logger: Logger.new('log/client.log'))

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

