-- =====================================================================
-- Lab 5: Subqueries and Analytical Queries
-- Team B | Variant 2: Production and Procurement ("Pitanie+" System)
-- =====================================================================

-- Task B-1. Purchase positions with unit price > 110% of quarterly average for the same material

SELECT
(SELECT s.supplier_name FROM suppliers AS s WHERE s.supplier_id = po.supplier_id) AS supplier_name,
(SELECT rm.material_name FROM raw_materials AS rm WHERE rm.material_id = poi.material_id) AS material_name,
COUNT(*) AS expensive_items_cnt
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
WHERE poi.unit_price > 1.10 * (
SELECT AVG(poi2.unit_price)
FROM purchase_order_items AS poi2
JOIN purchase_orders AS po2 ON po2.po_id = poi2.po_id
WHERE poi2.material_id = poi.material_id
AND DATE_TRUNC('quarter', po2.order_date) = DATE_TRUNC('quarter', po.order_date)
)
GROUP BY po.supplier_id, poi.material_id
ORDER BY expensive_items_cnt DESC;

-- Task B-2. Overpayment analysis relative to the best (minimum average) supplier price

SELECT
s.supplier_name,
ROUND(SUM(poi.quantity * (poi.unit_price - best.min_avg_price)), 2) AS total_overpayment
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
JOIN (
SELECT material_id, MIN(avg_sup_price) AS min_avg_price
FROM (
SELECT po_sub.supplier_id, poi_sub.material_id, AVG(poi_sub.unit_price) AS avg_sup_price
FROM purchase_order_items AS poi_sub
JOIN purchase_orders AS po_sub ON po_sub.po_id = poi_sub.po_id
GROUP BY po_sub.supplier_id, poi_sub.material_id
) AS sup_avg
GROUP BY material_id
) AS best ON best.material_id = poi.material_id
GROUP BY s.supplier_id, s.supplier_name
ORDER BY total_overpayment DESC;

-- Task B-2 (Sub-query). Purchasing agents responsible for orders from ООО "АгроСнаб-М"
SELECT
e.employee_id,
e.full_name,
COUNT(po.po_id) AS orders_cnt
FROM purchase_orders AS po
JOIN employees AS e ON e.employee_id = po.employee_id
WHERE po.supplier_id = (
SELECT s.supplier_id
FROM suppliers AS s
WHERE s.supplier_name = 'ООО "АгроСнаб-М"'
)
GROUP BY e.employee_id, e.full_name
ORDER BY orders_cnt DESC;

-- Task B-3. Supplier Reliability Benchmarks (using NOT EXISTS)

-- B-3.1. Suppliers with no rejected items
SELECT s.supplier_id, s.supplier_name
FROM suppliers AS s
WHERE NOT EXISTS (
SELECT 1
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
WHERE po.supplier_id = s.supplier_id
AND poi.quality_status = 'Отклонено'
)
ORDER BY s.supplier_id;

-- B-3.2. Suppliers with no rejected or partially accepted items ("Ideal" suppliers)
SELECT s.supplier_id, s.supplier_name
FROM suppliers AS s
WHERE NOT EXISTS (
SELECT 1
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
WHERE po.supplier_id = s.supplier_id
AND poi.quality_status IN ('Отклонено', 'Принято частично')
)
ORDER BY s.supplier_id;

-- B-3.3. Price comparison for sugar (ID = 4) between ideal supplier and ООО "АгроСнаб-М"
SELECT
s.supplier_name,
COUNT(poi.po_item_id) AS deliveries_cnt,
ROUND(AVG(poi.unit_price), 2) AS avg_sugar_price,
ROUND(SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity), 2) AS weighted_sugar_price
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
WHERE poi.material_id = 4
AND (
s.supplier_name = 'ООО "АгроСнаб-М"'
OR NOT EXISTS (
SELECT 1
FROM purchase_order_items AS poi2
JOIN purchase_orders AS po2 ON po2.po_id = poi2.po_id
WHERE po2.supplier_id = s.supplier_id
AND poi2.quality_status IN ('Отклонено', 'Принято частично')
)
)
GROUP BY s.supplier_id, s.supplier_name
ORDER BY weighted_sugar_price;

-- Task B-4. Defect analysis by line and shift (batches above line average)

SELECT
b.line_id,
l.line_name,
b.shift,
COUNT(*) AS batches_above_line_avg
FROM production_batches AS b
JOIN production_lines AS l ON l.line_id = b.line_id
WHERE (1.0 * b.defect_qty / NULLIF(b.produced_qty, 0)) > (
SELECT 1.0 * SUM(b2.defect_qty) / NULLIF(SUM(b2.produced_qty), 0)
FROM production_batches AS b2
WHERE b2.line_id = b.line_id
)
GROUP BY b.line_id, l.line_name, b.shift
ORDER BY b.line_id, b.shift;

-- Task B-5. Materials both purchased and written off

SELECT
rm.material_id,
rm.material_name,
rm.shelf_life_days,
COALESCE(pur.total_received, 0) AS total_received,
COALESCE(w.total_written_off, 0) AS total_written_off,
COALESCE(w.total_writeoff_amount, 0) AS total_writeoff_amount
FROM raw_materials AS rm
LEFT JOIN (
SELECT poi.material_id, SUM(poi.received_qty) AS total_received
FROM purchase_order_items AS poi
GROUP BY poi.material_id
) AS pur ON pur.material_id = rm.material_id
LEFT JOIN (
SELECT mw.material_id, SUM(mw.quantity) AS total_written_off, SUM(mw.amount) AS total_writeoff_amount
FROM material_writeoffs AS mw
WHERE mw.quantity > 0
GROUP BY mw.material_id
) AS w ON w.material_id = rm.material_id
WHERE EXISTS (
SELECT 1
FROM purchase_order_items AS poi
WHERE poi.material_id = rm.material_id
)
AND EXISTS (
SELECT 1
FROM material_writeoffs AS mw
WHERE mw.material_id = rm.material_id
AND mw.quantity > 0
)
ORDER BY total_writeoff_amount DESC;

-- Task B-6. Raw material overconsumption analysis (> 2% threshold)

SELECT
rm.material_id,
rm.material_name,
rm.unit,
ROUND(COALESCE(norm.norm_qty, 0), 2) AS norm_qty,
ROUND(COALESCE(fact.fact_qty, 0), 2) AS fact_qty,
ROUND(COALESCE(fact.fact_qty, 0) - COALESCE(norm.norm_qty, 0), 2) AS diff_qty,
ROUND(100.0 * (COALESCE(fact.fact_qty, 0) - COALESCE(norm.norm_qty, 0)) / NULLIF(norm.norm_qty, 0), 2) AS overconsumption_pct,
ROUND((COALESCE(fact.fact_qty, 0) - COALESCE(norm.norm_qty, 0)) * COALESCE(p.avg_price, 0), 2) AS overconsumption_rub
FROM raw_materials AS rm
LEFT JOIN (
SELECT r.material_id, SUM(b.produced_qty * r.qty_per_unit) AS norm_qty
FROM production_batches AS b
JOIN recipes AS r ON r.product_id = b.product_id
GROUP BY r.material_id
) AS norm ON norm.material_id = rm.material_id
LEFT JOIN (
SELECT mc.material_id, SUM(mc.quantity) AS fact_qty
FROM material_consumption AS mc
GROUP BY mc.material_id
) AS fact ON fact.material_id = rm.material_id
LEFT JOIN (
SELECT poi.material_id, SUM(poi.quantity * poi.unit_price) / NULLIF(SUM(poi.quantity), 0) AS avg_price
FROM purchase_order_items AS poi
GROUP BY poi.material_id
) AS p ON p.material_id = rm.material_id
WHERE COALESCE(fact.fact_qty, 0) > 1.02 * COALESCE(norm.norm_qty, 0)
ORDER BY overconsumption_pct DESC;