require 'slack-ruby-client'
require 'logger'
require './db-slack-rsvp'
require './key-gen'
require './admin-list'


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


    # 管理者

    @admin_list = AdminList.new


    # DB を開く

    @db = DBSlackRsvp.new


    # キーワード生成器

    @key_gen = KeyGen.new(@db)


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
        elsif message_attend?(data)
          message_attend(data)
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


  # 指定した日のキーワードを取得する

  def get_key(time)
    from = time.strftime('%Y-%m-%d 00:00:00')
    to = time.strftime('%Y-%m-%d 23:59:59')
    @db.exec 'days-range', { :from => from, :to => to } do |_, _, key, _|
      return key
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
    nowstr = now.strftime('%Y-%m-%d %X')
    res = nil
    if @admin_list.is_op?(data['user'])
      @db.transaction do
        user = get_responsibility(now)
        if user == nil
          key = @key_gen.generate
          user = data['user']
          @db.exec 'days-insert', { :datetime => nowstr, :key => key, :responsibility => user }
          @db.exec 'attendees-insert', { :datetime => nowstr, :attendee => user }
          res = "今日のキーワードは '#{key}' だよ。"
        else
          res = "<@#{user}> が既に出欠確認を始めているよ。"
        end
      end
      @rt_client.message channel: data['channel'], text: res unless res == nil
    else
      res = nil
      user = get_responsibility(now)
      if user.nil?
        res = '出欠確認を開始する権限がないよ。'
      else
        res = "出欠確認を開始する権限がないよ。<@#{user}> が既に出欠確認を始めているよ。"
      end
      @rt_client.message channel: data['channel'], text: res unless res.nil?
    end
  end


  # 出席メッセージ

  def message_attend?(data)
    not data['text'].upcase.match(/^[AC-HJKPR-Y3-578]{4}$/).nil?
  end

  def message_attend(data)
    now = Time.now
    nowstr = now.strftime('%Y-%m-%d %X')
    key = get_key(now)
    if key.nil?
      @rt_client.message channel: data['channel'], text: '今日の出欠確認はまだ始まっていないみたいだよ。'
    elsif data['text'].upcase != key
      @rt_client.message channel: data['channel'], text: 'キーワードが違うよ。'
    elsif already_attended?(now, data['user'])
      @rt_client.message channel: data['channel'], text: "今日の <@#{data['user']}> の出席は確認済みだよ。"
    else
      @db.exec 'attendees-insert', { :datetime => nowstr, :attendee => data['user'] }
      @rt_client.message channel: data['channel'], text: "今日の <@#{data['user']}> の出席を確認したよ。"
    end
  end

  def already_attended?(time, user)
    from = time.strftime('%Y-%m-%d 00:00:00')
    to = time.strftime('%Y-%m-%d 23:59:59')
    @db.exec 'attendees-range-user', { :from => from, :to => to, :user => user } do |row|
      return true
    end
    return false
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

