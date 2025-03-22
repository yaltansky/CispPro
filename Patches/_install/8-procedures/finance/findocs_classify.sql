if object_id('findocs_classify') is not null drop proc findocs_classify
go
create proc findocs_classify
	@mol_id int,
	@filter_goal_account_id int = null,
	@filter_budget_id int = null,
	@filter_article_id int = null,
	@new_goal_account_id int = null,
	@new_budget_id int = null,
	@new_article_id int = null
as
begin

	set nocount on;

-- @buffer
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer table(findoc_id int primary key)
	insert into @buffer select distinct obj_id from objs_folders_details where folder_id = @buffer_id and obj_type = 'FD'

-- reglament
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id, @for_update = 1
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

	if exists(
		select 1 from findocs
		where findoc_id in (select findoc_id from @buffer)
			and subject_id not in (select id from @subjects)
		)
	begin
		raiserror('У Вас недостаточно прав (по субъекту учёта) для модификации оплат.', 16, 1)
		return
	end

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
		' @mol_id=', @mol_id
		)
	exec tracer_log @tid, @tid_msg
	
	update x set 
		goal_account_id = isnull(@new_goal_account_id, x.goal_account_id),
		budget_id = isnull(@new_budget_id, x.budget_id),
		article_id = isnull(@new_article_id, x.article_id)
	from findocs x
	where findoc_id in (select findoc_id from @buffer)
		and (@filter_goal_account_id is null or x.goal_account_id = @filter_goal_account_id)
		and (@filter_budget_id is null or x.budget_id = @filter_budget_id)
		and (@filter_article_id is null or x.article_id = @filter_article_id)

	update x set 
		goal_account_id = isnull(@new_goal_account_id, x.goal_account_id),
		budget_id = isnull(@new_budget_id, x.budget_id),
		article_id = isnull(@new_article_id, x.article_id),
		update_date = getdate(),
		update_mol_id = @mol_id
	from findocs_details x
	where findoc_id in (select findoc_id from @buffer)
		and (@filter_goal_account_id is null or x.goal_account_id = @filter_goal_account_id)
		and (@filter_budget_id is null or x.budget_id = @filter_budget_id)
		and (@filter_article_id is null or x.article_id = @filter_article_id)

	exec tracer_close @tid
end
go
