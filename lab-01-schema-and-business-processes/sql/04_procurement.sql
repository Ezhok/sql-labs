-- Лабораторная № 1. Команда Б: Б.2
SET search_path TO pitanie, public;

-- Маршрут закупки ЗП-2024-00081. Шаг 1: заказ поставщику.
SELECT po.*,
       s.supplier_name,
       e.full_name AS buyer
FROM purchase_orders AS po
JOIN suppliers AS s
  ON s.supplier_id = po.supplier_id
JOIN employees AS e
  ON e.employee_id = po.employee_id
WHERE po.po_number = 'ЗП-2024-00081';

-- Шаг 2: заказанные позиции и фактическая приёмка.
SELECT m.material_name,
       m.unit,
       poi.quantity,
       poi.unit_price,
       poi.received_qty,
       poi.received_date,
       poi.quality_status
FROM purchase_order_items AS poi
JOIN raw_materials AS m
  ON m.material_id = poi.material_id
WHERE poi.po_id = 81
ORDER BY m.material_name;

-- Бонус: повтор маршрута для заказа ЗП-2025-00900.
SELECT po.*,
       s.supplier_name,
       e.full_name AS buyer
FROM purchase_orders AS po
JOIN suppliers AS s
  ON s.supplier_id = po.supplier_id
JOIN employees AS e
  ON e.employee_id = po.employee_id
WHERE po.po_number = 'ЗП-2025-00900';

SELECT m.material_name,
       m.unit,
       poi.quantity,
       poi.unit_price,
       poi.received_qty,
       poi.received_date,
       poi.quality_status
FROM purchase_order_items AS poi
JOIN raw_materials AS m
  ON m.material_id = poi.material_id
WHERE poi.po_id = 900
ORDER BY m.material_name;
