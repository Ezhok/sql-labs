-- ============================================================
-- Модуль 7. Лабораторная работа «Наводим порядок в данных»
-- Вариант 2. Команда Б «Производство и закупки»
-- Личная схема: stud_fedina
--
-- Перед запуском:
-- 1. Создать личную схему и восстановить исходные данные.
-- 2. Загрузить скрипты:
--    03_load_supplier_price_offer.sql
--    04_load_recipe_norms_2026.sql
--    05_lab_b_receipt_glitch.sql
-- 3. Выполнять задания последовательно.
--
-- ВНИМАНИЕ:
-- Скрипт изменяет данные личной схемы stud_fedina.
-- Не запускайте его в общей схеме pitanie.
-- ============================================================


-- ============================================================
-- 0. ПОДГОТОВКА
-- ============================================================

SET search_path TO stud_fedina, pitanie, public;

SELECT
    current_schema() AS current_schema,
    current_setting('search_path') AS search_path;

-- Контроль загруженных данных.
SELECT
    (SELECT COUNT(*) FROM supplier_price_offer) AS offers,
    (SELECT COUNT(*) FROM recipe_norms_2026) AS norms,
    (SELECT COUNT(*) FROM purchase_order_items) AS po_items;

-- Ожидается:
-- offers = 18
-- norms = 12
-- po_items = 2346


-- ============================================================
-- Б1. СОЗДАНИЕ ТАБЛИЦЫ КОНТРАКТНЫХ ЦЕН
-- ============================================================

CREATE TABLE supplier_contract_prices (
    supplier_id    integer       NOT NULL REFERENCES suppliers (supplier_id),
    material_id    integer       NOT NULL REFERENCES raw_materials (material_id),
    contract_price numeric(12,2) NOT NULL CHECK (contract_price > 0),
    valid_from     date          NOT NULL,
    source         varchar(50)   NOT NULL,
    updated_at     timestamptz   NOT NULL DEFAULT now(),
    PRIMARY KEY (supplier_id, material_id)
);

-- Заполнение последними закупочными ценами за 2025 год.
INSERT INTO supplier_contract_prices (
    supplier_id,
    material_id,
    contract_price,
    valid_from,
    source
)
SELECT DISTINCT ON (po.supplier_id, poi.material_id)
       po.supplier_id,
       poi.material_id,
       poi.unit_price,
       po.order_date,
       'Закупки 2025'
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON po.po_id = poi.po_id
WHERE po.order_date >= DATE '2025-01-01'
  AND po.order_date < DATE '2026-01-01'
ORDER BY
    po.supplier_id,
    poi.material_id,
    po.order_date DESC,
    poi.po_item_id DESC;

-- Контроль количества записей.
SELECT COUNT(*) AS contract_prices_count
FROM supplier_contract_prices;

-- Проверка цен по сахару (material_id = 4).
SELECT
    cp.supplier_id,
    s.supplier_name,
    cp.contract_price,
    cp.valid_from
FROM supplier_contract_prices AS cp
JOIN suppliers AS s
    ON s.supplier_id = cp.supplier_id
WHERE cp.material_id = 4
ORDER BY cp.contract_price DESC;

-- Ожидается 40 записей.
-- По сахару: 3 поставщика.
-- Максимальная цена: 84.73 у ООО «АгроСнаб-М».


-- ============================================================
-- Б2. ОБРАБОТКА КОММЕРЧЕСКИХ ПРЕДЛОЖЕНИЙ С ПОМОЩЬЮ MERGE
-- ============================================================

-- 1. Поиск неизвестных поставщиков.
SELECT
    o.offer_id,
    o.supplier_inn,
    o.supplier_name,
    o.material_name,
    o.offer_price
FROM supplier_price_offer AS o
WHERE NOT EXISTS (
    SELECT 1
    FROM suppliers AS s
    WHERE s.inn = o.supplier_inn
);

-- Ожидается ООО «ВкусЭкспорт».


-- 2. Классификация предложений.
SELECT
    CASE
        WHEN cp.contract_price IS NULL THEN 'новая пара'
        WHEN o.offer_price < cp.contract_price THEN 'ниже'
        WHEN o.offer_price > cp.contract_price THEN 'выше'
        ELSE 'та же'
    END AS offer_class,
    COUNT(*) AS cnt
FROM supplier_price_offer AS o
JOIN suppliers AS s
    ON s.inn = o.supplier_inn
LEFT JOIN supplier_contract_prices AS cp
    ON cp.supplier_id = s.supplier_id
   AND cp.material_id = o.material_id
GROUP BY 1
ORDER BY 2 DESC;

-- Ожидается:
-- ниже: 9
-- выше: 3
-- новая пара: 4
-- та же: 1
-- Один неизвестный поставщик не входит в классификацию.


-- 3. Расчёт экономии на объёмах закупок 2025 года.
SELECT
    ROUND(
        SUM((cp.contract_price - o.offer_price) * v.qty_2025),
        0
    ) AS saving_rub
FROM supplier_price_offer AS o
JOIN suppliers AS s
    ON s.inn = o.supplier_inn
JOIN supplier_contract_prices AS cp
    ON cp.supplier_id = s.supplier_id
   AND cp.material_id = o.material_id
JOIN (
    SELECT
        po.supplier_id,
        poi.material_id,
        SUM(poi.quantity) AS qty_2025
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po
        ON po.po_id = poi.po_id
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    GROUP BY po.supplier_id, poi.material_id
) AS v
    ON v.supplier_id = cp.supplier_id
   AND v.material_id = cp.material_id
WHERE o.offer_price < cp.contract_price;

-- Ожидаемая экономия: около 3 096 969 руб.


-- 4. Обновление и добавление контрактных цен.
BEGIN;

MERGE INTO supplier_contract_prices AS t
USING (
    SELECT
        s.supplier_id,
        o.material_id,
        o.offer_price,
        o.valid_from
    FROM supplier_price_offer AS o
    JOIN suppliers AS s
        ON s.inn = o.supplier_inn
) AS src
ON t.supplier_id = src.supplier_id
AND t.material_id = src.material_id

WHEN MATCHED AND src.offer_price < t.contract_price THEN
    UPDATE SET
        contract_price = src.offer_price,
        valid_from = src.valid_from,
        source = 'КП 2026',
        updated_at = now()

WHEN MATCHED THEN
    DO NOTHING

WHEN NOT MATCHED THEN
    INSERT (
        supplier_id,
        material_id,
        contract_price,
        valid_from,
        source
    )
    VALUES (
        src.supplier_id,
        src.material_id,
        src.offer_price,
        src.valid_from,
        'КП 2026 (новая пара)'
    );

-- Контроль распределения источников.
SELECT
    source,
    COUNT(*) AS cnt
FROM supplier_contract_prices
GROUP BY source
ORDER BY cnt DESC;

-- Ожидается MERGE 13:
-- 9 обновлений и 4 вставки.
-- Источники: 31 / 9 / 4.

COMMIT;


-- ============================================================
-- Б3. ЗАКРЫТИЕ НЕЗАВЕРШЁННЫХ ПРОСТОЕВ
-- ============================================================

-- 1. Проверка незакрытых простоев.
SELECT
    downtime_id,
    line_id,
    start_time,
    end_time,
    downtime_category
FROM equipment_downtime
WHERE end_time IS NULL;

-- Ожидается 4 записи.

-- 2. Добавление признака расчётного времени окончания.
ALTER TABLE equipment_downtime
ADD COLUMN end_time_estimated boolean NOT NULL DEFAULT FALSE;

-- 3. Расчёт времени окончания.
BEGIN;

UPDATE equipment_downtime AS d
SET
    end_time = date_trunc('minute', d.start_time + a.avg_dur),
    end_time_estimated = TRUE
FROM (
    SELECT
        line_id,
        downtime_category,
        AVG(end_time - start_time) AS avg_dur
    FROM equipment_downtime
    WHERE end_time IS NOT NULL
    GROUP BY line_id, downtime_category
) AS a
WHERE a.line_id = d.line_id
  AND a.downtime_category = d.downtime_category
  AND d.end_time IS NULL
RETURNING
    d.downtime_id,
    d.line_id,
    d.downtime_category,
    d.start_time,
    d.end_time,
    d.end_time - d.start_time AS estimated_duration;

-- Контроль незакрытых простоев.
SELECT COUNT(*) AS still_open
FROM equipment_downtime
WHERE end_time IS NULL;

COMMIT;

-- Ожидается:
-- обновлено 4 записи;
-- still_open = 0.


-- ============================================================
-- Б4. ИСПРАВЛЕНИЕ ОШИБОЧНЫХ ПРИЁМОК WMS
-- ============================================================

-- 1. Поиск повторяющихся пар «заказ — материал».
SELECT
    po_id,
    material_id,
    COUNT(*) AS cnt
FROM purchase_order_items
GROUP BY po_id, material_id
HAVING COUNT(*) > 1
ORDER BY po_id;

-- По методичке ожидается 18 дублирующих строк.


-- 2. Добавление признака ошибки.
ALTER TABLE purchase_order_items
ADD COLUMN receipt_error varchar(50);


-- 3. Пометка повторных записей.
BEGIN;

UPDATE purchase_order_items AS dup
SET receipt_error = 'Двойной ввод (сбой WMS 11.2025)'
FROM purchase_order_items AS orig
WHERE orig.po_id = dup.po_id
  AND orig.material_id = dup.material_id
  AND orig.po_item_id < dup.po_item_id;

-- Контроль количества помеченных строк и суммы завышения.
SELECT
    COUNT(*) AS marked,
    ROUND(SUM(quantity * unit_price), 2) AS overstated_rub
FROM purchase_order_items
WHERE receipt_error IS NOT NULL;

-- Удаление помеченных дубликатов.
DELETE FROM purchase_order_items
WHERE receipt_error IS NOT NULL;

-- Контроль оставшихся записей.
SELECT COUNT(*) AS po_items
FROM purchase_order_items;

COMMIT;

-- Ожидается:
-- marked = 18
-- overstated_rub = 2570703.33
-- po_items = 2328


-- ============================================================
-- Б5. ОБНОВЛЕНИЕ НОРМ РАСХОДА С ПОМОЩЬЮ UPSERT
-- ============================================================

-- Проверка исходного количества рецептур.
SELECT COUNT(*) AS recipes_before
FROM recipes;

-- Первая попытка намеренно не выполняется в итоговом скрипте:
-- она приводит к ошибке, если в источнике есть дубли ключей.
--
-- Ошибка:
-- ON CONFLICT DO UPDATE command cannot affect row a second time
--
-- Причина: пара (product_id, material_id) = (8, 10)
-- присутствует в recipe_norms_2026 дважды.


-- Проверка повторяющихся пар в источнике.
SELECT
    product_id,
    material_id,
    COUNT(*) AS cnt,
    STRING_AGG(line_no::text, ', ') AS lines
FROM recipe_norms_2026
GROUP BY product_id, material_id
HAVING COUNT(*) > 1;


-- Удаление дублей при загрузке и обновление рецептур.
INSERT INTO recipes (
    product_id,
    material_id,
    qty_per_unit
)
SELECT DISTINCT ON (n.product_id, n.material_id)
    n.product_id,
    n.material_id,
    n.qty_per_unit
FROM recipe_norms_2026 AS n
ORDER BY
    n.product_id,
    n.material_id,
    n.line_no DESC
ON CONFLICT (product_id, material_id)
DO UPDATE
SET qty_per_unit = EXCLUDED.qty_per_unit
WHERE recipes.qty_per_unit IS DISTINCT FROM EXCLUDED.qty_per_unit
RETURNING
    product_id,
    material_id,
    qty_per_unit,
    (xmax = 0) AS inserted;

-- Контроль итогового количества рецептур.
SELECT COUNT(*) AS recipes_after
FROM recipes;

-- Ожидается:
-- 4 вставки;
-- 4 обновления;
-- recipes_after = 150.


-- ============================================================
-- Б6. ФОРМИРОВАНИЕ СТОП-ЛИСТА ПОСТАВЩИКОВ
-- ============================================================

CREATE TABLE supplier_stop_list (
    supplier_id integer PRIMARY KEY REFERENCES suppliers (supplier_id),
    reason      text NOT NULL,
    added_at    timestamptz NOT NULL DEFAULT now()
);


-- Критерий 1. Переплата более 15% относительно лучшей
-- средневзвешенной цены по материалу за 2025 год.

INSERT INTO supplier_stop_list (supplier_id, reason)
SELECT
    a.supplier_id,
    'Переплата: ' || COUNT(*) ||
    ' мат., до +' ||
    ROUND(MAX(100 * (a.avg_price / b.best_price - 1)), 0) || '%'
FROM (
    SELECT
        po.supplier_id,
        poi.material_id,
        SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity) AS avg_price
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po
        ON po.po_id = poi.po_id
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    GROUP BY po.supplier_id, poi.material_id
) AS a
JOIN (
    SELECT
        material_id,
        MIN(avg_price) AS best_price
    FROM (
        SELECT
            po.supplier_id,
            poi.material_id,
            SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity) AS avg_price
        FROM purchase_order_items AS poi
        JOIN purchase_orders AS po
            ON po.po_id = poi.po_id
        WHERE po.order_date >= DATE '2025-01-01'
          AND po.order_date < DATE '2026-01-01'
        GROUP BY po.supplier_id, poi.material_id
    ) AS x
    GROUP BY material_id
) AS b
    ON b.material_id = a.material_id
WHERE a.avg_price > 1.15 * b.best_price
GROUP BY a.supplier_id;


-- Критерий 2. Средняя задержка поставок более 2 дней.

INSERT INTO supplier_stop_list AS sl (
    supplier_id,
    reason
)
SELECT
    po.supplier_id,
    'Опоздания: в среднем ' ||
    ROUND(AVG(poi.received_date - po.expected_date), 1) || ' дн.'
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON po.po_id = poi.po_id
WHERE po.order_date >= DATE '2025-01-01'
  AND po.order_date < DATE '2026-01-01'
  AND poi.received_date IS NOT NULL
GROUP BY po.supplier_id
HAVING AVG(poi.received_date - po.expected_date) > 2
ON CONFLICT (supplier_id)
DO UPDATE
SET reason = sl.reason || '; ' || EXCLUDED.reason;


-- Контроль стоп-листа.
SELECT
    sl.supplier_id,
    s.supplier_name,
    sl.reason
FROM supplier_stop_list AS sl
JOIN suppliers AS s
    ON s.supplier_id = sl.supplier_id;

-- Ожидается:
-- ООО «АгроСнаб-М»: переплата по 10 материалам, до +27%.
-- ООО «МолПром Регион»: средняя задержка 2.8 дня.


-- ============================================================
-- Б7. ДОПОЛНИТЕЛЬНОЕ ЗАДАНИЕ «ЧТО ЕСЛИ» ОТКАЗАТЬСЯ ОТ ПОСТАВЩИКА
-- ============================================================

-- Моделирование удаления контрактных цен ООО «АгроСнаб-М».
-- Изменения обязательно откатываются через ROLLBACK.

BEGIN;

DELETE FROM supplier_contract_prices AS cp
USING supplier_stop_list AS sl
WHERE sl.supplier_id = cp.supplier_id
  AND sl.reason LIKE 'Переплата%'
  AND EXISTS (
      SELECT 1
      FROM supplier_contract_prices AS alt
      WHERE alt.material_id = cp.material_id
        AND alt.supplier_id <> cp.supplier_id
  );

-- Ожидается удаление 10 пар.

-- Проверка материалов без альтернативного источника.
SELECT COUNT(*) AS materials_without_source
FROM raw_materials AS m
WHERE NOT EXISTS (
    SELECT 1
    FROM supplier_contract_prices AS cp
    WHERE cp.material_id = m.material_id
);

-- Ожидается 0.

ROLLBACK;


-- Расчёт переплаты ООО «АгроСнаб-М» за 2025 год
-- относительно лучшей средневзвешенной цены по материалу.

WITH a AS (
    SELECT
        po.supplier_id,
        poi.material_id,
        SUM(poi.quantity) AS qty,
        SUM(poi.quantity * poi.unit_price) / SUM(poi.quantity) AS avg_price
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po
        ON po.po_id = poi.po_id
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    GROUP BY po.supplier_id, poi.material_id
)
SELECT
    ROUND(SUM(a.qty * (a.avg_price - b.best)), 0) AS agro_overpay_2025
FROM a
JOIN (
    SELECT
        material_id,
        MIN(avg_price) AS best
    FROM a
    GROUP BY material_id
) AS b
    ON b.material_id = a.material_id
WHERE a.supplier_id = 3;

-- Ожидаемая переплата: 1 987 015 руб.


-- ============================================================
-- КОНЕЦ ЛАБОРАТОРНОЙ РАБОТЫ
-- ============================================================