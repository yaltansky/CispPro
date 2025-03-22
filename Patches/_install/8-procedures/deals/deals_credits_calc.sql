if object_id('deals_credits_calc') is not null drop procedure deals_credits_calc
go
-- exec deals_credits_calc 700, 9, '2019-08-06', 1
create proc deals_credits_calc
	@mol_id int = -25,
	@principal_id int = 9,
	@d_doc datetime = null,
	@usecache bit = 0,
	@trace bit = 0
as
begin
	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @usecache = 1 and exists(select 1 from deals_credits_lefts where subject_id = @principal_id and d_doc = @d_doc)
	begin
		print concat('deals_credits_calc: use cache for subject ', @principal_id, ' on ', convert(varchar, @d_doc, 20))
		return -- nothing todo
	end

	declare @tid int; exec tracer_init 'deal_credits_calc', @trace_id = @tid out --, @echo = 1
	declare @principal_pred_id int = (select pred_id from subjects where subject_id = @principal_id and pred_id is not null)
	
	delete from deals_credits where subject_id = @principal_id and move_type_id <> 1

	declare @min_d_doc datetime = isnull(
		(select max(d_doc) from deals_credits where subject_id = @principal_id and move_type_id = 1) + 1
		, 0)

exec tracer_log @tid, 'приходы'
	insert into deals_credits(subject_id, move_type_id, findoc_id, d_doc, budget_id, article_id, value)
	select @principal_id, 2, f.findoc_id, f.d_doc, f.budget_id, f.article_id, -f.value_rur
	from findocs# f
		join deals d on d.budget_id = f.budget_id
	where f.subject_id = @principal_id		
		and (f.d_doc >= @min_d_doc)
		and (@d_doc is null or f.d_doc <= @d_doc)
		and (f.value_rur < 0)

exec tracer_log @tid, 'расходы'
	insert into deals_credits(subject_id, move_type_id, findoc_id, d_doc, budget_id, article_id, value)
	select @principal_id, 3, f.findoc_id, f.d_doc, f.budget_id, f.article_id, f.value_rur
	from findocs# f
		join deals d on d.subject_id = f.subject_id and d.budget_id = f.budget_id
	where f.agent_id = @principal_pred_id
		and (f.d_doc >= @min_d_doc)
		and (@d_doc is null or f.d_doc <= @d_doc)
		and (f.value_rur < 0)

exec tracer_log @tid, 'сохранить исходящий остаток'
	if @d_doc is not null
	begin
		delete from deals_credits_lefts where subject_id = @principal_id and d_doc = @d_doc
		
		insert into deals_credits_lefts(subject_id, d_doc, budget_id, article_id, value)
		select subject_id, @d_doc, budget_id, article_id, sum(value)
		from deals_credits
		where d_doc <= @d_doc
		group by subject_id, budget_id, article_id
		having sum(value) > 0
	end 

	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid
end
go
