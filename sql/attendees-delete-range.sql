delete
  from attendees
  where
    datetime >= :from
    and datetime <= :to
;
