-- Лабораторная № 1. Команда Б: Б.3–Б.4
SET search_path TO pitanie, public;

-- Б.3. Производственные линии и ответственные сотрудники.
SELECT l.*,
       e.full_name AS responsible
FROM production_lines AS l
JOIN employees AS e
  ON e.employee_id = l.responsible_id
ORDER BY l.line_id;

-- Б.4. Ночная партия. Шаг 1: сведения о партии.
SELECT b.*,
       p.product_name,
       e.full_name AS operator
FROM production_batches AS b
JOIN products AS p
  ON p.product_id = b.product_id
JOIN employees AS e
  ON e.employee_id = b.operator_id
WHERE b.batch_number = 'П250312-3Н';

-- Шаг 2: рецептура ночной партии.
SELECT m.material_name,
       m.unit,
       r.qty_per_unit
FROM recipes AS r
JOIN raw_materials AS m
  ON m.material_id = r.material_id
WHERE r.product_id = 7;

-- Шаг 3: фактический и нормативный расход для ночной партии.
SELECT m.material_name,
       mc.quantity AS fact_qty,
       ROUND(r.qty_per_unit * b.produced_qty, 3) AS norm_qty
FROM material_consumption AS mc
JOIN production_batches AS b
  ON b.batch_id = mc.batch_id
JOIN raw_materials AS m
  ON m.material_id = mc.material_id
JOIN recipes AS r
  ON r.product_id = b.product_id
 AND r.material_id = mc.material_id
WHERE b.batch_number = 'П250312-3Н';

-- Б.4. Дневная партия того же дня. Шаг 1.
SELECT b.*,
       p.product_name,
       e.full_name AS operator
FROM production_batches AS b
JOIN products AS p
  ON p.product_id = b.product_id
JOIN employees AS e
  ON e.employee_id = b.operator_id
WHERE b.batch_number = 'П250312-3Д';

-- Шаг 2: рецептура дневной партии.
-- Подзапрос берёт product_id непосредственно из найденной партии.
SELECT m.material_name,
       m.unit,
       r.qty_per_unit
FROM recipes AS r
JOIN raw_materials AS m
  ON m.material_id = r.material_id
WHERE r.product_id = (
    SELECT b.product_id
    FROM production_batches AS b
    WHERE b.batch_number = 'П250312-3Д'
);

-- Шаг 3: фактический и нормативный расход для дневной партии.
SELECT m.material_name,
       mc.quantity AS fact_qty,
       ROUND(r.qty_per_unit * b.produced_qty, 3) AS norm_qty
FROM material_consumption AS mc
JOIN production_batches AS b
  ON b.batch_id = mc.batch_id
JOIN raw_materials AS m
  ON m.material_id = mc.material_id
JOIN recipes AS r
  ON r.product_id = b.product_id
 AND r.material_id = mc.material_id
WHERE b.batch_number = 'П250312-3Д';
