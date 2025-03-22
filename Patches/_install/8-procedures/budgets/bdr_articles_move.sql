if exists(select 1 from sys.objects where name = 'bdr_articles_move')
	drop procedure bdr_articles_move
go
create procedure bdr_articles_move
	@article_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	exec tree_move_node 
		@table_name = 'bdr_articles',
		@key_name = 'article_id',
		@source_id = @article_id,
		@target_id = @target_id,
		@where = @where
	
end
GO
