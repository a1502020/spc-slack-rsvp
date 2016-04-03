create table days (
  id integer primary key autoincrement,
  datetime datetime not null,
  key text not null,
  responsibility text not null
);
create index datetime_index
  on days(datetime)
;
