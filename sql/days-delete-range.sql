delete
  from days
  where
    datetime >= :from
    and datetime <= :to
;
