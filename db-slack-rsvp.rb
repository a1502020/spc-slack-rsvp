require 'sqlite3'

class DBSlackRsvp

  include SQLite3

  attr_reader :db

  def initialize
    @db = Database.new('slack-rsvp.db')
    ObjectSpace.define_finalizer self, DBSlackRsvp.finalize(@db)
    self.exec 'days-exists' do |row|
       self.exec_batch 'days-create' if row[0] == 0
    end
    self.exec 'attendees-exists' do |row|
      self.exec_batch 'attendees-create' if row[0] == 0
    end
  end

  def DBSlackRsvp.finalize(db)
    proc {
      db.close
    }
  end

  def exec(sql_file, bind_vars = [], *args, &block)
    @db.execute File.open("sql/#{sql_file}.sql").read, bind_vars, *args, &block
  end

  def exec_batch(sql_file, bind_vars = [], *args, &block)
    @db.execute_batch File.open("sql/#{sql_file}.sql").read, bind_vars, *args, &block
  end

  def transaction(&block)
    @db.transaction &block
  end

end

