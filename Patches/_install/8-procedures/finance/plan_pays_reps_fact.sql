if object_id('plan_pays_reps_fact') is not null drop proc plan_pays_reps_fact
go
-- exec plan_pays_reps_fact 700, 2019, 2020
create proc plan_pays_reps_fact
	@mol_id int,
	@year_from int,
	@year_to int
as
begin

	set nocount on;

-- access
	declare @managers as app_pkids
	
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin,Finance.Plans.Admin,Finance.Plans.Reader')
	if @is_admin = 0
	begin
		insert into @managers
		select mol_id from mols where mol_id = @mol_id or chief_id = @mol_id
	end

	select 
		year(per.date_start) as year_name,
		right(concat('00', month(per.date_start)), 2) as month_name,
		x.d_doc,
		s.name as subject_name,
		coalesce(dir.short_name, dir.name, '-') as direction_name,
		m.name as mol_name,
		isnull(v.short_name, '-') as vendor_name,
		coalesce(ag.name, x.agent_name, '-') as agent_name,
        ag.inn as agent_inn,
		coalesce(ag2.name, ag.name, x.agent_name, '-') as consumer_name,
		isnull(ppt.name,'') as pay_type,
		d.number as deal_number,
		x.note,
		x.value_fact
	from plan_pays_az x
		join periods per on per.period_id = x.period_id
		left join subjects s on s.subject_id = x.subject_id
		left join depts dir on dir.dept_id = x.direction_id
		left join mols m on m.mol_id = x.mol_id
		left join vendors v on v.subject_id = x.vendor_id
		left join agents ag on ag.agent_id = x.agent_id
		left join deals d on d.deal_id = x.deal_id
			left join agents ag2 on ag2.agent_id = d.consumer_id
		left join plan_pays_types ppt on ppt.pay_type_id = x.pay_type_id
	where year(per.date_start) between @year_from and @year_to
		and (@is_admin = 1
			or x.mol_id in (select id from @managers)
			or x.mol_id is null
			)
		and x.value_fact > 0
end
go