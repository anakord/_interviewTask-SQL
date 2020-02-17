/*
    Изменения:
    1) В таблице Drinks вместо первичного ключа (varchar) было взято автоинкрементируемое поле id
    2) Таблица Nominals изменена, теперь на номинал ссылаются через поле id - первичный ключ номинала
    Отдельная таблица необходима, чтобы производя изменение только в ней изменять возможные к использованию номиналы
    Иного решения не нашел, перечислять можно только метки, которые сложно преобразовывать
    3) Убрал индексы, осталась мысль 
    добавить индекс на поиск суммы счетов клиента и автомата, так как это наиболее затратный и частоиспользуемый запрос.
    4) Добавил триггер на таблицу Nominals чтобы потом не усложнять алгоритмы вопросом: учитываются ли такие монеты в автомате.
    Теперь при добавлении нового номинала, он автоматически начинает учитываться на кошельках
*/



DROP TABLE Customer_Credit, Seller_Credit, Nominals, Drinks;

--создание таблицы напитков в автомате
CREATE TABLE IF NOT EXISTS Drinks (
    id SERIAL, -- id напитка (первичный ключ)
    
    drink_name varchar(35)
    NOT NULL    
    UNIQUE, -- уникальное название напитка

    price    int4
    NOT NULL
    DEFAULT 0
    CHECK (price >= 0), 

    number_of_portions   int4
    NOT NULL
    DEFAULT 0
    CHECK (price > 0) 
);
ALTER TABLE Drinks -- добавление первичного ключа
  ADD CONSTRAINT PK_Drinks_DrinkName PRIMARY KEY (id);

--создание таблицы номиналов
CREATE TABLE IF NOT EXISTS Nominals (
    
    id SERIAL,
    
    nominal    int4  --значение номинала монеты. 
      UNIQUE,
      CHECK (nominal > 0)   
 
);
ALTER TABLE Nominals -- добавление первичного ключа
  ADD CONSTRAINT PK_Nominals_Nominal PRIMARY KEY (id);

--создание таблицы кошелька покупателя
CREATE TABLE IF NOT EXISTS Customer_credit (
    
    nominal    int4, -- перечисление возможных номиналов  

    number_of    int4  
      NOT NULL 
      DEFAULT 0 
      CHECK (number_of >= 0) --количество монет определенного типа

); 
ALTER TABLE Customer_credit -- добавление первичного ключа
   ADD CONSTRAINT PK_CustomerCredit_nominal PRIMARY KEY (nominal);
ALTER TABLE Customer_credit -- связь с таблицей Nominals теперь через id
   ADD CONSTRAINT FK_CustomerCredit_id 
     FOREIGN KEY (nominal) REFERENCES Nominals (id) -- при отмене номинала не считаем его за деньги. При изменении цена номинала 
       ON DELETE CASCADE ON UPDATE CASCADE; -- возрастает вне зависимости от цифры на реальной монете  

     
--создание таблицы кошелька автомата (по образу предыдущего) так как логика данных идентична
CREATE TABLE IF NOT EXISTS Seller_credit (
    
    nominal    int4,
    
    number_of    int4 
      NOT NULL 
      DEFAULT 0 
      CHECK (number_of >= 0) 

); 
ALTER TABLE Seller_credit -- та же логика
   ADD CONSTRAINT PK_SellerCredit_nominal PRIMARY KEY (nominal); --pk - перечисление
ALTER TABLE Seller_credit -- связь с таблицей Nominals теперь через id
   ADD CONSTRAINT FK_SellerCredit_id 
     FOREIGN KEY (nominal) REFERENCES Nominals (id) -- при отмене номинала не считаем его за деньги. При изменении цена номинала 
       ON DELETE CASCADE ON UPDATE CASCADE; -- возрастает вне зависимости от цифры на реальной монете  

-- Триггерная функция для добавления новых номиналов
CREATE OR REPLACE FUNCTION tf_nominal_add() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Customer_Credit(nominal, number_of) VALUES (NEW.id, 0);
    INSERT INTO Seller_Credit(nominal, number_of) VALUES (NEW.id, 0);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER t_nominal_add
    AFTER INSERT ON nominals
    FOR EACH ROW
    EXECUTE PROCEDURE tf_nominal_add();
    
-- Заполнение таблицы номиналов, одновременно внос новых монет в кошельки (чтобы потом об этом не думать)
INSERT INTO Nominals (nominal) 
  VALUES (1),(2),(5),(10);

-- По 10 монет каждого номинала в автомате
UPDATE Seller_credit 
  SET number_of = 10;
-- Заполнение таблицы напитков в автомате
INSERT INTO Drinks (drink_name, price) 
  VALUES ('чай', 25), ('капучино', 39), ('какао', 23), ('шоколад', 31);
-- Завоз каждого напитка по 10 единиц (для реализации функции продажи)
UPDATE Drinks 
  SET number_of_portions = 10;

-- Проверка корректности ввода
/*SELECT SUM(coin_sum) AS seller_sum FROM
  (SELECT number_of * Nominals.nominal AS coin_sum 
    FROM Seller_Credit LEFT JOIN Nominals ON Seller_credit.nominal = id) AS summator;

SELECT SUM(coin_sum) AS seller_sum FROM
  (SELECT number_of * Nominals.nominal AS coin_sum 
    FROM Customer_Credit LEFT JOIN Nominals ON Customer_credit.nominal = id) AS summator;
    
--SELECT * FROM Seller_credit
--SELECT * FROM Nominals
*/
