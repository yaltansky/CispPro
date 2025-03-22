if object_id('sales_autoadmin') is not null drop proc sales_autoadmin
go
create proc sales_autoadmin
as
begin
	
	set nocount on;

	IF DB_NAME() NOT IN ('CISP') RETURN

	declare @today datetime = dbo.today()
	declare @period_from varchar(16) = (select period_id from periods where type_id = 'month' and @today - 10 between date_start and date_end)
	declare @period_to varchar(16) = (select period_id from periods where type_id = 'month' and @today between date_start and date_end)

	declare c_periods cursor local read_only for 
		select period_id from periods where type_id = 'month' and period_id between @period_from and @period_to
	
	declare @period_id varchar(16)
	
	open c_periods; fetch next from c_periods into @period_id
		while (@@fetch_status <> -1)
		begin
			if (@@fetch_status <> -2) exec plan_pays_calc @period_id = @period_id
			fetch next from c_periods into @period_id
		end
	close c_periods; deallocate c_periods
end
go
