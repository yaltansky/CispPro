if object_id('tasks_print_agree_list') is not null drop proc tasks_print_agree_list
go
create proc tasks_print_agree_list
	@task_id int
as
begin
  	set nocount on;

	declare @xml xml = (select reserved from tasks where task_id = @task_id)
    
	declare @handle_xml int
	exec sp_xml_preparedocument @handle_xml output, @xml

    declare @dataxml table(
        Task_Id int primary key,
        CreatedOn datetime,
        ApprovalListNo varchar(500),
        Note varchar(1000),
        OpportunityNo varchar(50),
        OpportunityContractType varchar(128),
        OpportunityCreatedOn datetime,
        ProductNameFirst varchar(1000),
        ProductReq varchar(1000)
    )

    insert into @dataxml
    select @task_id, CreatedOn, ApprovalListNo, Note, OpportunityNo, OpportunityContractType, OpportunityCreatedOn, ProductNameFirst, ProductReq
    from openxml (@handle_xml, '/ApprovalListData', 2) with (
        CreatedOn datetime,
        ApprovalListNo varchar(500),
        Note varchar(1000),
        OpportunityNo varchar(50),
        OpportunityContractType varchar(128),
        OpportunityCreatedOn datetime,
        ProductNameFirst varchar(1000),
        ProductReq varchar(1000)
    )

	select dbo.xml2json((
		select 
			t.task_id as TaskId, 
			TaskDate = format(t.add_date, 'dd.MM.yyyy'), 
			CrmManagerName = isnull(m.name, '-'),		 
			ProductFullName = isnull(ta1.attr_value, '-'),
			DocNumber = isnull(ta2.attr_value, '-'),
			MfrPlace = isnull(ta3.attr_value, '-'),
			TransferPrice = isnull(ta4.attr_value, '-'),
			CustomerName = isnull(ta5.attr_value, '-') + ' (ИНН: ' + isnull(ta6.attr_value, '-') + ')',
			CustomerINN = isnull(ta6.attr_value, '-'),
			ReadyDuration = isnull(ta7.attr_value, '-'),
            MatPct = isnull(ta8.attr_value, '-'),
            SpecialConditions = ta9.attr_value,
            AppListValidityPeriod = isnull(format(cast(ta10.attr_value as datetime), 'dd.MM.yyyy'), '-'),
            InnovationLevel = isnull(ta11.attr_value, '-'),
            DesignDuration = isnull(ta12.attr_value, '-'),
            SertDuration = isnull(ta13.attr_value, '-'),
            MfrPrepareDuration = isnull(ta14.attr_value, '-'),
            MfrDuration = isnull(ta15.attr_value, '-'),
            CreatedOn = format(x.CreatedOn, 'dd.MM.yyyy'),
			ApprovalListNo = isnull(x.ApprovalListNo, '-'),
            Note = isnull(x.Note, '-'),
            OpportunityNo = isnull(x.OpportunityNo, '-'),
            OpportunityContractType = isnull(x.OpportunityContractType, '-'),
            OpportunityCreatedOn = format(x.OpportunityCreatedOn,'dd.MM.yyyy'),
            ProductNameFirst = x.ProductNameFirst + '\r\n' + x.ProductReq
		from tasks t 
            left join @dataxml x on t.task_id = x.Task_Id
			left join mols m on t.author_id = m.mol_id
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'FullName'
			) ta1 on t.task_id = ta1.task_id
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'RegulatoryDocs'
			) ta2 on t.task_id = ta2.task_id
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'MfrPlace'
			) ta3 on t.task_id = ta3.task_id
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'TrfPrice'
			) ta4 on t.task_id = ta4.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'CustomerName'
			) ta5 on t.task_id = ta5.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'CustomerINN'
			) ta6 on t.task_id = ta6.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'ReadyDuration'
			) ta7 on t.task_id = ta7.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'MatPct'
			) ta8 on t.task_id = ta8.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'SpecialConditions'
			) ta9 on t.task_id = ta9.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'AppListValidityPeriod'
			) ta10 on t.task_id = ta10.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'InnovationLevel'
			) ta11 on t.task_id = ta11.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'DesignDuration'
			) ta12 on t.task_id = ta12.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'SertDuration'
			) ta13 on t.task_id = ta13.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'MfrPrepareDuration'
			) ta14 on t.task_id = ta14.task_id 
			left join (
				select task_id, attr_value from tasks_attrs where attr_name = 'MfrDuration'
			) ta15 on t.task_id = ta15.task_id 
		where t.task_id = @task_id for xml raw
	))

	exec sp_xml_removedocument @handle_xml
end
go
