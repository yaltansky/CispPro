if object_id('payorders_print') is not null drop proc payorders_print
go
create proc payorders_print
	@mol_id int,
	@folder_id int,
	@project_id int = null,
	@budget_id int = null
as
begin

	set nocount on;	

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'po'

	declare @folder_name varchar(100), @folder hierarchyid
		select @folder_name = name, @folder = node from objs_folders where folder_id = @folder_id
	
	if @folder_name like 'Реестр %'
	begin
		declare @folders as app_pkids
			insert into @folders
			select distinct folder_id from objs_folders 
			where keyword = 'PAYORDER' and node.IsDescendantOf(@folder) = 1
				and is_deleted = 0
		-- set folder_id, folder_slice_id (used below)
		exec payorder_calc;10 @folders = @folders
	end

-- reglament access
	declare @objects as app_objects; insert into @objects exec payorders_reglament @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'

-- #orders
	select
		fp.folder_id as parent_folder_id,
		fp.name as parent_folder_name,
		o.payorder_id,
		f2.folder_id,
		f2.name as folder_name,
		isnull(projects.project_id, 0) as project_id,
		coalesce(prj_deals.name, projects.name, '-') as project_name,
		isnull(o.pays_path, '-') as pays_path,
		agents.name as recipient_name,
		o.number as pays_basis,
		budgets.budget_id,
		budgets.name as budget_name,
		art.article_id,
		art.name as article_name,
		concat(od.note, ' /R:', od.payorder_id, '/') as 'note',
		od.value_ccy
	into #orders 
	from payorders o
		join objs_folders fp on fp.folder_id = o.folder_id and fp.is_deleted = 0
		join objs_folders f2 on f2.folder_id = o.folder_slice_id and f2.is_deleted = 0
		join payorders_details od on od.payorder_id = o.payorder_id
			left join budgets on budgets.budget_id = od.budget_id
				left join deals d on d.budget_id = budgets.budget_id
					left join projects_tasks t_deals on t_deals.ref_project_id = d.deal_id
						left join projects prj_deals on prj_deals.project_id = t_deals.project_id
				left join projects on projects.project_id = budgets.project_id
			left join bdr_articles art on art.article_id = od.article_id
		left join agents on agents.agent_id = o.recipient_id
	where 
		-- reglament access
		(
		o.mol_id = @mol_id
		or o.subject_id in (select id from @subjects)
		or od.budget_id in (select id from @budgets)
		)
		and o.payorder_id in (select id from @ids)
		and o.status_id > 0
		and od.is_deleted = 0
		and (@project_id is null or projects.project_id = @project_id)
		and (@budget_id is null or budgets.budget_id = @budget_id)

	delete from #orders where value_ccy is null

-- build @result
	declare @result table(
		NODE HIERARCHYID,
		NODE_ID INT IDENTITY PRIMARY KEY,
		PARENT_ID INT,
        NAME VARCHAR(250),
        HAS_CHILDS BIT,
        --
        PARENT_FOLDER_ID INT,
		FOLDER_ID INT,
		PROJECT_ID INT,
		PAYS_PATH VARCHAR(250),
		ARTICLE_ID INT,
		PAYORDER_ID INT,
        RECIPIENT_NAME VARCHAR(250),
		PAYS_BASIS VARCHAR(250),
        BUDGET_NAME VARCHAR(250),
        VALUE_CCY DECIMAL(18,2),
        NOTE VARCHAR(500)
	)

-- group by parent folders
	declare @map_parent_folders table(parent_folder_id int, node_id int)

	insert into @result(parent_folder_id, name, value_ccy)
		output inserted.parent_folder_id, inserted.node_id into @map_parent_folders
	select parent_folder_id, parent_folder_name, sum(value_ccy)
	from #orders
	group by parent_folder_id, parent_folder_name

-- group by folders
	declare @map_folders table(folder_id int, node_id int)

	insert into @result(parent_id, folder_id, name, value_ccy)
		output inserted.folder_id, inserted.node_id into @map_folders
	select m.node_id, o.folder_id, o.folder_name, sum(o.value_ccy)
	from #orders o
		inner join @map_parent_folders m on m.parent_folder_id = o.parent_folder_id
	group by m.node_id, o.folder_id, o.folder_name

-- group by projects
	declare @map_projects table(folder_id int, project_id int, node_id int)
	
	insert into @result(parent_id, folder_id, project_id, name, value_ccy)
		output inserted.folder_id, inserted.project_id, inserted.node_id into @map_projects
	select m.node_id, o.folder_id, o.project_id, o.project_name, sum(value_ccy)
	from #orders o
		inner join @map_folders m on m.folder_id = o.folder_id
	group by m.node_id, o.folder_id, o.project_id, o.project_name

-- group by pays_path
	declare @map_path table(folder_id int, project_id int, pays_path varchar(250), node_id int)
	
	insert into @result(parent_id, folder_id, project_id, pays_path, name, value_ccy)
		output inserted.folder_id, inserted.project_id, inserted.pays_path, inserted.node_id into @map_path
	select m.node_id, o.folder_id, o.project_id, o.pays_path, o.pays_path, sum(value_ccy)
	from #orders o
		inner join @map_projects m on m.folder_id = o.folder_id and m.project_id = o.project_id
	group by m.node_id, o.folder_id, o.project_id, o.pays_path

-- group by article
	declare @map_articles table(folder_id int, project_id int, pays_path varchar(250), article_id int, node_id int)
	
	insert into @result(parent_id, folder_id, project_id, pays_path, article_id, name, value_ccy)
		output inserted.folder_id, inserted.project_id, inserted.pays_path, inserted.article_id, inserted.node_id into @map_articles
	select m.node_id, o.folder_id, o.project_id, o.pays_path, o.article_id, o.article_name, sum(value_ccy)
	from #orders o
		inner join @map_path m on m.folder_id = o.folder_id and m.project_id = o.project_id and m.pays_path = o.pays_path
	group by  m.node_id, o.folder_id, o.project_id, o.pays_path, o.article_id, o.article_name

-- orders
	insert into @result(
		parent_id, payorder_id, pays_basis, recipient_name, budget_name, note, value_ccy
		)
	select 
		m.node_id,
		o.payorder_id,
		o.pays_basis,
		o.recipient_name,
		o.budget_name,
		o.note,
		o.value_ccy
	from #orders o
		inner join @map_articles m on m.folder_id = o.folder_id and m.project_id = o.project_id and m.pays_path = o.pays_path and m.article_id = o.article_id

-- build tree
	declare @children tree_nodes
		insert @children (node_id, parent_id, num)
		select node_id, parent_id,  
		  row_number() over (partition by parent_id order by name, payorder_id)
		from @result

	declare @nodes tree_nodes; insert into @nodes exec tree_calc @children

	update x
	set node = xx.node
	from @result x
		join @nodes as xx on xx.node_id = x.node_id

-- final
	select * from @result order by node
end
GO
