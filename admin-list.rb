require 'json'


class AdminList

  def initialize
    if File.exists?('ops')
      self.load
    else
      @admins = []
      @ops = []
      self.save
    end
  end


  def admin?(user)
    @admins.include?(user)
  end

  def op?(user)
    admin?(user) || @ops.include?(user)
  end


  def add_admin(user)
    return if admin?(user)
    @admins.push(user)
    @ops.delete(user)
    self.save
  end

  def remove_admin(user)
    @admins.delete(user)
    self.save
  end


  def add_op(user)
    return if op?(user)
    @ops.push(user)
    self.save
  end

  def remove_op(user)
    raise "can't remove op from admin user." if admin?(user)
    @ops.delete(user)
    self.save
  end


  def load
    return unless File.exists?('ops')
    admin_list = JSON.parse(File.read('ops'))
    @admins = admin_list['admins']
    @ops = admin_list['ops']
  end

  def save
    admin_list = { :admins => @admins, :ops => @ops }
    File.write('ops', admin_list.to_json)
  end

end

