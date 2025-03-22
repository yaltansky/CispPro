if object_id('project_risk_raci_downwards') is not null
	drop proc project_risk_raci_downwards
go

create proc project_risk_raci_downwards
	@mol_id int,
	@risk_id int
as
begin

	set nocount on;

	declare @project_id int, @node hierarchyid
	select @project_id = project_id, @node = node from projects_risks where risk_id = @risk_id

	declare @risks table(risk_id int primary key)
		insert into @risks(risk_id)
		select risk_id 
		from projects_risks 
		where project_id = @project_id
			and node.IsDescendantOf(@node) = 1
			and risk_id <> @risk_id

-- delete RACI
	delete from projects_risks_raci
	where risk_id in (select risk_id from @risks)

-- insert RACI (clone)
	insert into projects_risks_raci(risk_id, mol_id, raci)
	select t.risk_id, r.mol_id, r.raci
	from projects_risks_raci r, @risks t
	where r.risk_id = @risk_id

end
GO
