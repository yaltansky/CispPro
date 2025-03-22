if object_id('ccy_rates_calc') is not null drop proc ccy_rates_calc
GO
create procedure ccy_rates_calc
	@d_last date = null
as
begin

	set nocount on;
    
    if object_id('budgetdb.dbo.ccy_rates') is null
        return -- TODO: no source for ccy_rates

	if @d_last is null set @d_last = isnull((select max(date_add) from ccy_rates), '2000-01-01')

-- import news
	delete from ccy_rates where date_add > @d_last

	insert into ccy_rates(date_add, ccy_id, rate)
	select ratedate, ccyid, rate
	from budgetdb.dbo.ccy_rates
	where ratedate > @d_last

-- padding ccy_rates (day-by-day)
	declare c_ccy cursor local read_only for select ccy_id from ccy where ccy_id <> 'RUR'
	declare @ccy_id char(3)
	
	open c_ccy; fetch next from c_ccy into @ccy_id
		while (@@fetch_status <> -1)
		begin
			if (@@fetch_status <> -2)
			begin			
				declare c_rates cursor local read_only for 
					select date_add, rate from ccy_rates 
					where ccy_id = @ccy_id
						and date_add >= @d_last
					order by date_add
				
				declare @d_doc datetime, @prev_d_doc datetime, @rate float, @prev_rate float
	
				open c_rates; fetch next from c_rates into @d_doc, @rate
					set @prev_d_doc = @d_doc
					set @prev_rate = @rate

					set @d_doc = dbo.today()

					while (@@fetch_status <> -1)
					begin
						if (@@fetch_status <> -2)
						begin			
							if @prev_d_doc + 1 < @d_doc
							begin
								set @prev_d_doc = @prev_d_doc + 1
								while @prev_d_doc < @d_doc
								begin
									if not exists(select 1 from ccy_rates where date_add = @prev_d_doc and ccy_id = @ccy_id)
										insert into ccy_rates(date_add, ccy_id, rate) values (@prev_d_doc, @ccy_id, @prev_rate)
									set @prev_d_doc = @prev_d_doc + 1
								end
							end
						end
						--
						set @prev_d_doc = @d_doc
						set @prev_rate = @rate
						fetch next from c_rates into @d_doc, @rate
					end

				close c_rates; deallocate c_rates
			end
			--
			fetch next from c_ccy into @ccy_id
		end
	close c_ccy; deallocate c_ccy

end
go

