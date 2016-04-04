select
  *
  from days
  where datetime >= :from and datetime <= :to
;

