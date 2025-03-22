if object_id('payorders_reps_planfact') is not null drop proc payorders_reps_planfact
go
-- exec payorders_reps_planfact 1000, 68139
create proc payorders_reps_planfact
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;	

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'po'

-- reglament access
	declare @objects as app_objects; insert into @objects exec payorders_reglament @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'

	declare @result table(
		payorder_id int index ix_oder,		
		folder_state_name varchar(100),
		findoc_id int index ix_findoc,
		subject_id int,
		account_id int,
		d_doc datetime,
		number varchar(100),
		agent_id int,
		budget_id int,
		article_id int,
		value_order decimal(18,2),
		value_pay decimal(18,2),
		note varchar(max)
		)

	insert into @result(
		payorder_id, subject_id, d_doc, number, agent_id, budget_id, article_id, value_order, note
		)
	select
		o.payorder_id, o.subject_id, o.d_add, o.number, o.recipient_id, od.budget_id, od.article_id, abs(od.value_rur), o.note
	from payorders o
		join payorders_details od on od.payorder_id = o.payorder_id
		join @ids i on i.id = o.payorder_id
	where o.status_id not in (-2,-1)
		and od.is_deleted = 0

	insert into @result(
		payorder_id, findoc_id, subject_id, account_id, d_doc, number, agent_id, budget_id, article_id, value_pay, note
		)
	select
		pp.payorder_id, pp.findoc_id, x.subject_id, x.account_id, x.d_doc, f.number, x.agent_id, x.budget_id, x.article_id, abs(x.value_rur), f.note
	from payorders_pays pp
		join @ids i on i.id = pp.payorder_id
		join findocs# x on x.findoc_id = pp.findoc_id
		join findocs f on f.findoc_id = pp.findoc_id

	declare @node hierarchyid, @keyword varchar(32)
	select @node = node, @keyword = keyword from objs_folders where folder_id = @folder_id

	declare @folders as app_pkids
		insert into @folders
		select folder_id from objs_folders
		where folder_id in (
			select folder_id from objs_folders 
			where keyword = @keyword and node.IsDescendantOf(@node) = 1
				and has_childs = 0
				and is_deleted = 0
			)

	update x
	set folder_state_name = f.name
	from @result x
		join objs_folders_details fd on fd.obj_type = 'po' and fd.obj_id = x.payorder_id
			join objs_folders f on f.folder_id = fd.folder_id
				join @folders i on i.id = f.folder_id

	-- parent_folder_name (папка реестра)
		exec payorder_calc;10 @folders = @folders

	select
		subject_name = s.short_name,
		x.folder_state_name,
		folder_name = isnull(fld.name, ''),
		account_name = isnull(fa.name, ''),
		period_name = dbo.date2month(x.d_doc),
		d_doc = dbo.getday(x.d_doc),
		x.number,
		o.pays_path,
		agent_name = ag.name,		
		project_name = isnull(p.name, '-'),
		budget_name = b.name,
		article_name = a.name,		
		note = isnull(x.note, ''),
		x.value_order,
        x.value_pay,
        x.payorder_id,
        x.findoc_id,
        p.project_id,
        x.budget_id,
        x.article_id
	from @result x
		join payorders o on o.payorder_id = x.payorder_id
			left join objs_folders fld on fld.folder_id = o.folder_id and fld.is_deleted = 0
		join subjects s on s.subject_id = x.subject_id
		left join findocs_accounts fa on fa.account_id = x.account_id
		left join agents ag on ag.agent_id = x.agent_id
		join budgets b on b.budget_id = x.budget_id
			left join projects p on p.project_id = b.project_id
		join bdr_articles a on a.article_id = x.article_id
	where 
		-- reglament access
		(
		@mol_id in (o.mol_id)
		or x.subject_id in (select id from @subjects)
		or exists(select 1 from payorders_details where payorder_id = x.payorder_id and budget_id in (select id from @budgets))
		)

end
GO
