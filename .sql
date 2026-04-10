--Количество уникальных сессий в месяц по менторам и менти
SELECT
  DATE_TRUNC('month', session_date_time) AS month,
  COUNT(DISTINCT mentor_id) AS unique_mentors_count,
  COUNT(DISTINCT mentee_id) AS unique_mentees_count
FROM sessions
GROUP BY DATE_TRUNC('month', session_date_time)
ORDER BY month

-- Количество уникальных сессий в месяц, среднее количество менторов и менти в месяц --
SELECT
  DATE_TRUNC('month', session_date_time) AS month,
  COUNT(DISTINCT mentor_id) AS unique_mentors_count,
  COUNT(DISTINCT mentee_id) AS unique_mentees_count,
  AVG(COUNT(DISTINCT mentor_id)) OVER () AS avg_mentors_per_month,
  AVG(COUNT(DISTINCT mentee_id)) OVER () AS avg_mentees_per_month
FROM sessions
GROUP BY DATE_TRUNC('month', session_date_time)
ORDER BY month;

-- Количество менторов и менти не принимавших участия в сессиях--
WITH mentors_not_in_sessions AS (
  SELECT COUNT(DISTINCT u.user_id) AS mentors_count
  FROM users u
  LEFT JOIN sessions s ON u.user_id = s.mentor_id
  WHERE u.role = 'mentor' AND s.mentor_id IS NULL
),
mentees_not_in_sessions AS (
  SELECT COUNT(DISTINCT u.user_id) AS mentees_count
  FROM users u
  LEFT JOIN sessions s ON u.user_id = s.mentee_id
  WHERE u.role = 'mentee' AND s.mentee_id IS NULL
)
SELECT
  mnis.mentors_count,
  mis.mentees_count
FROM mentors_not_in_sessions mnis, mentees_not_in_sessions mis

-- Уникальные значения статуса -- 
select distinct session_status
from sessions s 

-- Количество успешных сессий в неделю у менторов--
WITH monthly_sessions AS (
  SELECT
    mentor_id,
    DATE_TRUNC('month', session_date_time) AS month,
    COUNT(*) AS successful_sessions_count
  FROM sessions
  WHERE session_status = 'finished'
  GROUP BY mentor_id, DATE_TRUNC('month', session_date_time)
),
weeks_in_month AS (
  SELECT
    month,
    EXTRACT(DAY FROM (month + INTERVAL '1 month') - INTERVAL '1 day') / 7.0 AS weeks_count
  FROM (
    SELECT DISTINCT DATE_TRUNC('month', session_date_time) AS month
    FROM sessions
    WHERE session_status = 'finished'
  ) months
)
SELECT
  ms.mentor_id,
  ms.month,
  ROUND(CAST(ms.successful_sessions_count AS numeric) / CAST(wm.weeks_count AS numeric), 2) AS avg_sessions_per_week
FROM monthly_sessions ms
JOIN weeks_in_month wm ON ms.month = wm.month
ORDER BY ms.month, ms.mentor_id;

--Расчет частоты сессий в неделю от  месяца к месяцу--
WITH monthly_stats AS (
  SELECT
    DATE_TRUNC('month', session_date_time) AS month,
    COUNT(*) AS total_successful_sessions,
    EXTRACT(DAY FROM (DATE_TRUNC('month', session_date_time) + INTERVAL '1 month') - INTERVAL '1 day') AS days_in_month
  FROM sessions
  WHERE session_status = 'finished'
  GROUP BY DATE_TRUNC('month', session_date_time)
)
SELECT
  month,
  total_successful_sessions,
  days_in_month,
  ROUND(
    CAST(total_successful_sessions AS numeric) /
    CAST((days_in_month / 7.0) AS numeric),
    2
  ) AS avg_weekly_sessions,
  LAG(ROUND(
    CAST(total_successful_sessions AS numeric) /
    CAST((days_in_month / 7.0) AS numeric),
    2
  )) OVER (ORDER BY month) AS prev_avg_weekly,
  ROUND(
    ROUND(
      CAST(total_successful_sessions AS numeric) /
      CAST((days_in_month / 7.0) AS numeric),
      2
    ) -
    LAG(ROUND(
      CAST(total_successful_sessions AS numeric) /
      CAST((days_in_month / 7.0) AS numeric),
      2
    )) OVER (ORDER BY month),
    2
  ) AS change_from_prev_month
FROM monthly_stats
ORDER BY month

-- Вычисление ТОП-5 менторов --
WITH last_full_month AS (
  SELECT
    DATE_TRUNC('month', MAX(session_date_time)) - INTERVAL '1 month' AS target_month
  FROM sessions
),
mentor_sessions_last_month AS (
  SELECT
    s.mentor_id,
    COUNT(*) AS session_count
  FROM sessions s
  JOIN last_full_month lfm ON
    s.session_date_time >= lfm.target_month
    AND s.session_date_time < (lfm.target_month + INTERVAL '1 month')
  WHERE s.session_status = 'finished'
  GROUP BY s.mentor_id
)
SELECT
  mentor_id,
  session_count
FROM mentor_sessions_last_month
ORDER BY session_count DESC
LIMIT 5;

-- Количество отмененный сессий--
SELECT
d.name,  -- название направления менторства (группировка)
COUNT(CASE WHEN s.session_status = 'canceled' THEN 1 END) AS canceled_count,  -- количество отменённых сессий
COUNT(CASE WHEN s.session_status = 'finished' THEN 1 END) AS finished_count,  -- количество завершённых сессий
ARRAY_AGG(s.session_id) AS session_ids,  -- список ID всех сессий в направлении (опционально)
ARRAY_AGG(s.session_date_time) AS session_dates,  -- список дат/времени сессий (опционально)
ARRAY_AGG(s.session_status) AS all_statuses  -- все статусы сессий в направлении (опционально)
FROM
sessions s
JOIN
domain d ON s.mentor_domain_id = d.id  -- соединяем таблицы по ID направления
GROUP BY
d.name  -- группируем по названию направления
ORDER BY
d.name

-- Сумма сессий на день недели --
WITH daily_sessions AS (
  SELECT
    s.session_id,
    s.session_date_time,
    s.session_status,
    s.mentor_domain_id,
    d.name,
    EXTRACT(DOW FROM s.session_date_time) AS day_of_week_num,  -- номер дня недели (0=воскресенье, 1=понедельник, ...)
    TO_CHAR(s.session_date_time, 'Day') AS day_of_week_name  -- название дня недели
  FROM
    sessions s
  JOIN
    domain d ON s.mentor_domain_id = d.id
  WHERE
    s.session_date_time >= '2022-08-01'::DATE  -- начало августа 2022
    AND s.session_date_time < '2022-09-01'::DATE    -- до начала сентября 2022
    AND s.session_status = 'finished'  -- только завершённые сессии
),
aggregated_data AS (
  SELECT
    name AS "Тип направления",
    day_of_week_num AS "Номер дня недели",
    TRIM(day_of_week_name) AS "День недели",
    COUNT(session_id) AS "Количество finished сессий",
    ARRAY_AGG(session_id) AS "Список session_id"  -- опционально: список ID сессий
  FROM daily_sessions
  GROUP BY
    name,
    day_of_week_num,
    day_of_week_name
),
ranked_data AS (
  SELECT
    "Тип направления",
    "День недели",
    "Номер дня недели",
    "Количество finished сессий",
    "Список session_id",
    ROW_NUMBER() OVER (
      PARTITION BY "Тип направления"
      ORDER BY "Количество finished сессий" DESC, "Номер дня недели"
    ) AS rn
  FROM aggregated_data
)
SELECT
  "Тип направления",
  "День недели",
  "Номер дня недели",
  "Количество finished сессий",
  "Список session_id"
FROM ranked_data
WHERE rn = 1
ORDER BY
  "Тип направления",
  "Номер дня недели"
  
  -- Среднее значение по количеству сессий на день недели --
 WITH august_weeks AS (
  -- Определяем границы каждой недели августа 2022 (понедельник — воскресенье)
  SELECT
    DATE '2022-08-01' + (7 * (n - 1))::INT AS week_start,
    DATE '2022-08-01' + (7 * n - 1)::INT AS week_end,
    n AS week_number
  FROM GENERATE_SERIES(1, 5) AS n  -- максимум 5 недель в месяце
),
daily_sessions AS (
  SELECT
    s.session_id,
    s.session_date_time,
    s.session_status,
    s.mentor_domain_id,
    d.name,
    DATE(s.session_date_time) AS session_date,
    EXTRACT(DOW FROM s.session_date_time) AS day_of_week_num,  -- 0=вс, 1=пн, ..., 6=сб
    TO_CHAR(s.session_date_time, 'Day') AS day_of_week_name
  FROM
    sessions s
  JOIN
    domain d ON s.mentor_domain_id = d.id
  WHERE
    s.session_date_time >= '2022-08-01'::DATE
    AND s.session_date_time < '2022-09-01'::DATE
    AND s.session_status = 'finished'
),
weekly_counts AS (
  -- Считаем сессии по неделям и дням недели
  SELECT
    ds.name AS direction_name,
    ds.day_of_week_num,
    TRIM(ds.day_of_week_name) AS day_name,
    aw.week_number,
    COUNT(ds.session_id) AS sessions_count
  FROM daily_sessions ds
  JOIN august_weeks aw ON ds.session_date BETWEEN aw.week_start AND aw.week_end
  GROUP BY
    ds.name, ds.day_of_week_num, ds.day_of_week_name, aw.week_number
),
averages AS (
  -- Вычисляем среднее для каждого дня недели по каждому направлению
  SELECT
    direction_name AS "Тип направления",
    day_name AS "День недели",
    day_of_week_num AS "Номер дня недели",
    COUNT(*) AS "Количество недель с сессиями",
    SUM(sessions_count) AS "Всего сессий за все недели",
    ROUND(
      SUM(sessions_count)::DECIMAL / COUNT(*),
      2
    ) AS "Среднее количество сессий в день недели"
  FROM weekly_counts
  GROUP BY
    direction_name, day_name, day_of_week_num
),
ranked_data AS (
  -- Ранжируем дни недели внутри каждого направления по среднему количеству сессий
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY "Тип направления"
      ORDER BY "Среднее количество сессий в день недели" DESC, "Номер дня недели"
    ) AS rn
  FROM averages
)
-- Финальный выбор: только дни с максимальным средним количеством сессий для каждого направления
SELECT
  "Тип направления",
  "День недели",
  "Номер дня недели",
  "Среднее количество сессий в день недели",
  "Количество недель с сессиями",
  "Всего сессий за все недели"
FROM ranked_data
WHERE rn = 1
ORDER BY
  "Тип направления",
  "Номер дня недели"
  
  -- ТоП-5 худших менторов --
  WITH last_full_month AS (
  SELECT
    DATE_TRUNC('month', MAX(session_date_time)) - INTERVAL '1 month' AS target_month
  FROM sessions
),
mentor_sessions_last_month AS (
  SELECT
    s.mentor_id,
    COUNT(*) AS session_count
  FROM sessions s
  JOIN last_full_month lfm ON
    s.session_date_time >= lfm.target_month
    AND s.session_date_time < (lfm.target_month + INTERVAL '1 month')
  WHERE s.session_status = 'finished'
  GROUP BY s.mentor_id
)
SELECT
  mentor_id,
  session_count
FROM mentor_sessions_last_month
ORDER BY session_count ASC
LIMIT 5
