-- Лабораторная № 1. Общая часть: О.1–О.3
-- Схема pitanie используется только для чтения.

SET search_path TO pitanie, public;

-- О.1. Список таблиц схемы pitanie (ожидается 23 таблицы).
SELECT c.relname AS table_name,
       obj_description(c.oid) AS description
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'pitanie'
  AND c.relkind = 'r'
ORDER BY c.relname;

-- О.2. Структура таблицы orders.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'pitanie'
  AND table_name = 'orders'
ORDER BY ordinal_position;

-- О.2. Дополнительная таблица команды Б: purchase_orders.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'pitanie'
  AND table_name = 'purchase_orders'
ORDER BY ordinal_position;

-- О.3. Все внешние ключи схемы pitanie (ожидается 30 связей).
SELECT conrelid::regclass AS child_table,
       confrelid::regclass AS parent_table,
       pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'pitanie'::regnamespace
ORDER BY 1, 2;
