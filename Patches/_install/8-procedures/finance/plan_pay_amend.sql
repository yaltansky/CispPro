if object_id('plan_pay_amend') is not null drop procedure plan_pay_amend
go
create proc plan_pay_amend
	@mol_id int,
	@plan_pay_id int
as
begin

	set nocount on;

	insert into plan_pays(period_id, d_doc, number, status_id, direction_id, chief_id, mol_id, add_mol_id)
	select
		x.period_id,
		dbo.today(),
		concat('v.', (select count(*) from plan_pays where period_id = x.period_id and mol_id = x.mol_id)),
		0,
		x.direction_id, x.chief_id, x.mol_id, @mol_id
	from plan_pays x
	where plan_pay_id = @plan_pay_id

	declare @new_id int = @@IDENTITY

	insert into plan_pays_rows(plan_pay_id, agent_id, agent_name, consumer_id, consumer_name, vendor_id, pay_type_id, d_doc, value_plan, note)
	select @new_id, agent_id, agent_name, consumer_id, consumer_name, vendor_id, pay_type_id, d_doc, value_plan, note
	from plan_pays_rows
	where plan_pay_id = @plan_pay_id

	select * from plan_pays where plan_pay_id = @new_id
end
go
