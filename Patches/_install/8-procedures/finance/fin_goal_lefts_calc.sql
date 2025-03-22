if object_id('fin_goal_lefts_calc') is not null drop proc fin_goal_lefts_calc
go
-- exec fin_goal_lefts_calc 1
create proc fin_goal_lefts_calc
	@fin_goal_id int
as
begin
	
	set nocount on;

-- read params
	declare @prev_id int,
		@d_from datetime, @d_to datetime

		select 
			@prev_id = parent_id,
			@d_from = d_from,
			@d_to = d_to
		from fin_goals where fin_goal_id = @fin_goal_id


	declare @subjects table(subject_id int)
	insert into @subjects select subject_id from fin_goals where fin_goal_id = @fin_goal_id

-- clear
	create table #fgl_lefts (
		goal_account_id int, budget_id int, article_id int, value_end decimal(18,2), note varchar(max),
		constraint pk_lefts primary key (goal_account_id, budget_id, article_id)
		)
	
	delete from fin_goals_lefts where fin_goal_id = @fin_goal_id
		and is_deleted = 1

	delete from fin_goals_lefts 
		output isnull(deleted.goal_account_id,0) as goal_account_id, deleted.budget_id, deleted.article_id, deleted.value_end, deleted.note into #fgl_lefts
	where fin_goal_id = @fin_goal_id

	if @prev_id is null set @d_from = 0

	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

-- insert new
	;with pays as (
		select
			f.goal_account_id, f.budget_id, f.article_id,
			sum(f.value_rur) as value_end
		from findocs# f
			join findocs_accounts fa on fa.account_id = f.account_id
		where f.subject_id in (select subject_id from @subjects)
			and f.d_doc between @d_from and @d_to
			and fa.name <> @vat_refund
		group by f.goal_account_id, f.budget_id, f.article_id
		)
		insert into fin_goals_lefts(fin_goal_id, goal_account_id, budget_id, article_id, value_end_calc, value_end, note)
		select 
			@fin_goal_id,
			coalesce(l.goal_account_id, calc.goal_account_id, 0),
			isnull(l.budget_id, calc.budget_id),
			isnull(l.article_id, calc.article_id),
			calc.value_end,
			nullif(l.value_end, 0),
			l.note
		from (				
			select
				 goal_account_id, budget_id, article_id, sum(value_end) as value_end
			from (
				select goal_account_id, budget_id, article_id, value_end
				from fin_goals_lefts
				where fin_goal_id = @prev_id
					and isnull(value_end,0) <> 0

				UNION ALL
				select goal_account_id, budget_id, article_id, value_end
				from pays
				) u
			group by goal_account_id, budget_id, article_id
			having sum(value_end) <> 0
			) calc
			full outer join #fgl_lefts l on 
					isnull(l.goal_account_id,0) = isnull(calc.goal_account_id,0)
				and l.budget_id = calc.budget_id
				and l.article_id = calc.article_id

    drop table #fgl_lefts

end
go
