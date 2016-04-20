require 'slack-ruby-client'
require 'logger'
require 'date'
require './db-slack-rsvp'
require './key-gen'
require './admin-list'


class App

  def initialize

    # 単語・パターンリスト

    @words_rsvp = [
      '出席', '出欠', '出席確認', '出欠確認',
      'RSVP', 'R.S.V.P.', 'rsvp'
    ]
    @patterns_attendee = [
      /^出席者一覧(.*)/, /^出席者(.*)/, /^(.*)の出席者/,
      /^出席一覧(.*)/, /^(.*)の出席一覧/,
      /^attendee(.*)/
    ]
    @words_today = [
      '今日', 'きょう', 'today', 'Today', 'TODAY', '本日'
    ]
    @words_yesterday = [
      '昨日', 'きのう', 'yesterday', 'Yesterday', 'YESTERDAY', '昨日'
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
      conf.token = File.read('slack-token').chomp
    end

    @rt_client = Slack::RealTime::Client.new(logger: Logger.new('log/rt-client.log'))
    @wb_client = Slack::Web::Client.new(logger: Logger.new('log/wb-client.log'))


    # [event] 接続

    @rt_client.on :hello do
      puts 'connected.'
    end


    # [event] メッセージ

    @rt_client.on :message do |data|
      @log.info(format_log_message(data))
      next if data['user'] == @rt_client.self['id']
      if im?(data['channel'])
        if message_reset?(data)
          message_reset(data)
        elsif message_attendee?(data)
          message_attendee(data)
        elsif message_rsvp?(data)
          message_rsvp(data)
        elsif message_attend?(data)
          message_attend(data)
        elsif message_op_add?(data)
          message_op_add(data)
        elsif message_op_remove?(data)
          message_op_remove(data)
        elsif message_op_list?(data)
          message_op_list(data)
        else
          message_unknown(data)
        end
      end
    end

  end


  # 指定した日のキーワードと代表者のユーザー ID を取得する

  def get_key_responsibility(time)
    from = time.strftime('%Y-%m-%d 00:00:00')
    to = time.strftime('%Y-%m-%d 23:59:59')
    res = nil
    @db.exec 'days-range', { :from => from, :to => to } do |_, _, key, responsibility|
      res = { 'key' => key, 'responsibility' => responsibility }
    end
    return res
  end

  def get_responsibility(time)
    kr = get_key_responsibility(time)
    return kr.nil? ? nil : kr['responsibility']
  end

  def get_key(time)
    kr = get_key_responsibility(time)
    return kr.nil? ? nil : kr['key']
  end


  # 文字列を DateTime に変換する
  # 変換できない場合は nil を返す
  def str_to_datetime(str)
    s = str.strip
    s.gsub!(/[0-9]+(年|月)/, '/')
    s.gsub!(/[0-9]+(日)/, ' ')
    s.gsub!(/[0-9]+(時)/, ':')
    s.gsub!(/[0-9]+(分)[0-9]+/, ':')
    s.gsub!(/[0-9]+(分|秒)/, ' ')
    s.strip!
    begin
      return DateTime.parse(s)
    rescue
    end
    return DateTime.now if @words_today.include?(s)
    return DateTime.now - 1 if @words_yesterday.include?(s)
    return nil
  end


  def format_log_message(data)
    "#{data['channel']} #{data['user']} \"#{data['text'].gsub(/\\/, '\\\\\\\\').gsub(/\r\n|\r|\n/, '\\n')}\""
  end


  def im?(channel)
    channel.start_with?('D')
  end


  # 出席者一覧メッセージ

  def message_attendee?(data)
    @patterns_attendee.any? { |p| data['text'].match(p) }
  end

  def message_attendee(data)
    @patterns_attendee.each do |p|
      data['text'].match(p) do |md|
        day = str_to_datetime(md[1])
        day = DateTime.now if day.nil?
        daystr = day.strftime('%Y/%m/%d')
        if get_responsibility(day).nil?
          @rt_client.message text: "#{daystr} は出席確認をしていないよ。", channel: data['channel']
        else
          from = day.strftime('%Y-%m-%d 00:00:00')
          to = day.strftime('%Y-%m-%d 23:59:59')
          list = []
          @db.exec 'attendees-range', { :from => from, :to => to } do |row|
            list.push row[2]
          end
          text = "#{daystr} の出席者一覧：\n"
          text += list.map { |user| "<@#{user}>" }.join(', ')
          @rt_client.message text: text, channel: data['channel']
        end
        return
      end
    end
  end


  # 出欠確認開始メッセージ

  def message_rsvp?(data)
    @words_rsvp.any? { |w| data['text'].include?(w) }
  end

  def message_rsvp(data)
    now = Time.now
    if @admin_list.op?(data['user'])
      message_rsvp_op(data, now)
    else
      message_rsvp_not_op(data, now)
    end
  end

  def message_rsvp_op(data, now)
    nowstr = now.strftime('%Y-%m-%d %X')
    res = nil
    @db.transaction do
      user = get_responsibility(now)
      if user.nil?
        key = @key_gen.generate
        user = data['user']
        @db.exec 'days-insert', { :datetime => nowstr, :key => key, :responsibility => user }
        @db.exec 'attendees-insert', { :datetime => nowstr, :attendee => user }
        res = "今日のキーワードは '#{key}' だよ。"
      else
        res = "<@#{user}> が既に出欠確認を始めているよ。"
      end
    end
    @rt_client.message channel: data['channel'], text: res unless res.nil?
  end

  def message_rsvp_not_op(data, now)
    res = nil
    user = get_responsibility(now)
    if user.nil?
      res = '出欠確認を開始する権限がないよ。'
    else
      res = "出欠確認を開始する権限がないよ。<@#{user}> が既に出欠確認を始めているよ。"
    end
    @rt_client.message channel: data['channel'], text: res unless res.nil?
  end


  # 出席メッセージ

  def message_attend?(data)
    not data['text'].strip.upcase.match(/^[AC-HJKPR-Y3-578]{4}$/).nil?
  end

  def message_attend(data)
    now = Time.now
    nowstr = now.strftime('%Y-%m-%d %X')
    key = get_key(now)
    user = data['user']
    res = nil
    if key.nil?
      res = '今日の出欠確認はまだ始まっていないみたいだよ。'
    elsif data['text'].strip.upcase != key
      res = 'キーワードが違うよ。'
    elsif already_attended?(now, user)
      res = "今日の <@#{user}> の出席は確認済みだよ。"
    else
      @db.exec 'attendees-insert', { :datetime => nowstr, :attendee => user }
      res = "今日の <@#{user}> の出席を確認したよ。"
    end
    @rt_client.message channel: data['channel'], text: res unless res.nil?
  end

  def already_attended?(time, user)
    from = time.strftime('%Y-%m-%d 00:00:00')
    to = time.strftime('%Y-%m-%d 23:59:59')
    @db.exec 'attendees-range-user', { :from => from, :to => to, :user => user } do
      return true
    end
    return false
  end


  # OP 追加メッセージ

  def message_op_add?(data)
    not data['text'].strip.match(/^op.add <@U[A-Z0-9]*>$/).nil?
  end

  def message_op_add(data)
    res = nil
    if @admin_list.admin?(data['user'])
      user = data['text'].strip.match(/^op.add <@(U[A-Z0-9]*)>$/)[1]
      log.error 'op.add match failed.' if user.nil?
      if @admin_list.op?(user)
        res = "<@#{user}> は既に OP 権限を持っているよ。"
      else
        @admin_list.add_op(user)
        res = "<@#{user}> に OP 権限を与えたよ。"
      end
    else
      res = 'OP 権限を与える権限を持っていないよ。'
    end
    @rt_client.message channel: data['channel'], text: res unless res.nil?
  end


  # OP 剥奪メッセージ

  def message_op_remove?(data)
    not data['text'].strip.match(/^op.remove <@U[A-Z0-9]*>$/).nil?
  end

  def message_op_remove(data)
    res = nil
    if @admin_list.admin?(data['user'])
      user = data['text'].strip.match(/^op.remove <@(U[A-Z0-9]*)>$/)[1]
      log.error 'op.remove match failed.' if user.nil?
      if @admin_list.admin?(user)
        res = "管理者の OP 権限は無くせないよ。"
      elsif @admin_list.op?(user)
        @admin_list.remove_op(user)
        res = "<@#{user}> の OP 権限を無くしたよ。"
      else
        res = "<@#{user}> は OP 権限を持っていないよ。"
      end
    else
      res = 'OP 権限を無くす権限を持っていないよ。'
    end
    @rt_client.message channel: data['channel'], text: res unless res.nil?
  end


  # OP 一覧メッセージ

  def message_op_list?(data)
    data['text'].strip == 'op.list'
  end

  def message_op_list(data)
    res = "OP 一覧:\n#{@admin_list.ops.map { |user| "<@#{user}>" }.join(', ')}"
    @rt_client.message channel: data['channel'], text: res unless res.nil?
  end


  # 出欠確認やりなおしメッセージ

  def message_reset?(data)
    data['text'].strip == 'rsvp.reset'
  end

  def message_reset(data)
    return unless @admin_list.admin?(data['user'])
    now = DateTime.now
    from = now.strftime('%Y-%m-%d 00:00:00')
    to = now.strftime('%Y-%m-%d 23:59:59')
    @db.transaction do
      @db.exec 'attendees-delete-range', { :from => from, :to => to }
      @db.exec 'days-delete-range', { :from => from, :to => to }
    end
    @rt_client.message text: '今日の出欠確認をリセットしたよ。', channel: data['channel']
  end


  # 未知のメッセージ

  def message_unknown(data)
  end


  # Slack クライアント起動

  def start!
    @rt_client.start!
  end

end


app = App.new
app.start!

