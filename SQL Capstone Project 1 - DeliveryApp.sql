
-- For info: The data set (imported from Excel) contains three tables: Delivery, Store, and Warehouse
-- Source of data set: https://forum.enterprisedna.co/uploads/short-url/d3gx5M3e6uIYstkdfWHIBpQYcXa.xlsx 
-- The purpose of this project is to work on Table Set Up, Data Cleaning and Data Exploration techniques

USE DeliveryApp;



-- 1. Table Set Up

-- Setting up the database in SQL
-- Set up primary, foreign, and unique keys (if applicable) to enhance runtime performance with primary keys acting as indexes, and to ensure data integrity
-- Change primary key columns from FLOAT to INT

CREATE TABLE Store_new(
	StoreID INT,
	StoreName NVARCHAR(255) NULL,
	PRIMARY KEY (StoreID)
	);

CREATE TABLE Warehouse_new(
	WarehouseID INT,
	WarehouseName NVARCHAR(255) NULL,
	WarehouseLocation NVARCHAR(255) NULL,
	WarehouseShortcde NVARCHAR(255) NULL,
	PRIMARY KEY (WarehouseID)
	);

CREATE TABLE Delivery_new(
	WarehouseID INT,
	StoreID INT,
	InvoiceID INT,
	MatchMethod NVARCHAR(255) NULL,
	LabelDamage INT NULL,
	Damage INT NULL,
	ReturnsCollected INT NULL,
	ArrivalTime DATETIME NULL,
	DepartTime DATETIME NULL,
	PRIMARY KEY (InvoiceID),
	FOREIGN KEY (WarehouseID) REFERENCES Warehouse_new(WarehouseID) ON DELETE CASCADE,
	FOREIGN KEY (StoreID) REFERENCES Store_new(StoreID) ON DELETE CASCADE);



-- Populate data into new tables 

INSERT INTO Store_new
SELECT *
FROM Store;

INSERT INTO Warehouse_new
SELECT *
FROM Warehouse;

INSERT INTO Delivery_new
SELECT *
FROM Delivery;



-- Drop original tables

DROP TABLE Delivery;
DROP TABLE Store;
DROP TABLE Warehouse;



-- 2. Data Cleaning

-- Rename tables in Object Explorer

-- Format ArrivalTime in Delivery table from NVARCHAR to DATETIME
-- Before SQL can convert NVARCHAR to DATETIME, there's a requirement to convert it to the machine's DATETIME format

UPDATE Delivery
SET ArrivalTime = CONVERT(DATETIME, ArrivalTime, 103);

ALTER TABLE Delivery
ALTER COLUMN ArrivalTime DATETIME;



-- Reformat ArrivalTime to ensure consistency with DepartTime

UPDATE Delivery
SET ArrivalTime = CONVERT(DATETIME, ArrivalTime, 120);



-- Separate the date and time from ArrivalTime and DepartTime
-- Create new columns to store these values

ALTER TABLE Delivery
ADD ArrivalDate DATE;

UPDATE Delivery
SET ArrivalDate = CAST(PARSENAME(ArrivalTime, 1) AS DATE)
FROM Delivery;

ALTER TABLE Delivery
ADD NewArrivalTime TIME;

UPDATE Delivery
SET NewArrivalTime = LEFT(CAST(PARSENAME(CAST(ArrivalTime AS NVARCHAR(255)), 1) AS TIME), 8)
FROM Delivery;

ALTER TABLE Delivery
ADD DepartDate DATE;

UPDATE Delivery
SET DepartDate = CAST(PARSENAME(DepartTime, 1) AS DATE);

ALTER TABLE Delivery
ADD NewDepartTime TIME;

UPDATE Delivery
SET NewDepartTime = LEFT(CAST(PARSENAME(CAST(DepartTime AS NVARCHAR(255)), 1) AS TIME), 8);



-- Delete first row of Store table as it shouldn't be inside

DELETE FROM Store
WHERE StoreID IS NULL;



-- 3. Data Exploration

-- Find out which warehouses contributed to both a higher than average parcel damage count, and label damage count for the stores
-- Assuming that this is because warehouse employees did not do a good job in QC and dispatched damaged goods to the stores

-- First, create a temp table to store the variables such as average parcel damage count, and label damage count

CREATE TABLE #var_temp_table(
	avg_overall_label_damage FLOAT,
	avg_overall_parcel_damage FLOAT
	);

INSERT INTO #var_temp_table(avg_overall_label_damage)
SELECT AVG(CAST(LabelDamage AS FLOAT))
FROM Delivery;

INSERT INTO #var_temp_table(avg_overall_parcel_damage)
SELECT AVG(CAST(Damage AS FLOAT))
FROM Delivery;

SELECT w.WarehouseLocation, AVG(CAST(d.LabelDamage AS FLOAT)) AS avg_label_damage, AVG(CAST(d.Damage AS FLOAT)) AS avg_parcel_damage
FROM Delivery d
JOIN Warehouse w ON d.WarehouseID = w.WarehouseID
GROUP BY w.WarehouseLocation
HAVING AVG(CAST(d.LabelDamage AS FLOAT)) > (SELECT avg_overall_label_damage FROM #var_temp_table WHERE avg_overall_label_damage IS NOT NULL)
AND AVG(CAST(d.Damage AS FLOAT)) > (SELECT avg_overall_parcel_damage FROM #var_temp_table WHERE avg_overall_parcel_damage IS NOT NULL)
ORDER BY w.WarehouseLocation DESC;



-- Find out the average returns collected amongst those stores that have suffered from both label and parcel damage, and insert the variable into #var_temp_table
-- Thereafter, find out the stores that have higher than average returns collected
-- Assuming that stores that have higher than average returns collected have either dispatched:
-- 1) wrong items
-- 2) or damaged goods
-- 3) or both

ALTER TABLE #var_temp_table
ADD avg_overall_returns FLOAT;

INSERT INTO #var_temp_table(avg_overall_returns)
SELECT AVG(CAST(ReturnsCollected AS FLOAT))
FROM Delivery
WHERE LabelDamage > 0 AND Damage > 0;

SELECT s.StoreName, AVG(CAST(d.LabelDamage AS FLOAT)) AS avg_label_damage, AVG(CAST(d.Damage AS FLOAT)) AS avg_parcel_damage, AVG(CAST(d.ReturnsCollected AS FLOAT)) AS avg_returns_collected
FROM Delivery d
JOIN Store s ON s.StoreID = d.StoreID
GROUP BY s.StoreName
HAVING AVG(CAST(d.ReturnsCollected AS FLOAT)) > (SELECT avg_overall_returns FROM #var_temp_table WHERE avg_overall_returns IS NOT NULL) 
AND AVG(CAST(d.LabelDamage AS FLOAT)) > (SELECT avg_overall_label_damage FROM #var_temp_table WHERE avg_overall_label_damage IS NOT NULL) 
AND AVG(CAST(d.Damage AS FLOAT)) > (SELECT avg_overall_parcel_damage FROM #var_temp_table WHERE avg_overall_parcel_damage IS NOT NULL)
ORDER BY StoreName;



-- Find out which stores have received orders from warehouses that have a record of both higher than average label damage and parcel damage

SELECT w.WarehouseLocation, s.StoreName, COUNT(s.StoreName) AS count_store
FROM Delivery d
JOIN Store s ON s.StoreID = d.StoreID
JOIN Warehouse w ON w.WarehouseID = d.WarehouseID
WHERE w.WarehouseLocation IN (
	SELECT w.WarehouseLocation
	FROM Warehouse w
	JOIN Delivery d ON d.WarehouseID = w.WarehouseID
	GROUP BY w.WarehouseLocation
	HAVING AVG(CAST(d.LabelDamage AS FLOAT)) > (SELECT avg_overall_label_damage FROM #var_temp_table WHERE avg_overall_label_damage IS NOT NULL)
	AND AVG(CAST(d.Damage AS FLOAT)) > (SELECT avg_overall_parcel_damage FROM #var_temp_table WHERE avg_overall_parcel_damage IS NOT NULL)
	) 
	AND 
	(d.LabelDamage > 0 OR d.Damage > 0)
GROUP BY w.WarehouseLocation, s.StoreName
ORDER BY w.WarehouseLocation;



-- Find out which stores(that have higher than average returns collected), have received orders from warehouses that have both higher than average label damage and parcel damage
-- These are the warehouses and stores to pay extra attention to, as they are the combination of both higher than average returns collected and higher than average damages 
-- This could mean that there may be deeper working issues, such as poor communication or poor training on the warehouses' end and unattentiveness at the stores' end
-- This will result in poor customer satisfaction

WITH warehouse_higher_avg_damage_cte AS
(SELECT w.WarehouseID
FROM Delivery d
JOIN Warehouse w ON d.WarehouseID = w.WarehouseID
GROUP BY w.WarehouseID
HAVING AVG(CAST(d.LabelDamage AS FLOAT)) > (SELECT avg_overall_label_damage FROM #var_temp_table WHERE avg_overall_label_damage IS NOT NULL)
AND AVG(CAST(d.Damage AS FLOAT)) > (SELECT avg_overall_parcel_damage FROM #var_temp_table WHERE avg_overall_parcel_damage IS NOT NULL)), 

store_higher_avg_return_cte AS
(SELECT s.StoreID
FROM Delivery d
JOIN Store s ON s.StoreID = d.StoreID
WHERE d.LabelDamage > 0 OR d.Damage > 0
GROUP BY s.StoreID
HAVING AVG(CAST(d.ReturnsCollected AS FLOAT)) > (SELECT avg_overall_returns FROM #var_temp_table WHERE avg_overall_returns IS NOT NULL))

SELECT DISTINCT w.WarehouseLocation, s.StoreName, SUM(d.LabelDamage) AS label_damage, SUM(d.Damage) AS parcel_damage, SUM(d.ReturnsCollected) AS returns_collected
FROM Delivery d
JOIN Warehouse w ON d.WarehouseID = w.WarehouseID
JOIN Store s ON d.StoreID = s.StoreID
WHERE w.WarehouseID IN (
	SELECT WarehouseID
	FROM warehouse_higher_avg_damage_cte)
	AND
	s.StoreID IN (
	SELECT StoreID
	FROM store_higher_avg_return_cte)
GROUP BY w.WarehouseLocation, s.StoreName
ORDER BY w.WarehouseLocation, s.StoreName;



-- Find out which stores have an above average time spent to dispatch orders
-- Declare one time use figure as a variable and run the query as a batch

GO
DECLARE @avg_dispatch_mins AS INT
SET @avg_dispatch_mins = (
	SELECT AVG(DATEDIFF(minute, ArrivalTime, DepartTime))
	FROM Delivery);

SELECT s.StoreName, AVG(DATEDIFF(minute, ArrivalTime, DepartTime)) AS store_avg_dispatch_mins
FROM Delivery d
JOIN Store s ON d.StoreID = s.StoreID
GROUP BY s.StoreName
HAVING AVG(DATEDIFF(minute, ArrivalTime, DepartTime)) > @avg_dispatch_mins
ORDER BY store_avg_dispatch_mins DESC;
GO



-- Find out proportion of Manual vs Scanned stock take matching method in each store 

CREATE TABLE #match_method_dist_by_store(
	StoreID INT,
	MatchMethod VARCHAR(40),
	sum_match_method INT,
	store_match_method INT,
	percentage_of_store DECIMAL(5,0),
	row_no INT
	);

WITH 
	store_sum_match_method_cte AS (
	SELECT StoreID, COUNT(MatchMethod) AS store_match_method
	FROM Delivery
	GROUP BY StoreID),

	matchmethod_sum_cte AS (
	SELECT StoreID, MatchMethod, COUNT(MatchMethod) AS sum_match_method
	FROM Delivery
	GROUP BY StoreID, MatchMethod)
	
	INSERT INTO #match_method_dist_by_store
	SELECT matchmethod_sum_cte.StoreID, matchmethod_sum_cte.MatchMethod, matchmethod_sum_cte.sum_match_method, store_sum_match_method_cte.store_match_method, 
		ROUND((CAST(matchmethod_sum_cte.sum_match_method AS DECIMAL(5,0)) / CAST(store_sum_match_method_cte.store_match_method AS DECIMAL(5,0))) * 100, 0) AS percentage_of_store,
		ROW_NUMBER() OVER (ORDER BY ROUND((CAST(matchmethod_sum_cte.sum_match_method AS DECIMAL(5,0)) / CAST(store_sum_match_method_cte.store_match_method AS DECIMAL(5,0))) * 100, 0)) AS row_no
	FROM store_sum_match_method_cte
	JOIN matchmethod_sum_cte ON store_sum_match_method_cte.StoreID = matchmethod_sum_cte.StoreID
	ORDER BY matchmethod_sum_cte.StoreID, matchmethod_sum_cte.MatchMethod;



-- Find out the mean, median, range of each matching method

SELECT MatchMethod, AVG(percentage_of_store) AS mean_percentage_of_store, 
	(SELECT percentage_of_store
	FROM #match_method_dist_by_store
	WHERE row_no = (((100+1)/2) + (100/2))) AS median_percentage_of_store,
	MAX(percentage_of_store) - MIN(percentage_of_store) AS range_percentage_of_store
FROM #match_method_dist_by_store
GROUP BY MatchMethod;



-- Find out which stores have a Manual matching method of above 50%
-- Have to look into these stores to help them in digitalisation efforts

SELECT s.StoreName, m.*
FROM #match_method_dist_by_store m
JOIN Store s ON s.StoreID = m.StoreID
WHERE m.MatchMethod = 'Manual' AND m.percentage_of_store > 50
ORDER BY m.percentage_of_store DESC;