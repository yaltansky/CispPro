if object_id('plan_pay_calc') is not null drop procedure plan_pay_calc
go
create proc plan_pay_calc
	@mol_id int = -25,
	@plan_pay_id int
as
begin

	set nocount on;

	declare @manager_id int = (select mol_id from plan_pays where plan_pay_id = @plan_pay_id)

	exec deals_calc @manager_id = @manager_id

	insert into plan_pays_rows(plan_pay_id, agent_id, consumer_id, vendor_id, pay_type_id, value_plan)
	select @plan_pay_id, x.customer_id, x.consumer_id, x.vendor_id, 2, sum(x.left_ccy)
	from deals x
	where x.manager_id = @manager_id
		and not exists(select 1 from plan_pays_rows where plan_pay_id = @plan_pay_id and agent_id = x.customer_id)
	group by 
		x.customer_id, x.consumer_id, x.vendor_id
	having 
		sum(x.left_ccy) > 1.00
end
go
