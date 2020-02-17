/* 
  add_coin(int4 n) 
  
  Функция вызывается после того, как автомат получил информацию о том,
  что покупатель опустил монету (условный момент срабатывания) 
  и был определен ее номинал (входной параметр).

  Работает с таблицей:
  Customer_Credit    
    nominal - int4 - UNIQUE
    number_of - int4
  Не возвращает результата

  Убрал проверку на учет монет такого типа (т.к. теперь есть триггер)
  Теперь изменяю количество монет по id номинала
*/

CREATE OR REPLACE FUNCTION add_coin (n int4) RETURNS VOID AS -- создание функции add_coin
$$ -- открытие языкового блока
BEGIN
  
  -- если покупатель кидает монету неизвестного номинала (нет в Nominals)
  IF NOT EXISTS (SELECT nominal FROM Nominals WHERE n = nominal) THEN
    RAISE EXCEPTION 'Unknown nominal.'; 
  ELSE 
    UPDATE Customer_Credit -- изменение счета покупателя
      SET number_of = number_of + 1 -- увеличение количества монет на 1
        WHERE nominal = (SELECT id FROM Nominals WHERE nominal = n); -- нужного номинала 
    -- Уникальность поля гарантирует изменение нужной записи
  END IF;

  --SELECT * FROM Customer_Credit; -- проверочный дамп 
END;
$$
LANGUAGE plpgSQL; -- на процедурном языке PostgreeSQL

--Тестирование
--Адекватные варианты
  SELECT add_coin(2);
  SELECT * FROM Customer_Credit;
/*SELECT add_coin(5);
  SELECT * FROM Customer_Credit;
  SELECT add_coin(1);
  SELECT * FROM Customer_Credit;
--Неадекватные варианты
SELECT add_coin(0);
  SELECT * FROM Customer_Credit;
  SELECT add_coin(-1);
  SELECT * FROM Customer_Credit;
  SELECT add_coin(3);
  SELECT * FROM Customer_Credit;

  Остальные варианты проверяются на уровне проверки синтаксиса.
  Автомат подразумевается как однопользовательская система
  поэтому проверку прав доступа на изменения не производил.
  Одно действие - одна транзакция, поэтому ничего не сохранялось.
*/
