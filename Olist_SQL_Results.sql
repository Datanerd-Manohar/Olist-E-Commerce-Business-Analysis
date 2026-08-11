-- Investigation 1: Customer Loyalty & Repeat Customer Analysis

with order_counts as 
(
	select count(order_status) as order_count, 
    extract(month from order_delivered_customer_date) as months,
	extract(year from order_delivered_customer_date) as years 
    from olist_orders_dataset
	where order_status = 'delivered'
	group by months, years
)    
		select * from order_counts
		order by order_count desc;


-- Investigation 2: Monthly Sales Performance

with repeat_customers as 
(
	select count(oo.order_id) as total_no_of_orders, oc.customer_unique_id 
	from olist_orders_dataset oo join olist_customers_dataset oc 
	on oo.customer_id = oc.customer_id 
	group by oc.customer_unique_id 
	having count(oo.order_id) > 1
) 
		select customer_unique_id, total_no_of_orders, 
			(select count(customer_unique_id) from repeat_customers)/ 
				(select count(distinct customer_unique_id) from olist_customers_dataset) * 100 
		as retention_rate from repeat_customers;


-- Investigation 3: Delivery Performance by State

select oc.customer_state, avg(datediff(oo.order_delivered_customer_date, oo.order_purchase_timestamp)) as avg_time_to_deliver
from olist_orders_dataset oo join olist_customers_dataset oc on oo.customer_id = oc.customer_id
where oo.order_status = 'delivered'
group by oc.customer_state
order by avg_time_to_deliver desc;


-- Investigation 4: Monthly Revenue Trend

select date_format(oo.order_delivered_customer_date, '%y-%m') as year_months, count(distinct oo.order_id) as total_orders,
round(sum(od.price),2) as total_revenue,  round(sum(od.price)/count(distinct oo.order_id), 2) as avg_order_value
from olist_orders_dataset oo join olist_order_items_dataset od on oo.order_id = od.order_id
where oo.order_status = 'delivered' and oo.order_delivered_customer_date is not null
group by year_months
order by total_revenue desc;


-- Investigation 5: Product Category Performance

with monthly_revenue as
(
	select date_format(oo.order_delivered_customer_date, '%y-%m') as month_year, 
	Round(sum(od.price), 2) as monthly_revenue
	from olist_orders_dataset oo join olist_order_items_dataset od
	on oo.order_id = od.order_id
	where oo.order_status = 'delivered' and oo.order_delivered_customer_date is not null
	group by month_year
	order by month_year
)
	select month_year, monthly_revenue,
	LAG(monthly_revenue) over() as previous_month,
	ROUND(((monthly_revenue - LAG(monthly_revenue) over()) / LAG(monthly_revenue) over())
	* 100, 2) as MoM_percentage
	from monthly_revenue;


-- Investigation 6: Product Category Trend Analysis

With product_categories as 
(
	select op.product_category_name, ROUND(SUM(oo.price), 2) as total_revenue, 
	COUNT(DISTINCT od.order_status) as total_delivered_orders,
    ROUND(SUM(SUM(OO.price)) over(), 2) as company_revenue,
	ROUND(SUM(oo.price)/COUNT(DISTINCT oo.order_id), 2) as avg_order_value
	from olist_products_dataset op join olist_order_items_dataset oo
	on op.product_id = oo.product_id join olist_orders_dataset od
	on oo.order_id = od.order_id
	where od.order_status = 'delivered'
	group by op.product_category_name
)
		select product_category_name, total_revenue, total_delivered_orders, avg_order_value,
		ROUND((total_revenue / company_revenue) * 100, 2) as revenu_contribution,
		dense_rank() over(order by total_revenue desc) as revenue_rank 
		from product_categories pc;


-- Investigation 7: High-Value Customer Analysis

with customer_value_analysis as
(
	select oc.customer_unique_id as Customer_id, ROUND(SUM(od.price), 2) as Total_Revenue, 
	Count(distinct oo.order_id) as Delivered_orders,
	ROUND(SUM(od.price)/COUNT(distinct od.order_id), 2) as Avg_order_value
	from olist_customers_dataset oc
	join olist_orders_dataset oo on oc.customer_id = oo.customer_id
	join olist_order_items_dataset od on oo.order_id = od.order_id
	where oo.order_status = 'delivered'
	group by oc.customer_unique_id
)
			select *, dense_rank() over(order by Total_Revenue desc) as revenue_rank,
			rank() over(order by Delivered_orders desc) as order_rank
			from customer_value_analysis
			order by total_revenue desc
			limit 10;


-- Investigation 8: Product Growth & Decline Analysis

with product_trend_analysis as 
(
	select distinct product_category_name, ROUND(sum(ooi.price), 2) as monthly_revenue, 
    DATE_FORMAT(order_delivered_customer_date, '%y-%m') as month_year
	from olist_products_dataset op join olist_order_items_dataset ooi
	on op.product_id = ooi.product_id join olist_orders_dataset oo
	on ooi.order_id = oo.order_id
    where oo.order_status = 'delivered'
	group by product_category_name, DATE_FORMAT(order_delivered_customer_date, '%y-%m')
),
growth_declined as 
(
	select product_category_name, month_year, monthly_revenue,
    lag(monthly_revenue) over(partition by product_category_name order by month_Year) as previous_month_revenue
	from product_trend_analysis
)
	select *, 
    Round(((monthly_revenue - previous_month_revenue) / previous_month_revenue) * 100, 2) as MoM_change, 
		case
			when monthly_revenue > previous_month_revenue then 'growth'
            when monthly_revenue < previous_month_revenue then 'declined'
            else 0
		end as growth_declined
	from growth_declined;


-- Investigation 9: Logistics & Delivery Delay Investigation

with delay_report as 
(
	select product_category_name, customer_state,
	round(avg(timestampdiff(hour, oo.order_purchase_timestamp, oo.order_approved_at)), 2) as avg_pur_app,
	round(avg(timestampdiff(day, oo.order_approved_at, oo.order_delivered_carrier_date)), 2) as avg_app_car,
	round(avg(timestampdiff(day, oo.order_delivered_carrier_date, oo.order_delivered_customer_date)), 2) as avg_car_cust,
	round(avg(timestampdiff(day, order_purchase_timestamp, order_delivered_customer_date)), 2) as est_cust_delivery
	from olist_orders_dataset oo join olist_customers_dataset oc
	on oc.customer_id = oo.customer_id join olist_order_items_dataset ooi
	on oo.order_id = ooi.order_id join olist_products_dataset op
	on op.product_id = ooi.product_id
    where oo.order_status = 'delivered'
	group by product_category_name, customer_state
)
select *, dense_rank() over(order by est_cust_delivery) as deliverey_rank from delay_report;


-- Investigation 10: Payment Behavior Analysis

with payment_behaviour as
(
	select op.payment_type, count(distinct op.order_id) as delivered_orders, 
	round(sum(op.payment_value), 2) as total_revenue, avg(op.payment_installments) as avg_payments, 
	round(sum(op.payment_value)/count(distinct op.order_id), 2) as avg_order_value 
	from olist_order_payments_dataset op 
	join olist_orders_dataset oo
	on op.order_id = oo.order_id
	where oo.order_status = 'delivered'
	group by op.payment_type
)
select *, round(((total_revenue * 100)/sum(total_revenue) over()), 2) 
as revenue_percentage from payment_behaviour
order by revenue_percentage desc;




select oc.customer_state, SUM(PRICE) from olist_order_items_dataset ooi join
olist_orders_dataset oo on ooi.order_id = oo.order_id
join olist_customers_dataset oc on oc.customer_id = oo.customer_id 
where order_status = 'delivered'
group by oc.customer_state
order by sum(price) desc;


use olist_sql_project;
select count(customer_unique_id) from olist_customers_dataset;


select customer_unique_id, count(distinct ooi.order_id), sum(price)
from olist_customers_dataset oc join olist_orders_dataset oo
on oc.customer_id = oo.customer_id join olist_order_items_dataset ooi
on oo.order_id = ooi.order_id
where customer_unique_id = '0a0a92112bd4c708ca5fde585afaa872'
group by customer_unique_id, ooi.order_id



























