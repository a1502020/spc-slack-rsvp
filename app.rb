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
      conf.token = File.read('slack-token').chomp
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
      return if data['user'] == @rt_client.self['id']
      if im?(data['channel'])
        if message_rsvp?(data)
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
    not data['text'].upcase.match(/^[AC-HJKPR-Y3-578]{4}$/).nil?
  end

  def message_attend(data)
    now = Time.now
    nowstr = now.strftime('%Y-%m-%d %X')
    key = get_key(now)
    user = data['user']
    res = nil
    if key.nil?
      res = '今日の出欠確認はまだ始まっていないみたいだよ。'
    elsif data['text'].upcase != key
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
    not data['text'].match(/^op.add <@U[A-Z0-9]*>$/).nil?
  end

  def message_op_add(data)
    res = nil
    if @admin_list.admin?(data['user'])
      user = data['text'].match(/^op.add <@(U[A-Z0-9]*)>$/)[1]
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
    not data['text'].match(/^op.remove <@U[A-Z0-9]*>$/).nil?
  end

  def message_op_remove(data)
    res = nil
    if @admin_list.admin?(data['user'])
      user = data['text'].match(/^op.remove <@(U[A-Z0-9]*)>$/)[1]
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
    data['text'] == 'op.list'
  end

  def message_op_list(data)
    res = "OP 一覧:\n#{@admin_list.ops.map { |user| "<@#{user}>" }.join(', ')}"
    @rt_client.message channel: data['channel'], text: res unless res.nil?
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

