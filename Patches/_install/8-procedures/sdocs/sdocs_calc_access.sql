if object_id('sdocs_calc_access') is not null drop proc sdocs_calc_access
go
create proc sdocs_calc_access
as
begin
	set nocount on;

    declare c_docs cursor local read_only for 
        select doc_id from sdocs where type_id = 5 and deal_id is not null
    declare @doc_id int

    open c_docs; fetch next from c_docs into @doc_id
        while (@@fetch_status != -1)
        begin
            if (@@fetch_status != -2) exec sdoc_calc_access @doc_id
            fetch next from c_docs into @doc_id
        end
    close c_docs; deallocate c_docs
end
go
