require 'slack-ruby-client'
require 'logger'
require './db-slack-rsvp'
require './words'


# ログ

FileUtils.mkdir('log') unless FileTest.exist?('log')
log = Logger.new('log/slack-rsvp.log')

def format_log_message(data)
  "#{data['channel']} #{data['user']} \"#{data['text'].gsub(/\\/, '\\\\\\\\').gsub(/\r\n|\r|\n/, '\\n')}\""
end


# DB を開く

db = DBSlackRsvp.new


# 指定した日の代表者のユーザー ID を取得する

def get_responsibility(time)
  from = time.strftime('%Y-%m-%d 00:00:00')
  to = time.strftime('%Y-%m-%d 23:59:59')
  db.exec 'days-range', { :from => from, :to => to } do |_, _, _, responsibility|
    return responsibility
  end
  return nil
end


# Slack クライアント

Slack.configure do |conf|
  conf.token = File.open('slack-token').read.chomp
end

client = Slack::RealTime::Client.new(logger: Logger.new('log/client.log'))


# [event] 接続

client.on :hello do
  puts 'connected.'
end


# [event] メッセージ

client.on :message do |data|
  log.info(format_log_message(data))
  if $words_rsvp.any? { |w| data['text'].start_with?(w) }
    message_rsvp(data)
  else
    message_unknown(data)
  end
end


# 出欠確認開始メッセージ

def message_rsvp(data)
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
end


# 未知のメッセージ

def message_unknown(data)
  client.message channel: data['channel'], text:'？'
end


# Slack クライアント起動

client.start!

