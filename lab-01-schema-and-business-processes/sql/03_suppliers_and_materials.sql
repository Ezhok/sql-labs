-- Лабораторная № 1. Команда Б: Б.1
SET search_path TO pitanie, public;

-- Поставщики.
SELECT *
FROM suppliers
ORDER BY supplier_id;

-- Сырьё и упаковочные материалы.
SELECT *
FROM raw_materials
ORDER BY material_group, material_name;
