
-- Модуль 3. Извлечение данных из нескольких таблиц
-- PostgreSQL
-- Команда Б, вариант 2: Производство и закупки
--
-- Задания Б1–Б10
-- Схема: pitanie

SET search_path TO pitanie, public;


/* =========================================================
   Б1. Партии с линией, продуктом и оператором
   Проверка: 3026 строк
   ========================================================= */

SELECT
    pb.batch_number,
    pb.production_date,
    pb.shift,
    pl.line_name,
    p.product_name,
    e.full_name AS operator_name,
    pb.produced_qty,
    pb.defect_qty,
    ROUND(
        100.0 * pb.defect_qty / NULLIF(pb.produced_qty, 0),
        2
    ) AS defect_pct
FROM production_batches AS pb
JOIN production_lines AS pl
    ON pl.line_id = pb.line_id
JOIN products AS p
    ON p.product_id = pb.product_id
LEFT JOIN employees AS e
    ON e.employee_id = pb.operator_id
WHERE pb.production_date >= DATE '2025-01-01'
  AND pb.production_date < DATE '2026-01-01'
ORDER BY pb.production_date, pb.batch_number;


/* =========================================================
   Б2. Партии с высоким браком
   Проверка: 625 партий; в сводке 2 строки
   ========================================================= */

-- Б2.1. Все партии с браком выше 6 %

SELECT
    pb.batch_number,
    pb.production_date,
    pl.line_name,
    pb.shift,
    e.full_name AS operator_name,
    pb.defect_qty,
    pb.produced_qty,
    ROUND(
        100.0 * pb.defect_qty / NULLIF(pb.produced_qty, 0),
        2
    ) AS defect_pct
FROM production_batches AS pb
JOIN production_lines AS pl
    ON pl.line_id = pb.line_id
LEFT JOIN employees AS e
    ON e.employee_id = pb.operator_id
WHERE 100.0 * pb.defect_qty / NULLIF(pb.produced_qty, 0) > 6
ORDER BY defect_pct DESC;


-- Б2.2. Сводка по линии, смене и оператору

SELECT
    pl.line_name,
    pb.shift,
    e.full_name AS operator_name,
    COUNT(*) AS batches_over_6pct
FROM production_batches AS pb
JOIN production_lines AS pl
    ON pl.line_id = pb.line_id
LEFT JOIN employees AS e
    ON e.employee_id = pb.operator_id
WHERE 100.0 * pb.defect_qty / NULLIF(pb.produced_qty, 0) > 6
GROUP BY
    pl.line_name,
    pb.shift,
    e.full_name
ORDER BY batches_over_6pct DESC;


/* =========================================================
   Б3. Ответственные за линии и их руководители
   Проверка: 5 строк
   ========================================================= */

SELECT
    pl.line_name,
    pl.launch_year,
    pl.responsible_id,
    e.full_name AS responsible_name,
    e."position" AS responsible_position,
    m.full_name AS manager_name,
    m."position" AS manager_position
FROM production_lines AS pl
JOIN employees AS e
    ON e.employee_id = pl.responsible_id
LEFT JOIN employees AS m
    ON m.employee_id = e.manager_id
ORDER BY pl.launch_year;


/* =========================================================
   Б4. Поставки сахара за 2025 год
   Проверка: 52 строки
   ========================================================= */

SELECT
    po.po_number,
    po.order_date,
    s.supplier_name,
    rm.material_name,
    e.full_name AS buyer_name,
    poi.quantity,
    poi.unit_price,
    ROUND(poi.quantity * poi.unit_price, 2) AS line_total
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON po.po_id = poi.po_id
JOIN suppliers AS s
    ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm
    ON rm.material_id = poi.material_id
JOIN employees AS e
    ON e.employee_id = po.employee_id
WHERE poi.material_id = 4
  AND po.order_date >= DATE '2025-01-01'
  AND po.order_date < DATE '2026-01-01'
ORDER BY poi.unit_price DESC;


/* =========================================================
   Б5. Сравнение закупочных цен разных поставщиков
   Проверка: 365 пар; в сводке 11 строк
   ========================================================= */

-- Б5.1. Пары позиций с разницей в цене более 20 %

SELECT
    rm.material_name,
    s_exp.supplier_name AS expensive_supplier,
    s_chp.supplier_name AS cheap_supplier,
    a.unit_price AS expensive_price,
    b.unit_price AS cheap_price,
    ROUND(
        100.0 * (a.unit_price - b.unit_price) / b.unit_price,
        2
    ) AS overpay_pct
FROM purchase_order_items AS a
JOIN purchase_orders AS po_a
    ON po_a.po_id = a.po_id
JOIN suppliers AS s_exp
    ON s_exp.supplier_id = po_a.supplier_id
JOIN purchase_order_items AS b
    ON b.material_id = a.material_id
   AND b.po_item_id <> a.po_item_id
JOIN purchase_orders AS po_b
    ON po_b.po_id = b.po_id
JOIN suppliers AS s_chp
    ON s_chp.supplier_id = po_b.supplier_id
JOIN raw_materials AS rm
    ON rm.material_id = a.material_id
WHERE po_a.supplier_id <> po_b.supplier_id
  AND DATE_TRUNC('month', po_a.order_date) =
      DATE_TRUNC('month', po_b.order_date)
  AND a.unit_price > b.unit_price * 1.2
ORDER BY overpay_pct DESC;


-- Б5.2. Сводка по дорогому поставщику и материалу

SELECT
    s_exp.supplier_name,
    rm.material_name,
    COUNT(*) AS pair_count
FROM purchase_order_items AS a
JOIN purchase_orders AS po_a
    ON po_a.po_id = a.po_id
JOIN suppliers AS s_exp
    ON s_exp.supplier_id = po_a.supplier_id
JOIN purchase_order_items AS b
    ON b.material_id = a.material_id
   AND b.po_item_id <> a.po_item_id
JOIN purchase_orders AS po_b
    ON po_b.po_id = b.po_id
JOIN suppliers AS s_chp
    ON s_chp.supplier_id = po_b.supplier_id
JOIN raw_materials AS rm
    ON rm.material_id = a.material_id
WHERE po_a.supplier_id <> po_b.supplier_id
  AND DATE_TRUNC('month', po_a.order_date) =
      DATE_TRUNC('month', po_b.order_date)
  AND a.unit_price > b.unit_price * 1.2
GROUP BY
    s_exp.supplier_name,
    rm.material_name
ORDER BY pair_count DESC;


/* =========================================================
   Б6. Анализ задержек и качества поставок
   ========================================================= */

-- Б6.1. Позиции поставок с задержкой более 3 дней

SELECT
    po.po_number,
    po.order_date,
    po.expected_date,
    s.supplier_name,
    rm.material_name,
    poi.quantity,
    poi.received_qty,
    poi.received_date,
    poi.quality_status,
    poi.received_date::date - po.expected_date::date
        AS delay_days
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON po.po_id = poi.po_id
JOIN suppliers AS s
    ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm
    ON rm.material_id = poi.material_id
WHERE poi.received_date IS NOT NULL
  AND poi.received_date::date > po.expected_date::date + 3
ORDER BY delay_days DESC;


-- Б6.2. Позиции с качеством, отличным от «Принято»
-- NULL не попадёт в результат этого условия.

SELECT
    poi.po_item_id,
    po.po_number,
    s.supplier_name,
    rm.material_name,
    poi.quality_status,
    poi.received_date
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON po.po_id = poi.po_id
JOIN suppliers AS s
    ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm
    ON rm.material_id = poi.material_id
WHERE poi.quality_status <> 'Принято'
ORDER BY po.po_number;


-- Б6.3. Альтернативная проверка с включением NULL

SELECT
    poi.po_item_id,
    po.po_number,
    s.supplier_name,
    rm.material_name,
    poi.quality_status,
    poi.received_date
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON po.po_id = poi.po_id
JOIN suppliers AS s
    ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm
    ON rm.material_id = poi.material_id
WHERE poi.quality_status IS DISTINCT FROM 'Принято'
ORDER BY po.po_number;


-- Б6.4. Позиции без даты фактического получения

SELECT
    poi.po_item_id,
    po.po_number,
    s.supplier_name,
    rm.material_name,
    po.expected_date,
    poi.received_date,
    poi.quality_status
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON po.po_id = poi.po_id
JOIN suppliers AS s
    ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm
    ON rm.material_id = poi.material_id
WHERE poi.received_date IS NULL
ORDER BY po.expected_date;


/* =========================================================
   Б7. Анализ простоев оборудования
   ========================================================= */

-- Б7.1. Простои с названием линии и ответственным

SELECT
    d.*,
    pl.line_name,
    e.full_name AS responsible_name
FROM equipment_downtime AS d
JOIN production_lines AS pl
    ON pl.line_id = d.line_id
JOIN employees AS e
    ON e.employee_id = pl.responsible_id
ORDER BY d.start_time;


-- Б7.2. Незакрытые простои

SELECT
    d.downtime_id,
    pl.line_name,
    d.start_time,
    d.downtime_category,
    d.end_time
FROM equipment_downtime AS d
JOIN production_lines AS pl
    ON pl.line_id = d.line_id
WHERE d.end_time IS NULL
ORDER BY d.start_time;


-- Б7.3. Поломки оборудования линии 2 по годам

SELECT
    EXTRACT(YEAR FROM d.start_time) AS yr,
    COUNT(*) AS breakdown_count
FROM equipment_downtime AS d
WHERE d.line_id = 2
  AND d.downtime_category = 'Поломка оборудования'
  AND d.start_time >= TIMESTAMP '2024-01-01 00:00:00'
  AND d.start_time < TIMESTAMP '2026-01-01 00:00:00'
GROUP BY EXTRACT(YEAR FROM d.start_time)
ORDER BY yr;


/* =========================================================
   Б8. Сравнение нормативного и фактического расхода сырья
   Линия 5, 2025 год, превышение нормы более чем на 10 %
   Проверка: 912 строк
   ========================================================= */

-- Б8.1. Позиции расхода с превышением нормы

SELECT
    pb.batch_number,
    pb.production_date,
    p.product_name,
    rm.material_name,
    r.qty_per_unit,
    pb.produced_qty,
    ROUND(r.qty_per_unit * pb.produced_qty, 3) AS norm_qty,
    mc.quantity AS actual_qty,
    ROUND(
        100.0 * (
            mc.quantity - r.qty_per_unit * pb.produced_qty
        ) / NULLIF(r.qty_per_unit * pb.produced_qty, 0),
        2
    ) AS excess_pct
FROM production_batches AS pb
JOIN production_lines AS pl
    ON pl.line_id = pb.line_id
JOIN products AS p
    ON p.product_id = pb.product_id
JOIN material_consumption AS mc
    ON mc.batch_id = pb.batch_id
JOIN recipes AS r
    ON r.product_id = pb.product_id
   AND r.material_id = mc.material_id
JOIN raw_materials AS rm
    ON rm.material_id = mc.material_id
WHERE pl.line_id = 5
  AND pb.production_date >= DATE '2025-01-01'
  AND pb.production_date < DATE '2026-01-01'
  AND mc.quantity > r.qty_per_unit * pb.produced_qty * 1.1
ORDER BY excess_pct DESC;


-- Б8.2. Сводка по материалам

SELECT
    rm.material_name,
    COUNT(*) AS excess_count,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (),
        1
    ) AS share_pct
FROM production_batches AS pb
JOIN production_lines AS pl
    ON pl.line_id = pb.line_id
JOIN material_consumption AS mc
    ON mc.batch_id = pb.batch_id
JOIN recipes AS r
    ON r.product_id = pb.product_id
   AND r.material_id = mc.material_id
JOIN raw_materials AS rm
    ON rm.material_id = mc.material_id
WHERE pl.line_id = 5
  AND pb.production_date >= DATE '2025-01-01'
  AND pb.production_date < DATE '2026-01-01'
  AND mc.quantity > r.qty_per_unit * pb.produced_qty * 1.1
GROUP BY rm.material_id, rm.material_name
ORDER BY excess_count DESC;


/* =========================================================
   Б9. Анализ списаний материалов
   ========================================================= */

-- Б9.1. Списания наполнителя клубничного
-- material_id = 10

SELECT
    w.writeoff_id,
    rm.material_name,
    w.writeoff_date,
    w.quantity,
    w.reason,
    w.amount
FROM material_writeoffs AS w
JOIN raw_materials AS rm
    ON rm.material_id = w.material_id
WHERE w.material_id = 10
ORDER BY w.writeoff_date;


-- Б9.2. Материалы без записей о списаниях

SELECT
    rm.material_id,
    rm.material_name
FROM raw_materials AS rm
LEFT JOIN material_writeoffs AS w
    ON w.material_id = rm.material_id
WHERE w.writeoff_id IS NULL
ORDER BY rm.material_id;


/* =========================================================
   Б10. Поиск пропущенных производственных смен
   2025 год
   Проверка: 10 строк в сводке
   ========================================================= */

WITH dates AS (
    SELECT
        generate_series(
            DATE '2025-01-01',
            DATE '2025-12-31',
            INTERVAL '1 day'
        )::date AS production_date
),
shifts AS (
    SELECT DISTINCT shift
    FROM production_batches
),
schedule AS (
    SELECT
        d.production_date,
        pl.line_id,
        pl.line_name,
        s.shift
    FROM dates AS d
    CROSS JOIN production_lines AS pl
    CROSS JOIN shifts AS s
)
SELECT
    sc.line_name,
    sc.shift,
    COUNT(*) AS missing_shifts
FROM schedule AS sc
LEFT JOIN production_batches AS pb
    ON pb.production_date = sc.production_date
   AND pb.line_id = sc.line_id
   AND pb.shift = sc.shift
WHERE pb.batch_id IS NULL
GROUP BY
    sc.line_id,
    sc.line_name,
    sc.shift
ORDER BY
    sc.line_id,
    sc.shift;
