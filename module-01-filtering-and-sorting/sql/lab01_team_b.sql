-- Модуль 1. Первые улики: фильтрация и сортировка
-- Команда Б: Производство и закупки
-- PostgreSQL 16, база данных pitanie
--
-- ВАЖНО:
-- Запросы выполняются по одной таблице за раз.
-- Для перехода между таблицами ID выписываются вручную.
-- Б5.4 и Б8.2 используют ID, полученные предыдущими запросами.
--
-- О1. Всего заказов и отменённых заказов
SELECT COUNT(*) AS total_orders,
       COUNT(*) FILTER (WHERE status = 'Отменён') AS cancelled_orders
FROM purchase_orders;

-- О2. Продукция со сроком годности не более 14 дней
SELECT *
FROM products
WHERE shelf_life_days <= 14
ORDER BY shelf_life_days ASC, product_name ASC;

-- О3. Сотрудники без email ИЛИ телефона
SELECT *
FROM employees
WHERE email IS NULL
   OR phone IS NULL
ORDER BY department, full_name;

-- Б1.1. Партии с долей брака более 5%
SELECT *,
       defect_qty * 1.0 / produced_qty AS defect_ratio
FROM production_batches
WHERE defect_qty > 0.05 * produced_qty
ORDER BY defect_qty * 1.0 / produced_qty DESC;

-- Б1.2. Проверка исключений из гипотезы: линия 3, ночная смена
SELECT COUNT(*) AS exceptions
FROM production_batches
WHERE defect_qty > 0.05 * produced_qty
  AND NOT (line_id = 3 AND shift = 'Ночь');

-- Б1.3. Всего партий линии 3 в ночную смену
SELECT COUNT(*) AS total_batches
FROM production_batches
WHERE line_id = 3
  AND shift = 'Ночь';

-- Б2.1. Уникальные операторы проблемной смены
SELECT DISTINCT operator_id
FROM production_batches
WHERE line_id = 3
  AND shift = 'Ночь'
ORDER BY operator_id;

-- Б2.2. Данные найденных операторов (ID получены в Б2.1)
SELECT employee_id, full_name, position, department
FROM employees
WHERE employee_id IN (52, 58)
ORDER BY employee_id;

-- Б3. Незакрытые простои
SELECT *
FROM equipment_downtime
WHERE end_time IS NULL
ORDER BY start_time ASC;

-- Б4.1. Простои линии 2 за 2024 год
SELECT COUNT(*) AS downtime_2024
FROM equipment_downtime
WHERE line_id = 2
  AND start_time >= DATE '2024-01-01'
  AND start_time < DATE '2025-01-01';

-- Б4.2. Простои линии 2 за 2025 год
SELECT COUNT(*) AS downtime_2025
FROM equipment_downtime
WHERE line_id = 2
  AND start_time >= DATE '2025-01-01'
  AND start_time < DATE '2026-01-01';

-- Б4.3. Поломки линии 2 за 2025 год: износ или отказ
SELECT *
FROM equipment_downtime
WHERE line_id = 2
  AND start_time >= DATE '2025-01-01'
  AND start_time < DATE '2026-01-01'
  AND (
      reason ILIKE '%износ%'
      OR reason ILIKE 'отказ%'
  )
ORDER BY start_time;

-- Б5.1. Позиции с отклонением качества
SELECT *
FROM purchase_order_items
WHERE quality_status IN ('Принято частично', 'Отклонено')
ORDER BY received_date;

-- Б5.2. Обычное сравнение: NULL не включаются
SELECT COUNT(*) AS cnt
FROM purchase_order_items
WHERE quality_status <> 'Принято';

-- Б5.2. Сравнение с учётом NULL
SELECT COUNT(*) AS cnt
FROM purchase_order_items
WHERE quality_status IS DISTINCT FROM 'Принято';

-- Б5.3. Отклонения качества по молочному сырью
SELECT *
FROM purchase_order_items
WHERE quality_status IN ('Принято частично', 'Отклонено')
  AND material_id IN (1, 2)
ORDER BY received_date;

-- Б5.4. Заказы для найденных po_id (ID выписаны вручную из Б5.3)
SELECT po_id, po_number, supplier_id, order_date, status
FROM purchase_orders
WHERE po_id IN (45, 81, 109, 136, 319, 398, 423, 538, 564, 610, 645, 656)
ORDER BY po_id;

-- Б6. Поставщики без рейтинга или с рейтингом ниже 4.0
SELECT *
FROM suppliers
WHERE rating IS NULL
   OR rating < 4.0
ORDER BY rating ASC NULLS FIRST;

-- Б7.1. Топ партий по недовыпуску, включая совпадающие значения
SELECT batch_number,
       planned_qty,
       produced_qty,
       planned_qty - produced_qty AS shortfall,
       ROUND(100.0 * produced_qty / planned_qty, 1) AS plan_percent
FROM production_batches
ORDER BY planned_qty - produced_qty DESC
FETCH FIRST 10 ROWS WITH TIES;

-- Б7.2. Количество партий с выполнением плана ниже 90%
SELECT COUNT(*) AS batches_below_90
FROM production_batches
WHERE produced_qty < 0.9 * planned_qty;

-- Б7.3. Исключения из гипотезы: линия 2, 2025 год
SELECT COUNT(*) AS exceptions
FROM production_batches
WHERE produced_qty < 0.9 * planned_qty
  AND NOT (
      line_id = 2
      AND production_date >= DATE '2025-01-01'
      AND production_date < DATE '2026-01-01'
  );

-- Б8.1. Десять крупнейших списаний по сроку годности
SELECT *
FROM material_writeoffs
WHERE reason = 'Истёк срок годности'
ORDER BY amount DESC
LIMIT 10;

-- Б8.2. Название и характеристики материала №10
SELECT *
FROM raw_materials
WHERE material_id = 10;

-- Б9.1. Количество и сумма списаний материала №10
SELECT COUNT(*) AS writeoffs,
       SUM(amount) AS writeoff_rub
FROM material_writeoffs
WHERE material_id = 10
  AND reason = 'Истёк срок годности';

-- Б9.2. Недовыпуск линии 2 за 2025 год.
-- Запрос сохранён в точности по формулировке лабораторной.
SELECT SUM(planned_qty - produced_qty) AS line2_2025_shortfall_units
FROM production_batches
WHERE line_id = 2
  AND production_date >= DATE '2025-01-01';
