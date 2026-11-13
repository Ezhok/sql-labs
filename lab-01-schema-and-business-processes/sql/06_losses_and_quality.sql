-- Лабораторная № 1. Команда Б: Б.5–Б.6
SET search_path TO pitanie, public;

-- Б.5. Первые 10 записей о простоях.
SELECT *
FROM equipment_downtime
ORDER BY start_time
LIMIT 10;

-- Б.5. Первые 10 записей о списаниях сырья.
SELECT *
FROM material_writeoffs
ORDER BY writeoff_date
LIMIT 10;

-- Дополнительная проверка: длительность закрытых простоев в минутах.
-- Для записей с end_time IS NULL длительность не рассчитывается.
SELECT line_id,
       start_time,
       end_time,
       reason,
       CASE
           WHEN end_time IS NULL THEN NULL
           ELSE ROUND(EXTRACT(EPOCH FROM (end_time - start_time)) / 60, 2)
       END AS duration_minutes
FROM equipment_downtime
ORDER BY start_time
LIMIT 10;

-- Б.6. Распределение результатов контроля качества.
SELECT quality_status,
       COUNT(*) AS items_cnt
FROM purchase_order_items
GROUP BY quality_status
ORDER BY items_cnt DESC;
