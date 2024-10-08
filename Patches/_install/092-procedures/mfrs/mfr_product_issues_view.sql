if object_id('mfr_product_issues_view') is not null drop proc mfr_product_issues_view
go
create proc [mfr_product_issues_view]
  @mol_id int,
  -- filter
  @search nvarchar(max) = null,
  @folder_id int = null,
  @buffer_operation int = null,
  -- sorting, paging
  @sort_expression varchar(50) = null,
  @offset int = 0,
  @fetchrows int = 30,
  --
  @rowscount int = null out
as
begin

  set nocount on;
  set transaction isolation level read uncommitted;

  create table #MFR_PRODUCTS_ISSUES (
    RowId int identity(1,1) primary key,
    PRODUCT_ISSUE_ID int,
    SUBJECT_ID int,
    SUBJECT_NAME varchar(20),
    PRODUCT_ID int,
    NAME nvarchar(255),
    NOTE_PRODUCT nvarchar(255),
    NOTE_MISC nvarchar(255),
    SERIAL_NUMBER varchar(100),
    SCANCODE varchar(255),
    QR_CODE varchar(255),
    RFID_CODE varchar(255),
    D_ISSUE datetime,
    MFR_NUMBER varchar(150)
  )
  -- список продукции с учётом фильтра @search
  insert into #MFR_PRODUCTS_ISSUES (
      PRODUCT_ISSUE_ID, SUBJECT_ID, SUBJECT_NAME, PRODUCT_ID, NAME, NOTE_PRODUCT, NOTE_MISC,
      SERIAL_NUMBER, SCANCODE, QR_CODE, RFID_CODE, D_ISSUE, MFR_NUMBER)
    select
        i.PRODUCT_ISSUE_ID,
        i.SUBJECT_ID,
        SUBJECT_NAME = s.SHORT_NAME,
        i.PRODUCT_ID,
        i.NAME,
        i.NOTE_PRODUCT,
        i.NOTE_MISC,
        i.SERIAL_NUMBER,
        i.SCANCODE,
        i.QR_CODE,
        i.RFID_CODE,
        i.D_ISSUE,
        i.MFR_NUMBER
      from MFR_PRODUCTS_ISSUES i
             --join PRODUCTS p on (i.PRODUCT_ID = p.PRODUCT_ID)
             left join SUBJECTS s on (i.SUBJECT_ID = s.SUBJECT_ID)
      where (i.NAME like '%' + isnull(@search, '') + '%') or
            (i.NOTE_PRODUCT like '%' + isnull(@search, '') + '%') or
            (i.SERIAL_NUMBER like '%' + isnull(@search, '') + '%') or
            (i.SCANCODE like '%' + isnull(@search, '') + '%') or
            (i.QR_CODE like '%' + isnull(@search, '') + '%') or
            (i.RFID_CODE like '%' + isnull(@search, '') + '%') or
            (i.MFR_NUMBER like '%' + isnull(@search, '') + '%')
      order by i.PRODUCT_ISSUE_ID
  -- учтём признак папки
  if (@folder_id is not null) begin
    delete t
      from #MFR_PRODUCTS_ISSUES t
             left join OBJS_FOLDERS_DETAILS d on (t.PRODUCT_ISSUE_ID = d.OBJ_ID) and
                                                 (d.FOLDER_ID = @folder_id) and
                                                 (d.OBJ_TYPE = 'PI')
      where (d.OBJ_ID is null)
  end
  -- перед тем, как вернуть записи, отработаем буфер
  if (@buffer_operation is not null) begin
    declare @buffer_id int; select @buffer_id = FOLDER_ID from OBJS_FOLDERS where (KEYWORD = 'BUFFER') and (ADD_MOL_ID = @mol_id)
    --
    if (@buffer_operation = 1) begin
      delete from OBJS_FOLDERS_DETAILS where (FOLDER_ID = @buffer_id) and (OBJ_TYPE = 'PI')
      --
      insert into OBJS_FOLDERS_DETAILS (FOLDER_ID, OBJ_TYPE, OBJ_ID, ADD_MOL_ID)
        select FOLDER_ID = @buffer_id, OBJ_TYPE = 'PI', OBJ_ID = x.PRODUCT_ISSUE_ID, ADD_MOL_ID = @mol_id
          from #MFR_PRODUCTS_ISSUES x
    end
    if (@buffer_operation = 2) begin
      delete d
        from OBJS_FOLDERS_DETAILS d
               join #MFR_PRODUCTS_ISSUES x on (d.OBJ_ID = x.PRODUCT_ISSUE_ID)
        where (d.FOLDER_ID = @buffer_id) and
              (d.OBJ_TYPE = 'PI')
    end
  end
  --
  select @rowscount = count(*) from #MFR_PRODUCTS_ISSUES
  --
  select *
    from #MFR_PRODUCTS_ISSUES
    order by RowId
    offset @offset rows fetch next @fetchrows rows only
  --
  drop table #MFR_PRODUCTS_ISSUES

end
GO
