select
  count(*)
  from sqlite_master
  where type = 'table' and name = 'attendees'
;
