-- =====================================================================
-- Лабораторная работа № 4. Группировка и агрегация в SQL (Advanced SQL)
-- Вариант 2 (Команда Б: Производство и снабжение — система "Pitanie+")
-- =====================================================================

-- ---------------------------------------------------------------------
-- Задание Б1. Анализ брака по производственным линиям и сменам (CUBE)
-- ---------------------------------------------------------------------
SELECT 
    l.line_name,
    b.shift,
    SUM(b.produced_qty) AS total_produced,
    SUM(b.defect_qty) AS total_defect,
    ROUND(100.0 * SUM(b.defect_qty) / NULLIF(SUM(b.produced_qty) + SUM(b.defect_qty), 0), 2) AS defect_pct
FROM production_batches AS b
JOIN production_lines AS l ON l.line_id = b.line_id
GROUP BY CUBE (l.line_name, b.shift)
ORDER BY l.line_name NULLS LAST, b.shift NULLS LAST;


-- ---------------------------------------------------------------------
-- Задание Б2.1. Цены материалов по поставщикам (сахар, глюкоза, какао: IDs 4, 5, 8)
-- ---------------------------------------------------------------------
SELECT 
    s.supplier_name,
    rm.material_id,
    rm.material_name,
    COUNT(poi.po_item_id) AS deliveries_cnt,
    SUM(poi.quantity) AS total_qty,
    ROUND(SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity), 2) AS weighted_avg_price,
    ROUND(AVG(poi.unit_price), 2) AS simple_avg_price
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm ON rm.material_id = poi.material_id
WHERE poi.material_id IN (4, 5, 8)
GROUP BY s.supplier_name, rm.material_id, rm.material_name
ORDER BY rm.material_id, weighted_avg_price DESC;


-- ---------------------------------------------------------------------
-- Задание Б2.2. Переплата по ООО "АгроСнаб-М" (supplier_id = 3)
-- ---------------------------------------------------------------------
SELECT 
    rm.material_name,
    SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3) AS agrosnab_qty,
    ROUND(SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id = 3) / NULLIF(SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3), 0), 2) AS agrosnab_price,
    ROUND(SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id <> 3) / NULLIF(SUM(poi.quantity) FILTER (WHERE po.supplier_id <> 3), 0), 2) AS others_price,
    ROUND(
        SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3) * 
        (
            COALESCE(SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id = 3) / NULLIF(SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3), 0), 0) - 
            COALESCE(SUM(poi.quantity * poi.unit_price) FILTER (WHERE po.supplier_id <> 3) / NULLIF(SUM(poi.quantity) FILTER (WHERE po.supplier_id <> 3), 0), 0)
        ), 2
    ) AS overpayment
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN raw_materials AS rm ON rm.material_id = poi.material_id
WHERE poi.material_id IN (
    SELECT DISTINCT material_id 
    FROM purchase_orders po2 
    JOIN purchase_order_items poi2 ON poi2.po_id = po2.po_id 
    WHERE po2.supplier_id = 3
)
GROUP BY rm.material_id, rm.material_name
ORDER BY overpayment DESC NULLS LAST;


-- ---------------------------------------------------------------------
-- Задание Б2.3. Доля позиций каждого закупщика у ООО "АгроСнаб-М"
-- ---------------------------------------------------------------------
SELECT 
    e.employee_id,
    e.full_name,
    COUNT(poi.po_item_id) AS total_positions,
    COUNT(poi.po_item_id) FILTER (WHERE po.supplier_id = 3) AS agrosnab_positions,
    ROUND(100.0 * COUNT(poi.po_item_id) FILTER (WHERE po.supplier_id = 3) / COUNT(poi.po_item_id), 2) AS agrosnab_pct
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN employees AS e ON e.employee_id = po.employee_id
GROUP BY e.employee_id, e.full_name
ORDER BY agrosnab_pct DESC;


-- ---------------------------------------------------------------------
-- Задание Б3. Опоздания и качество поставщиков (HAVING avg_delay > 1)
-- ---------------------------------------------------------------------
SELECT 
    s.supplier_id,
    s.supplier_name,
    COUNT(poi.po_item_id) AS items_cnt,
    ROUND(AVG(poi.received_date - po.expected_date), 2) AS avg_delay_days,
    MAX(poi.received_date - po.expected_date) AS max_delay_days,
    COUNT(poi.po_item_id) FILTER (WHERE poi.received_date > po.expected_date) AS delayed_items_cnt,
    COUNT(poi.po_item_id) FILTER (WHERE poi.quality_status IN ('Принято частично', 'Отклонено')) AS quality_issues_cnt,
    ROUND(100.0 * SUM(poi.received_qty) / NULLIF(SUM(poi.quantity), 0), 2) AS accepted_volume_pct
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
GROUP BY s.supplier_id, s.supplier_name
HAVING AVG(poi.received_date - po.expected_date) > 1
ORDER BY avg_delay_days DESC;


-- ---------------------------------------------------------------------
-- Задание Б4.1. Часы простоя по линиям и годам с ROLLUP
-- ---------------------------------------------------------------------
SELECT 
    CASE WHEN GROUPING(l.line_name) = 1 THEN 'ВСЕГО' ELSE l.line_name END AS line_name,
    CASE WHEN GROUPING(l.line_name) = 1 THEN ''
         WHEN GROUPING(EXTRACT(YEAR FROM ed.start_time)) = 1 THEN 'Итого по линии'
         ELSE EXTRACT(YEAR FROM ed.start_time)::text END AS yr,
    COUNT(ed.downtime_id) AS downtimes_cnt,
    COUNT(ed.downtime_id) - COUNT(ed.end_time) AS open_downtimes_cnt,
    ROUND(SUM(EXTRACT(EPOCH FROM (ed.end_time - ed.start_time)) / 3600.0), 1) AS downtime_hours
FROM equipment_downtime AS ed
JOIN production_lines AS l ON l.line_id = ed.line_id
GROUP BY ROLLUP (l.line_name, EXTRACT(YEAR FROM ed.start_time))
ORDER BY GROUPING(l.line_name), l.line_name, GROUPING(EXTRACT(YEAR FROM ed.start_time)), yr;


-- ---------------------------------------------------------------------
-- Задание Б4.2. Сводная таблица по простоям и поломкам по линиям
-- ---------------------------------------------------------------------
SELECT 
    l.line_name,
    ROUND(SUM(EXTRACT(EPOCH FROM (ed.end_time - ed.start_time)) / 3600.0) 
          FILTER (WHERE EXTRACT(YEAR FROM ed.start_time) = 2024), 1) AS hours_2024,
    ROUND(SUM(EXTRACT(EPOCH FROM (ed.end_time - ed.start_time)) / 3600.0) 
          FILTER (WHERE EXTRACT(YEAR FROM ed.start_time) = 2025), 1) AS hours_2025,
    COUNT(ed.downtime_id) FILTER (WHERE ed.downtime_category = 'Поломка оборудования') AS breakdowns_cnt
FROM equipment_downtime AS ed
JOIN production_lines AS l ON l.line_id = ed.line_id
GROUP BY l.line_id, l.line_name
ORDER BY l.line_id;


-- ---------------------------------------------------------------------
-- Задание Б4.3. Расходы на ремонт оборудования по годам
-- ---------------------------------------------------------------------
SELECT 
    EXTRACT(YEAR FROM expense_date)::int AS yr,
    ROUND(SUM(amount) / 1e6, 2) AS repair_cost_mln,
    SUM(amount) AS repair_cost_rub
FROM expenses
WHERE expense_category = 'Ремонт оборудования'
GROUP BY EXTRACT(YEAR FROM expense_date)
ORDER BY yr;


-- ---------------------------------------------------------------------
-- Задание Б5.1. Списания сырья (сумма > 50 000 руб.)
-- ---------------------------------------------------------------------
SELECT 
    rm.material_id,
    rm.material_name,
    COUNT(mw.writeoff_id) AS writeoffs_cnt,
    SUM(mw.quantity) AS total_qty,
    SUM(mw.amount) AS total_amount,
    ROUND(100.0 * SUM(mw.amount) / (SELECT SUM(amount) FROM material_writeoffs), 1) AS share_pct,
    STRING_AGG(DISTINCT mw.reason, '; ' ORDER BY mw.reason) AS reasons
FROM material_writeoffs AS mw
JOIN raw_materials AS rm ON rm.material_id = mw.material_id
GROUP BY rm.material_id, rm.material_name
HAVING SUM(mw.amount) > 50000
ORDER BY total_amount DESC;


-- ---------------------------------------------------------------------
-- Задание Б5.2. Закупленный и израсходованный объём по годам для лидера (ID = 10)
-- ---------------------------------------------------------------------
SELECT 
    COALESCE(pur.yr, cons.yr) AS yr,
    COALESCE(pur.purchased_qty, 0) AS purchased_qty,
    COALESCE(cons.consumed_qty, 0) AS consumed_qty,
    COALESCE(pur.purchased_qty, 0) - COALESCE(cons.consumed_qty, 0) AS diff_qty
FROM (
    SELECT EXTRACT(YEAR FROM COALESCE(poi.received_date, po.order_date))::int AS yr,
           SUM(poi.received_qty) AS purchased_qty
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po ON po.po_id = poi.po_id
    WHERE poi.material_id = 10
    GROUP BY EXTRACT(YEAR FROM COALESCE(poi.received_date, po.order_date))
) AS pur
FULL OUTER JOIN (
    SELECT EXTRACT(YEAR FROM b.production_date)::int AS yr,
           SUM(mc.quantity) AS consumed_qty
    FROM material_consumption AS mc
    JOIN production_batches AS b ON b.batch_id = mc.batch_id
    WHERE mc.material_id = 10
    GROUP BY EXTRACT(YEAR FROM b.production_date)
) AS cons ON pur.yr = cons.yr
ORDER BY yr;


-- ---------------------------------------------------------------------
-- Задание Б6. Нормативный и фактический расход сырья по материалам
-- ---------------------------------------------------------------------
SELECT 
    rm.material_id,
    rm.material_name,
    rm.unit,
    ROUND(COALESCE(norm.norm_qty, 0), 2) AS norm_qty,
    ROUND(COALESCE(fact.fact_qty, 0), 2) AS fact_qty,
    ROUND(COALESCE(fact.fact_qty, 0) - COALESCE(norm.norm_qty, 0), 2) AS diff_qty,
    ROUND(100.0 * (COALESCE(fact.fact_qty, 0) - COALESCE(norm.norm_qty, 0)) / NULLIF(norm.norm_qty, 0), 2) AS overconsumption_pct
FROM raw_materials AS rm
LEFT JOIN (
    SELECT r.material_id,
           SUM(b.produced_qty * r.qty_per_unit) AS norm_qty
    FROM production_batches AS b
    JOIN recipes AS r ON r.product_id = b.product_id
    GROUP BY r.material_id
) AS norm ON norm.material_id = rm.material_id
LEFT JOIN (
    SELECT mc.material_id,
           SUM(mc.quantity) AS fact_qty
    FROM material_consumption AS mc
    GROUP BY mc.material_id
) AS fact ON fact.material_id = rm.material_id
ORDER BY overconsumption_pct DESC NULLS LAST;


-- ---------------------------------------------------------------------
-- Задание Б7. Сравнение плановых продаж, факта продаж и выпуска (2025 год)
-- ---------------------------------------------------------------------
SELECT 
    pc.category_id,
    pc.category_name,
    ROUND(COALESCE(p.plan_sum, 0), 2) AS plan_sales_sum,
    ROUND(COALESCE(f.fact_sales_sum, 0), 2) AS fact_sales_sum,
    ROUND(COALESCE(f.fact_sales_sum, 0) - COALESCE(p.plan_sum, 0), 2) AS sales_diff,
    ROUND(100.0 * COALESCE(f.fact_sales_sum, 0) / NULLIF(p.plan_sum, 0), 2) AS plan_exec_pct,
    ROUND(COALESCE(pr.produced_sum, 0), 2) AS produced_cost_sum
FROM product_categories AS pc
LEFT JOIN (
    SELECT category_id, SUM(plan_amount) AS plan_sum
    FROM sales_plan
    WHERE plan_year = 2025
    GROUP BY category_id
) AS p ON p.category_id = pc.category_id
LEFT JOIN (
    SELECT COALESCE(cat.parent_category_id, cat.category_id) AS top_cat_id,
           SUM(oi.quantity * oi.unit_price * (1 - COALESCE(oi.discount_pct, 0) / 100.0)) AS fact_sales_sum
    FROM order_items AS oi
    JOIN orders AS o ON o.order_id = oi.order_id
    JOIN products AS prd ON prd.product_id = oi.product_id
    JOIN product_categories AS cat ON cat.category_id = prd.category_id
    WHERE EXTRACT(YEAR FROM o.order_date) = 2025
    GROUP BY COALESCE(cat.parent_category_id, cat.category_id)
) AS f ON f.top_cat_id = pc.category_id
LEFT JOIN (
    SELECT COALESCE(cat.parent_category_id, cat.category_id) AS top_cat_id,
           SUM(b.produced_qty * prd.standard_cost) AS produced_sum
    FROM production_batches AS b
    JOIN products AS prd ON prd.product_id = b.product_id
    JOIN product_categories AS cat ON cat.category_id = prd.category_id
    WHERE EXTRACT(YEAR FROM b.production_date) = 2025
    GROUP BY COALESCE(cat.parent_category_id, cat.category_id)
) AS pr ON pr.top_cat_id = pc.category_id
WHERE pc.parent_category_id IS NULL
ORDER BY pc.category_id;


-- ---------------------------------------------------------------------
-- Задание Б8. Итоговая сводная витрина по производственным линиям (2025 год)
-- ---------------------------------------------------------------------
SELECT 
    l.line_id,
    l.line_name,
    COALESCE(b.batches_cnt, 0) AS batches_cnt,
    COALESCE(b.total_produced_qty, 0) AS total_produced_qty,
    COALESCE(b.total_defect_qty, 0) AS total_defect_qty,
    ROUND(100.0 * COALESCE(b.total_defect_qty, 0) / NULLIF(COALESCE(b.total_produced_qty, 0) + COALESCE(b.total_defect_qty, 0), 0), 2) AS defect_pct,
    COALESCE(d.downtimes_cnt, 0) AS downtimes_cnt,
    COALESCE(d.breakdowns_cnt, 0) AS breakdowns_cnt,
    COALESCE(d.downtime_hours, 0) AS downtime_hours
FROM production_lines AS l
LEFT JOIN (
    SELECT 
        line_id,
        COUNT(batch_id) AS batches_cnt,
        SUM(produced_qty) AS total_produced_qty,
        SUM(defect_qty) AS total_defect_qty
    FROM production_batches
    WHERE EXTRACT(YEAR FROM production_date) = 2025
    GROUP BY line_id
) AS b ON b.line_id = l.line_id
LEFT JOIN (
    SELECT 
        line_id,
        COUNT(downtime_id) AS downtimes_cnt,
        COUNT(downtime_id) FILTER (WHERE downtime_category = 'Поломка оборудования') AS breakdowns_cnt,
        ROUND(SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600.0), 1) AS downtime_hours
    FROM equipment_downtime
    WHERE EXTRACT(YEAR FROM start_time) = 2025
    GROUP BY line_id
) AS d ON d.line_id = l.line_id
ORDER BY l.line_id;