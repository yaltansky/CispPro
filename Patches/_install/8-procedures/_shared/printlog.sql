if object_id('printlog') is not null drop proc printlog
go
create proc printlog(@s varchar(max))
as print concat(substring(convert(varchar, getdate(), 20), 11, 255), ': ', @s)
go
