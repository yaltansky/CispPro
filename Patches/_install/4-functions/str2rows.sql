if object_id('str2rows') is not null drop function str2rows
GO
create function [dbo].[str2rows]
	(@str varchar(8000) = '', 
	 @delim char(1) = ',')
returns @items table (item varchar(256))
as
begin
	declare @curr_pos int, @next_pos int, @item varchar(256)
	select @curr_pos = 1
if @str is null return
	while 0 = 0 begin
		set @next_pos = charindex (@delim , @str , @curr_pos)
		if @next_pos <> 0 begin
			set @item = rtrim(ltrim(substring(@str, @curr_pos, @next_pos - @curr_pos)))
			insert into @items select case when @item = '' then null else @item end
		end
		else begin
			set @item = 
					case
						when len(@str) - @curr_pos + 1 > 0 then rtrim(ltrim(right(@str, len(@str) - @curr_pos + 1)))
						else ''
					end
			insert into @items select case when @item = '' then null else @item end
			break
		end 
		set @curr_pos = @next_pos + 1
	end --while	
	return 
end
GO
