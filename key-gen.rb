class KeyGen

  def initialize(db)
    @db = db
    @chars = 'ACDEFGHJKPRSTUVWXY34578'
  end

  def generate
    now = Time.now
    from = (now - 60 * 60 * 24 * 7).strftime('%Y-%m-%d 00:00:00')
    to = now.strftime('%Y-%m-%d 23:59:59')
    res = generate_one
    while used?(res, from, to)
      res = generate_one
    end
    return res
  end

  private

  def generate_one
    res = 'RSVP'
    until res != 'RSVP'
      res = (1..4).map { @chars[rand(@chars.length)] }.join
    end
    return res
  end

  def used?(key, from, to)
    @db.exec 'days-range-key', { :from => from, :to => to, :key => key } do
      return true
    end
    return false
  end

end

