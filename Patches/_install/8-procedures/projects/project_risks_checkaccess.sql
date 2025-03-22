if object_id('project_risks_checkaccess') is not null
	drop proc project_risks_checkaccess
go

create proc project_risks_checkaccess
	@mol_id int,
	@risk_id int,
	@allowaccess bit out
as
begin

	declare @project_id int
	declare @node hierarchyid

	select 
		@project_id = project_id,
		@node = node
	from projects_risks 
	where risk_id = @risk_id

	set @allowaccess = 
			case 
				when exists(select 1 from projects_risks where risk_id = @risk_id and mol_id = @mol_id)
					then 1
				when exists(
					select 1
					from projects_risks_raci
					where risk_id in (
						select risk_id
						from projects_risks
						where project_id = @project_id
							and @node.IsDescendantOf(node) = 1				
						) 
						and mol_id = @mol_id
						and (charindex('A', raci) >= 1 or charindex('R', raci) >= 1)
					)
				then 1
				else 0
			end

end
GO
