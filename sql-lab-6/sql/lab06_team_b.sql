-- Модуль 6. Лабораторная работа № 6
-- Объединение наборов: единые журналы и сравнение периодов
-- Вариант 2, команда Б: «Производство и закупки»
-- PostgreSQL, схема pitanie

SET search_path TO pitanie, public;


-- ОБЩАЯ ЧАСТЬ. Сравнение количества ИНН через UNION ALL и UNION

SELECT
    (
        SELECT COUNT(*)
        FROM (
            SELECT inn FROM customers
            UNION ALL
            SELECT inn FROM suppliers
        ) AS all_inn
    ) AS count_union_all,
    (
        SELECT COUNT(*)
        FROM (
            SELECT inn FROM customers
            UNION
            SELECT inn FROM suppliers
        ) AS unique_inn
    ) AS count_union;


-- ОБЩАЯ ЧАСТЬ. Повторяющиеся ИНН внутри customers

SELECT
    inn,
    COUNT(*) AS occurrences
FROM customers
WHERE inn IS NOT NULL
GROUP BY inn
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, inn;


-- ОБЩАЯ ЧАСТЬ. Повторяющиеся ИНН внутри suppliers

SELECT
    inn,
    COUNT(*) AS occurrences
FROM suppliers
WHERE inn IS NOT NULL
GROUP BY inn
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, inn;


-- ОБЩАЯ ЧАСТЬ. ИНН, общие для customers и suppliers

SELECT inn
FROM customers
WHERE inn IS NOT NULL

INTERSECT

SELECT inn
FROM suppliers
WHERE inn IS NOT NULL;


-- Задание Б-1. Единый журнал потерь производства

WITH loss_journal AS (
    -- Брак продукции
    SELECT
        'Брак' AS event_type,
        pb.production_date AS event_date,
        pb.line_id,
        pb.defect_qty::numeric AS qty,
        p.unit,
        (pb.defect_qty * p.standard_cost)::numeric AS amount_rub
    FROM production_batches pb
    JOIN products p ON p.product_id = pb.product_id
    WHERE pb.defect_qty > 0

    UNION ALL

    -- Закрытые простои оборудования
    SELECT
        'Простой',
        ed.start_time::date,
        ed.line_id,
        EXTRACT(EPOCH FROM (ed.end_time - ed.start_time)) / 3600,
        'ч',
        NULL::numeric
    FROM equipment_downtime ed
    WHERE ed.end_time IS NOT NULL

    UNION ALL

    -- Списания сырья
    SELECT
        'Списание',
        mw.writeoff_date,
        NULL::integer,
        mw.quantity,
        rm.unit,
        mw.amount
    FROM material_writeoffs mw
    JOIN raw_materials rm ON rm.material_id = mw.material_id
    WHERE mw.quantity > 0
)
SELECT
    event_type,
    EXTRACT(YEAR FROM event_date)::integer AS year,
    unit,
    COUNT(*) AS event_count,
    ROUND(SUM(qty), 2) AS total_qty,
    ROUND(SUM(amount_rub), 2) AS total_amount_rub
FROM loss_journal
GROUP BY event_type, EXTRACT(YEAR FROM event_date), unit
ORDER BY event_type, year, unit;


-- Задание Б-2. Часы простоев по линиям за 2024 и 2025 годы

SELECT
    pl.line_name,
    ROUND(
        SUM(EXTRACT(EPOCH FROM (ed.end_time - ed.start_time)) / 3600)
        FILTER (
            WHERE ed.start_time >= DATE '2024-01-01'
              AND ed.start_time < DATE '2025-01-01'
        )::numeric,
        2
    ) AS hours_2024,
    ROUND(
        SUM(EXTRACT(EPOCH FROM (ed.end_time - ed.start_time)) / 3600)
        FILTER (
            WHERE ed.start_time >= DATE '2025-01-01'
              AND ed.start_time < DATE '2026-01-01'
        )::numeric,
        2
    ) AS hours_2025
FROM production_lines pl
LEFT JOIN equipment_downtime ed
    ON ed.line_id = pl.line_id
   AND ed.end_time IS NOT NULL
   AND ed.start_time >= DATE '2024-01-01'
   AND ed.start_time < DATE '2026-01-01'
GROUP BY pl.line_id, pl.line_name
ORDER BY pl.line_id;


-- Задание Б-3.1. Закупаемые материалы, отсутствующие в рецептурах

SELECT material_id
FROM purchase_order_items

EXCEPT

SELECT material_id
FROM recipes
ORDER BY material_id;


-- Задание Б-3.2. Материалы рецептур, которые ни разу не закупались

SELECT material_id
FROM recipes

EXCEPT

SELECT material_id
FROM purchase_order_items
ORDER BY material_id;


-- Задание Б-3.3. Новые пары «поставщик — материал» в 2025 году,
-- которых не было в 2024 году

SELECT DISTINCT
    po.supplier_id,
    poi.material_id
FROM purchase_orders po
JOIN purchase_order_items poi ON poi.po_id = po.po_id
WHERE po.order_date >= DATE '2025-01-01'
  AND po.order_date < DATE '2026-01-01'

EXCEPT

SELECT DISTINCT
    po.supplier_id,
    poi.material_id
FROM purchase_orders po
JOIN purchase_order_items poi ON poi.po_id = po.po_id
WHERE po.order_date >= DATE '2024-01-01'
  AND po.order_date < DATE '2025-01-01'
ORDER BY supplier_id, material_id;


-- Задание Б-4.1. Материалы ООО «АгроСнаб-М»,
-- которые поставляет хотя бы один другой поставщик

(
    SELECT DISTINCT poi.material_id
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.po_id = po.po_id
    JOIN suppliers s ON s.supplier_id = po.supplier_id
    WHERE s.supplier_name = 'ООО "АгроСнаб-М"'

    INTERSECT

    SELECT DISTINCT poi.material_id
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.po_id = po.po_id
    WHERE po.supplier_id <> (
        SELECT supplier_id
        FROM suppliers
        WHERE supplier_name = 'ООО "АгроСнаб-М"'
    )
)
ORDER BY material_id;


-- Задание Б-4.2. Количество общих материалов для каждой пары поставщиков

SELECT
    s1.supplier_name AS supplier_1,
    s2.supplier_name AS supplier_2,
    common_materials.common_count
FROM suppliers s1
JOIN suppliers s2
    ON s1.supplier_id < s2.supplier_id
CROSS JOIN LATERAL (
    SELECT COUNT(*) AS common_count
    FROM (
        SELECT poi.material_id
        FROM purchase_orders po
        JOIN purchase_order_items poi ON poi.po_id = po.po_id
        WHERE po.supplier_id = s1.supplier_id

        INTERSECT

        SELECT poi.material_id
        FROM purchase_orders po
        JOIN purchase_order_items poi ON poi.po_id = po.po_id
        WHERE po.supplier_id = s2.supplier_id
    ) AS common_set
) AS common_materials
ORDER BY s1.supplier_id, s2.supplier_id;


-- Задание Б-5. Последние 3 позиции закупок каждого поставщика
-- и минимальная цена конкурента за предыдущие 90 дней

SELECT
    s.supplier_name,
    recent.material_id,
    rm.material_name,
    recent.order_date,
    recent.unit_price AS our_price,
    competitor.min_competitor_price,
    ROUND(
        (
            recent.unit_price - competitor.min_competitor_price
        ) * 100.0 / NULLIF(competitor.min_competitor_price, 0),
        2
    ) AS price_difference_pct
FROM suppliers s

CROSS JOIN LATERAL (
    SELECT
        po.order_date,
        poi.material_id,
        poi.unit_price
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.po_id = po.po_id
    WHERE po.supplier_id = s.supplier_id
    ORDER BY po.order_date DESC, poi.po_item_id DESC
    LIMIT 3
) AS recent

JOIN raw_materials rm
    ON rm.material_id = recent.material_id

LEFT JOIN LATERAL (
    SELECT
        MIN(poi.unit_price) AS min_competitor_price
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.po_id = po.po_id
    WHERE po.supplier_id <> s.supplier_id
      AND poi.material_id = recent.material_id
      AND po.order_date >= recent.order_date - INTERVAL '90 days'
      AND po.order_date <= recent.order_date
) AS competitor ON TRUE

ORDER BY s.supplier_name, recent.order_date DESC;


-- Задание Б-6. Календарь простоев линии 2 за 2024–2025 годы

SELECT
    TO_CHAR(months.month_start, 'YYYY-MM') AS month,
    COALESCE(downtime.downtime_count, 0) AS downtime_count,
    COALESCE(downtime.total_hours, 0) AS total_hours
FROM generate_series(
    DATE '2024-01-01',
    DATE '2025-12-01',
    INTERVAL '1 month'
) AS months(month_start)

LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS downtime_count,
        ROUND(
            SUM(EXTRACT(EPOCH FROM (ed.end_time - ed.start_time)) / 3600)::numeric,
            2
        ) AS total_hours
    FROM equipment_downtime ed
    WHERE ed.line_id = 2
      AND ed.end_time IS NOT NULL
      AND ed.start_time >= months.month_start
      AND ed.start_time < months.month_start + INTERVAL '1 month'
) AS downtime ON TRUE

ORDER BY months.month_start;