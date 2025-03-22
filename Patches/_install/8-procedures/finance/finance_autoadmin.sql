if object_id('finance_autoadmin') is not null drop proc finance_autoadmin
go
create proc finance_autoadmin
as
begin

	set nocount on;

	if db_name() not in ('CISP') return -- nothing todo

	if datepart(hour, getdate()) = 11		
	begin
		exec deals_reps_funding2 @is_calc = 1
		exec deals_reps_work_capital @is_calc = 1
	end

	else if datepart(hour, getdate()) = 12
		-- deals
		exec deals_calc @all = 0
	
	else begin
		-- deals
		exec deals_calc @all = 1

		declare @today datetime = dbo.today() - 1
		exec deals_credits_calc @mol_id = -25, @principal_id = 9, @d_doc = @today, @usecache = 1

		delete from deals_uploads where add_date < dateadd(d, -7, @today)

		update b set project_id = d.deal_id
		from budgets b
			join deals d on d.budget_id = b.budget_id
		where b.project_id is null
			and b.is_deleted = 0

		-- fin_goals
		truncate table fin_goals_details
		truncate table fin_goals_sums
		truncate table fin_goals_sums_details

		-- recalc budgets tree
		exec budgets_by_vendors_calc
	end
end
go
