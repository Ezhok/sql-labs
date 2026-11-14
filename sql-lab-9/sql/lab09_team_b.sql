
-- Модуль 9. Лабораторная работа «Витрины аналитика»: представления, CTE и табличные функции
-- Вариант 2. Команда Б «Производство и закупки»
--
-- Исходные данные: схема pitanie
-- Создаваемые объекты: схема stud_komanda_b

SET search_path TO stud_komanda_b, pitanie, public;


-- ============================================================
-- Б1. Представление v_batch_quality
-- ============================================================

CREATE OR REPLACE VIEW stud_komanda_b.v_batch_quality AS
SELECT
    b.batch_id,
    b.batch_number,
    b.production_date,
    EXTRACT(YEAR FROM b.production_date)::int AS prod_year,
    b.line_id,
    l.line_name,
    b.shift,
    b.operator_id,
    e.full_name AS operator_name,
    b.product_id,
    p.product_name,
    b.planned_qty,
    b.produced_qty,
    b.defect_qty,
    ROUND(100.0 * b.defect_qty / NULLIF(b.produced_qty, 0), 2) AS defect_pct,
    ROUND(100.0 * b.produced_qty / NULLIF(b.planned_qty, 0), 2) AS plan_pct,
    b.defect_qty * p.standard_cost AS defect_cost
FROM pitanie.production_batches AS b
JOIN pitanie.production_lines AS l
    ON l.line_id = b.line_id
JOIN pitanie.products AS p
    ON p.product_id = b.product_id
LEFT JOIN pitanie.employees AS e
    ON e.employee_id = b.operator_id;

COMMENT ON VIEW stud_komanda_b.v_batch_quality IS
    'Партии: брак, выполнение плана, стоимость брака';


-- Общая статистика по партиям и стоимости брака

SELECT
    COUNT(*) AS batches,
    ROUND(SUM(defect_cost) / 1e6, 2) AS defect_cost_mln
FROM v_batch_quality;


-- Брак и стоимость брака по линии и смене

SELECT
    line_id,
    shift,
    COUNT(*) AS batches,
    ROUND(100.0 * SUM(defect_qty) / SUM(produced_qty), 2) AS defect_pct,
    ROUND(SUM(defect_cost), 0) AS defect_cost
FROM v_batch_quality
GROUP BY line_id, shift
ORDER BY defect_pct DESC;


-- ============================================================
-- Б2. Представление v_supplier_price_benchmark
-- ============================================================

CREATE OR REPLACE VIEW stud_komanda_b.v_supplier_price_benchmark AS
WITH base AS (
    SELECT
        poi.material_id,
        po.supplier_id,
        SUM(poi.quantity) AS qty,
        SUM(poi.quantity * poi.unit_price) AS amount,
        SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity) AS avg_price
    FROM pitanie.purchase_order_items AS poi
    JOIN pitanie.purchase_orders AS po
        ON po.po_id = poi.po_id
    GROUP BY poi.material_id, po.supplier_id
),
w AS (
    SELECT
        base.*,
        MIN(avg_price) OVER (
            PARTITION BY material_id
        ) AS best_price,
        SUM(qty) OVER (
            PARTITION BY material_id
        ) AS material_qty,
        COUNT(*) OVER (
            PARTITION BY material_id
        ) AS suppliers_cnt
    FROM base
)
SELECT
    w.material_id,
    m.material_name,
    w.supplier_id,
    s.supplier_name,
    w.qty,
    ROUND(w.amount, 2) AS amount,
    ROUND(w.avg_price, 2) AS avg_price,
    ROUND(w.best_price, 2) AS best_price,
    ROUND(100 * (w.avg_price / w.best_price - 1), 1) AS overprice_pct,
    ROUND(w.qty * (w.avg_price - w.best_price), 2) AS overpay,
    ROUND(100.0 * w.qty / w.material_qty, 1) AS qty_share_pct,
    w.suppliers_cnt
FROM w
JOIN pitanie.raw_materials AS m
    ON m.material_id = w.material_id
JOIN pitanie.suppliers AS s
    ON s.supplier_id = w.supplier_id;

COMMENT ON VIEW stud_komanda_b.v_supplier_price_benchmark IS
    'Средняя цена поставщика по материалу против лучшей, переплата';


-- Топ-6 переплат по материалам

SELECT
    material_name,
    supplier_name,
    avg_price,
    best_price,
    overprice_pct,
    overpay,
    qty_share_pct
FROM v_supplier_price_benchmark
WHERE suppliers_cnt > 1
ORDER BY overpay DESC
LIMIT 6;


-- Общая переплата по поставщикам

SELECT
    supplier_name,
    ROUND(SUM(overpay), 0) AS overpay_total
FROM v_supplier_price_benchmark
GROUP BY supplier_name
HAVING SUM(overpay) > 0
ORDER BY overpay_total DESC;


-- ============================================================
-- Б3. Материализованное представление mv_material_overuse
-- ============================================================

DROP MATERIALIZED VIEW IF EXISTS stud_komanda_b.mv_material_overuse;

CREATE MATERIALIZED VIEW stud_komanda_b.mv_material_overuse AS
WITH norm AS (
    SELECT
        b.line_id,
        b.shift,
        r.material_id,
        SUM(r.qty_per_unit * b.produced_qty) AS norm_qty
    FROM pitanie.production_batches AS b
    JOIN pitanie.recipes AS r
        ON r.product_id = b.product_id
    GROUP BY b.line_id, b.shift, r.material_id
),
fact AS (
    SELECT
        b.line_id,
        b.shift,
        mc.material_id,
        SUM(mc.quantity) AS fact_qty
    FROM pitanie.material_consumption AS mc
    JOIN pitanie.production_batches AS b
        ON b.batch_id = mc.batch_id
    GROUP BY b.line_id, b.shift, mc.material_id
),
price AS (
    SELECT
        material_id,
        SUM(quantity * unit_price) / SUM(quantity) AS avg_price
    FROM pitanie.purchase_order_items
    GROUP BY material_id
)
SELECT
    n.line_id,
    n.shift,
    n.material_id,
    ROUND(n.norm_qty, 3) AS norm_qty,
    ROUND(f.fact_qty, 3) AS fact_qty,
    ROUND(100 * (f.fact_qty / n.norm_qty - 1), 2) AS overuse_pct,
    ROUND((f.fact_qty - n.norm_qty) * p.avg_price, 2) AS overuse_cost
FROM norm AS n
JOIN fact AS f
    ON f.line_id = n.line_id
   AND f.shift = n.shift
   AND f.material_id = n.material_id
LEFT JOIN price AS p
    ON p.material_id = n.material_id;

CREATE UNIQUE INDEX
    ON stud_komanda_b.mv_material_overuse (line_id, shift, material_id);

COMMENT ON MATERIALIZED VIEW stud_komanda_b.mv_material_overuse IS
    'Перерасход сырья к норме по линии, смене, материалу';

REFRESH MATERIALIZED VIEW CONCURRENTLY stud_komanda_b.mv_material_overuse;


-- Общая статистика перерасхода

SELECT
    COUNT(*) AS all_rows,
    COUNT(*) FILTER (WHERE overuse_pct > 3) AS over_3pct,
    ROUND(AVG(overuse_pct) FILTER (WHERE overuse_pct <= 3), 2) AS normal_bg_pct
FROM mv_material_overuse;


-- Материалы с перерасходом более 3 %

SELECT
    o.line_id,
    o.shift,
    m.material_name,
    o.overuse_pct,
    o.overuse_cost
FROM mv_material_overuse AS o
JOIN pitanie.raw_materials AS m
    ON m.material_id = o.material_id
WHERE o.overuse_pct > 3
ORDER BY o.overuse_cost DESC;


-- ============================================================
-- Б4. CTE-цепочка «Стоимость потерь производства 2025»
-- ============================================================

WITH defects AS (
    SELECT
        line_id,
        SUM(defect_cost) AS defect_cost
    FROM v_batch_quality
    WHERE prod_year = 2025
    GROUP BY line_id
),
line_margin AS (
    SELECT
        b.line_id,
        SUM(b.produced_qty * (p.base_price - p.standard_cost))
            / SUM(b.produced_qty) AS unit_margin
    FROM pitanie.production_batches AS b
    JOIN pitanie.products AS p
        ON p.product_id = b.product_id
    WHERE b.production_date >= DATE '2025-01-01'
      AND b.production_date < DATE '2026-01-01'
    GROUP BY b.line_id
),
downtime AS (
    SELECT
        line_id,
        SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600 AS hours
    FROM pitanie.equipment_downtime
    WHERE end_time IS NOT NULL
      AND start_time >= '2025-01-01'
      AND start_time < '2026-01-01'
    GROUP BY line_id
),
downtime_cost AS (
    SELECT
        d.line_id,
        d.hours,
        d.hours * l.capacity_per_hour * m.unit_margin AS cost
    FROM downtime AS d
    JOIN pitanie.production_lines AS l
        ON l.line_id = d.line_id
    JOIN line_margin AS m
        ON m.line_id = d.line_id
),
writeoffs AS (
    SELECT
        SUM(amount) AS amount
    FROM pitanie.material_writeoffs
    WHERE writeoff_date >= DATE '2025-01-01'
      AND writeoff_date < DATE '2026-01-01'
)
SELECT
    'Линия ' || df.line_id AS object,
    ROUND(df.defect_cost / 1e6, 2) AS defect_mln,
    ROUND(dc.hours, 1) AS downtime_h,
    ROUND(dc.cost / 1e6, 2) AS downtime_mln,
    ROUND((df.defect_cost + COALESCE(dc.cost, 0)) / 1e6, 2) AS total_mln
FROM defects AS df
LEFT JOIN downtime_cost AS dc
    ON dc.line_id = df.line_id

UNION ALL

SELECT
    'Списания сырья',
    NULL,
    NULL,
    NULL,
    ROUND(amount / 1e6, 2)
FROM writeoffs
ORDER BY total_mln DESC;


-- ============================================================
-- Б5. Рекурсивный CTE «Производственный персонал»
-- ============================================================

-- Иерархия сотрудников от руководителя с employee_id = 4

WITH RECURSIVE staff AS (
    SELECT
        employee_id,
        full_name,
        position,
        manager_id,
        1 AS lvl
    FROM pitanie.employees
    WHERE employee_id = 4

    UNION ALL

    SELECT
        e.employee_id,
        e.full_name,
        e.position,
        e.manager_id,
        s.lvl + 1
    FROM pitanie.employees AS e
    JOIN staff AS s
        ON e.manager_id = s.employee_id
)
SELECT
    lvl,
    full_name,
    position
FROM staff
ORDER BY lvl, full_name;


-- Брак операторов из построенной иерархии

WITH RECURSIVE staff AS (
    SELECT
        employee_id
    FROM pitanie.employees
    WHERE employee_id = 4

    UNION ALL

    SELECT
        e.employee_id
    FROM pitanie.employees AS e
    JOIN staff AS s
        ON e.manager_id = s.employee_id
)
SELECT
    q.operator_name,
    q.line_id,
    q.shift,
    COUNT(*) AS batches,
    ROUND(100.0 * SUM(q.defect_qty) / SUM(q.produced_qty), 2) AS defect_pct
FROM v_batch_quality AS q
WHERE q.operator_id IN (
    SELECT employee_id
    FROM staff
)
GROUP BY q.operator_name, q.line_id, q.shift
ORDER BY defect_pct DESC
LIMIT 6;


-- ============================================================
-- Б6. Табличная функция fn_line_report
-- ============================================================

CREATE OR REPLACE FUNCTION stud_komanda_b.fn_line_report(
    p_line int,
    p_from date,
    p_to date
)
RETURNS TABLE (
    month date,
    batches bigint,
    planned_qty bigint,
    produced_qty bigint,
    defect_pct numeric,
    plan_pct numeric,
    downtime_hours numeric
)
LANGUAGE sql STABLE AS $$
    WITH cal AS (
        SELECT
            generate_series(
                date_trunc('month', p_from),
                date_trunc('month', p_to),
                INTERVAL '1 month'
            )::date AS m
    ),
    b AS (
        SELECT
            date_trunc('month', production_date)::date AS m,
            COUNT(*) AS batches,
            SUM(planned_qty) AS planned,
            SUM(produced_qty) AS produced,
            SUM(defect_qty) AS defects
        FROM pitanie.production_batches
        WHERE line_id = p_line
          AND production_date BETWEEN p_from AND p_to
        GROUP BY 1
    ),
    d AS (
        SELECT
            date_trunc('month', start_time)::date AS m,
            SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600 AS hours
        FROM pitanie.equipment_downtime
        WHERE line_id = p_line
          AND end_time IS NOT NULL
          AND start_time >= p_from
          AND start_time < p_to + 1
        GROUP BY 1
    )
    SELECT
        cal.m,
        COALESCE(b.batches, 0),
        COALESCE(b.planned, 0),
        COALESCE(b.produced, 0),
        ROUND(100.0 * b.defects / NULLIF(b.produced, 0), 2),
        ROUND(100.0 * b.produced / NULLIF(b.planned, 0), 1),
        ROUND(COALESCE(d.hours, 0), 1)
    FROM cal
    LEFT JOIN b
        ON b.m = cal.m
    LEFT JOIN d
        ON d.m = cal.m
    ORDER BY cal.m;
$$;

COMMENT ON FUNCTION stud_komanda_b.fn_line_report(int, date, date) IS
    'Помесячный отчёт по линии за период';


-- Помесячный отчёт по линии 2 за 2025 год

SELECT *
FROM fn_line_report(2, '2025-01-01', '2025-12-31');


-- Сравнение выполнения плана и простоев по всем линиям за два года

SELECT
    l.line_id,
    y.yr,
    ROUND(SUM(r.produced_qty) * 100.0 / SUM(r.planned_qty), 1) AS plan_pct,
    ROUND(SUM(r.downtime_hours), 1) AS downtime_h
FROM pitanie.production_lines AS l
CROSS JOIN (VALUES (2024), (2025)) AS y(yr)
CROSS JOIN LATERAL fn_line_report(
    l.line_id,
    make_date(y.yr, 1, 1),
    make_date(y.yr, 12, 31)
) AS r
GROUP BY l.line_id, y.yr
ORDER BY l.line_id, y.yr;


-- ============================================================
-- Б7. Табличная функция fn_supplier_overpay
-- ============================================================

CREATE OR REPLACE FUNCTION stud_komanda_b.fn_supplier_overpay(
    p_material int
)
RETURNS TABLE (
    supplier_id int,
    supplier_name varchar,
    qty numeric,
    avg_price numeric,
    best_price numeric,
    overpay numeric
)
LANGUAGE sql STABLE AS $$
    SELECT
        v.supplier_id,
        v.supplier_name,
        v.qty,
        v.avg_price,
        v.best_price,
        v.overpay
    FROM stud_komanda_b.v_supplier_price_benchmark AS v
    WHERE v.material_id = p_material
    ORDER BY v.overpay DESC;
$$;

COMMENT ON FUNCTION stud_komanda_b.fn_supplier_overpay(int) IS
    'Поставщики материала и переплата к лучшей цене';


-- Поставщики и переплата по сахару-песку

SELECT *
FROM fn_supplier_overpay(4);


-- Топ-5 переплат по всем материалам

SELECT
    m.material_name,
    f.supplier_name,
    f.overpay
FROM pitanie.raw_materials AS m
CROSS JOIN LATERAL fn_supplier_overpay(m.material_id) AS f
ORDER BY f.overpay DESC
LIMIT 5;


-- Сотрудники, оформлявшие закупки сахара у ООО «АгроСнаб-М»

SELECT
    e.full_name AS buyer,
    COUNT(*) AS sugar_items
FROM pitanie.purchase_order_items AS poi
JOIN pitanie.purchase_orders AS po
    ON po.po_id = poi.po_id
JOIN pitanie.employees AS e
    ON e.employee_id = po.employee_id
WHERE poi.material_id = 4
  AND po.supplier_id = 3
GROUP BY e.full_name
ORDER BY sugar_items DESC;


-- ============================================================
-- Б8. Вывод для руководства
-- ============================================================

WITH overpay AS (
    SELECT
        'Переплата ООО "АгроСнаб-М"'::text AS finding,
        SUM(overpay) AS rub
    FROM v_supplier_price_benchmark
    WHERE supplier_id = 3
),
defect AS (
    SELECT
        'Брак: линия 3, ночная смена',
        SUM(defect_cost)
    FROM v_batch_quality
    WHERE line_id = 3
      AND shift = 'Ночь'
),
overuse AS (
    SELECT
        'Перерасход сырья: линия 5',
        SUM(overuse_cost)
    FROM mv_material_overuse
    WHERE line_id = 5
      AND overuse_pct > 3
),
writeoff AS (
    SELECT
        'Списания по сроку: наполнитель клубничный',
        SUM(amount)
    FROM pitanie.material_writeoffs
    WHERE reason = 'Истёк срок годности'
      AND material_id = 10
)
SELECT
    finding,
    ROUND(rub / 1e6, 2) AS mln_rub
FROM (
    SELECT * FROM overpay
    UNION ALL
    SELECT * FROM defect
    UNION ALL
    SELECT * FROM overuse
    UNION ALL
    SELECT * FROM writeoff
) AS t
ORDER BY mln_rub DESC;


-- ============================================================
-- Дополнительное задание. Функция fn_material_balance
-- ============================================================

CREATE OR REPLACE FUNCTION stud_komanda_b.fn_material_balance(
    p_material int,
    p_from date,
    p_to date
)
RETURNS TABLE (
    month date,
    received numeric,
    consumed numeric,
    written_off numeric
)
LANGUAGE sql STABLE AS $$
    WITH cal AS (
        SELECT
            generate_series(
                date_trunc('month', p_from),
                date_trunc('month', p_to),
                INTERVAL '1 month'
            )::date AS m
    )
    SELECT
        cal.m,
        COALESCE(
            (
                SELECT SUM(received_qty)
                FROM pitanie.purchase_order_items
                WHERE material_id = p_material
                  AND date_trunc('month', received_date) = cal.m
            ),
            0
        ),
        COALESCE(
            (
                SELECT SUM(mc.quantity)
                FROM pitanie.material_consumption AS mc
                JOIN pitanie.production_batches AS b
                    ON b.batch_id = mc.batch_id
                WHERE mc.material_id = p_material
                  AND date_trunc('month', b.production_date) = cal.m
            ),
            0
        ),
        COALESCE(
            (
                SELECT SUM(quantity)
                FROM pitanie.material_writeoffs
                WHERE material_id = p_material
                  AND date_trunc('month', writeoff_date) = cal.m
            ),
            0
        )
    FROM cal
    ORDER BY cal.m;
$$;

COMMENT ON FUNCTION stud_komanda_b.fn_material_balance(int, date, date) IS
    'Закуплено / израсходовано / списано по месяцам';


-- Топ-5 материалов по отношению закупок к расходу за 2024–2025 годы

SELECT
    m.material_name,
    ROUND(SUM(f.received), 0) AS received,
    ROUND(SUM(f.consumed), 0) AS consumed,
    ROUND(SUM(f.received) / NULLIF(SUM(f.consumed), 0), 2) AS ratio,
    COUNT(*) FILTER (
        WHERE f.received > f.consumed
    ) AS months_recv_gt_cons
FROM pitanie.raw_materials AS m
CROSS JOIN LATERAL fn_material_balance(
    m.material_id,
    '2024-01-01',
    '2025-12-31'
) AS f
GROUP BY m.material_name
ORDER BY ratio DESC
LIMIT 5;
