if object_id('projects_pivots_planfact_bds') is not null drop proc projects_pivots_planfact_bds
go
-- exec projects_pivots_planfact_bds 1000, -1
create proc projects_pivots_planfact_bds
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	-- @budgets
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit = 
		case 
			when exists(select 1 from @budgets where id = -1) and not exists(select 1 from @budgets where id <> -1) then 1 
			else 0 
		end

-- @ids
	declare @ids as app_pkids
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'prj'

-- final
	select
		PROJECT_NAME = P.NAME,
		BUDGET_NAME = B.NAME,
		ARTICLE_GROUP_NAME = A2.NAME,
		ARTICLE_NAME = A.NAME,
		BT.PLAN_DDS,
		BT.PLAN_DDS_CURRENT,
		BT.FACT_DDS,
		DIFF_BDS = ISNULL(BT.PLAN_DDS_CURRENT,0) - ISNULL(BT.FACT_DDS,0),
		-- 
		BUDGET_HID = concat('#', b.budget_id)
	from budgets_totals bt
		join budgets b on b.budget_id = bt.budget_id
			join projects p on p.project_id = b.project_id
				join @ids i on i.id = p.project_id
		join bdr_articles a on a.article_id = bt.article_id
			left join bdr_articles a2 on a2.article_id = a.parent_id
end
go
