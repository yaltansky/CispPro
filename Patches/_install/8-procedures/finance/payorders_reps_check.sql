if object_id('payorders_reps_check') is not null drop proc payorders_reps_check
go
create proc payorders_reps_check
	@mol_id int,
	@folder_id int,
	@project_id int = null,
	@budget_id int = null
as
begin

	set nocount on;	

	declare @folders table(folder_id int primary key)
	declare @folder_name varchar(100) = (select name from objs_folders where folder_id = @folder_id)
	
	if @folder_name like 'Реестр %-%-%'
		insert into @folders select @folder_id
	else begin
		declare @folder hierarchyid = (select node from OBJS_FOLDERS where folder_id = @folder_id)
		insert into @folders 
			select distinct folder_id from objs_folders 
			where node.IsDescendantOf(@folder) = 1
	end

-- reglament access
	declare @objects as app_objects;	insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

-- #orders
	select
		fp.folder_id as parent_folder_id,
		fp.name as parent_folder_name,
		o.payorder_id,
		f2.folder_id,
		f2.name as folder_name,
		isnull(projects.project_id, 0) as project_id,
		isnull(projects.name, '-') as project_name,
		isnull(o.pays_path, '-') as pays_path,
		agents.name as recipient_name,
		o.number as pays_basis,
		budgets.budget_id,
		budgets.name as budget_name,
		art.article_id,
		art.name as article_name,
		od.note,
		case	
			when exists(
				select 1 from payorders_partials_details 
				where payorder_id = o.payorder_id
					and folder_id = fp.folder_id
				) then parts.value_ccy
			else
				od.value_ccy
		end as value_ccy
	into #orders 
	from payorders o
		join objs_folders_details fd on fd.obj_id = o.payorder_id
			join objs_folders f2 on f2.folder_id = fd.folder_id
				join objs_folders fp on fp.folder_id = f2.parent_id
		join payorders_details od on od.payorder_id = o.payorder_id
			-- частичные оплаты
			left join (
				select folder_id, payorder_id, budget_id, article_id, sum(value_ccy) as value_ccy
				from payorders_partials_details
				group by folder_id, payorder_id, budget_id, article_id
			) parts on 
					parts.folder_id = fp.folder_id
				and parts.payorder_id = o.payorder_id 
				and parts.budget_id = od.budget_id
				and parts.article_id = od.article_id
			join budgets on budgets.budget_id = od.budget_id
				left join projects on projects.project_id = budgets.project_id
			join bdr_articles art on art.article_id = od.article_id
		left join agents on agents.agent_id = o.recipient_id
	where 
		-- reglament access
		(
		o.mol_id = @mol_id
		or o.subject_id in (select id from @subjects)
		)
		and fp.folder_id in (select folder_id from @folders)
		and od.is_deleted = 0
		and (@project_id is null or projects.project_id = @project_id)
		and (@budget_id is null or budgets.budget_id = @budget_id)

	delete from #orders where value_ccy is null

	select
		parent_folder_name,
		folder_name,
		project_name,
		pays_path,
		article_name,
		payorder_id,
		recipient_name,
		pays_basis,			
		budget_name,
		note,
		value_ccy
	from #orders
	order by 
		parent_folder_id,
		folder_name,
		project_name,
		pays_path,
		article_name,
		payorder_id

end
GO
