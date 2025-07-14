-- CHANGE-OVER-TIME TRENDS --

-- Analyze Sales Performance Over Time
SELECT 
YEAR(order_date) as order_year,
SUM(sales_amount) as total_sales,
COUNT(distinct customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date)


-- For Months of Each Year Analysis
SELECT 
Year(order_date) as order_year,
Month(order_date) as order_month,
SUM(sales_amount) as total_sales,
COUNT(distinct customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date), Month(order_date)
ORDER BY YEAR(order_date), Month(order_date)

-- For Particular Year
SELECT 
DATETRUNC(Month, order_date) as order_date,
SUM(sales_amount) as total_sales,
COUNT(distinct customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(Month, order_date)
ORDER BY DATETRUNC(Month, order_date)

SELECT 
FORMAT(order_date, 'yyyy-MMM') as order_date,
SUM(sales_amount) as total_sales,
COUNT(distinct customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM')
ORDER BY FORMAT(order_date, 'yyyy-MMM')


-- CUMULATIVE ANALYSIS --

-- Calculate Total Sales per Each Month
SELECT
DATETRUNC(Month, order_date) as order_date,
SUM(sales_amount) as total_sales
FROM gold.fact_sales
WHERE order_date is not null
GROUP BY DATETRUNC(Month, order_date)
ORDER BY DATETRUNC(Month, order_date)

-- The Running total of sales over Time
SELECT
order_date, 
total_sales,
SUM(total_sales) OVER (PARTITION BY order_date ORDER BY order_date) as running_total_sales
FROM
(
SELECT
DATETRUNC(Month, order_date) as order_date,
SUM(sales_amount) as total_sales
FROM gold.fact_sales
WHERE order_date is not null
GROUP BY DATETRUNC(Month, order_date)
) t


-- Cumulative metrics over years
SELECT
order_date, 
total_sales,
SUM(total_sales) OVER (ORDER BY order_date) as running_total_sales
FROM
(
SELECT
DATETRUNC(Year, order_date) as order_date,
SUM(sales_amount) as total_sales
FROM gold.fact_sales
WHERE order_date is not null
GROUP BY DATETRUNC(Year, order_date)
) t

-- Moving Average Price
SELECT
order_date, 
total_sales,
SUM(total_sales) OVER (ORDER BY order_date) as running_total_sales,
AVG(avg_price) OVER (ORDER BY order_date) as moving_average_price
FROM
(
SELECT
DATETRUNC(Year, order_date) as order_date,
SUM(sales_amount) as total_sales,
AVG(Price) as avg_price
FROM gold.fact_sales
WHERE order_date is not null
GROUP BY DATETRUNC(Year, order_date)
) t

-- PERFORMANCE ANALYSIS --
/* Analyze the yearly performance of poducts by comparing their sales to both
the average sales performance of the product and the previous year's sales */
WITH yearly_product_sales AS (
SELECT
YEAR(f.order_date) AS order_year,
p.product_name,
SUM(f.sales_amount) AS current_sales
FROM gold.fact_sales f 
LEFT JOIN gold.dim_products p 
ON f.product_key = p.product_key
WHERE f.order_date  IS NOT NULL
GROUP BY 
YEAR(f.order_date), 
p.product_name
)
SELECT 
order_year,
product_name,
current_sales,
AVG(current_sales) OVER (PARTITION by product_name) avg_sales,
current_sales - AVG(current_sales) OVER (PARTITION by product_name) AS Diff_avg,
CASE WHEN current_sales - AVG(current_sales) OVER (PARTITION by product_name) > 0 THEN 'Above Avg'
    WHEN current_sales - AVG(current_sales) OVER (PARTITION by product_name) < 0 THEN 'Below Avg'
    ELSE 'Avg'
END avg_change,
-- Year-over-Year Analysis --
LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) py_sales,
current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS Diff_py,
CASE WHEN current_sales -LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
    WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
    ELSE 'No Change'
END py_change
FROM yearly_product_sales
ORDER BY product_name, order_year


-- PART-TO-WHOLE ANALYSIS --
-- Which Categories contribute the most to overall sales

WITH category_sales AS(
SELECT
category,
SUM(sales_amount) total_sales
FROM gold.fact_sales f 
LEFT  JOIN gold.dim_products p 
on p.product_key = f.product_key
GROUP BY category)

SELECT
category,
total_sales,
SUM(total_sales) OVER () overall_sales,
CONCAT(ROUND((cast (total_sales AS float) / SUM(total_sales) OVER ())*100, 2),'%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales desc

-- DATA SEGMENTATION --
/* Segment products into cost range and count
how many products fall into each segment */

WITH product_segments AS (
SELECT 
product_key,
product_name,
cost,
CASE WHEN cost < 100 then 'Below 100'
     WHEN cost BETWEEN 100 and 500 THEN '100-500'
     WHEN cost BETWEEN 500 and 1000 THEN '500-1000'
     ELSE 'Above 1000'
END cost_range
FROM gold.dim_products)

SELECT 
cost_range,
COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products desc

/*Group customers into three segments based on their spending behavior:
- VIP: Customers with at least 12 months of history and spending more than €5,000.
- Regular: Customers with at least 12 months of history but spEding €5,000 or less.
- New: Customers with a lifespan less than 12 months.
And find the total number of customers by each group */

WITH customer_spending AS(
SELECT
c.customer_key,
SUM(f.sales_amount) as total_spending,
MIN(order_date) AS first_order,
MAX(order_date) as last_order,
DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan
from gold.fact_sales f 
LEFT JOIN gold.dim_customers c 
ON f.customer_key = c.customer_key
GROUP BY c.customer_key
)

SELECT
customer_segment,
COUNT(customer_key) as total_customers
FROM (
    SELECT
    customer_key,
        CASE WHEN lifespan >= 12 and total_spending > 5000 THEN 'VIP'
            WHEN lifespan >= 12 and total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END customer_segment
        FROM customer_spending ) t 
GROUP BY customer_segment
ORDER BY total_customers DESC




-- CUSTOMER REPORT --
/*
Purpose:
- This report consolidates key customer metrics and behaviors

Highlights:
1. Gathers essential fields such as names, ages, and transaction details.
2. Segments customers into categories (VIP, Regular, New) and age groups.
3. Aggregates customer-level metrics:
- total orders
- total sales
- total quantity purchased
- total products
- lifespan (in months)
4. Calculates valuable KPIs:
- recency (months since last order)
- average order value
- average monthly spend 
*/


CREATE VIEW gold.report_customers AS
WITH Base_query AS(
-- Basic Queries : Retrieves Core Columns from table --
SELECT
    f.order_number,
    f.product_key,
    f.order_date,
    f.sales_amount,
    f.quantity,
    c.customer_key,
    c.customer_number,
    CONCAT(c.first_name, ' ' , c.last_name) AS customer_name,
    DATEDIFF(year, c.birthdate, getdate()) age
FROM gold. fact_sales f
LEFT JOIN gold.dim_customers c
ON c.customer_key = f.customer_key
WHERE order_date IS NOT NULL)

, customer_aggregation as (
-- Customer Aggregation: Summarize Keymetrics at the customer level --
SELECT
    customer_key,
    customer_number,
    customer_name,
    age,
    COUNT(distinct order_number) as total_orders,
    sum(sales_amount) as total_sales,
    SUM(quantity) as total_quantity,
    COUNT(distinct product_key) as total_products,
    MAX(order_date) as last_order_date,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan
FROM base_query
GROUP BY
    customer_key,
    customer_number,
    customer_name,
    age
)

SELECT
customer_key,
customer_number,
customer_name,
age,
CASE  WHEN age < 20 THEN 'Under 20'
      WHEN age BETWEEN 20 and 29 THEN '20-29'
      WHEN age BETWEEN 30 and 39 THEN '30-39'
      WHEN age BETWEEN 40 and 49 THEN '40-49'
      ELSE '50 and above'
END AS age_group,
CASE WHEN lifespan >= 12 and total_sales > 5000 THEN 'VIP'
            WHEN lifespan >= 12 and total_sales <= 5000 THEN 'Regular'
            ELSE 'New'
END customer_segment,
last_order_date,
DATEDIFF(Month, last_order_date, GETDATE()) AS recency,
total_orders,
total_sales,
total_quantity,
total_products,
-- Compute average order value (AVG)
CASE WHEN total_sales =0 THEN 0
     ELSE total_sales / total_orders
END AS avg_order_value,

-- Compute average monthly spends
CASE WHEN lifespan = 0 THEN total_sales
     ELSE total_sales / lifespan
END AS avg_monthly_spends

FROM customer_aggregation;



-- PRODUCT REPORT --
/*
Purpose:
- This report consolidates key product metrics and behaviors.

Highlights:
1. Gathers essential fields such as product name, category, subcategory, and cost.
2. Segments products by revenue to identify High-Performers, Mid-Range, or Low-Performers.
3. Aggregates product-level metrics:
- total orders
- total sales
- total quantity sold
- total customers (unique)
- lifespan (in months)
4. Calculates valuable KPIs:
- recency (months since last sale)
- average order revenue (AOR)
- average monthly revenue 
*/

CREATE VIEW gold.report_products AS
WITH base_query AS (
--Base Query: Retrieves core columns from fact_sales and dim_products 

SELECT
    f.order_number,
    f.order_date,
    f.customer_key,
    f.sales_amount,
    f.quantity,
    p.product_key,
    p.product_name,
    p.category,
    p.subcategory,
    p.cost
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON f.product_key = p.product_key
WHERE order_date IS NOT NULL -- only consider valid sales dates
),

product_aggregations AS (
--Product Aggregations: Summarizes key metrics at the product level
SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
    MAX(order_date) AS last_sale_date,
    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0) ) ,1) AS average_selling_price
from base_query
GROUP BY
product_key,
product_name,
category,
subcategory,
cost
)

--Final Query: Combines all product results into one output
SELECT
product_key,
product_name,
category,
subcategory,
cost,
last_sale_date,
DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_in_months,
CASE
    WHEN total_sales > 50000 THEN 'High-Performer'
    WHEN total_sales >= 10000 THEN 'Mid-Range'
    ELSE 'Low-Performer'
END AS product_segment,
lifespan,
total_orders,
total_sales,
total_quantity,
total_customers,
average_selling_price,

--Average Order Revenue (AOR)
CASE
    WHEN total_orders = 0 THEN 0
    ELSE total_sales / total_orders
END AS avg_order_revenue,

-- Average Monthly Revenue
CASE
WHEN lifespan = 0 THEN total_sales
ELSE total_sales / lifespan
END AS avg_monthly_revenue

FROM product_aggregations;