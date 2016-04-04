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

def format_log_message(data)
  "#{data['channel']} #{data['user']} \"#{data['text'].gsub(/\\/, '\\\\\\\\').gsub(/\r\n|\r|\n/, '\\n')}\""
end

def get_responsibility(time)
  from = time.strftime('%Y-%m-%d 00:00:00')
  to = time.strftime('%Y-%m-%d 23:59:59')
  db.exec 'days-range', { :from => from, :to => to } do |_, _, _, responsibility|
    return responsibility
  end
  return nil
end

client = Slack::RealTime::Client.new(logger: Logger.new('log/client.log'))

client.on :hello do
  puts 'connected.'
end

client.on :message do |data|
  log.info(format_log_message(data))
  if $words_rsvp.any? { |w| data['text'].start_with?(w) }
    now = Time.now
    user = get_responsibility(now)
    if user == nil
      key = 'AAAA'
      user = data['user']
      db.exec 'days-insert', {:datetime => now.strftime('%Y-%m-%d %X'), :key => key, :responsibility => user}
      client.message channel: data['channel'], text:"今日のキーワードは '#{key}' だよ。"
    else
      client.message channel: data['channel'], text:"#{user} が既に出欠確認を始めてるよ。"
    end
  else
    client.message channel: data['channel'], text:'？'
  end
end

client.start!

