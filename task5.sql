/*
  is_charge(ch int4);

  Функция возвращает boolean, показывающий, возможно ли выдать сдачу.
  В качестве параметра принимает сумму, которую нужно разменять.
  -- Разумнее было бы возвращать список монет, которыми можно выдавать сдачу
  
*/
DROP FUNCTION is_charge(ch int4);

CREATE OR REPLACE FUNCTION is_charge (ch int4) 
RETURNS TABLE (nominal int4, number_of int4) AS -- создание функции is_charge
$$ -- открытие языкового блока    
DECLARE
  CR_coin CURSOR FOR SELECT 
    Nominals.nominal AS nominal, 
    Seller_Credit.number_of + COALESCE(Customer_Credit.number_of, 0) AS number_of
  FROM Seller_Credit 
    LEFT JOIN Nominals ON Seller_Credit.nominal = Nominals.id 
    LEFT JOIN Customer_Credit ON Seller_Credit.nominal = Customer_Credit.nominal   
  ORDER BY Nominals.nominal DESC; 
BEGIN  
  CREATE TABLE IF NOT EXISTS buf ( -- таблица, куда вносятся результаты набранных монет
    nominal int4,
    number_of int4
  );
  FOR n IN CR_coin -- открытие курсора при проходе всех монет в автомате
  LOOP
    IF((ch % n.nominal = 0) AND -- если данным номиналом можно расчитаться 
    (n.number_of >= ch / n.nominal)) THEN -- и хватает монет для этого расчета
      INSERT INTO buf VALUES(n.nominal, ch / n.nominal); --сохраняем монеты, которыми выдали
      ch := 0; -- можем расчитаться
    ELSIF (n.number_of >= ch / n.nominal) THEN -- считаем остаток, выдавая сколько нужно  
      INSERT INTO buf VALUES(n.nominal, ch / n.nominal); --сохраняем монеты, которыми выдали
      ch := ch % n.nominal; -- остаток от того, что не можем разбить этим номиналом
    ELSE -- считаем остаток, выдавая сколько можем
      INSERT INTO buf VALUES(n.nominal, n.number_of);
      ch := ch - n.number_of * n.nominal;
    END IF;
  END LOOP; --все поля пройдены и курсор закрывается
   
  IF (ch != 0) THEN -- если не были найдены монеты на сдачу
    DELETE FROM buf; -- не нашлось монет для сдачи    
  END IF;
  RETURN QUERY(SELECT buf.nominal, buf.number_of FROM buf);
  DROP TABLE buf; -- удаляем временную буферную таблицу
END; 
$$
LANGUAGE plpgSQL; -- на процедурном языке PostgreeSQL


/*
  buy_drink(d_name varchar(35)) 
  
  Функция вызывается при выборе (условный момент срабатывания) 
  покупателем напитка (входной параметр)
  
  Необходимо определить:
  1. Является ли введенная строка напитком (возможно, пользователь вводит ее вручную).
  2. Есть ли напиток в наличии.
  3. Хватает ли на него денег.
      -- Возможно, стоит написать какую-нибудь хранимую процедуру для быстрого подсчета баланса.
  4. Проверить, возможна ли выдача сдачи (по сумме и в "размене"). 
  Слишком много действий, и решил вынести проверку в отдельную функцию is_charge(ch int4), возвращающую boolean
  
  Если все условия соблюдены необходимо:
  1. Выдать сдачу (уменьшить количество монет подходящего номинала) и перевести эти номиналы на счет.
  2. Уменьшить количество монет в кошельке на сумму покупки.
  3. Уменьшить количество напитков на 1. (покупка).
      
Работает с таблицами:
  Drinks 
    drink_name    varchar(35)
    price    int4
    number_of_portions   int4

  Customer_Credit    
    nominal - int4 - UNIQUE
    number_of - int4

  Seller_Credit
    nominal - int4 - UNIQUE
    number_of - int4
    
  Возвращает результат:
    -1 - сделка невозможна,
     0 - сделка удалась.

*/

CREATE OR REPLACE FUNCTION buy_drink (d_name varchar(35)) 
RETURNS int2 AS -- создание функции buy_drink
$$ -- открытие языкового блока
DECLARE
  -- предварительное вычисление суммы кошелька клиента
  customer_sum int4 = (SELECT SUM(Nominals.nominal*number_of) 
    FROM Customer_Credit LEFT JOIN Nominals ON Customer_Credit.nominal = Nominals.id);
  -- СДАЧА = сумма на счете - стоимость товара 
  ch int4 = customer_sum - (SELECT price FROM Drinks WHERE drink_name = d_name);
BEGIN  
  IF (
     NOT EXISTS (SELECT drink_name FROM Drinks WHERE drink_name = d_name) OR -- такого напитка нет в продаже
     (SELECT number_of_portions FROM Drinks WHERE drink_name = d_name) = 0 OR -- такого напитка нет в наличии
     customer_sum < (SELECT price FROM Drinks WHERE drink_name = d_name) -- недостаточно денег внесено
     ) 
    THEN RETURN -1; -- возврат невозможности сделки
  
  ELSE --вычисление возможности выдать сдачу
     -- сохранение результата в временной таблице buf
    CREATE TEMPORARY TABLE IF NOT EXISTS buf_ch (nominal int4, number_of int4);     
    DELETE FROM buf_ch;
    INSERT INTO buf_ch (nominal, number_of) -- запись результата
      SELECT Nominals.id, number_of FROM is_charge(ch) AS res
      LEFT JOIN Nominals ON res.nominal = Nominals.nominal;
      
    IF(NOT EXISTS (SELECT * FROM buf_ch)) -- нет возможности набрать сдачу 
      THEN RETURN -1;
    ELSE -- сделка возможна, выполнение   
    -- Забрать один напиток
      UPDATE Drinks
        SET number_of_portions = number_of_portions - 1
        WHERE drink_name = d_name;
      -- Отправить деньги на счет автомата
      UPDATE Seller_Credit 
        SET number_of = Seller_Credit.number_of + Customer_Credit.number_of
        FROM Customer_Credit WHERE Seller_Credit.nominal = Customer_Credit.nominal;
      -- Забрать деньги у покупателя
      UPDATE Customer_Credit 
        SET number_of = 0; -- обнулив все монеты
      -- Выдать ему сдачу которую выяснили заранее
      UPDATE Customer_Credit 
        SET number_of = buf_ch.number_of
        FROM buf_ch WHERE buf_ch.nominal = Customer_Credit.nominal;
      
      RETURN 0; -- возвращение результата выполнения
    END IF;
  END IF; -- конец условного блока   
  DROP TABLE buf_ch; -- удалить буферную таблицу
END; 
$$
LANGUAGE plpgSQL; -- на процедурном языке PostgreeSQL

--Тестирование
UPDATE Customer_Credit
  SET number_of = 5 WHERE Customer_Credit.nominal = 4; --внесем на счет 50 рублей (5 шт 10-рублевых)
UPDATE Seller_Credit
  SET number_of = 10 WHERE Seller_Credit.nominal = 1 OR Seller_Credit.nominal = 3; -- достаточное количество 1-3-рублевых на автомате

SELECT buy_drink ('капучино'); -- сдача в 11 рублей выдается (50 - 39 руб стоимости капучино) 


/*
--Возможности выдать сдачи
  SELECT is_charge(10);
  SELECT is_charge(13);
--Адекватные варианты
  SELECT buy_drink('какао');
  SELECT add_coin(10);
  SELECT buy_drink('кола');
--Неадекватные варианты
  SELECT buy_drink('какаво');
*/
