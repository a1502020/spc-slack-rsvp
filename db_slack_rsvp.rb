require 'sqlite3'

class DBSlackRsvp

  include SQLite3

  attr_reader :db

  def initialize
    @db = Database.new('slack_rsvp.db')
    ObjectSpace.define_finalizer self, DBSlackRsvp.finalize(@db)
    self.exec 'days_exists' do |row|
      if row[0] == 0 then self.exec_batch 'days_create' end
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

end

