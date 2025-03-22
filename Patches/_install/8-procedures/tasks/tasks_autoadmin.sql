if object_id('tasks_autoadmin') is not null drop proc tasks_autoadmin
go
create proc tasks_autoadmin
as
begin

	set nocount on;

	IF DB_NAME() NOT IN ('CISP') RETURN

	-- удалить пустые комментарии
	delete from tasks_hists 
	where description is null and body is null
		and has_files = 0
		and action_name = 'Комментировать'

	-- пересчитать линии поддержки
	exec tasks_themes_calc

	-- удалить кеш
	if exists(select 1 from sys.databases where name = 'CISPTMP')
	begin
		declare @drop nvarchar(max) = N'use cisptmp;' + (
			select 'drop table '+ name + ';'  [text()] from cisptmp.sys.tables where name like 'tasks_cache%'
			for xml path('')
			)
		exec sp_executesql @drop
	end
end
go
