require 'slack-ruby-client'
require 'logger'
require './db-slack-rsvp'


class App

  def initialize

    # 単語リスト

    @words_rsvp = [
      '出席', '出欠', '出席確認', '出欠確認',
      'RSVP', 'R.S.V.P.', 'rsvp'
    ]

    # ログ

    FileUtils.mkdir('log') unless FileTest.exist?('log')
    @log = Logger.new('log/slack-rsvp.log')


    # DB を開く

    @db = DBSlackRsvp.new


    # Slack クライアント

    Slack.configure do |conf|
      conf.token = File.open('slack-token').read.chomp
    end

    @rt_client = Slack::RealTime::Client.new(logger: Logger.new('log/rt-client.log'))
    @wb_client = Slack::Web::Client.new(logger: Logger.new('log/wb-client.log'))

    @ims = @wb_client.im_list['ims']


    # [event] 接続

    @rt_client.on :hello do
      puts 'connected.'
    end


    # [event] メッセージ

    @rt_client.on :message do |data|
      @log.info(format_log_message(data))
      if im?(data['channel'])
        if message_rsvp?(data)
          message_rsvp(data)
        else
          message_unknown(data)
        end
      end
    end

  end


  # 指定した日の代表者のユーザー ID を取得する

  def get_responsibility(time)
    from = time.strftime('%Y-%m-%d 00:00:00')
    to = time.strftime('%Y-%m-%d 23:59:59')
    @db.exec 'days-range', { :from => from, :to => to } do |_, _, _, responsibility|
      return responsibility
    end
    return nil
  end


  def format_log_message(data)
    "#{data['channel']} #{data['user']} \"#{data['text'].gsub(/\\/, '\\\\\\\\').gsub(/\r\n|\r|\n/, '\\n')}\""
  end


  def im?(channel)
    @ims.any? { |im| im['id'] == channel }
  end


  # 出欠確認開始メッセージ

  def message_rsvp?(data)
    @words_rsvp.any? { |w| data['text'].start_with?(w) }
  end

  def message_rsvp(data)
    now = Time.now
    res = nil
    @db.transaction do
      user = get_responsibility(now)
      if user == nil
        key = 'AAAA'
        user = data['user']
        @db.exec 'days-insert', {:datetime => now.strftime('%Y-%m-%d %X'), :key => key, :responsibility => user}
        res = "今日のキーワードは '#{key}' だよ。"
      else
        res = "<@#{user}> が既に出欠確認を始めているよ。"
      end
    end
    @rt_client.message channel: data['channel'], text: res unless res == nil
  end


  # 未知のメッセージ

  def message_unknown(data)
    @rt_client.message channel: data['channel'], text:'？'
  end


  # Slack クライアント起動

  def start!
    @rt_client.start!
  end

end


app = App.new
app.start!

