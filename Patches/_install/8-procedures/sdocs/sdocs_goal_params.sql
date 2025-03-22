if object_id('sdocs_goal_params') is not null drop proc sdocs_goal_params
go
create proc sdocs_goal_params
	@mol_id int,
	@goal_id int,	
	@d_from datetime out,
	@d_to datetime out,
	@stock_id int out
as
begin
	
	set nocount on;

	select 		
		@d_from = d_from,
		@d_to = d_to,
		@stock_id = stock_id
	from sdocs_goals where goal_id = @goal_id

	-- use personal book's params (if any)
	if exists(select 1 from sdocs_goals_mols where goal_id = @goal_id and mol_id = @mol_id)
	begin
		select 			
			@d_from = d_from,
			@d_to = d_to,
			@stock_id = stock_id
		from sdocs_goals_mols where goal_id = @goal_id and mol_id = @mol_id
	end

end
go
