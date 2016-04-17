select
  *
  from attendees
  where
    datetime >= :from
    and datetime <= :to
;
