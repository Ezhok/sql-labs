-- Модуль 2. Приводим данные в порядок и считаем точно
-- Курс: «Углублённый SQL»
-- PostgreSQL 16
-- Команда Б, вариант 2: Производство и закупки
-- Дата среза: 31.12.2025
--
-- Все временные расчёты привязаны к фиксированной дате.
-- CURRENT_DATE в работе не используется.

-- Подготовка окружения
SET search_path TO pitanie, public;
SET lc_time = 'ru_RU.UTF-8';


/* =========================================================
   О1. Проверка структуры production_batches
   ========================================================= */

SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'pitanie'
  AND table_name = 'production_batches'
ORDER BY ordinal_position;


/* =========================================================
   О2. Календарь декабря 2025 года
   ========================================================= */

SELECT
    d::date AS calendar_date,
    TO_CHAR(d, 'TMDay') AS weekday,
    CASE
        WHEN EXTRACT(ISODOW FROM d) IN (6, 7)
            THEN 'выходной'
        ELSE 'рабочий'
    END AS day_type
FROM GENERATE_SERIES(
    DATE '2025-12-01',
    DATE '2025-12-31',
    INTERVAL '1 day'
) AS d
ORDER BY d;


/* =========================================================
   Б1. Десять самых продолжительных закрытых простоев
   ========================================================= */

SELECT
    d.downtime_id,
    d.line_id,
    d.start_time,
    d.end_time,
    (d.end_time - d.start_time)::text AS downtime_interval,
    ROUND(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600, 2)
        AS downtime_hours
FROM equipment_downtime AS d
WHERE d.end_time IS NOT NULL
ORDER BY d.end_time - d.start_time DESC, d.downtime_id
LIMIT 10;


/* =========================================================
   Б2. Незакрытые простои на дату среза 31.12.2025
   Для расчёта гипотетической длительности используется
   граница 01.01.2026 00:00:00.
   ========================================================= */

SELECT
    d.downtime_id,
    d.line_id,
    d.start_time,
    DATE '2026-01-01' - d.start_time::date AS open_days,
    ROUND(
        EXTRACT(EPOCH FROM TIMESTAMP '2026-01-01 00:00:00' - d.start_time)
        / 3600,
        2
    ) AS hypothetical_hours
FROM equipment_downtime AS d
WHERE d.end_time IS NULL
ORDER BY d.start_time;


/* =========================================================
   Б3. Простои линии 2 по годам
   ========================================================= */

SELECT
    EXTRACT(YEAR FROM start_time) AS yr,
    COUNT(*) AS events,
    ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600, 1)
        AS hours
FROM equipment_downtime
WHERE line_id = 2
GROUP BY EXTRACT(YEAR FROM start_time)
ORDER BY yr;


/* =========================================================
   Б4. Процент брака и влияние целочисленного деления
   ========================================================= */

-- Б4.1. Сравнение целочисленного и дробного расчёта
SELECT
    p.batch_number,
    p.produced_qty,
    p.defect_qty,
    p.defect_qty / NULLIF(p.produced_qty, 0) AS fraction_integer,
    100 * p.defect_qty / NULLIF(p.produced_qty, 0) AS percent_integer,
    ROUND(100.0 * p.defect_qty / NULLIF(p.produced_qty, 0), 2)
        AS percent_correct
FROM production_batches AS p
WHERE p.batch_number IN ('П250602-3Д', 'П250602-3Н')
ORDER BY p.batch_number;

-- Б4.2. Сколько партий превышают порог брака 5%
-- Сравниваются целочисленная и дробная арифметика.
SELECT
    COUNT(*) FILTER (
        WHERE 100 * defect_qty / NULLIF(produced_qty, 0) > 5
    ) AS integer_method,
    COUNT(*) FILTER (
        WHERE 100.0 * defect_qty / NULLIF(produced_qty, 0) > 5
    ) AS numeric_method
FROM production_batches;

-- Б4.3. Партии, которые целочисленный расчёт ошибочно оставляет
-- на уровне 5% или ниже, хотя точный процент превышает 5%.
SELECT
    p.batch_id,
    p.batch_number,
    p.line_id,
    p.shift,
    p.production_date,
    p.defect_qty,
    p.produced_qty,
    100 * p.defect_qty / NULLIF(p.produced_qty, 0) AS percent_integer,
    ROUND(100.0 * p.defect_qty / NULLIF(p.produced_qty, 0), 4)
        AS percent_exact
FROM production_batches AS p
WHERE 100.0 * p.defect_qty / NULLIF(p.produced_qty, 0) > 5
  AND 100 * p.defect_qty / NULLIF(p.produced_qty, 0) <= 5
ORDER BY p.batch_number;


/* =========================================================
   Б5. Разбор номера партии и контроль целостности
   ========================================================= */

-- Б5.1. Разбор первых 20 номеров партий
SELECT
    p.batch_id,
    p.batch_number,
    p.production_date,
    p.line_id,
    p.shift,
    TO_DATE(SUBSTRING(p.batch_number FROM 2 FOR 6), 'YYMMDD')
        AS date_from_number,
    REGEXP_REPLACE(
        SPLIT_PART(p.batch_number, '-', 2),
        '[^0-9]', '', 'g'
    )::int AS line_from_number,
    CASE RIGHT(p.batch_number, 1)
        WHEN 'Д' THEN 'дневная'
        WHEN 'Н' THEN 'ночная'
        ELSE 'неизвестная'
    END AS shift_from_number
FROM production_batches AS p
ORDER BY p.batch_id
LIMIT 20;

-- Б5.2. Число партий с несовпадением данных в номере и столбцах
WITH decoded AS (
    SELECT
        p.batch_id,
        p.batch_number,
        p.production_date,
        p.line_id,
        p.shift,
        TO_DATE(SUBSTRING(p.batch_number FROM 2 FOR 6), 'YYMMDD')
            AS date_from_number,
        REGEXP_REPLACE(
            SPLIT_PART(p.batch_number, '-', 2),
            '[^0-9]', '', 'g'
        )::int AS line_from_number,
        UPPER(RIGHT(p.batch_number, 1)) AS shift_from_number,
        UPPER(LEFT(BTRIM(p.shift::text), 1)) AS shift_from_field
    FROM production_batches AS p
)
SELECT COUNT(*) AS mismatched_batches
FROM decoded
WHERE production_date IS DISTINCT FROM date_from_number
   OR line_id IS DISTINCT FROM line_from_number
   OR shift_from_field IS DISTINCT FROM shift_from_number;


/* =========================================================
   Б6. Задержки поставок
   ========================================================= */

-- Б6.1. Десять наибольших задержек
SELECT
    poi.po_item_id,
    po.po_number,
    s.supplier_name,
    po.expected_date,
    poi.received_date,
    poi.received_date::date - po.expected_date::date AS delay_days,
    GREATEST(
        poi.received_date::date - po.expected_date::date,
        0
    ) AS late_days_nonnegative
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
WHERE poi.received_date IS NOT NULL
ORDER BY delay_days DESC, poi.po_item_id
LIMIT 10;

-- Б6.2. Количество позиций с задержкой не менее 4 дней
SELECT COUNT(*) AS late_items_4plus
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
WHERE poi.received_date IS NOT NULL
  AND poi.received_date::date - po.expected_date::date >= 4;

-- Б6.3. Задержки в разрезе поставщиков
SELECT
    s.supplier_id,
    s.supplier_name,
    s.rating,
    COUNT(*) AS late_items_4plus
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
WHERE poi.received_date IS NOT NULL
  AND poi.received_date::date - po.expected_date::date >= 4
GROUP BY s.supplier_id, s.supplier_name, s.rating
ORDER BY late_items_4plus DESC, s.supplier_id;


/* =========================================================
   Б7. Возраст производственных линий
   ========================================================= */

SELECT
    pl.line_id,
    pl.line_name,
    pl.launch_year,
    2025 - pl.launch_year AS age_years,
    AGE(DATE '2025-12-31', MAKE_DATE(pl.launch_year, 1, 1))
        AS exact_age,
    CASE
        WHEN 2025 - pl.launch_year >= 15 THEN 'кандидат на модернизацию'
        WHEN 2025 - pl.launch_year BETWEEN 8 AND 14 THEN 'плановый контроль'
        ELSE 'в норме'
    END AS equipment_status
FROM production_lines AS pl
ORDER BY pl.launch_year, pl.line_id;


/* =========================================================
   Б8. Стоимость и частота списаний сырья
   ========================================================= */

-- Б8.1. Десять самых дорогих списаний по причине истечения срока годности
SELECT
    w.writeoff_id,
    r.material_name,
    w.writeoff_date,
    w.quantity,
    w.amount,
    ROUND(w.amount / NULLIF(w.quantity, 0), 2) AS price_per_unit,
    ROUND(w.amount, -3) AS amount_rounded_to_thousands,
    TO_CHAR(w.amount, 'FM999G999G999G990D00') AS amount_formatted
FROM material_writeoffs AS w
JOIN raw_materials AS r ON r.material_id = w.material_id
WHERE w.reason = 'Истёк срок годности'
ORDER BY w.amount DESC, w.writeoff_id
LIMIT 10;

-- Б8.2. Количество списаний с нулевым количеством
SELECT COUNT(*) AS zero_quantity_writeoffs
FROM material_writeoffs
WHERE quantity = 0;

-- Б8.3. Материал с наибольшей суммой списаний по сроку годности
WITH total_per_material AS (
    SELECT
        r.material_id,
        r.material_name,
        SUM(w.amount) AS exact_total
    FROM material_writeoffs AS w
    JOIN raw_materials AS r ON r.material_id = w.material_id
    WHERE w.reason = 'Истёк срок годности'
    GROUP BY r.material_id, r.material_name
)
SELECT
    material_id,
    material_name,
    ROUND(exact_total, 2) AS total_exact_rub,
    ROUND(exact_total, -3) AS total_thousands_rub,
    ROUND(exact_total / 1000000, 2) AS total_million_rub,
    TO_CHAR(exact_total, 'FM999G999G999G990D00') AS total_formatted
FROM total_per_material
ORDER BY exact_total DESC
LIMIT 1;

-- Б8.4. Частота и сумма списаний по каждому виду сырья
SELECT
    r.material_name,
    COUNT(*) AS writeoff_count,
    ROUND(SUM(w.amount), 2) AS total_amount_rub
FROM material_writeoffs AS w
JOIN raw_materials AS r ON r.material_id = w.material_id
GROUP BY r.material_id, r.material_name
ORDER BY writeoff_count DESC, total_amount_rub DESC
LIMIT 10;


/* =========================================================
   Б9. Время поломок линии 2 в 2025 году
   ========================================================= */

-- Б9.1. Категории и причины простоев
SELECT DISTINCT
    downtime_category,
    reason
FROM equipment_downtime
WHERE line_id = 2
  AND start_time >= TIMESTAMP '2025-01-01 00:00:00'
  AND start_time < TIMESTAMP '2026-01-01 00:00:00'
ORDER BY downtime_category, reason;

-- Б9.2. Даты, дни недели, часы начала и длительность поломок
SELECT
    d.downtime_id,
    d.start_time,
    TO_CHAR(d.start_time, 'TMDy') AS weekday,
    EXTRACT(HOUR FROM d.start_time)::int AS start_hour,
    CASE
        WHEN EXTRACT(HOUR FROM d.start_time) BETWEEN 8 AND 19
            THEN 'день'
        ELSE 'ночь'
    END AS time_of_day,
    ROUND(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600, 2)
        AS downtime_hours
FROM equipment_downtime AS d
WHERE d.line_id = 2
  AND d.start_time >= TIMESTAMP '2025-01-01 00:00:00'
  AND d.start_time < TIMESTAMP '2026-01-01 00:00:00'
  AND d.downtime_category = 'Поломка оборудования'
ORDER BY d.start_time;

-- Б9.3. Сводка по времени суток
SELECT
    CASE
        WHEN EXTRACT(HOUR FROM d.start_time) BETWEEN 8 AND 19
            THEN 'день'
        ELSE 'ночь'
    END AS time_of_day,
    COUNT(*) AS breakdown_count,
    ROUND(
        SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time)) / 3600,
        2
    ) AS downtime_hours
FROM equipment_downtime AS d
WHERE d.line_id = 2
  AND d.start_time >= TIMESTAMP '2025-01-01 00:00:00'
  AND d.start_time < TIMESTAMP '2026-01-01 00:00:00'
  AND d.downtime_category = 'Поломка оборудования'
GROUP BY time_of_day
ORDER BY breakdown_count DESC;
