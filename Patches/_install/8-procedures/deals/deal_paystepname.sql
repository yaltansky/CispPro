if object_id('deal_paystepname') is not null drop function deal_paystepname
go
create function deal_paystepname(@task_name varchar(50), @date_lag int, @ratio float)
returns varchar(50)
as
begin

	return
		concat(
			@task_name, ' (',
			case 
				when @date_lag = 0 then ''
				else 
					concat(
						case when @date_lag > 0 then '+' else '-' end,
						@date_lag, ' дн, '
						)
			end,
			cast(@ratio * 100 as int), '%)'
			)

end
GO
