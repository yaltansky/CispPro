if exists(select 1 from sys.objects where name = 'document_get_points')
	drop procedure document_get_points
go
create procedure document_get_points
	@route_id int,
	@document_id int = null
AS  
begin  

	if @route_id = 1
	begin
	
		declare @owner_id int, @owner_key varchar(250)
		exec document_get_owner @document_id = @document_id, @owner_id = @owner_id out, @owner_key = @owner_key out
	
		if charindex('/projects', @owner_key) > 0
		begin
			select
				@route_id as DICT_ROUTE_ID,
				cast(row_number() over(order by mols.name) as int) as DICT_POINT_ID,
				x.NAME,
				mols.MOL_ID,
				mols.NAME as MOL_NAME,
				cast(0 as bit) as ALLOW_REJECT,
				x.RESPONSE as NOTE,
				-- tree
				x.ID as NODE_ID,
				x.PARENT_ID,
				x.HAS_CHILDS
			from projects_mols x
				left join mols on mols.mol_id = x.mol_id and mols.is_working = 1
			where x.project_id = @owner_id
			order by x.node
		end

		else if charindex('/agents', @owner_key) > 0
		begin
			select
				@route_id as DICT_ROUTE_ID,
				cast(row_number() over(order by mols.name) as int) as DICT_POINT_ID,
				x.NAME,
				mols.MOL_ID,
				mols.NAME as MOL_NAME,
				cast(0 as bit) as ALLOW_REJECT,
				x.RESPONSE as NOTE,
				--
				x.ID as NODE_ID,
				x.PARENT_ID,
				x.HAS_CHILDS
			from agents_mols x
				left join mols on mols.mol_id = x.mol_id and mols.is_working = 1
			where x.agent_id = @owner_id
			order by x.node
		end
	end

	else

		select 
			DICT_ROUTE_ID,
			DICT_POINT_ID,
			p.NAME,
			mols.MOL_ID,
			mols.NAME as MOL_NAME,
			p.ALLOW_REJECT,
			p.NOTE
		from documents_dict_routes_points p
			inner join mols on mols.mol_id = p.mol_id
		where dict_route_id = @route_id
			and mols.is_working = 1

end
go
