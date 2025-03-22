if object_id('finance_reps_pays') is not null drop proc finance_reps_pays
go
-- exec finance_reps_pays 700, 8161
create proc finance_reps_pays
	@mol_id int,
	@folder_id int,
	@d_from datetime = null,
	@d_to datetime = null
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	-- @subjects
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	-- @budgets
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'

-- #folders_details
	create table #folders(folder_id int, parent_id int, name varchar(50), has_childs bit)
	create table #folders_details(findoc_id int primary key, folder_id int)

	declare @folder hierarchyid, @keyword varchar(50)
	select @folder = node, @keyword = keyword from objs_folders where folder_id = @folder_id
			
	-- #folders
	insert into #folders(folder_id, parent_id, name, has_childs)
	select folder_id, parent_id, name, has_childs
	from objs_folders
	where node.IsDescendantOf(@folder) = 1			
		and keyword = @keyword
		and is_deleted = 0

	insert into #folders_details(findoc_id, folder_id)
	select fd.obj_id, max(f.folder_id)
	from objs_folders_details fd
		join #folders f on f.folder_id = fd.folder_id and f.has_childs = 0
	where fd.obj_type = 'FD'
	group by fd.obj_id

-- result
	select
		SUBJECT_NAME,
		ACCOUNT_NAME,
		MFR_NAME,
		PROJECT_NAME,
		BUDGET_NAME,
		ARTICLE_NAME,
		D_DOC,
		VALUE_IN = cast(sum(value_in) as decimal(18,2)),
		VALUE_OUT = cast(sum(value_out) as decimal(18,2))
	from (
		select 
			subject_name = s.short_name,
			account_name = fa.name,
			mfr_name = coalesce(d.mfr_name, v.short_name, '-'),
			project_name = 
				case
					when p.project_id is null then '<ТЕКУЩАЯ ДЕЯТЕЛЬНОСТЬ>'
					when p.type_id = 3 then '<БЮДЖЕТЫ СДЕЛОК>'
					else p.name
				end,
			budget_name = b.name,
			article_name = a.name,
			f.d_doc,
			value_in = case when f.value_rur > 0 then f.value_rur end,
			value_out = case when f.value_rur < 0 then f.value_rur end
		from findocs# f			
			join #folders_details buf on buf.findoc_id = f.findoc_id
			join subjects s on s.subject_id = f.subject_id
			join findocs_accounts fa on fa.account_id = f.account_id
			left join budgets b on b.budget_id = f.budget_id
				left join projects p on p.project_id = b.project_id
			left join deals d on d.budget_id = f.budget_id
			left join bdr_articles a on a.article_id = f.article_id
				left join subjects v on v.subject_id = a.subject_id
		where 
			exists(select 1 from @subjects where id = f.subject_id)
			or exists(select 1 from @budgets where id = f.budget_id)
		) x
	group by 
		subject_name,
		account_name,
		mfr_name,
		project_name,
		budget_name,
		article_name,
		d_doc

end
go