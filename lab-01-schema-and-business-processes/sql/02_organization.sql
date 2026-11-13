-- Лабораторная № 1. Общая часть: О.4
SET search_path TO pitanie, public;

-- Сотрудники, должности, подразделения и непосредственные руководители.
SELECT e.department,
       e.full_name,
       e.position,
       m.full_name AS manager_name
FROM employees AS e
LEFT JOIN employees AS m
       ON m.employee_id = e.manager_id
ORDER BY e.department, e.position;
