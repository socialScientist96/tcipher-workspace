-- 24-hour test, round 2 · step 2 of 2 · run about 24 hours after ops-test-3-again.sql, then paste the result to Claude
-- before: old setup, average per day until 13 Nov · test1: 13–14 Nov · test2: the last 24 hours
-- vs_before / vs_test1: change in % (negative = less; -90 means 90% less)

select ops.take_snap('end');

select b.metric,
       b.per_day as before_per_day,
       t1.per_day as test1_per_day,
       t2.per_day as test2_per_day,
       round(100 * (t2.per_day - b.per_day) / nullif(b.per_day, 0)) as vs_before_pct,
       round(100 * (t2.per_day - t1.per_day) / nullif(t1.per_day, 0)) as vs_test1_pct,
       t2.days as test2_days
from ops.per_day('zero', 'run1_start') b
left join ops.per_day('run1_start', 'run1_end') t1 using (ord, metric)
left join ops.per_day('start', 'end') t2 using (ord, metric)
order by b.ord, b.metric;
